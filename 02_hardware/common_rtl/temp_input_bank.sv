`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// input_bank -- collects every state machine's input pins into one 16-bit bank,
// synchronized to clk, that all state machines read.
//
//   in_bank[1:0]    SM0 (regular)
//   in_bank[5:2]    SM1 (bi-dir)
//
//////////////////////////////////////////////////////////////////////////////////

module input_bank #(
    parameter int STAGES = 2                 // synchronizer depth (>= 2)
) (
    input  logic        clk,
    input  logic        nrst,                // chip-wide reset (see header)

    input  logic [1:0]  sm0_pins,            // raw, from SM0 bank_out

    input  logic [3:0]  sm1_pins,            // raw, from SM1 (bidirectional) bank_out

    output logic [5:0] out_bank              // synchronized, to every state machine
);

    logic [5:0] raw_bank;

    assign raw_bank = {sm1_pins, sm0_pins};

    synch_ff #(
        .WIDTH  (6),
        .STAGES (STAGES)
    ) bank_sync (
        .clk  (clk),
        .nrst (nrst),
        .d_i  (raw_bank),
        .q_o  (out_bank)
    );

endmodule