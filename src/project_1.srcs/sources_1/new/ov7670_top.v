`timescale 1ns / 1ps

// ============================================================
// TOP MODULE
// OV7670 Camera + VGA Display + CNN Face Detection
// Board : Basys3
// ============================================================

module ov7670_top(

    // ========================================================
    // SYSTEM CLOCK
    // ========================================================
    input  clk100,          // 100 MHz onboard clock

    // ========================================================
    // OV7670 CAMERA SIGNALS
    // ========================================================
    input  OV7670_VSYNC,    // frame sync
    input  OV7670_HREF,     // line valid
    input  OV7670_PCLK,     // pixel clock from camera

    output OV7670_XCLK,     // external clock to camera
    output OV7670_SIOC,     // SCCB/I2C clock
    inout  OV7670_SIOD,     // SCCB/I2C data

    input [7:0] OV7670_D,   // 8-bit camera pixel bus

    // ========================================================
    // VGA OUTPUT
    // ========================================================
    output[3:0] vga_red,
    output[3:0] vga_green,
    output[3:0] vga_blue,
    output vga_hsync,
    output vga_vsync,

    // ========================================================
    // USER IO
    // ========================================================
    output[3:0] LED,
    input btn,

    output [1:0] Tled,
    output [2:0] Sled,

    output reg [6:0] seg,
    output reg [3:0] an,

    input [11:0] sw,

    // ========================================================
    // CAMERA POWER CONTROL
    // ========================================================
    output pwdn,
    output reset
);

// ============================================================
// FRAME BUFFER SIGNALS
// ============================================================

wire [16:0] frame_addr;     // VGA read address
wire [16:0] capture_addr;   // camera write address

wire capture_we;            // camera write enable

wire [11:0] frame_pixel;    // pixel from framebuffer
wire [11:0] data_16;        // captured pixel

// ============================================================
// CLOCKS
// ============================================================

wire clk25;     // VGA clock
wire clk50;     // Debouncer clock
wire clk;       // ila clock
wire clk24;     // camera XCLK
wire clk108;    // 1280x960 VGA pixel clock

// ============================================================
// CAMERA CAPTURE COORDINATES
// ============================================================

wire [9:0] capture_x;
wire [9:0] capture_y;

// ============================================================
// CNN SIGNALS
// ============================================================

wire [9:0] cnn_addr;
wire [7:0] cnn_pixel;

wire cnn_done;
wire signed [31:0] cnn_result;

wire face_detected;
wire [31:0] score;

// ============================================================
// DOWNSCALE SIGNALS
// ============================================================

wire [7:0] small_data;
wire [9:0] small_addr;
wire small_we;
wire frame_done;

// ============================================================
// MISC
// ============================================================

wire config_finished;
wire resend;

// ============================================================
// CAMERA POWER
// ============================================================

assign pwdn  = 0;   // camera always enabled
assign reset = 1;   // camera not reset

// ============================================================
// CNN START CONTROL
// Start CNN once per completed 32x32 frame
// ============================================================

reg cnn_start = 0;
reg running   = 0;

always @(posedge OV7670_PCLK) begin

    // start CNN after downscale frame complete
    if (frame_done && !running) begin
        cnn_start <= 1;
        running   <= 1;
    end
    else begin
        cnn_start <= 0;
    end

    // CNN finished
    if (cnn_done) begin
        running <= 0;
    end
end

// ============================================================
// STATUS LED
// LED0 lights when camera configured successfully
// ============================================================

assign LED = {3'b0, config_finished};

// ============================================================
// CAMERA CLOCK OUTPUT
// ============================================================

assign OV7670_XCLK = clk24;

// ============================================================
// BUTTON DEBOUNCE
// Used to resend camera configuration
// ============================================================

debounce btn_debounce(
    .clk(clk50),
    .i(btn),
    .o(resend)
);

// ============================================================
// OPTIONAL PIXEL FILTER
// Controlled by switches
// ============================================================

wire [11:0] filtered_pixel;

pixel_filter pf(
    .pixel_in(frame_pixel),
    .sw(sw),
    .pixel_out(filtered_pixel)
);

// ============================================================
// VGA DISPLAY MODULE
// 1280x960 bilinear upscaled display
// ============================================================

vga_bilinear_1280x960 vga_display (

    .clk108(clk108),

    .vga_red(vga_red),
    .vga_green(vga_green),
    .vga_blue(vga_blue),

    .vga_hsync(vga_hsync),
    .vga_vsync(vga_vsync),

    .frame_addr(frame_addr),
    .frame_pixel(filtered_pixel)
);

// ============================================================
// FRAME BUFFER
// Camera writes
// VGA reads
// ============================================================

blk_mem_gen_0 u_frame_buffer(

    // camera write port
    .clka(OV7670_PCLK),
    .wea(capture_we),
    .addra(capture_addr),
    .dina(data_16),

    // VGA read port
    .clkb(clk108),
    .addrb(frame_addr),
    .doutb(frame_pixel)
);

// ============================================================
// DOWNSCALE 320x240 -> 32x32
// Used for CNN input
// ============================================================

downscale_32x32 ds(

    .clk(OV7670_PCLK),

    .we(capture_we),

    .pixel_in(data_16),

    .x(capture_x),
    .y(capture_y),

    .small_data(small_data),
    .small_addr(small_addr),
    .small_we(small_we),

    .frame_done(frame_done)
);

// ============================================================
// CLASSIFIER
// Accumulates CNN scores
// Decides face/non-face
// ============================================================

classifier cls(

    .clk(OV7670_PCLK),

    .conv_done(cnn_done),
    .conv_result(cnn_result),

    .face_detected(face_detected),

    .score_out(score)
);

// ============================================================
// 32x32 CNN INPUT BUFFER
// ============================================================

buffer_32x32 buf32(

    .clk(OV7670_PCLK),

    // write from downscale
    .we(small_we),
    .w_addr(small_addr),
    .w_data(small_data),

    // read by CNN
    .r_addr(cnn_addr),
    .r_data(cnn_pixel)
);

// ============================================================
// CAMERA CAPTURE MODULE
// Converts OV7670 stream into RGB444 framebuffer format
// ============================================================

ov7670_capture capture(

    .pclk(OV7670_PCLK),

    .vsync(OV7670_VSYNC),
    .href(OV7670_HREF),

    .d(OV7670_D),

    .addr(capture_addr),
    .dout(data_16),

    .we(capture_we),

    .x(capture_x),
    .y(capture_y)
);

// ============================================================
// CAMERA SCCB CONFIGURATION
// ============================================================

I2C_AV_Config IIC(

    .iCLK(clk25),

    .iRST_N(!resend),

    .Config_Done(config_finished),

    .I2C_SDAT(OV7670_SIOD),
    .I2C_SCLK(OV7670_SIOC),

    .LUT_INDEX(),
    .I2C_RDATA()
);

// ============================================================
// CLOCK GENERATOR
// ============================================================

clk_wiz_0 clk_div(

    .clk_in1(clk100),

    .clk_out1(clk50),
    .clk_out2(clk25),
    .clk_out3(clk),
    .clk_out4(clk24),
    .clk_out5(clk108)
);

// ============================================================
// ILA DEBUG
// ============================================================

ila_1 ila_cnn (

    .clk(clk),

    .probe0(frame_done),
    .probe1(cnn_start),
    .probe2(cnn_addr),
    .probe3(cnn_pixel),
    .probe4(score),
    .probe5(cnn_done),
    .probe6(score),
    .probe7(running)
);

// ============================================================
// SIMPLE CNN CONVOLUTION ENGINE
// ============================================================

conv3x3 cnn(

    .clk(OV7670_PCLK),

    .start(cnn_start),

    .addr(cnn_addr),
    .pixel(cnn_pixel),

    .done(cnn_done),

    .result(cnn_result)
);

// ============================================================
// FACE STABILITY FILTER
// Prevent flickering detections
// Requires multiple consecutive detections
// ============================================================

reg [5:0] face_count = 0;
reg stable_face = 0;

always @(posedge OV7670_PCLK) begin

    if (cnn_done) begin

        // increase confidence
        if (face_detected) begin

            if (face_count < 20)
                face_count <= face_count + 1;
        end

        // decrease confidence
        else begin

            if (face_count > 0)
                face_count <= face_count - 1;
        end

        // stable detection threshold
        if (face_count > 10)
            stable_face <= 1;
        else
            stable_face <= 0;
    end
end

// ============================================================
// DEBUG LEDS
// ============================================================

// CNN completed
assign Tled[0] = cnn_done;

// stable face detected
assign Tled[1] = stable_face;

// extra status LEDs
assign Sled[0] = stable_face;
assign Sled[1] = running;
assign Sled[2] = cnn_start;

// ============================================================
// 7-SEGMENT DISPLAY
// Show:
// F = face detected
// 0 = no face
// ============================================================

always @(*) begin

    // enable first digit only
    an = 4'b1110;

    if (stable_face) begin

        // display F
        seg = 7'b0001110;
    end
    else begin

        // display 0
        seg = 7'b1000000;
    end
end

endmodule