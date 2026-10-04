`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Synthesizable system wrapper: Divider + external T-FF (DRS §2.2)
 // SDM is NOT included here (behavioral / TB-only).
//------------------------------------------------------------------------------
module frac_div_system (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] N_sel,
    output wire       INT65K_CLK,
    output wire       CLK32K
);

    fractional_n_divider u_div (
        .clk        (clk),
        .rst_n      (rst_n),
        .N_sel      (N_sel),
        .INT65K_CLK (INT65K_CLK)
    );

    t_flip_flop u_tff (
        .clk   (INT65K_CLK),
        .rst_n (rst_n),
        .q     (CLK32K)
    );

endmodule
