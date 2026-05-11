# How to run the testbenches

All testbenches use [cocotb](https://docs.cocotb.org/) with [Icarus Verilog](http://iverilog.icarus.com/) as the simulator. They live in this directory and are self-contained — each `*_tb.py` builds its DUT, runs its tests, and writes an FST waveform under `sim_build/`.

## Prerequisites

- Icarus Verilog on `PATH` (`iverilog --version` should work).
- Python environment named `cocotb` with `cocotb` and `cocotb_tools` installed.

## Running

```powershell
conda activate cocotb
cd testbench
python <name>_tb.py
```

Each script builds + runs. Waveforms land in `sim_build/<top>.fst` and the test report in `sim_build/results.xml`.

## Testbench summary

| Testbench | Tests | Time | Coverage |
|---|---|---|---|
| [debounce_tb.py](debounce_tb.py) | 1/1 | ~1s | Short-glitch rejection (100-cycle burst, output stays 0) |
| [con3x3_tb.py](con3x3_tb.py) | 1/1 | ~1s | First-pixel 3x3 convolution result vs Python reference |
| [bilinear_upscale_tb.py](bilinear_upscale_tb.py) | 4/4 | ~1s | fx=0/fy=0 (no interp), fx=2/fy=0 (half-step), fx=2/fy=2 (center), uniform-pixel sweep over all fx,fy |
| [camera_capture_tb.py](camera_capture_tb.py) | 4/4 | ~1s | vsync resets x/y/we, single RGB565 pixel write, x increments per pixel, addr = y*320 + x |
| [sccb_sender_tb.py](sccb_sender_tb.py) | 2/2 | ~1s | Full 3-byte I2C write with ACK, reset mid-transaction |
| [vga_disp_tb.py](vga_disp_tb.py) | 4/4 | ~46s | hsync period (800 clk), hsync pulse width (96 clk), vsync period (one full frame, slow), blank region outputs black |

Total: **16/16 PASS, ~50s**. The vga `test_vsync_period` dominates because it simulates two full VGA frames (~812k pixel-clock cycles).

## Ready-to-paste commands

Run from the repo root in PowerShell. Each line activates the env, cds into `testbench/`, and runs one testbench.

```powershell
# debounce        (~1s)
conda activate cocotb; cd testbench; python debounce_tb.py

# con3x3          (~1s)
conda activate cocotb; cd testbench; python con3x3_tb.py

# bilinear_upscale (~1s)
conda activate cocotb; cd testbench; python bilinear_upscale_tb.py

# camera_capture  (~1s)
conda activate cocotb; cd testbench; python camera_capture_tb.py

# sccb_sender     (~1s)
conda activate cocotb; cd testbench; python sccb_sender_tb.py

# vga_disp        (~46s)
conda activate cocotb; cd testbench; python vga_disp_tb.py
```

Run all six sequentially:

```powershell
conda activate cocotb; cd testbench; foreach ($tb in 'debounce_tb','con3x3_tb','bilinear_upscale_tb','camera_capture_tb','sccb_sender_tb','vga_disp_tb') { Write-Host "=== $tb ==="; python "$tb.py" }
```

## View waveforms (GTKWave)

Each run writes its FST to `testbench/sim_build/<top>.fst`. The FST `<top>` matches the `hdl_toplevel` set inside each testbench, **not** the testbench filename.

Run these from inside `testbench/` (same directory you ran the testbench from):

```powershell
gtkwave sim_build\debounce.fst
gtkwave sim_build\conv3x3.fst
gtkwave sim_build\bilinear_upscale.fst
gtkwave sim_build\ov7670_capture.fst
gtkwave sim_build\I2C_Controller.fst
gtkwave sim_build\vga.fst
```

From the repo root, prefix with `testbench\` (e.g. `gtkwave testbench\sim_build\debounce.fst`).
