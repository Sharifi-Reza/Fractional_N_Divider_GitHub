`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Week-4 top-level integration:
//   Group-4 MASH 1-1 SDM -> Fractional-N Divider -> external T-FF
//
// Integration clocking decision:
//   The divider DRS states that the SDM presents a new N_sel on a rising edge of
//   INT65K_CLK. Therefore the Group-4 SDM is clocked by INT65K_CLK here.
//   The Group-4 block was timing-verified up to 131.072 kHz; INT65K_CLK is never
//   faster than that (N=1 is the maximum-frequency case), so this connection is
//   within its standalone timing constraint.
//
// Sequential latency:
//   N_sel produced on an INT65K_CLK edge is consumed at the next complete
//   divider-period boundary. The current divide operation is never interrupted.
//------------------------------------------------------------------------------
module frac_div_g4_top (
    input  wire                     clk,          // RO_CLK, nominal 131.072 kHz
    input  wire                     rst_n,
    input  wire signed [23:0]       epsilon_RO,   // Group-4 format: signed Q1.23
    input  wire                     dither_en,
    output wire [1:0]               N_sel,
    output wire                     INT65K_CLK,
    output wire                     CLK32K
);

    // Actual Group-4 SDM handoff. Do not edit its internal RTL in this package.
    sdm_mash11 u_sdm (
        .clk        (INT65K_CLK),
        .rst_n      (rst_n),
        .epsilon_RO (epsilon_RO),
        .dither_en  (dither_en),
        .N_sel      (N_sel)
    );

    frac_div_system u_div_system (
        .clk        (clk),
        .rst_n      (rst_n),
        .N_sel      (N_sel),
        .INT65K_CLK (INT65K_CLK),
        .CLK32K     (CLK32K)
    );

endmodule
