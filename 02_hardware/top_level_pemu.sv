`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Top Level: 2 state machines for testing
//   SM0 = state_machine     (regular: 2 input pins, 2 output pins)
//   SM1 = bi_state_machine  (4 bidirectional pins)
//////////////////////////////////////////////////////////////////////////////////

module top_level_pemu #(
    parameter SM0_IMEM_INIT_FILE = "spi_tx.mem",
    parameter SM1_IMEM_INIT_FILE = "spi_rx.mem",
    parameter int FIFO_DEPTH  = 8,            // power of 2, at least 4
    parameter int NUM_SFF     = 2,            // synchronizer stages in the FIFOs
    parameter int BANK_STAGES = 2             // synchronizer stages in the input bank
) (
    input  logic        clk,
    input  logic        nrst,                 // active-low reset for everything
    input  logic [1:0]  sm_en,                // sm_en[n] runs state machine n

    // host -> TX FIFO n (through fifo_writer n)
    input  logic [1:0]        wr_req,
    input  logic [1:0][15:0]  wr_data,
    output logic [1:0]        wr_ready,

    // RX FIFO n -> host
    input  logic [1:0]        rx_rd_en,
    output logic [1:0][15:0]  rx_data,
    output logic [1:0]        rx_empty,

    // SM0 (regular) pins
    input  logic [1:0]  sm0_in,               // 2 input pins (raw, from the pads)
    output logic [1:0]  sm0_out,              // 2 output values
    output logic [1:0]  sm0_oe,               // 2 output enables (pindirs), 1 = drive

    // SM1 (bidirectional) pins
    inout  wire  [3:0]  sm1_pins,
    output logic [3:0]  sm1_oe                // SM1 pindirs, for status / LEDs
);

    // ---------------------------------------------------------------- signals
    // Index [n] = state machine n
    logic [1:0]        tx_wr_en;              // fifo_writer -> TX FIFO
    logic [1:0][15:0]  tx_wr_data;
    logic [1:0]        tx_full;

    logic [1:0]        tx_rd_en;              // TX FIFO -> state machine
    logic [1:0][15:0]  tx_rd_data;
    logic [1:0]        tx_empty;

    logic [1:0]        rx_wr_en;              // state machine -> RX FIFO
    logic [1:0][15:0]  rx_wr_data;
    logic [1:0]        rx_full;

    logic [1:0]  sm0_bank_out;                // raw pin levels -> input bank
    logic [3:0]  sm1_bank_out;
    logic [5:0]  bank;                        // synchronized
    logic [15:0] in_bank;

    // ---------------------------------------------------------------- FIFOs
    // NOTE: the state machines have no FIFO status inputs yet, so
    //   PULL on an empty TX FIFO loads whatever tx_rd_data shows (stale data), and
    //   PUSH to a full RX FIFO is dropped (the FIFO ignores writes when full).
    for (genvar n = 0; n < 2; n++) begin : g_fifos
        fifo_writer #(.WIDTH(16)) tx_writer (
            .clk            (clk),
            .nrst           (nrst),
            .wr_req_i       (wr_req[n]),
            .data_i         (wr_data[n]),
            .ready_o        (wr_ready[n]),
            .fifo_full_i    (tx_full[n]),
            .fifo_wr_en_o   (tx_wr_en[n]),
            .fifo_wr_data_o (tx_wr_data[n])
        );

        asynch_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH), .NUM_SFF(NUM_SFF)) tx_fifo (
            .wr_clk    (clk),
            .rd_clk    (clk),
            .wr_EN     (tx_wr_en[n]),
            .rd_EN     (tx_rd_en[n]),
            .nrst      (nrst),
            .wr_data_i (tx_wr_data[n]),
            .rd_data_o (tx_rd_data[n]),
            .full      (tx_full[n]),
            .empty     (tx_empty[n])          // not used yet: see note above
        );

        asynch_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH), .NUM_SFF(NUM_SFF)) rx_fifo (
            .wr_clk    (clk),
            .rd_clk    (clk),
            .wr_EN     (rx_wr_en[n]),
            .rd_EN     (rx_rd_en[n]),
            .nrst      (nrst),
            .wr_data_i (rx_wr_data[n]),
            .rd_data_o (rx_data[n]),
            .full      (rx_full[n]),          // not used yet: see note above
            .empty     (rx_empty[n])
        );
    end

    // ---------------------------------------------------------------- input bank
    // Chip-wide nrst only (never an sm_en): the other state machine keeps
    // reading these pins while one is stopped.
    input_bank #(.STAGES(BANK_STAGES)) u_input_bank (
        .clk      (clk),
        .nrst     (nrst),
        .sm0_pins (sm0_bank_out),
        .sm1_pins (sm1_bank_out),
        .out_bank (bank)
    );

    assign in_bank = {10'b0, bank};

    // ---------------------------------------------------------------- state machines
    state_machine #(
        .ID             (0),
        .IMEM_INIT_FILE (SM0_IMEM_INIT_FILE)
    ) sm_0 (
        .clk           (clk),
        .nrst          (nrst),
        .en            (sm_en[0]),
        .fifo_in       (tx_rd_data[0]),
        .in_pins       (sm0_in),
        .bank_out      (sm0_bank_out),
        .in_bank       (in_bank),
        .o_pins        (sm0_out),
        .po_en         (sm0_oe),
        .rx_fifo_wr_en (rx_wr_en[0]),
        .tx_fifo_rd_en (tx_rd_en[0]),
        .fifo_o        (rx_wr_data[0])
    );

    bi_state_machine #(
        .ID             (1),
        .IMEM_INIT_FILE (SM1_IMEM_INIT_FILE)
    ) sm_1 (
        .clk           (clk),
        .nrst          (nrst),
        .en            (sm_en[1]),
        .fifo_in       (tx_rd_data[1]),
        .pins          (sm1_pins),
        .bank_out      (sm1_bank_out),
        .in_bank       (in_bank),
        .po_en         (sm1_oe),
        .rx_fifo_wr_en (rx_wr_en[1]),
        .tx_fifo_rd_en (tx_rd_en[1]),
        .fifo_o        (rx_wr_data[1])
    );

endmodule