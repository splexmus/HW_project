import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb_tools.runner import get_runner


def rgb444(r, g, b):
    return ((r & 0xF) << 8) | ((g & 0xF) << 4) | (b & 0xF)


def expected_gray(r, g, b):
    """Match RTL: gray = min(r*3 + g*6 + b, 255)."""
    raw = r * 3 + g * 6 + b
    return 255 if raw > 255 else raw


async def setup_clock(dut):
    """Start clock, force we=0 + (x,y)=(0,0) to reset internal sx,sy."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.we.value = 0
    dut.x.value = 0
    dut.y.value = 0
    dut.pixel_in.value = 0
    # Two cycles with x=y=0 -> internal reset (sx,sy <= 0)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def set_and_wait(dut, **inputs):
    """Apply inputs on a falling edge, then wait two rising edges:
    one for cocotb's deposit to land, one for the RTL always block to react.
    """
    await FallingEdge(dut.clk)
    for name, value in inputs.items():
        getattr(dut, name).value = value
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_grayscale_no_clip(dut):
    """r=g=b=8 -> raw = 80, no clip."""
    await setup_clock(dut)
    await set_and_wait(dut, we=1, x=0, y=0, pixel_in=rgb444(8, 8, 8))
    await FallingEdge(dut.clk)
    dut.we.value = 0

    assert int(dut.small_data.value) == expected_gray(8, 8, 8), (
        f"gray no-clip: got {int(dut.small_data.value)}, "
        f"expected {expected_gray(8, 8, 8)}"
    )
    dut._log.info(f"PASS: gray no-clip = {int(dut.small_data.value)}")


@cocotb.test()
async def test_grayscale_max_nibble(dut):
    """r=g=b=15 -> raw = 150 (still below 255 clip)."""
    await setup_clock(dut)
    await set_and_wait(dut, we=1, x=0, y=0, pixel_in=rgb444(15, 15, 15))
    await FallingEdge(dut.clk)
    dut.we.value = 0

    assert int(dut.small_data.value) == 150, (
        f"gray max-nibble: got {int(dut.small_data.value)}, expected 150"
    )
    dut._log.info(f"PASS: gray max-nibble = {int(dut.small_data.value)}")


@cocotb.test()
async def test_sample_gating(dut):
    """small_we asserts only when we=1 AND x%10==0 AND y%7==0."""
    await setup_clock(dut)

    # we=0 at (0,0) -> no sample
    await set_and_wait(dut, we=0, x=0, y=0, pixel_in=rgb444(8, 8, 8))
    assert dut.small_we.value == 0, "small_we asserted with we=0"

    # we=1 but x=5 -> x%10 != 0
    await set_and_wait(dut, we=1, x=5, y=0)
    assert dut.small_we.value == 0, "small_we asserted on x=5"

    # we=1, x=0, y=3 -> y%7 != 0
    await set_and_wait(dut, x=0, y=3)
    assert dut.small_we.value == 0, "small_we asserted on y=3"

    # we=1, x=10, y=7 -> sample
    await set_and_wait(dut, x=10, y=7)
    assert dut.small_we.value == 1, "small_we did NOT assert on (10,7)"

    await FallingEdge(dut.clk)
    dut.we.value = 0
    dut._log.info("PASS: sample gating respects we, x%10, y%7")


@cocotb.test()
async def test_frame_done_pulse(dut):
    """After 1024 valid samples, frame_done asserts for ~20 cycles."""
    await setup_clock(dut)

    # Drive 1024 samples with we=1 at (x=10,y=7) — that gate stays valid every cycle
    # so sx,sy increment once per clock until they wrap.
    await FallingEdge(dut.clk)
    dut.x.value = 10
    dut.y.value = 7
    dut.pixel_in.value = rgb444(1, 1, 1)
    dut.we.value = 1

    samples = 0
    cycles = 0
    while samples < 1024 and cycles < 5000:
        await RisingEdge(dut.clk)
        if dut.small_we.value == 1:
            samples += 1
        cycles += 1

    assert samples == 1024, f"only got {samples} samples in {cycles} cycles"

    await FallingEdge(dut.clk)
    dut.we.value = 0

    # frame_done should already be high or assert within a couple cycles
    for _ in range(5):
        await RisingEdge(dut.clk)
        if dut.frame_done.value == 1:
            break
    assert dut.frame_done.value == 1, "frame_done did not assert after 1024 samples"

    # Count cycles it stays high
    high = 1
    for _ in range(30):
        await RisingEdge(dut.clk)
        if dut.frame_done.value == 1:
            high += 1
        else:
            break
    # done_cnt is loaded with 20; pulse length is ~20 cycles (allow window 15..25)
    assert 15 <= high <= 25, f"frame_done high for {high} cycles (expected ~20)"
    dut._log.info(f"PASS: frame_done pulses for {high} cycles after 1024 samples")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/downscale_32x32.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="downscale_32x32",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="downscale_32x32",
        test_module="downscale_32x32_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
