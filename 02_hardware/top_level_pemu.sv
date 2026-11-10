`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Top Level: one state machine with its TX and RX FIFOs
//
//   wr_req/wr_data --> fifo_writer --> [ TX FIFO ] --> state_machine --> pin_out
//                                                       (PULL)     <-- pin_in
//   rx_rd_en/rx_data <---------------- [ RX FIFO ] <-- state_machine
//                                                       (PUSH)
//
//   Everything runs on one clock (Basys 3: 100 MHz). The asynch FIFOs still
//   work with the same clock on both sides; their full/empty flags just lag a
//   write/read by NUM_SFF cycles because of the synchronizers.
//
//   Host side, for a testbench now and the Basys 3 wrapper later:
//     - Write words with the fifo_writer handshake: hold wr_req and wr_data
//       until a rising clk edge where wr_ready is high.
//     - Read words from the RX FIFO: rx_data always shows the oldest word
//       (first word fall through). When rx_empty is low, use rx_data and
//       pulse rx_rd_en for one clk cycle to pop it.
//
//////////////////////////////////////////////////////////////////////////////////

module top_level_pemu #(
    parameter IMEM_INIT_FILE = "program.mem",
    parameter int FIFO_DEPTH = 8,             // power of 2, at least 4
    parameter int NUM_SFF    = 2              // synchronizer stages in the FIFOs
) (
    input  logic        clk,
    input  logic        nrst,                 // active-low reset for everything
    input  logic        sm_en,                // run the state machine

    // host -> TX FIFO (through fifo_writer)
    input  logic        wr_req,
    input  logic [15:0] wr_data,
    output logic        wr_ready,

    // RX FIFO -> host
    input  logic        rx_rd_en,
    output logic [15:0] rx_data,
    output logic        rx_empty,

    // state machine pin
    input  logic        pin_in,
    output logic        pin_out,
    output logic [1:0]  pin_dir               // pindirs (po_en)
);

    // TX FIFO write port (fifo_writer -> FIFO)
    logic        tx_wr_en;
    logic [15:0] tx_wr_data;
    logic        tx_full;

    // TX FIFO read port (FIFO -> state machine)
    logic        tx_rd_en;
    logic [15:0] tx_rd_data;
    logic        tx_empty;

    // RX FIFO write port (state machine -> FIFO)
    logic        rx_wr_en;
    logic [15:0] rx_wr_data;
    logic        rx_full;

    // ---------------------------------------------------------------- host side
    fifo_writer #(.WIDTH(16)) tx_writer (
        .clk            (clk),
        .nrst           (nrst),
        .wr_req_i       (wr_req),
        .data_i         (wr_data),
        .ready_o        (wr_ready),
        .fifo_full_i    (tx_full),
        .fifo_wr_en_o   (tx_wr_en),
        .fifo_wr_data_o (tx_wr_data)
    );

    // ---------------------------------------------------------------- FIFOs
    asynch_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH), .NUM_SFF(NUM_SFF)) tx_fifo_0 (
        .wr_clk    (clk),
        .rd_clk    (clk),
        .wr_EN     (tx_wr_en),
        .rd_EN     (tx_rd_en),
        .nrst      (nrst),
        .wr_data_i (tx_wr_data),
        .rd_data_o (tx_rd_data),
        .full      (tx_full),
        .empty     (tx_empty)          // not used yet: see note on PULL below
    );

    asynch_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH), .NUM_SFF(NUM_SFF)) rx_fifo_0 (
        .wr_clk    (clk),
        .rd_clk    (clk),
        .wr_EN     (rx_wr_en),
        .rd_EN     (rx_rd_en),
        .nrst      (nrst),
        .wr_data_i (rx_wr_data),
        .rd_data_o (rx_data),
        .full      (rx_full),          // not used yet: see note on PUSH below
        .empty     (rx_empty)
    );

    // ---------------------------------------------------------------- state machine
    // NOTE: the state machine has no FIFO status inputs yet, so
    //   PULL on an empty TX FIFO loads whatever tx_rd_data shows (stale data), and
    //   PUSH to a full RX FIFO is dropped (the FIFO ignores writes when full).
    state_machine #(
        .ID             (0),
        .IMEM_INIT_FILE (IMEM_INIT_FILE)
    ) sm_0 (
        .clk           (clk),
        .nrst          (nrst),
        .en            (sm_en),
        .fifo_in       (tx_rd_data),
        .in_pin        (pin_in),
        .o_pin         (pin_out),
        .po_en         (pin_dir),
        .rx_fifo_wr_en (rx_wr_en),
        .tx_fifo_rd_en (tx_rd_en),
        .fifo_o        (rx_wr_data)
    );

endmodule