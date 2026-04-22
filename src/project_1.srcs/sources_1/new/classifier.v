module classifier(
    input clk,
    input conv_done,
    input signed [31:0] conv_result,
    output reg face_detected,
    output reg signed [31:0] score_out
);

reg signed [31:0] score = 0;
reg [9:0] count = 0;

parameter THRESHOLD = 500;

always @(posedge clk) begin
    score_out <= score;

    if (conv_done) begin
        score <= score + conv_result;

        if (count == 899) begin   // ✅ FIX (0-899 = 900 pixels)
            face_detected <= (score > THRESHOLD);
            score <= 0;
            count <= 0;
        end else begin
            count <= count + 1;
        end
    end
end

endmodule