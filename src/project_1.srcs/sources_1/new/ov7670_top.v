`timescale 1ns / 1ps


module ov7670_top(
input  clk100,
input  OV7670_VSYNC, 
input  OV7670_HREF,  
input  OV7670_PCLK,  
output OV7670_XCLK,  
output OV7670_SIOC, 
inout  OV7670_SIOD,
input [7:0] OV7670_D, 

output[3:0] LED,
output[3:0] vga_red,
output[3:0] vga_green,
output[3:0] vga_blue,
output vga_hsync, 
output vga_vsync, 
input btn,
output pwdn,
output reset,
input [11:0] sw,
output [1:0] Tled,
output [2:0] Sled,
output reg [6:0] seg,
output reg [3:0] an
);
wire [16:0] frame_addr;
wire [16:0] capture_addr;   
wire  capture_we;  
wire  config_finished;  
wire  clk25; 
wire  clk50;
wire  clk;
wire  clk24;
wire  clk108;     
wire  resend;        
wire [11:0] frame_pixel;  
wire [11:0]  data_16;
wire [9:0] capture_x;
wire [9:0] capture_y;


wire [9:0] cnn_addr;
wire [7:0] cnn_pixel;
wire cnn_done;
wire signed [31:0] cnn_result;
wire [7:0] small_data;
wire [9:0] small_addr;
wire small_we;
wire frame_done;
wire face_detected;
wire [31:0] score;
  
assign pwdn = 0; 
assign reset = 1;
  
reg cnn_start = 0;
reg running = 0;

always @(posedge OV7670_PCLK) begin
    if (frame_done && !running) begin
        cnn_start <= 1;
        running <= 1;
    end
    else begin
        cnn_start <= 0;
    end

    if (cnn_done) begin
        running <= 0;
    end
end

assign LED = {3'b0,config_finished};
assign  	OV7670_XCLK = clk24;  
debounce   btn_debounce(
		.clk(clk50),
		.i(btn),
		.o(resend)
);
 
wire [11:0] filtered_pixel;

pixel_filter pf(
    .pixel_in(frame_pixel),
    .sw(sw),
    .pixel_out(filtered_pixel)
);

vga_bilinear_1280x960   vga_display (
		.clk108       (clk108),
		.vga_red    (vga_red),
		.vga_green   (vga_green),
		.vga_blue    (vga_blue),
		.vga_hsync   (vga_hsync),
		.vga_vsync  (vga_vsync),
		//.HCnt       (),
		//.VCnt       (),

		.frame_addr   (frame_addr),
		.frame_pixel  (filtered_pixel)//replace with frame_pixel
 );
 
 blk_mem_gen_0 u_frame_buffer(
		.clka (OV7670_PCLK),
		.wea  (capture_we),
		.addra (capture_addr),
		.dina  (data_16),

		.clkb   (clk108),//clk25
		.addrb (frame_addr),
		.doutb (frame_pixel)
 );

downscale_32x32 ds(
    .clk(OV7670_PCLK),
    .we(capture_we),
    .pixel_in(data_16),
    .x(capture_x),
    .y(capture_y),

    .small_data(small_data),
    .small_addr(small_addr),
    .small_we(small_we),
    .frame_done(frame_done)   // FIX
);

classifier cls(
    .clk(OV7670_PCLK),
    .conv_done(cnn_done),
    .conv_result(cnn_result),
    .face_detected(face_detected),
    .score_out(score)
);

buffer_32x32 buf32(
    .clk(OV7670_PCLK),

    // write from downscale
    .we(small_we),
    .w_addr(small_addr),
    .w_data(small_data),

    // read for CNN
    .r_addr(cnn_addr),
    .r_data(cnn_pixel)
);

 ov7670_capture capture(         //����ov7670����ͷ����
 		.pclk  (OV7670_PCLK),    //�������ʱ��
 		.vsync (OV7670_VSYNC),   //��ͬ��
 		.href  (OV7670_HREF),    //��ֱͬ�� 
 		.d     ( OV7670_D),      //ͼ���������
 		.addr  (capture_addr),   //�洢��ĵ�ַ
 		.dout (data_16),         //12λ�������
 		.we   (capture_we),
 		.x     (capture_x),   // ✅ NEW
        .y     (capture_y)
 	);
 
I2C_AV_Config IIC(                 //����ͷSCCBЭ���ʵ��
 		.iCLK   ( clk25),          //����25MHzʱ��
 		.iRST_N (! resend),        //��λ
 		.Config_Done ( config_finished),    //��ov7670�ļĴ�������������ɺ󣬷���config_finished�ź�
 		.I2C_SDAT  ( OV7670_SIOD),   //�������� 
 		.I2C_SCLK  ( OV7670_SIOC),   //����ʱ������
 		.LUT_INDEX (),
 		.I2C_RDATA ()
 		);
		
clk_wiz_0 clk_div(
		.clk_in1 (clk100),
		.clk_out1 (clk50),
		.clk_out2 (clk25),
		.clk_out3 (clk),
		.clk_out4 (clk24),
		.clk_out5 (clk108)
);


reg [9:0] dbg_addr;
reg [7:0] dbg_pixel;
reg signed [31:0] dbg_result;
reg dbg_done;
reg dbg_frame;

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

conv3x3 cnn(
    .clk(OV7670_PCLK),
    .start(cnn_start),
    .addr(cnn_addr),
    .pixel(cnn_pixel),
    .done(cnn_done),
    .result(cnn_result)
);

// ==========================================
// FACE STABILITY DETECTOR
// ==========================================

reg [5:0] face_count = 0;
reg stable_face = 0;

always @(posedge OV7670_PCLK) begin

    if (cnn_done) begin

        // require several consecutive detections
        if (face_detected) begin
            if (face_count < 20)
                face_count <= face_count + 1;
        end
        else begin
            if (face_count > 0)
                face_count <= face_count - 1;
        end

        // stable decision
        if (face_count > 10)
            stable_face <= 1;
        else
            stable_face <= 0;

    end
end


// ==========================================
// LEDs
// ==========================================

assign Tled[0] = cnn_done;
assign Tled[1] = stable_face;

assign Sled[0] = stable_face;
assign Sled[1] = running;
assign Sled[2] = cnn_start;


// ==========================================
// 7-SEGMENT DISPLAY
// Basys3 common-anode
// ==========================================

always @(*) begin

    // enable only first digit
    an = 4'b1110;

    if (stable_face) begin
        // show "F"
        seg = 7'b0001110;
    end
    else begin
        // show "0"
        seg = 7'b1000000;
    end
end

endmodule