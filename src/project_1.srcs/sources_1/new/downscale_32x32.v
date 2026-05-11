`timescale 1ns / 1ps

// ============================================================
// DOWNSCALE 320x240 CAMERA IMAGE -> 32x32
// ============================================================
//
// Purpose:
// - Reduce camera frame size for CNN processing
// - Convert RGB444 to grayscale
// - Store result into 32x32 buffer
//
// Input:
//   pixel_in : RGB444 camera pixel
//   x,y      : current camera coordinate
//   we       : pixel valid signal
//
// Output:
//   small_data : grayscale output pixel
//   small_addr : address inside 32x32 memory
//   small_we   : write enable for 32x32 memory
//   frame_done : pulse when 32x32 image finished
//
// ============================================================

module downscale_32x32(

    input clk,

    // pixel valid
    input we,

    // RGB444 pixel from camera/framebuffer
    input [11:0] pixel_in,

    // current camera coordinate
    input [9:0] x,
    input [9:0] y,

    // output grayscale pixel
    output reg [7:0] small_data,

    // address inside 32x32 memory
    output reg [9:0] small_addr,

    // write enable for 32x32 memory
    output reg small_we,

    // asserted when full 32x32 image ready
    output reg frame_done
);

// ============================================================
// RGB444 -> GRAYSCALE
// ============================================================
//
// RGB444:
//   R = [11:8]
//   G = [7:4]
//   B = [3:0]
//
// Weighted grayscale:
//
// gray = 0.3R + 0.6G + 0.1B
//
// Approximated using integer math:
//
// gray = r*3 + g*6 + b
//
// Green contributes more because
// human eyes are most sensitive to green.
//
// ============================================================

wire [3:0] r = pixel_in[11:8];
wire [3:0] g = pixel_in[7:4];
wire [3:0] b = pixel_in[3:0];

// grayscale output

wire [7:0] gray =
    ((r*3 + g*6 + b) > 255) ?
    8'd255 :
    (r*3 + g*6 + b);

// ============================================================
// 32x32 OUTPUT COORDINATES
// ============================================================
//
// sx = x coordinate inside 32x32 image
// sy = y coordinate inside 32x32 image
//
// ============================================================

reg [5:0] sx = 0;
reg [5:0] sy = 0;

// ============================================================
// FRAME DONE PULSE EXTENDER
// ============================================================
//
// CNN may miss a 1-clock pulse.
//
// So when frame completes,
// stretch frame_done for multiple cycles.
//
// ============================================================

reg [4:0] done_cnt = 0;

// ============================================================
// MAIN LOGIC
// ============================================================

always @(posedge clk) begin

    // default
    small_we <= 0;

    // ========================================================
    // FRAME DONE PULSE GENERATION
    // ========================================================

    if (done_cnt != 0) begin

        // keep frame_done high
        frame_done <= 1;

        // countdown
        done_cnt <= done_cnt - 1;

    end
    else begin

        frame_done <= 0;
    end

    // ========================================================
    // PROCESS VALID CAMERA PIXELS
    // ========================================================

    if (we) begin

        // ====================================================
        // DOWNSAMPLING
        // ====================================================
        //
        // Take one pixel every:
        //
        // horizontal : 10 pixels
        // vertical   : 7 pixels
        //
        // 320/10 ≈ 32
        // 240/7  ≈ 34
        //
        // close enough for 32x32 CNN input
        //
        // ====================================================

        if (x % 10 == 0 && y % 7 == 0) begin

            // grayscale pixel output
            small_data <= gray;

            // linear memory address
            // address = row*32 + col
            small_addr <= sy * 32 + sx;

            // write enable
            small_we <= 1;

            // =================================================
            // ADVANCE X POSITION
            // =================================================

            if (sx < 31)
                sx <= sx + 1;

            // =================================================
            // NEXT ROW
            // =================================================

            else begin

                sx <= 0;

                if (sy < 31)
                    sy <= sy + 1;

                // =============================================
                // FULL 32x32 FRAME COMPLETE
                // =============================================

                else begin

                    sy <= 0;

                    // stretch frame_done pulse
                    done_cnt <= 20;
                end
            end
        end
    end

    // ========================================================
    // RESET POSITION AT START OF NEW CAMERA FRAME
    // ========================================================

    if (x == 0 && y == 0) begin

        sx <= 0;
        sy <= 0;
    end
end

endmodule