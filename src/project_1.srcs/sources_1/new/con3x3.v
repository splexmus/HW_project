`timescale 1ns / 1ps
module conv3x3(
    input clk,
    input start,

    output reg [9:0] addr,      // read from 32x32 buffer
    input [7:0] pixel,

    output reg done,
    output reg signed [31:0] result
);

// =====================
// KERNEL (trained weights)
// =====================
reg signed [7:0] k [0:8];

initial begin
    k[0] = 32;  k[1] = 16;  k[2] = -18;
    k[3] = 14;   k[4] = -7;   k[5] = -11;
    k[6] = -9;  k[7] = -13;  k[8] = 1;
end

// =====================
// INTERNAL REGISTERS
// =====================
reg [3:0] state = 0;
reg [3:0] idx = 0;

reg signed [31:0] sum = 0;

reg [5:0] x = 0;   // 0..29
reg [5:0] y = 0;   // 0..29

// =====================
// START EDGE DETECT
// =====================
reg start_d = 0;
wire start_pulse;

always @(posedge clk)
    start_d <= start;

assign start_pulse = start & ~start_d;

// =====================
// FSM STATES
// =====================
localparam IDLE = 0,
           ADDR = 1,
           WAIT = 2,
           MAC  = 3,
           DONE = 4;

// =====================
// MAIN FSM
// =====================
always @(posedge clk) begin
    done <= 0;

    case(state)

    // -----------------
    // WAIT FOR START
    // -----------------
    IDLE: begin
        if (start_pulse) begin
            sum <= 0;
            idx <= 0;
            x <= 0;
            y <= 0;
            state <= ADDR;
        end
    end

    // -----------------
    // SET ADDRESS
    // -----------------
    ADDR: begin
        addr <= (y + idx/3)*32 + (x + idx%3);
        state <= WAIT;   // BRAM latency
    end

    // -----------------
    // WAIT 1 CYCLE
    // -----------------
    WAIT: begin
        state <= MAC;
    end

    // -----------------
    // MULTIPLY-ACCUMULATE
    // -----------------
    MAC: begin
        sum <= sum + $signed(pixel) * k[idx];

        if (idx == 8) begin
            state <= DONE;
        end else begin
            idx <= idx + 1;
            state <= ADDR;
        end
    end

    // -----------------
    // OUTPUT RESULT
    // -----------------
    DONE: begin
        result <= sum - 6;
        done <= 1;
    
        if (x < 29) begin
            x <= x + 1;
        end else begin
            x <= 0;
            if (y < 29)
                y <= y + 1;
            else
                y <= 29;   // stay here
        end
    
        idx <= 0;
        sum <= 0;
    
        if (x == 29 && y == 29)
            state <= IDLE;   // ✅ STOP HERE
        else
            state <= ADDR;
    end

    endcase
end

endmodule