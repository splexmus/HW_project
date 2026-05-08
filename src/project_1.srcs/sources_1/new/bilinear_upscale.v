`timescale 1ns / 1ps
module bilinear_upscale(
    input clk,

    input [10:0] x,
    input [9:0] y,

    output reg [16:0] addr00,
    output reg [16:0] addr01,
    output reg [16:0] addr10,
    output reg [16:0] addr11,

    input [11:0] p00,
    input [11:0] p01,
    input [11:0] p10,
    input [11:0] p11,

    output reg [11:0] pixel_out
);

reg [8:0] sx;
reg [7:0] sy;

reg [1:0] fx;
reg [1:0] fy;

reg [7:0] r00,r01,r10,r11;
reg [7:0] g00,g01,g10,g11;
reg [7:0] b00,b01,b10,b11;

reg [9:0] top_r,bot_r,final_r;
reg [9:0] top_g,bot_g,final_g;
reg [9:0] top_b,bot_b,final_b;

always @(posedge clk) begin

    // integer source coordinate
    sx <= x >> 2;
    sy <= y >> 2;

    // fractional coordinate
    fx <= x[1:0];
    fy <= y[1:0];

    // neighboring addresses
    addr00 <= sy * 320 + sx;
    addr01 <= sy * 320 + (sx + 1);
    addr10 <= (sy + 1) * 320 + sx;
    addr11 <= (sy + 1) * 320 + (sx + 1);

    // unpack RGB444
    r00 <= {p00[11:8],4'b0};
    r01 <= {p01[11:8],4'b0};
    r10 <= {p10[11:8],4'b0};
    r11 <= {p11[11:8],4'b0};

    g00 <= {p00[7:4],4'b0};
    g01 <= {p01[7:4],4'b0};
    g10 <= {p10[7:4],4'b0};
    g11 <= {p11[7:4],4'b0};

    b00 <= {p00[3:0],4'b0};
    b01 <= {p01[3:0],4'b0};
    b10 <= {p10[3:0],4'b0};
    b11 <= {p11[3:0],4'b0};

    // horizontal interpolation
    top_r <= ((4-fx)*r00 + fx*r01) >> 2;
    bot_r <= ((4-fx)*r10 + fx*r11) >> 2;

    top_g <= ((4-fx)*g00 + fx*g01) >> 2;
    bot_g <= ((4-fx)*g10 + fx*g11) >> 2;

    top_b <= ((4-fx)*b00 + fx*b01) >> 2;
    bot_b <= ((4-fx)*b10 + fx*b11) >> 2;

    // vertical interpolation
    final_r <= ((4-fy)*top_r + fy*bot_r) >> 2;
    final_g <= ((4-fy)*top_g + fy*bot_g) >> 2;
    final_b <= ((4-fy)*top_b + fy*bot_b) >> 2;

    // back to RGB444
    pixel_out <= {
        final_r[7:4],
        final_g[7:4],
        final_b[7:4]
    };
end

endmodule
