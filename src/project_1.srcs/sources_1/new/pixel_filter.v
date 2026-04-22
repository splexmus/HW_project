module pixel_filter(
    input [11:0] pixel_in,     // RGB444
    input [11:0] sw,
    output reg [11:0] pixel_out
);

wire [3:0] r = pixel_in[11:8];
wire [3:0] g = pixel_in[7:4];
wire [3:0] b = pixel_in[3:0];

// better grayscale (weighted, looks nicer)
wire [7:0] gray8 = r*3 + g*6 + b*1;
wire [3:0] gray = gray8[7:4];

// threshold
wire [3:0] thresh = sw[7:4];

always @(*) begin
    case (sw[1:0])

        // ================= NORMAL =================
        2'b00: pixel_out = pixel_in;

        // ================= GRAYSCALE =================
        2'b01: pixel_out = {gray, gray, gray};

        // ================= COLOR CHANNEL =================
        2'b10: begin
            case (sw[3:2])
                2'b00: pixel_out = {r, 4'b0, 4'b0}; // 🔴 RED only
                2'b01: pixel_out = {4'b0, g, 4'b0}; // 🟢 GREEN only
                2'b10: pixel_out = {4'b0, 4'b0, b}; // 🔵 BLUE only  ← THIS IS WHAT YOU WANT
                2'b11: pixel_out = pixel_in;        // fallback
            endcase
        end

        // ================= SPECIAL =================
        2'b11: begin
            case (sw[3:2])

                // reverse (invert)
                2'b00: pixel_out = {~r, ~g, ~b};

                // threshold
                2'b01: begin
                    if (gray > thresh)
                        pixel_out = 12'hFFF;
                    else
                        pixel_out = 12'h000;
                end

                default: pixel_out = pixel_in;
            endcase
        end

        default: pixel_out = pixel_in;
    endcase
end

endmodule