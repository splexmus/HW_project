`timescale 1ns / 1ps

// ============================================================
// SIMPLE CNN CLASSIFIER
// ============================================================
//
// Purpose:
// - Accumulate convolution outputs from CNN
// - Compare accumulated score against threshold
// - Decide whether a face is detected
//
// Input:
//   conv_done   : asserted when CNN produces output
//   conv_result : signed CNN convolution value
//
// Output:
//   face_detected : 1 = face detected
//   score_out     : accumulated CNN score
//
// ============================================================

module classifier(

    input clk,

    // asserted when CNN output is valid
    input conv_done,

    // signed convolution result from CNN
    input signed [31:0] conv_result,

    // final face decision
    output reg face_detected,

    // debug score output
    output reg signed [31:0] score_out
);

// ============================================================
// INTERNAL REGISTERS
// ============================================================

// accumulated CNN score
reg signed [31:0] score = 0;

// counts number of convolution outputs processed
reg [9:0] count = 0;

// ============================================================
// FACE DETECTION THRESHOLD
// ============================================================
//
// If accumulated score exceeds this value,
// classifier considers image as a face.
//
// Must be tuned experimentally.
//
// Higher threshold:
//   fewer false positives
//
// Lower threshold:
//   more sensitive detection
//
// ============================================================

parameter THRESHOLD = 800000;

// ============================================================
// MAIN CLASSIFIER LOGIC
// ============================================================

always @(posedge clk) begin

    // ========================================================
    // PROCESS CNN OUTPUT
    // ========================================================

    if (conv_done) begin

        // ====================================================
        // ACCUMULATE CNN SCORE
        // ====================================================
        //
        // Add current convolution result
        // into running total.
        //
        // conv_result may be positive or negative.
        //
        // ====================================================

        score <= score + conv_result;

        // debug output
        score_out <= score + conv_result;

        // ====================================================
        // CHECK IF ALL CNN OUTPUTS PROCESSED
        // ====================================================
        //
        // 900 outputs total:
        //
        // 30 x 30 = 900
        //
        // ====================================================

        if (count == 899) begin

            // ================================================
            // FINAL DECISION
            // ================================================

            if (score > THRESHOLD)
                face_detected <= 1;
            else
                face_detected <= 0;

            // ================================================
            // RESET FOR NEXT FRAME
            // ================================================

            count <= 0;
            score <= 0;

        end
        else begin

            // continue processing
            count <= count + 1;
        end
    end
end

endmodule