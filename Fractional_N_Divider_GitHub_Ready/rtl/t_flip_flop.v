`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// External T-flip-flop (DRS §2.2)
// Divides INT65K_CLK by 2 -> 50% duty 32.768 kHz when INT65K avg is 65.536 kHz.
//------------------------------------------------------------------------------
module t_flip_flop (
    input  wire clk,
    input  wire rst_n,
    output reg  q
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= 1'b0;
        else
            q <= ~q;
    end

endmodule
