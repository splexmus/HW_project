import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner

# Kernel weights matching con3x3.v initial block
KERNEL = [32, 16, -18, 14, -7, -11, -9, -13, 1]


def expected_conv(pixels_3x3):
    """Compute expected result: sum(pixel * kernel) - 6."""
    total = sum(int(p) * int(k) for p, k in zip(pixels_3x3, KERNEL))
    return total - 6


# 32x32 flat pixel buffer for the DUT to read from
PIXEL_MEM = [i % 256 for i in range(32 * 32)]


async def pixel_driver(dut):
    """Respond to addr each cycle with the corresponding pixel value."""
    while True:
        await RisingEdge(dut.clk)
        if not dut.addr.value.is_resolvable:
            continue
        addr = int(dut.addr.value)
        if addr < len(PIXEL_MEM):
            dut.pixel.value = PIXEL_MEM[addr]


@cocotb.test()
async def test_conv_first_pixel(dut):
    """Run one full convolution at (x=0,y=0) and verify result matches software model.

    Note: conv3x3.v has no reset input. Once start_pulse fires the FSM walks
    through all 30x30 = 900 output pixels before returning to IDLE. This single
    test covers the MAC path; multi-scenario tests would require a reset port.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    cocotb.start_soon(pixel_driver(dut))

    dut.start.value = 0
    dut.pixel.value = 0
    await Timer(30, unit="ns")

    # Pulse start for one cycle
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for done to assert (max 200 cycles per pixel x first pixel)
    for _ in range(500):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break

    assert dut.done.value == 1, "conv3x3 never asserted done"

    # Extract the 3x3 neighbourhood at (x=0, y=0)
    neighbourhood = [PIXEL_MEM[(r // 3) * 32 + (r % 3)] for r in range(9)]
    expected = expected_conv(neighbourhood)

    actual = dut.result.value.signed_integer
    assert actual == expected, f"Result mismatch: got {actual}, expected {expected}"
    dut._log.info(f"PASS: conv result={actual}, expected={expected}")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/con3x3.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="conv3x3",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="conv3x3",
        test_module="con3x3_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
