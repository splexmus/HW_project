`timescale 1ns / 1ps

// ============================================================
// 1280x960 VGA WITH 4x BILINEAR UPSCALE
// INPUT IMAGE : 320x240
// OUTPUT      : 1280x960
//
// Rotation preserved:
// address = cam_x * 320 + (319 - cam_y)
//
// Designed for Basys3
// ============================================================

module vga_bilinear_1280x960(
    input clk108, // 108 MHz pixel clock

    output reg [3:0] vga_red,
    output reg [3:0] vga_green,
    output reg [3:0] vga_blue,

    output reg vga_hsync,
    output reg vga_vsync,

    output reg [16:0] frame_addr,
    input [11:0] frame_pixel
);

// ============================================================
// 1280x960@60 timing
// pixel clock ≈108MHz
// ============================================================

parameter H_VISIBLE = 1280;
parameter H_FRONT   = 48;
parameter H_SYNC    = 112;
parameter H_BACK    = 248;
parameter H_TOTAL   = 1688;

parameter V_VISIBLE = 960;
parameter V_FRONT   = 1;
parameter V_SYNC    = 3;
parameter V_BACK    = 38;
parameter V_TOTAL   = 1002;

// ============================================================
// COUNTERS
// ============================================================

reg [11:0] hCounter = 0;
reg [10:0] vCounter = 0;

always @(posedge clk108) begin

    if(hCounter == H_TOTAL-1) begin
        hCounter <= 0;

        if(vCounter == V_TOTAL-1)
            vCounter <= 0;
        else
            vCounter <= vCounter + 1;
    end
    else begin
        hCounter <= hCounter + 1;
    end
end

// ============================================================
// SYNC
// ============================================================

always @(posedge clk108) begin

    vga_hsync <= ~(
        hCounter >= (H_VISIBLE + H_FRONT) &&
        hCounter <  (H_VISIBLE + H_FRONT + H_SYNC)
    );

    vga_vsync <= ~(
        vCounter >= (V_VISIBLE + V_FRONT) &&
        vCounter <  (V_VISIBLE + V_FRONT + V_SYNC)
    );
end

// ============================================================
// CORRECT SCALING FOR ROTATED IMAGE
// rotated source = 240x320
// display         = 1280x960
// ============================================================

// 0..239
wire [8:0] src_x = (hCounter * 240) / 1280;

// 0..319
wire [8:0] src_y = (vCounter * 320) / 960;

// fractional part (0..3)
wire [1:0] frac_x = hCounter[1:0];
wire [1:0] frac_y = vCounter[1:0];

// ============================================================
// ROTATION FIX (90 degree)
// OLD:
// address <= cam_x * 320 + (319 - cam_y);
//
// NEW source mapping
// ============================================================

// ============================================================
// ROTATION FIX (90 degree RIGHT)
// ^ becomes >
// ============================================================

wire [8:0] rot_x = src_x;
wire [8:0] rot_y = 319-src_y;

// ============================================================
// ADDRESS PIPELINE
// ============================================================

reg [16:0] addr00;
reg [16:0] addr01;
reg [16:0] addr10;
reg [16:0] addr11;

always @(posedge clk108) begin

    if(hCounter < H_VISIBLE && vCounter < V_VISIBLE) begin

        addr00 <= rot_x * 320 + rot_y;
        addr01 <= rot_x * 320 + (rot_y + 1);

        addr10 <= (rot_x + 1) * 320 + rot_y;
        addr11 <= (rot_x + 1) * 320 + (rot_y + 1);

        frame_addr <= addr00;
    end
    else begin
        frame_addr <= 0;
    end
end

// ============================================================
// PIXEL FETCH
// NOTE:
// single BRAM port approximation
// ============================================================

reg [11:0] p00;
reg [11:0] p01;
reg [11:0] p10;
reg [11:0] p11;

always @(posedge clk108) begin

    p00 <= frame_pixel;
    p01 <= frame_pixel;
    p10 <= frame_pixel;
    p11 <= frame_pixel;
end

// ============================================================
// RGB unpack
// ============================================================

wire [5:0] r00 = {p00[11:8],2'b00};
wire [5:0] g00 = {p00[7:4],2'b00};
wire [5:0] b00 = {p00[3:0],2'b00};

wire [5:0] r01 = {p01[11:8],2'b00};
wire [5:0] g01 = {p01[7:4],2'b00};
wire [5:0] b01 = {p01[3:0],2'b00};

wire [5:0] r10 = {p10[11:8],2'b00};
wire [5:0] g10 = {p10[7:4],2'b00};
wire [5:0] b10 = {p10[3:0],2'b00};

wire [5:0] r11 = {p11[11:8],2'b00};
wire [5:0] g11 = {p11[7:4],2'b00};
wire [5:0] b11 = {p11[3:0],2'b00};

// ============================================================
// BILINEAR
// ============================================================

reg [7:0] r_interp;
reg [7:0] g_interp;
reg [7:0] b_interp;

always @(posedge clk108) begin

    case({frac_y, frac_x})

    // exact
    4'b0000: begin
        r_interp <= r00;
        g_interp <= g00;
        b_interp <= b00;
    end

    // horizontal
    4'b0001,
    4'b0010,
    4'b0011: begin
        r_interp <= ((4-frac_x)*r00 + frac_x*r01) >> 2;
        g_interp <= ((4-frac_x)*g00 + frac_x*g01) >> 2;
        b_interp <= ((4-frac_x)*b00 + frac_x*b01) >> 2;
    end

    // vertical
    4'b0100,
    4'b1000,
    4'b1100: begin
        r_interp <= ((4-frac_y)*r00 + frac_y*r10) >> 2;
        g_interp <= ((4-frac_y)*g00 + frac_y*g10) >> 2;
        b_interp <= ((4-frac_y)*b00 + frac_y*b10) >> 2;
    end

    // full bilinear
    default: begin

        r_interp <= (
            (4-frac_x)*(4-frac_y)*r00 +
            frac_x*(4-frac_y)*r01 +
            (4-frac_x)*frac_y*r10 +
            frac_x*frac_y*r11
        ) >> 4;

        g_interp <= (
            (4-frac_x)*(4-frac_y)*g00 +
            frac_x*(4-frac_y)*g01 +
            (4-frac_x)*frac_y*g10 +
            frac_x*frac_y*g11
        ) >> 4;

        b_interp <= (
            (4-frac_x)*(4-frac_y)*b00 +
            frac_x*(4-frac_y)*b01 +
            (4-frac_x)*frac_y*b10 +
            frac_x*frac_y*b11
        ) >> 4;
    end

    endcase
end

// ============================================================
// VGA OUTPUT
// ============================================================

always @(posedge clk108) begin

    if(hCounter < H_VISIBLE && vCounter < V_VISIBLE) begin

        vga_red   <= r_interp[5:2];
        vga_green <= g_interp[5:2];
        vga_blue  <= b_interp[5:2];
    end
    else begin

        vga_red   <= 0;
        vga_green <= 0;
        vga_blue  <= 0;
    end
end

endmodule