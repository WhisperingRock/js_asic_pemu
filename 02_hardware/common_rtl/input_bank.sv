`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// input_bank -- collects every state machine's input pins into one 16-bit bank,
// synchronized to clk, that all state machines read.
//
//   in_bank[1:0]    SM0 (regular)          in_bank[11:8]   SM4 (bidirectional)
//   in_bank[3:2]    SM1 (regular)          in_bank[15:12]  SM5 (bidirectional)
//   in_bank[5:4]    SM2 (regular)
//   in_bank[7:6]    SM3 (regular)
//
//////////////////////////////////////////////////////////////////////////////////

module input_bank #(
    parameter int STAGES = 2                 // synchronizer depth (>= 2)
) (
    input  logic        clk,
    input  logic        nrst,                // chip-wide reset (see header)

    input  logic [1:0]  sm0_pins,            // raw, from SM0 bank_out
    input  logic [1:0]  sm1_pins,
    input  logic [1:0]  sm2_pins,
    input  logic [1:0]  sm3_pins,

    input  logic [3:0]  sm4_pins,            // raw, from SM4 (bidirectional) bank_out
    input  logic [3:0]  sm5_pins,

    output logic [15:0] out_bank              // synchronized, to every state machine
);

    logic [15:0] raw_bank;

    assign raw_bank = {sm5_pins, sm4_pins, sm3_pins, sm2_pins, sm1_pins, sm0_pins};

    synch_ff #(
        .WIDTH  (16),
        .STAGES (STAGES)
    ) bank_sync (
        .clk  (clk),
        .nrst (nrst),
        .d_i  (raw_bank),
        .q_o  (out_bank)
    );

endmodule