module ov7670_capture(
    input pclk,
    input vsync,
    input href,
    input [7:0] d,
    output [16:0] addr,
    output [11:0] dout,
    output reg we,
    output [9:0] x,
    output [9:0] y
);

reg [15:0] d_latch = 0;
reg [11:0] dout1 = 0;
reg [1:0] wr_hold = 0;

// x/y position
reg [9:0] x_reg = 0;
reg [9:0] y_reg = 0;

// ===== CORRECT RGB565 extraction =====
wire [4:0] r5 = d_latch[15:11];
wire [5:0] g6 = d_latch[10:5];
wire [4:0] b5 = d_latch[4:0];

// Convert to 4-bit (RGB444)
wire [3:0] r4 = r5[4:1];
wire [3:0] g4 = g6[5:2];
wire [3:0] b4 = b5[4:1];

assign addr = y_reg * 320 + x_reg;
assign dout = dout1;

always @(posedge pclk) begin
    if (vsync) begin
        x_reg <= 0;
        y_reg <= 0;
        wr_hold <= 0;
        we <= 0;
    end else begin
        // latch 2 bytes → 16-bit pixel
        d_latch <= {d_latch[7:0], d};

        // detect valid pixel
        wr_hold <= {wr_hold[0], (href && !wr_hold[0])};

        we <= wr_hold[1];

        if (wr_hold[1]) begin
            // ✅ FINAL OUTPUT (after correction)
            dout1 <= {r4, g4, b4};

            // increment position
            if (x_reg < 319) begin
                x_reg <= x_reg + 1;
            end else begin
                x_reg <= 0;
                if (y_reg < 239)
                    y_reg <= y_reg + 1;
                else
                    y_reg <= 0;
            end
        end
    end
end
assign x = x_reg;
assign y = y_reg;

endmodule