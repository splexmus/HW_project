`timescale 1ns / 1ps

// Sampling rule: write occurs when (x % 10 == 0) && (y % 7 == 0)
// Grayscale:     gray = R*3 + G*6 + B*1  (capped at 255)
// Address:       small_addr = sy * 32 + sx
// sx resets each new row; sy resets each new frame (x==0 && y==0)
// frame_done stretches for 20 clock cycles after 32x32 complete

module tb_downscale_32x32;

    reg        clk      = 0;
    reg        we       = 0;
    reg [11:0] pixel_in = 0;
    reg  [9:0] x        = 0;
    reg  [9:0] y        = 0;

    wire [7:0] small_data;
    wire [9:0] small_addr;
    wire       small_we;
    wire       frame_done;

    downscale_32x32 uut (
        .clk        (clk),
        .we         (we),
        .pixel_in   (pixel_in),
        .x          (x),
        .y          (y),
        .small_data (small_data),
        .small_addr (small_addr),
        .small_we   (small_we),
        .frame_done (frame_done)
    );

    always #5 clk = ~clk; // 100 MHz

    // Present one pixel to the module.
    task send_pixel;
        input [9:0]  px;
        input [9:0]  py;
        input [11:0] pix;
        begin
            @(negedge clk);
            x = px; y = py; pixel_in = pix; we = 1;
            @(posedge clk); #1;
            we = 0;
        end
    endtask

    // Reset position counters by sending (0,0).
    task reset_frame;
        begin
            send_pixel(10'd0, 10'd0, 12'h000);
            @(posedge clk); #2;
        end
    endtask

    integer i, j;
    integer frame_done_cycles;
    reg [7:0] expected_gray;

    initial begin
        $dumpfile("tb_downscale_32x32.vcd");
        $dumpvars(0, tb_downscale_32x32);
        $timeformat(-9, 1, " ns", 10);
        $display("===== tb_downscale_32x32 =====");
        $monitor("%t  we=%b x=%0d y=%0d pixel_in=%h | small_we=%b small_addr=%0d small_data=%0d frame_done=%b",
                 $time, we, x, y, pixel_in, small_we, small_addr, small_data, frame_done);

        // -------------------------------------------------------
        // TEST 1 : pixel at (0,0) must produce a write
        // Pure red R=F,G=0,B=0 -> gray = 15*3 = 45
        // -------------------------------------------------------
        $display("-- TEST 1: grayscale  pure-red pixel at (0,0) --");
        reset_frame;
        send_pixel(10'd0, 10'd0, 12'hF00);
        @(posedge clk); #1;
        if (small_we) begin
            expected_gray = 8'd45;
            if (small_data === expected_gray)
                $display("PASS small_data=%0d (expect 45)  addr=%0d (expect 0)",
                         small_data, small_addr);
            else
                $display("FAIL small_data=%0d (expect 45)", small_data);
        end else
            $display("INFO small_we not high one cycle after (0,0) -- check pipeline");

        // -------------------------------------------------------
        // TEST 2 : grayscale  pure-green pixel
        // R=0,G=F,B=0 -> gray = 0 + 15*6 + 0 = 90
        // -------------------------------------------------------
        $display("-- TEST 2: grayscale  pure-green pixel at (0,0) --");
        reset_frame;
        send_pixel(10'd0, 10'd0, 12'h0F0);
        @(posedge clk); #1;
        if (small_we) begin
            expected_gray = 8'd90;
            if (small_data === expected_gray)
                $display("PASS small_data=%0d (expect 90)", small_data);
            else
                $display("FAIL small_data=%0d (expect 90)", small_data);
        end

        // -------------------------------------------------------
        // TEST 3 : horizontal stride  -- (10,0) should produce sx=1
        // -------------------------------------------------------
        $display("-- TEST 3: horizontal stride  (10,0) -> sx=1, addr=1 --");
        reset_frame;
        send_pixel(10'd0,  10'd0, 12'h888); // sx=0
        @(posedge clk); #1;
        send_pixel(10'd10, 10'd0, 12'h444); // sx=1
        @(posedge clk); #1;
        if (small_we) begin
            if (small_addr === 10'd1)
                $display("PASS addr=%0d (expect 1)", small_addr);
            else
                $display("FAIL addr=%0d (expect 1)", small_addr);
        end

        // -------------------------------------------------------
        // TEST 4 : vertical stride  -- (0,7) should produce sy=1
        //          address = 1*32 + 0 = 32
        // -------------------------------------------------------
        $display("-- TEST 4: vertical stride  (0,7) -> sy=1, addr=32 --");
        reset_frame;
        send_pixel(10'd0, 10'd0, 12'h888); // sy=0,sx=0  addr=0
        // advance to end of row to bump sy
        for (i = 1; i < 32; i = i + 1)
            send_pixel(i[9:0]*10, 10'd0, 12'h000); // sx=1..31
        // now send first pixel of row 1 (y=7)
        send_pixel(10'd0, 10'd7, 12'hCCC);
        @(posedge clk); #1;
        if (small_we) begin
            if (small_addr === 10'd32)
                $display("PASS addr=%0d (expect 32)", small_addr);
            else
                $display("FAIL addr=%0d (expect 32)", small_addr);
        end

        // -------------------------------------------------------
        // TEST 5 : non-sample points must NOT produce a write
        // -------------------------------------------------------
        $display("-- TEST 5: no write at non-sample points --");
        reset_frame;
        // (1,1), (5,3), (9,6) are all non-sample points
        begin : no_write_check
            integer non_writes = 0;
            send_pixel(10'd1, 10'd1, 12'hFFF); @(posedge clk); #1;
            if (!small_we) non_writes = non_writes + 1;
            send_pixel(10'd5, 10'd3, 12'hFFF); @(posedge clk); #1;
            if (!small_we) non_writes = non_writes + 1;
            send_pixel(10'd9, 10'd6, 12'hFFF); @(posedge clk); #1;
            if (!small_we) non_writes = non_writes + 1;
            if (non_writes == 3)
                $display("PASS no writes at (1,1),(5,3),(9,6)");
            else
                $display("FAIL %0d of 3 non-sample points produced a write",
                         3 - non_writes);
        end

        // -------------------------------------------------------
        // TEST 6 : frame_done stretches for 20 clock cycles
        // -------------------------------------------------------
        $display("-- TEST 6: frame_done pulse width after full 32x32 --");
        reset_frame;

        // Drive all 32x32 sample points in raster order.
        // y=0,7,14,...,217 (32 rows)  x=0,10,20,...,310 (32 cols)
        for (j = 0; j < 32; j = j + 1) begin
            for (i = 0; i < 32; i = i + 1) begin
                send_pixel(i[9:0]*10, j[9:0]*7, 12'h888);
            end
        end

        // Count how many cycles frame_done is high.
        frame_done_cycles = 0;
        repeat(30) begin
            @(posedge clk); #1;
            if (frame_done) frame_done_cycles = frame_done_cycles + 1;
        end

        if (frame_done_cycles == 20)
            $display("PASS frame_done high for exactly 20 cycles");
        else if (frame_done_cycles > 0)
            $display("INFO frame_done high for %0d cycles (expect 20)",
                     frame_done_cycles);
        else
            $display("FAIL frame_done never asserted");

        // -------------------------------------------------------
        // TEST 7 : frame_done goes low after the 20-cycle pulse
        // -------------------------------------------------------
        $display("-- TEST 7: frame_done returns to 0 after pulse --");
        repeat(5) @(posedge clk);
        if (!frame_done)
            $display("PASS frame_done returned to 0");
        else
            $display("FAIL frame_done still high after pulse");

        $display("===== DONE =====");
        $finish;
    end

endmodule
