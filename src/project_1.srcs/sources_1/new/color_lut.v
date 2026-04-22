module color_lut(
    input  [3:0] r_in,
    input  [3:0] g_in,
    input  [3:0] b_in,

    output reg [3:0] r_out,
    output reg [3:0] g_out,
    output reg [3:0] b_out
);

always @(*) begin
    // 🔴 Red boost slightly
    case (r_in)
        4'h0: r_out = 4'h0;
        4'h1: r_out = 4'h1;
        4'h2: r_out = 4'h2;
        4'h3: r_out = 4'h3;
        4'h4: r_out = 4'h4;
        4'h5: r_out = 4'h5;
        4'h6: r_out = 4'h6;
        4'h7: r_out = 4'h8; // boost
        4'h8: r_out = 4'h9;
        4'h9: r_out = 4'hA;
        default: r_out = r_in;
    endcase

    // 🟢 Green reduce slightly (fix OV7670 green tint)
    g_out = (g_in > 4'h8) ? (g_in - 1) : g_in;

    // 🔵 Blue boost slightly
    b_out = (b_in < 4'h6) ? (b_in - 1) : b_in;
    //b_out = (b_in > 4'h3) ? (b_in - 3) : b_in;
end

endmodule