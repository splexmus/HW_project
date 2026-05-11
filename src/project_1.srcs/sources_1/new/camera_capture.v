`timescale 1ns / 1ps

// ============================================================
// OV7670 CAMERA CAPTURE MODULE
// ============================================================
// Captures pixel data from OV7670 camera
// and converts RGB565 -> RGB444.
//
// Camera output format:
// RGB565 (16-bit)
//
// FPGA framebuffer format:
// RGB444 (12-bit)
//
// Resolution used:
// 320 x 240
//
// ============================================================

module ov7670_capture(
    input pclk,               // camera pixel clock
    input vsync,              // frame sync
    input href,               // line valid
    input [7:0] d,            // camera data bus

    output [16:0] addr,       // framebuffer address
    output [11:0] dout,       // RGB444 pixel output
    output reg we,            // write enable

    output [9:0] x,           // current x coordinate
    output [9:0] y            // current y coordinate
);

// ============================================================
// INTERNAL REGISTERS
// ============================================================

// stores temporary 16-bit RGB565 pixel
reg [15:0] d_latch = 0;

// final RGB444 output pixel
reg [11:0] dout1 = 0;

// used to detect full pixel arrival
// OV7670 sends:
// byte1 -> byte2
reg [1:0] wr_hold = 0;

// current pixel coordinate
reg [9:0] x_reg = 0;
reg [9:0] y_reg = 0;

// ============================================================
// RGB565 EXTRACTION
// ============================================================
//
// RGB565 format:
//
// [15:11] = Red   (5 bits)
// [10:5 ] = Green (6 bits)
// [4 :0 ] = Blue  (5 bits)
//
// ============================================================

// extract red
wire [4:0] r5 = d_latch[15:11];

// extract green
wire [5:0] g6 = d_latch[10:5];

// extract blue
wire [4:0] b5 = d_latch[4:0];

// ============================================================
// RGB565 -> RGB444 CONVERSION
// ============================================================
//
// Reduce color depth:
//
// Red:   5-bit -> 4-bit
// Green: 6-bit -> 4-bit
// Blue:  5-bit -> 4-bit
//
// ============================================================

wire [3:0] r4 = r5[4:1];
wire [3:0] g4 = g6[5:2];
wire [3:0] b4 = b5[4:1];

// ============================================================
// FRAMEBUFFER ADDRESS
// ============================================================
//
// Convert (x,y) -> linear address
//
// address = y*320 + x
//
// ============================================================

assign addr = y_reg * 320 + x_reg;

// output pixel
assign dout = dout1;

// ============================================================
// MAIN CAPTURE LOGIC
// ============================================================

always @(posedge pclk) begin

    // ========================================================
    // VSYNC = NEW FRAME
    // ========================================================
    // Reset position counters
    // ========================================================

    if (vsync) begin

        x_reg <= 0;
        y_reg <= 0;

        wr_hold <= 0;

        we <= 0;

    end else begin

        // ====================================================
        // LATCH CAMERA DATA
        // ====================================================
        // OV7670 sends 8 bits at a time
        //
        // Two cycles needed:
        //
        // cycle 1 -> upper byte
        // cycle 2 -> lower byte
        //
        // Result:
        // d_latch = full RGB565 pixel
        // ====================================================

        d_latch <= {d_latch[7:0], d};

        // ====================================================
        // PIXEL VALID DETECTION
        // ====================================================
        // href indicates valid line data
        //
        // wr_hold generates write pulse
        // after both bytes received
        // ====================================================

        wr_hold <= {wr_hold[0], (href && !wr_hold[0])};

        // framebuffer write enable
        we <= wr_hold[1];

        // ====================================================
        // WHEN FULL PIXEL RECEIVED
        // ====================================================

        if (wr_hold[1]) begin

            // ================================================
            // RGB444 OUTPUT
            // ================================================

            dout1 <= {r4, g4, b4};

            // ================================================
            // NEXT PIXEL POSITION
            // ================================================

            if (x_reg < 319) begin

                // next pixel in same row
                x_reg <= x_reg + 1;

            end else begin

                // move to next row
                x_reg <= 0;

                if (y_reg < 239)
                    y_reg <= y_reg + 1;
                else
                    y_reg <= 0;
            end
        end
    end
end

// ============================================================
// OUTPUT CURRENT POSITION
// ============================================================

assign x = x_reg;
assign y = y_reg;

endmodule