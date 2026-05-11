import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb_tools.runner import get_runner


THRESHOLD = 800_000
N_PIXELS = 900  # classifier accumulates 900 conv_done pulses (count: 0..899)


async def pulse_done(dut, value):
    """Drive conv_result+conv_done for one clock; sampled on the next rising edge.

    Set the inputs on a falling edge so they are stable well before the next
    rising edge — avoids any race where the deposit arrives too close to
    posedge for the RTL to capture.
    """
    await FallingEdge(dut.clk)
    dut.conv_result.value = value
    dut.conv_done.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.conv_done.value = 0
    dut.conv_result.value = 0


@cocotb.test()
async def test_below_threshold_clears_detect(dut):
    """Sum below THRESHOLD after 900 pulses -> face_detected stays 0."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.conv_done.value = 0
    dut.conv_result.value = 0
    await Timer(20, unit="ns")

    # 900 small positive values: total = 900 * 100 = 90,000 (< 800,000)
    for _ in range(N_PIXELS):
        await pulse_done(dut, 100)

    # face_detected updates the cycle after count==899 fires
    await RisingEdge(dut.clk)
    assert dut.face_detected.value == 0, (
        f"below-threshold case asserted face_detected: {dut.face_detected.value}"
    )
    dut._log.info("PASS: low-score classification -> face_detected = 0")


@cocotb.test()
async def test_above_threshold_sets_detect(dut):
    """Sum above THRESHOLD after 900 pulses -> face_detected = 1."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.conv_done.value = 0
    dut.conv_result.value = 0
    await Timer(20, unit="ns")

    # 900 * 1000 = 900,000 (> 800,000)
    for _ in range(N_PIXELS):
        await pulse_done(dut, 1000)

    await RisingEdge(dut.clk)
    assert dut.face_detected.value == 1, (
        f"above-threshold case did not assert face_detected: {dut.face_detected.value}"
    )
    dut._log.info("PASS: high-score classification -> face_detected = 1")


@cocotb.test()
async def test_score_out_accumulates(dut):
    """score_out reflects running sum on every conv_done pulse."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.conv_done.value = 0
    dut.conv_result.value = 0
    await Timer(20, unit="ns")

    running = 0
    for v in [10, 20, 30, -5, 100, -50, 200]:
        await pulse_done(dut, v)
        running += v
        actual = dut.score_out.value.signed_integer
        assert actual == running, (
            f"score_out mismatch after adding {v}: got {actual}, expected {running}"
        )
    dut._log.info(f"PASS: score_out accumulator tracks running sum (final={running})")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/classifier.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="classifier",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="classifier",
        test_module="classifier_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
