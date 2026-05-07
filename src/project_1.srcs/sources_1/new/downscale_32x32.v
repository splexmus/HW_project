module downscale_32x32(
    input clk,
    input we,
    input [11:0] pixel_in,
    input [9:0] x,
    input [9:0] y,

    output reg [7:0] small_data,
    output reg [9:0] small_addr,
    output reg small_we,
    output reg frame_done
);

// grayscale
wire [3:0] r = pixel_in[11:8];
wire [3:0] g = pixel_in[7:4];
wire [3:0] b = pixel_in[3:0];
wire [7:0] gray =
    ((r*3 + g*6 + b) > 255) ?
    8'd255 :
    (r*3 + g*6 + b);
// coords
reg [5:0] sx = 0;
reg [5:0] sy = 0;

// stretch pulse
reg [4:0] done_cnt = 0;

always @(posedge clk) begin
    small_we <= 0;

    // ===== FRAME DONE PULSE =====
    if (done_cnt != 0) begin
        frame_done <= 1;
        done_cnt <= done_cnt - 1;
    end else begin
        frame_done <= 0;
    end

    if (we) begin
        if (x % 10 == 0 && y % 7 == 0) begin
            small_data <= gray;
            small_addr <= sy * 32 + sx;
            small_we <= 1;

            if (sx < 31)
                sx <= sx + 1;
            else begin
                sx <= 0;
                if (sy < 31)
                    sy <= sy + 1;
                else begin
                    sy <= 0;
                    done_cnt <= 20;  // 🔥 VERY IMPORTANT (long pulse)
                end
            end
        end
    end

    // reset at new frame
    if (x == 0 && y == 0) begin
        sx <= 0;
        sy <= 0;
    end
end

endmodule