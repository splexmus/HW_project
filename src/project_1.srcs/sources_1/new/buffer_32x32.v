`timescale 1ns / 1ps

// ============================================================
// 32x32 IMAGE BUFFER
// ============================================================
// Stores the downscaled grayscale image for CNN processing.
//
// Memory size:
// 32 x 32 = 1024 pixels
//
// Each pixel:
// 8-bit grayscale
//
// The module supports:
//
// 1. WRITE
//    - From downscale_32x32 module
//    - Stores processed camera image
//
// 2. READ
//    - From CNN module
//    - CNN fetches pixels sequentially
//
// ============================================================

module buffer_32x32(
    input clk,

    // ========================================================
    // WRITE PORT
    // Used by downscale_32x32
    // ========================================================

    input we,                 // write enable
    input [9:0] w_addr,       // write address (0-1023)
    input [7:0] w_data,       // grayscale pixel to store

    // ========================================================
    // READ PORT
    // Used by CNN
    // ========================================================

    input [9:0] r_addr,       // read address
    output reg [7:0] r_data   // output pixel
);

// ============================================================
// MEMORY ARRAY
// ============================================================
// 1024 entries
// each entry = 8 bits
//
// Represents:
//
// mem[y*32 + x]
//
// ============================================================

reg [7:0] mem [0:1023];

// ============================================================
// SYNCHRONOUS READ + WRITE
// ============================================================
// Both operations occur on rising edge of clock.
//
// WRITE:
// If we=1, store incoming pixel.
//
// READ:
// CNN receives pixel from requested address.
//
// ============================================================

always @(posedge clk) begin

    // ========================================================
    // WRITE OPERATION
    // ========================================================
    // Store new pixel into memory
    // ========================================================

    if (we)
        mem[w_addr] <= w_data;

    // ========================================================
    // READ OPERATION
    // ========================================================
    // Output selected pixel for CNN
    // ========================================================

    r_data <= mem[r_addr];
end

endmodule