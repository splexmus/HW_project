`timescale 1ns / 1ps

// THRESHOLD inside classifier = 800000
// 900 results per frame (30x30 output map)

module tb_classifier;

    reg        clk          = 0;
    reg        conv_done    = 0;
    reg signed [31:0] conv_result = 0;
    wire       face_detected;
    wire signed [31:0] score_out;

    classifier uut (
        .clk           (clk),
        .conv_done     (conv_done),
        .conv_result   (conv_result),
        .face_detected (face_detected),
        .score_out     (score_out)
    );

    always #5 clk = ~clk; // 100 MHz

    // Send a single convolution result.
    task send_result;
        input signed [31:0] val;
        begin
            @(negedge clk);
            conv_result = val; conv_done = 1;
            @(posedge clk); #1;
            conv_done = 0;
        end
    endtask

    // Send a complete 900-result frame with the same value each time.
    task send_frame;
        input signed [31:0] per_result;
        integer j;
        begin
            for (j = 0; j < 900; j = j + 1)
                send_result(per_result);
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("tb_classifier.vcd");
        $dumpvars(0, tb_classifier);
        $timeformat(-9, 1, " ns", 10);
        $display("===== tb_classifier =====");
        $display("THRESHOLD = 800000,  frame size = 900 results");
        $monitor("%t  conv_done=%b conv_result=%0d | score_out=%0d face_detected=%b",
                 $time, conv_done, conv_result, score_out, face_detected);

        // -------------------------------------------------------
        // TEST 1 : below threshold  (900 * 888 = 799200 < 800000)
        // -------------------------------------------------------
        $display("-- TEST 1: below threshold -> no face --");
        send_frame(32'd888);
        if (face_detected === 1'b0)
            $display("PASS no face: score=%0d  face_detected=%0d",
                     score_out, face_detected);
        else
            $display("FAIL expected no face, got face_detected=%0d", face_detected);

        // -------------------------------------------------------
        // TEST 2 : above threshold  (900 * 890 = 801000 > 800000)
        // -------------------------------------------------------
        $display("-- TEST 2: above threshold -> face --");
        send_frame(32'd890);
        if (face_detected === 1'b1)
            $display("PASS face: score=%0d  face_detected=%0d",
                     score_out, face_detected);
        else
            $display("FAIL expected face, got face_detected=%0d", face_detected);

        // -------------------------------------------------------
        // TEST 3 : auto-reset -- zero frame must give 0 score
        // -------------------------------------------------------
        $display("-- TEST 3: auto-reset after frame --");
        send_frame(32'd0);
        if (face_detected === 1'b0)
            $display("PASS reset: zero frame -> no face, score=%0d", score_out);
        else
            $display("FAIL reset not working, face_detected=%0d", face_detected);

        // -------------------------------------------------------
        // TEST 4 : mixed positive/negative
        //   450 * (+2000) + 450 * (-1000) = 900 000 - 450 000 = 450 000 < 800000
        // -------------------------------------------------------
        $display("-- TEST 4: mixed pos/neg (total=450000 < 800000) --");
        begin : mixed
            integer k;
            for (k = 0; k < 450; k = k + 1) send_result(32'd2000);
            for (k = 0; k < 450; k = k + 1) send_result(-32'd1000);
            @(posedge clk); #1;
        end
        if (face_detected === 1'b0)
            $display("PASS mixed: no face (450000 < 800000)");
        else
            $display("FAIL mixed: unexpected face_detected=%0d", face_detected);

        // -------------------------------------------------------
        // TEST 5 : boundary -- 900 * 889 = 800100 > 800000 -> face
        // -------------------------------------------------------
        $display("-- TEST 5: boundary (900*889=800100 > 800000) --");
        send_frame(32'd889);
        if (face_detected === 1'b1)
            $display("PASS boundary: face (800100 > 800000)");
        else
            $display("FAIL boundary: expected face, got %0d", face_detected);

        // -------------------------------------------------------
        // TEST 6 : two consecutive frames, decision flips each time
        // -------------------------------------------------------
        $display("-- TEST 6: two consecutive frames --");
        send_frame(32'd890); // above -> face
        $display("  Frame A: face_detected=%0d (expect 1)", face_detected);
        send_frame(32'd888); // below -> no face
        $display("  Frame B: face_detected=%0d (expect 0)", face_detected);
        if (face_detected === 1'b0)
            $display("PASS consecutive frames flip correctly");
        else
            $display("FAIL consecutive frames did not flip");

        $display("===== DONE =====");
        $finish;
    end

endmodule
