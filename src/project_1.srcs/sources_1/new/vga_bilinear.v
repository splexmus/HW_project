`timescale 1ns / 1ps

module vga_bilinear(
input clk25,

output reg [3:0] vga_red,
output reg [3:0] vga_green,
output reg [3:0] vga_blue,
output reg vga_hsync,
output reg vga_vsync,

output reg [16:0] frame_addr,
input [11:0] frame_pixel
);

// =====================================================
// 640x480 VGA TIMING
// =====================================================

parameter hRez         = 640;
parameter hStartSync   = 656;
parameter hEndSync     = 752;
parameter hMaxCount    = 800;

parameter vRez         = 480;
parameter vStartSync   = 490;
parameter vEndSync     = 492;
parameter vMaxCount    = 525;

// =====================================================
// COUNTERS
// =====================================================

reg [9:0] hCounter = 0;
reg [9:0] vCounter = 0;

always @(posedge clk25) begin

    if(hCounter == hMaxCount-1) begin

        hCounter <= 0;

        if(vCounter == vMaxCount-1)
            vCounter <= 0;
        else
            vCounter <= vCounter + 1;
    end
    else begin
        hCounter <= hCounter + 1;
    end
end

// =====================================================
// VGA SYNC
// =====================================================

always @(posedge clk25) begin

    vga_hsync <= ~((hCounter >= hStartSync) &&
                   (hCounter <  hEndSync));

    vga_vsync <= ~((vCounter >= vStartSync) &&
                   (vCounter <  vEndSync));
end

// =====================================================
// UPSCALE 320x240 -> 640x480
// ROTATE 90 DEGREE
// =====================================================

wire [8:0] src_x = hCounter >> 1;
wire [7:0] src_y = vCounter >> 1;

wire frac_x = hCounter[0];
wire frac_y = vCounter[0];

// =====================================================
// NEIGHBOR COORDINATES
// =====================================================

wire [8:0] x0 = src_x;
wire [8:0] x1 = src_x + 1;

wire [7:0] y0 = src_y;
wire [7:0] y1 = src_y + 1;

// =====================================================
// MULTICYCLE FSM
// =====================================================

reg [2:0] state = 0;

localparam S_P00  = 0;
localparam S_P01  = 1;
localparam S_P10  = 2;
localparam S_P11  = 3;
localparam S_CALC = 4;

// =====================================================
// PIXEL STORAGE
// =====================================================

reg [11:0] p00;
reg [11:0] p01;
reg [11:0] p10;
reg [11:0] p11;

// =====================================================
// INTERPOLATED RGB
// =====================================================

reg [5:0] r_interp;
reg [5:0] g_interp;
reg [5:0] b_interp;

// =====================================================
// MEMORY FETCH + INTERPOLATION
// =====================================================

always @(posedge clk25) begin

    case(state)

    // =================================================
    // P00
    // =================================================
    S_P00: begin

        // rotate right
        frame_addr <= x0 * 320 + (319 - y0);

        state <= S_P01;
    end

    // =================================================
    // P01
    // =================================================
    S_P01: begin

        p00 <= frame_pixel;

        frame_addr <= x1 * 320 + (319 - y0);

        state <= S_P10;
    end

    // =================================================
    // P10
    // =================================================
    S_P10: begin

        p01 <= frame_pixel;

        frame_addr <= x0 * 320 + (319 - y1);

        state <= S_P11;
    end

    // =================================================
    // P11
    // =================================================
    S_P11: begin

        p10 <= frame_pixel;

        frame_addr <= x1 * 320 + (319 - y1);

        state <= S_CALC;
    end

    // =================================================
    // INTERPOLATION
    // =================================================
    S_CALC: begin

        p11 <= frame_pixel;

        case({frac_y, frac_x})

        // exact
        2'b00: begin

            r_interp <= p00[11:8];
            g_interp <= p00[7:4];
            b_interp <= p00[3:0];
        end

        // horizontal
        2'b01: begin

            r_interp <= (p00[11:8] + p01[11:8]) >> 1;
            g_interp <= (p00[7:4]  + p01[7:4])  >> 1;
            b_interp <= (p00[3:0]  + p01[3:0])  >> 1;
        end

        // vertical
        2'b10: begin

            r_interp <= (p00[11:8] + p10[11:8]) >> 1;
            g_interp <= (p00[7:4]  + p10[7:4])  >> 1;
            b_interp <= (p00[3:0]  + p10[3:0])  >> 1;
        end

        // bilinear
        2'b11: begin

            r_interp <=
                (p00[11:8] + p01[11:8] +
                 p10[11:8] + p11[11:8]) >> 2;

            g_interp <=
                (p00[7:4] + p01[7:4] +
                 p10[7:4] + p11[7:4]) >> 2;

            b_interp <=
                (p00[3:0] + p01[3:0] +
                 p10[3:0] + p11[3:0]) >> 2;
        end

        endcase

        state <= S_P00;
    end

    endcase
end

// =====================================================
// VGA RGB OUTPUT
// =====================================================

always @(posedge clk25) begin

    if(hCounter < 640 && vCounter < 480) begin

        vga_red   <= r_interp[3:0];
        vga_green <= g_interp[3:0];
        vga_blue  <= b_interp[3:0];
    end
    else begin

        vga_red   <= 0;
        vga_green <= 0;
        vga_blue  <= 0;
    end
end

endmodule