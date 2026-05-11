`timescale 1ns / 1ps

module tb_buffer_32x32;

    reg        clk    = 0;
    reg        we     = 0;
    reg  [9:0] w_addr = 0;
    reg  [7:0] w_data = 0;
    reg  [9:0] r_addr = 0;
    wire [7:0] r_data;

    buffer_32x32 uut (
        .clk    (clk),
        .we     (we),
        .w_addr (w_addr),
        .w_data (w_data),
        .r_addr (r_addr),
        .r_data (r_data)
    );

    always #5 clk = ~clk; // 100 MHz

    // Write one pixel and return.
    task write_pixel;
        input [9:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            w_addr = addr; w_data = data; we = 1;
            @(posedge clk); #1;
            we = 0;
        end
    endtask

    // Issue a read and check the result on the next rising edge.
    task read_check;
        input [9:0]  addr;
        input [7:0]  expected;
        input [63:0] label;
        begin
            @(negedge clk);
            r_addr = addr;
            @(posedge clk); #1; // registered read: data appears one cycle later
            @(posedge clk); #1;
            if (r_data === expected)
                $display("PASS [%s] addr=%0d  data=%0d", label, addr, r_data);
            else
                $display("FAIL [%s] addr=%0d  got=%0d  expected=%0d",
                         label, addr, r_data, expected);
        end
    endtask

    integer i;
    integer fail_cnt;

    initial begin
        $dumpfile("tb_buffer_32x32.vcd");
        $dumpvars(0, tb_buffer_32x32);
        $timeformat(-9, 1, " ns", 10);
        $display("===== tb_buffer_32x32 =====");
        $monitor("%t  we=%b w_addr=%0d w_data=%0d | r_addr=%0d r_data=%0d",
                 $time, we, w_addr, w_data, r_addr, r_data);

        // -------------------------------------------------------
        // TEST 1 : single write then read back
        // -------------------------------------------------------
        $display("-- TEST 1: single write/read --");
        write_pixel(10'd0, 8'd42);
        read_check (10'd0, 8'd42, "single");

        // -------------------------------------------------------
        // TEST 2 : boundary addresses (0 and 1023)
        // -------------------------------------------------------
        $display("-- TEST 2: boundary addresses --");
        write_pixel(10'd0,    8'd10);
        write_pixel(10'd1023, 8'd255);
        read_check (10'd0,    8'd10,  "boundary_lo");
        read_check (10'd1023, 8'd255, "boundary_hi");

        // -------------------------------------------------------
        // TEST 3 : fill all 1024 locations, read back pattern
        // -------------------------------------------------------
        $display("-- TEST 3: full memory fill (1024 pixels) --");
        for (i = 0; i < 1024; i = i + 1) begin
            @(negedge clk);
            w_addr = i[9:0];
            w_data = i[7:0]; // lower 8 bits as data pattern
            we = 1;
            @(posedge clk); #1;
        end
        we = 0;

        fail_cnt = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            @(negedge clk);
            r_addr = i[9:0];
            @(posedge clk); #1;
            @(posedge clk); #1;
            if (r_data !== i[7:0]) begin
                $display("FAIL full_fill addr=%0d  got=%0d  expected=%0d",
                         i, r_data, i[7:0]);
                fail_cnt = fail_cnt + 1;
            end
        end
        if (fail_cnt == 0)
            $display("PASS full memory fill: all 1024 locations verified");
        else
            $display("FAIL full memory fill: %0d mismatches", fail_cnt);

        // -------------------------------------------------------
        // TEST 4 : read without new write returns old value
        // -------------------------------------------------------
        $display("-- TEST 4: read without write retains value --");
        // addr 5 was written with 5 during TEST 3
        @(negedge clk); r_addr = 10'd5;
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (r_data === 8'd5)
            $display("PASS retained: addr 5 = %0d", r_data);
        else
            $display("FAIL retained: addr 5 = %0d (expected 5)", r_data);

        // -------------------------------------------------------
        // TEST 5 : simultaneous write to one address, read another
        // -------------------------------------------------------
        $display("-- TEST 5: simultaneous read+write different addresses --");
        write_pixel(10'd100, 8'd99);
        @(negedge clk);
        w_addr = 10'd200; w_data = 8'd77; we = 1;
        r_addr = 10'd100;
        @(posedge clk); #1;
        we = 0;
        @(posedge clk); #1;
        if (r_data === 8'd99)
            $display("PASS simultaneous: read addr 100 = %0d  write addr 200 = 77",
                     r_data);
        else
            $display("FAIL simultaneous: read addr 100 = %0d (expected 99)", r_data);

        // verify addr 200 was actually written
        read_check(10'd200, 8'd77, "sim_write_200");

        $display("===== DONE =====");
        $finish;
    end

endmodule
