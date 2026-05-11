import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb_tools.runner import get_runner

# VGA 640x480 @ 60Hz timing constants (from vga_disp.v)
H_MAX       = 800
H_START_SYNC = 656   # 640+16
H_END_SYNC   = 752   # 640+16+96
V_MAX        = 525   # 480+10+2+33
V_START_SYNC = 490   # 480+10
V_END_SYNC   = 492   # 480+10+2


async def count_pulses(signal, n, edge="falling"):
    """Wait for n falling (or rising) edges on signal, return cycle count."""
    count = 0
    trigger = FallingEdge(signal) if edge == "falling" else RisingEdge(signal)
    for _ in range(n):
        await trigger
        count += 1
    return count


@cocotb.test()
async def test_hsync_period(dut):
    """Verify hsync period equals H_MAX (800) pixel clocks."""
    cocotb.start_soon(Clock(dut.clk25, 40, unit="ns").start())   # 25 MHz
    dut.frame_pixel.value = 0xABC

    # Wait for first falling edge of hsync (active-low pulse starts)
    await FallingEdge(dut.vga_hsync)
    start_ns = cocotb.utils.get_sim_time(units="ns")

    await FallingEdge(dut.vga_hsync)
    end_ns = cocotb.utils.get_sim_time(units="ns")

    period_cycles = (end_ns - start_ns) / 40   # 40 ns per pixel clock
    assert abs(period_cycles - H_MAX) < 2, (
        f"hsync period wrong: got {period_cycles:.1f} clocks, expected {H_MAX}"
    )
    dut._log.info(f"PASS: hsync period = {period_cycles:.1f} clocks (expected {H_MAX})")


@cocotb.test()
async def test_hsync_pulse_width(dut):
    """Verify hsync active pulse width is 96 pixel clocks."""
    cocotb.start_soon(Clock(dut.clk25, 40, unit="ns").start())
    dut.frame_pixel.value = 0

    await FallingEdge(dut.vga_hsync)        # pulse starts (active low)
    fall_ns = cocotb.utils.get_sim_time(units="ns")

    await RisingEdge(dut.vga_hsync)         # pulse ends
    rise_ns = cocotb.utils.get_sim_time(units="ns")

    width_cycles = (rise_ns - fall_ns) / 40
    expected = H_END_SYNC - H_START_SYNC    # 96
    assert abs(width_cycles - expected) < 2, (
        f"hsync pulse width: got {width_cycles:.1f}, expected {expected}"
    )
    dut._log.info(f"PASS: hsync pulse width = {width_cycles:.1f} clocks")


@cocotb.test()
async def test_vsync_period(dut):
    """Verify vsync period equals V_MAX * H_MAX pixel clocks (one full frame).

    Note: simulates ~800k cycles — runs slow (~10s). Icarus does not permit
    cocotb writes to internal regs, so we cannot shortcut by forcing vCounter.
    """
    cocotb.start_soon(Clock(dut.clk25, 40, unit="ns").start())
    dut.frame_pixel.value = 0

    await FallingEdge(dut.vga_vsync)
    start_ns = cocotb.utils.get_sim_time(units="ns")

    await FallingEdge(dut.vga_vsync)
    end_ns = cocotb.utils.get_sim_time(units="ns")

    period_cycles = (end_ns - start_ns) / 40
    expected = V_MAX * H_MAX   # 525 * 800 = 420000
    assert abs(period_cycles - expected) < 10, (
        f"vsync period: got {period_cycles:.0f}, expected {expected}"
    )
    dut._log.info(f"PASS: vsync period = {period_cycles:.0f} clocks (expected {expected})")


@cocotb.test()
async def test_blank_region_black(dut):
    """Pixels outside active area (blank=1) must output RGB = 0."""
    cocotb.start_soon(Clock(dut.clk25, 40, unit="ns").start())
    # Feed a non-zero pixel so any bleed-through is visible
    dut.frame_pixel.value = 0xFFF

    # Wait until we're past the active area (after hCounter > 640)
    # Skip one full frame then sample during hsync pulse
    await FallingEdge(dut.vga_hsync)
    await RisingEdge(dut.clk25)

    assert int(dut.vga_red.value) == 0, f"red leaked in blank: {dut.vga_red.value}"
    assert int(dut.vga_green.value) == 0, f"green leaked in blank: {dut.vga_green.value}"
    assert int(dut.vga_blue.value) == 0, f"blue leaked in blank: {dut.vga_blue.value}"
    dut._log.info("PASS: blank region outputs black")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/vga_disp.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="vga",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="vga",
        test_module="vga_disp_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
