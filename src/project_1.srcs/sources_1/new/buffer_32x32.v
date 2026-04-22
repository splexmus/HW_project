`timescale 1ns / 1ps
module buffer_32x32(
    input clk,

    // WRITE (from downscale)
    input we,
    input [9:0] w_addr,     // 0-1023
    input [7:0] w_data,

    // READ (for CNN)
    input [9:0] r_addr,
    output reg [7:0] r_data
);

// 1024 x 8-bit memory
reg [7:0] mem [0:1023];

always @(posedge clk) begin
    // write
    if (we)
        mem[w_addr] <= w_data;

    // read
    r_data <= mem[r_addr];
end

endmodule
