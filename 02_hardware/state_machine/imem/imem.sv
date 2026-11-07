`timescale 1ns/1ps
`default_nettype none

//module imem
//(
//    input wire clk,
//    input wire en,
//    input wire wen,
//    input wire rden,
//    input wire [7:0] addr,
//    input wire [15:0] din,
//    output wire [15:0] dout
//);

// Use the same macro instance in RTL simulation and synthesis. Simulation
// supplies the PDK's Verilog models with FUNCTIONAL defined.
//RM_IHPSG13_1P_256x16_c2_bm_bist u_sram (
//    .A_CLK       (clk),
//    .A_MEN       (en),
//    .A_WEN       (wen),
//    .A_REN       (rden),
//    .A_ADDR      (addr),
//    .A_DIN       (din),
//    .A_DOUT      (dout),
//    .A_BM        (16'hFFFF), // Write all 16 bits
//    .A_DLY       (1'b1),    // Required by the macro datasheet
//
//    .A_BIST_EN   (1'b0),
//    .A_BIST_CLK  (1'b0),
//    .A_BIST_MEN  (1'b0),
//    .A_BIST_WEN  (1'b0),
//    .A_BIST_REN  (1'b0),
//    .A_BIST_ADDR (8'b0),
//    .A_BIST_DIN  (16'b0),
//    .A_BIST_BM   (16'b0)
//);

module imem #(
    parameter INIT_FILE = "program.mem"
) (
    input  logic        clk,
    input  logic        en,
    input  logic        wen,
    input  logic        rden,
    input  logic [7:0]  addr,
    input  logic [15:0] din,
    output logic [15:0] dout
);

    (* ram_style = "block" *)
    logic [15:0] ram [0:255];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, ram, 0, 255);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            if (wen)
                ram[addr] <= din;

            if (rden)
                dout <= wen ? din : ram[addr];
        end
    end

endmodule
