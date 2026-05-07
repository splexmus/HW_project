module classifier(
    input clk,
    input conv_done,
    input signed [31:0] conv_result,

    output reg face_detected,
    output reg signed [31:0] score_out
);

reg signed [31:0] score = 0;
reg [9:0] count = 0;

parameter THRESHOLD = 800000;

always @(posedge clk) begin

    if (conv_done) begin

        score <= score + conv_result;
        score_out <= score + conv_result;

        if (count == 899) begin

            if (score > THRESHOLD)
                face_detected <= 1;
            else
                face_detected <= 0;

            count <= 0;
            score <= 0;

        end else begin
            count <= count + 1;
        end
    end
end

endmodule