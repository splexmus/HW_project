`timescale 1ns / 1ps

// ============================================================
// 3x3 CONVOLUTION ENGINE
// ============================================================
// This module performs a 3x3 convolution on a 32x32 image.
//
// Input image:
//   - Stored in external BRAM / buffer
//   - Accessed through addr + pixel
//
// Output:
//   - One convolution result per 3x3 window
//   - Total outputs = 30 x 30 = 900
//
// Operation:
//   1. Read 9 pixels
//   2. Multiply with kernel weights
//   3. Accumulate result
//   4. Output convolution value
//
// Used for:
//   CNN face detection preprocessing
// ============================================================

module conv3x3(
    input clk,
    input start,

    // address to read pixel from 32x32 buffer
    output reg [9:0] addr,

    // pixel data from buffer
    input [7:0] pixel,

    // asserted when one convolution result is ready
    output reg done,

    // convolution output value
    output reg signed [31:0] result
);

// ============================================================
// 3x3 KERNEL WEIGHTS
// ============================================================
// These are trained CNN filter weights
//
// Kernel layout:
//
// k[0] k[1] k[2]
// k[3] k[4] k[5]
// k[6] k[7] k[8]
//
// ============================================================

reg signed [7:0] k [0:8];

initial begin
    k[0] =  32;
    k[1] =  16;
    k[2] = -18;

    k[3] =  14;
    k[4] =  -7;
    k[5] = -11;

    k[6] =  -9;
    k[7] = -13;
    k[8] =   1;
end

// ============================================================
// INTERNAL REGISTERS
// ============================================================

// extend done pulse so other modules can detect it
reg [4:0] done_hold = 0;

// FSM state
reg [3:0] state = 0;

// current kernel index (0..8)
reg [3:0] idx = 0;

// accumulation sum
reg signed [31:0] sum = 0;

// current top-left coordinate of 3x3 window
// valid range:
// x = 0..29
// y = 0..29
//
// because:
// 32 - 3 + 1 = 30
//
reg [5:0] x = 0;
reg [5:0] y = 0;

// ============================================================
// START EDGE DETECTOR
// ============================================================
// Converts start signal into 1-cycle pulse
// ============================================================

reg start_d = 0;

wire start_pulse;

always @(posedge clk)
    start_d <= start;

assign start_pulse = start & ~start_d;

// ============================================================
// FSM STATES
// ============================================================

localparam IDLE = 0,
           ADDR = 1,
           WAIT = 2,
           MAC  = 3,
           DONE = 4;

// ============================================================
// MAIN FSM
// ============================================================

always @(posedge clk) begin

    // default
    done <= 0;

    // ========================================================
    // EXTEND done SIGNAL
    // ========================================================
    // Makes done visible longer
    // ========================================================

    if (done_hold != 0) begin
        done <= 1;
        done_hold <= done_hold - 1;
    end
    else begin
        done <= 0;
    end

    // ========================================================
    // FSM
    // ========================================================

    case(state)

    // ========================================================
    // IDLE STATE
    // Wait for start pulse
    // ========================================================

    IDLE: begin

        if (start_pulse) begin

            // reset convolution state
            sum <= 0;

            idx <= 0;

            x <= 0;
            y <= 0;

            // begin reading first pixel
            state <= ADDR;
        end
    end

    // ========================================================
    // ADDR STATE
    // Generate BRAM address for current kernel pixel
    // ========================================================
    //
    // Address formula:
    //
    // row = y + idx/3
    // col = x + idx%3
    //
    // Example:
    // idx = 0 -> top-left
    // idx = 4 -> center
    // idx = 8 -> bottom-right
    //
    // ========================================================

    ADDR: begin

        addr <= (y + idx/3) * 32 + (x + idx%3);

        // wait for BRAM output latency
        state <= WAIT;
    end

    // ========================================================
    // WAIT STATE
    // BRAM latency wait
    // ========================================================

    WAIT: begin
        state <= MAC;
    end

    // ========================================================
    // MAC STATE
    // Multiply and accumulate
    // ========================================================

    MAC: begin

        // sum += pixel * kernel_weight
        sum <= sum + $signed(pixel) * k[idx];

        // finished all 9 kernel elements?
        if (idx == 8) begin
            state <= DONE;
        end
        else begin

            // next kernel position
            idx <= idx + 1;

            // fetch next pixel
            state <= ADDR;
        end
    end

    // ========================================================
    // DONE STATE
    // Output one convolution result
    // ========================================================

    DONE: begin

        // optional bias
        result <= sum - 6;

        // pulse done
        done <= 1;

        // extend done pulse
        done_hold <= 15;

        // ====================================================
        // Move to next convolution window
        // ====================================================

        if (x < 29) begin

            // next column
            x <= x + 1;
        end
        else begin

            // next row
            x <= 0;

            if (y < 29)
                y <= y + 1;
        end

        // reset for next convolution
        idx <= 0;
        sum <= 0;

        // ====================================================
        // Finish after 30x30 outputs
        // ====================================================

        if (x == 29 && y == 29)
            state <= IDLE;   // stop
        else
            state <= ADDR;   // continue next window
    end

    endcase
end

endmodule