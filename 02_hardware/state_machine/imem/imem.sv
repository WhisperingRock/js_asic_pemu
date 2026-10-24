`timescale 1ns/1ps
`default_nettype none

module imem
(
    input wire clk,
    input wire en,
    input wire we,
    input wire [7:0] addr,
    input wire [15:0] din,
    output wire [15:0] dout
);

// Use the same macro instance in RTL simulation and synthesis. Simulation
// supplies the PDK's Verilog models with FUNCTIONAL defined.
RM_IHPSG13_1P_256x16_c2_bm_bist u_sram (
    .A_CLK       (clk),
    .A_MEN       (en),
    .A_WEN       (we),
    .A_REN       (~we),
    .A_ADDR      (addr),
    .A_DIN       (din),
    .A_DOUT      (dout),
    .A_BM        (16'hFFFF), // Write all 16 bits
    .A_DLY       (1'b1),    // Required by the macro datasheet

    .A_BIST_EN   (1'b0),
    .A_BIST_CLK  (1'b0),
    .A_BIST_MEN  (1'b0),
    .A_BIST_WEN  (1'b0),
    .A_BIST_REN  (1'b0),
    .A_BIST_ADDR (8'b0),
    .A_BIST_DIN  (16'b0),
    .A_BIST_BM   (16'b0)
);


endmodule
