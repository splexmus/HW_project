`timescale 1ns / 1ps

// ============================================================
// PIXEL FILTER MODULE
//
// Applies realtime image processing effects
// to RGB444 camera pixels.
//
// Input  : RGB444 pixel
// Output : filtered RGB444 pixel
//
// Controlled by switches:
//
// sw[1:0] = main mode select
// sw[3:2] = sub-mode select
// sw[7:4] = threshold value
//
// ============================================================

module pixel_filter(

    // ========================================================
    // INPUT PIXEL
    // RGB444 format:
    // [11:8] = RED
    // [7:4]  = GREEN
    // [3:0]  = BLUE
    // ========================================================

    input [11:0] pixel_in,

    // ========================================================
    // SWITCH CONTROL
    // ========================================================

    input [11:0] sw,

    // ========================================================
    // OUTPUT FILTERED PIXEL
    // ========================================================

    output reg [11:0] pixel_out
);

// ============================================================
// SPLIT RGB CHANNELS
// ============================================================

wire [3:0] r = pixel_in[11:8];
wire [3:0] g = pixel_in[7:4];
wire [3:0] b = pixel_in[3:0];

// ============================================================
// GRAYSCALE CONVERSION
//
// Weighted grayscale:
//
// gray = 0.3R + 0.6G + 0.1B
//
// Green contributes more because
// human eyes are more sensitive to green.
//
// Result stored as 8-bit temporary value.
// ============================================================

wire [7:0] gray8 = r*3 + g*6 + b;

// Convert back to 4-bit grayscale
wire [3:0] gray = gray8[7:4];

// ============================================================
// THRESHOLD VALUE
// Controlled by switches SW[7:4]
//
// Used in binary threshold mode.
// ============================================================

wire [3:0] thresh = sw[7:4];

// ============================================================
// FILTER LOGIC
// ============================================================

always @(*) begin

    // ========================================================
    // MAIN FILTER MODE
    // sw[1:0]
    // ========================================================

    case (sw[1:0])

        // ====================================================
        // MODE 0 : NORMAL IMAGE
        // ====================================================

        2'b00:
            pixel_out = pixel_in;

        // ====================================================
        // MODE 1 : GRAYSCALE
        // ====================================================

        2'b01:
            pixel_out = {gray, gray, gray};

        // ====================================================
        // MODE 2 : COLOR CHANNEL FILTER
        // sw[3:2] selects channel
        // ====================================================

        2'b10: begin

            case (sw[3:2])

                // RED only
                2'b00:
                    pixel_out = {r, 4'b0, 4'b0};

                // GREEN only
                2'b01:
                    pixel_out = {4'b0, g, 4'b0};

                // BLUE only
                2'b10:
                    pixel_out = {4'b0, 4'b0, b};

                // fallback
                2'b11:
                    pixel_out = pixel_in;

            endcase
        end

        // ====================================================
        // MODE 3 : SPECIAL EFFECTS
        // ====================================================

        2'b11: begin

            case (sw[3:2])

                // ============================================
                // INVERT COLORS
                // ============================================

                2'b00:
                    pixel_out = {~r, ~g, ~b};

                // ============================================
                // THRESHOLD FILTER
                //
                // White if brightness > threshold
                // Black otherwise
                // ============================================

                2'b01: begin

                    if (gray > thresh)
                        pixel_out = 12'hFFF; // white
                    else
                        pixel_out = 12'h000; // black
                end

                // ============================================
                // DEFAULT
                // ============================================

                default:
                    pixel_out = pixel_in;
            endcase
        end

        // ====================================================
        // SAFETY DEFAULT
        // ====================================================

        default:
            pixel_out = pixel_in;
    endcase
end

endmodule