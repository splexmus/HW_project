import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner


# Pipeline depth: in bilinear_upscale.v all stages live in one always block but
# each stage reads the previous stage's reg, so the dataflow depth from x/y to
# pixel_out is 4 clocks (x->fx, r->top_r, top_r->final_r, final_r->pixel_out).
PIPELINE_DEPTH = 5  # one extra cycle of margin

_clock_started = False


def _ensure_clock(dut):
    """Start the pixel clock exactly once across the whole regression."""
    global _clock_started
    if not _clock_started:
        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
        _clock_started = True


def rgb444(r4, g4, b4):
    """Pack 4-bit R,G,B into 12-bit RGB444."""
    return ((r4 & 0xF) << 8) | ((g4 & 0xF) << 4) | (b4 & 0xF)


def bilinear_ref(p00, p01, p10, p11, fx, fy):
    """Python reference model matching bilinear_upscale.v pipeline."""
    def unpack(p):
        r = (p >> 8) & 0xF
        g = (p >> 4) & 0xF
        b = p & 0xF
        return r << 4, g << 4, b << 4

    r00, g00, b00 = unpack(p00)
    r01, g01, b01 = unpack(p01)
    r10, g10, b10 = unpack(p10)
    r11, g11, b11 = unpack(p11)

    top_r = ((4 - fx) * r00 + fx * r01) >> 2
    bot_r = ((4 - fx) * r10 + fx * r11) >> 2
    top_g = ((4 - fx) * g00 + fx * g01) >> 2
    bot_g = ((4 - fx) * g10 + fx * g11) >> 2
    top_b = ((4 - fx) * b00 + fx * b01) >> 2
    bot_b = ((4 - fx) * b10 + fx * b11) >> 2

    final_r = ((4 - fy) * top_r + fy * bot_r) >> 2
    final_g = ((4 - fy) * top_g + fy * bot_g) >> 2
    final_b = ((4 - fy) * top_b + fy * bot_b) >> 2

    return ((final_r >> 4) & 0xF) << 8 | ((final_g >> 4) & 0xF) << 4 | ((final_b >> 4) & 0xF)


async def drive_and_read(dut, x, y, p00, p01, p10, p11):
    """Hold inputs steady for PIPELINE_DEPTH clocks, then read pixel_out."""
    dut.x.value = x
    dut.y.value = y
    dut.p00.value = p00
    dut.p01.value = p01
    dut.p10.value = p10
    dut.p11.value = p11
    for _ in range(PIPELINE_DEPTH):
        await RisingEdge(dut.clk)
    return int(dut.pixel_out.value)


@cocotb.test()
async def test_no_interpolation_fx0_fy0(dut):
    """When fx=0 and fy=0 (pixel-aligned), output must equal p00."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await Timer(20, unit="ns")

    p00 = rgb444(0xA, 0x5, 0x3)
    p01 = rgb444(0x1, 0x2, 0x3)
    p10 = rgb444(0x4, 0x5, 0x6)
    p11 = rgb444(0x7, 0x8, 0x9)

    result = await drive_and_read(dut, x=0, y=0, p00=p00, p01=p01, p10=p10, p11=p11)
    expected = bilinear_ref(p00, p01, p10, p11, fx=0, fy=0)

    assert result == expected, f"fx=0,fy=0: got {hex(result)}, expected {hex(expected)}"
    dut._log.info(f"PASS: no-interp result={hex(result)}")


@cocotb.test()
async def test_half_interpolation_fx2_fy0(dut):
    """fx=2 (half-step) with fy=0 -> output is average of p00 and p01."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    p00 = rgb444(0x0, 0x0, 0x0)
    p01 = rgb444(0xF, 0xF, 0xF)
    p10 = rgb444(0x0, 0x0, 0x0)
    p11 = rgb444(0xF, 0xF, 0xF)

    result = await drive_and_read(dut, x=2, y=0, p00=p00, p01=p01, p10=p10, p11=p11)
    expected = bilinear_ref(p00, p01, p10, p11, fx=2, fy=0)

    assert result == expected, f"fx=2,fy=0: got {hex(result)}, expected {hex(expected)}"
    dut._log.info(f"PASS: half-interp result={hex(result)}")


@cocotb.test()
async def test_full_interpolation_fx2_fy2(dut):
    """fx=2, fy=2 -> bilinear center — verify against Python reference."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    p00 = rgb444(0x0, 0x0, 0x0)
    p01 = rgb444(0xF, 0x0, 0x0)
    p10 = rgb444(0x0, 0xF, 0x0)
    p11 = rgb444(0xF, 0xF, 0x0)

    result = await drive_and_read(dut, x=2, y=2, p00=p00, p01=p01, p10=p10, p11=p11)
    expected = bilinear_ref(p00, p01, p10, p11, fx=2, fy=2)

    assert result == expected, f"fx=2,fy=2: got {hex(result)}, expected {hex(expected)}"
    dut._log.info(f"PASS: full bilinear result={hex(result)}")


@cocotb.test()
async def test_uniform_pixels(dut):
    """All four neighbours identical -> output must equal that pixel regardless of fx/fy."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    p = rgb444(0x7, 0x3, 0xB)
    for fx in range(4):
        for fy in range(4):
            result = await drive_and_read(dut, x=fx, y=fy, p00=p, p01=p, p10=p, p11=p)
            expected = bilinear_ref(p, p, p, p, fx=fx, fy=fy)
            assert result == expected, (
                f"uniform px fx={fx},fy={fy}: got {hex(result)}, expected {hex(expected)}"
            )
    dut._log.info("PASS: uniform pixels pass all fx/fy combinations")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/bilinear_upscale.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="bilinear_upscale",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="bilinear_upscale",
        test_module="bilinear_upscale_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
