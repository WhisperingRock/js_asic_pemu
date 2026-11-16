`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// FIFO Writer
//   Drives the write port of one asynch_fifo. Whoever is upstream (a testbench
//   for now, a bus or UART receiver later) hands it one word at a time with a
//   valid/ready handshake; this module holds the word and keeps wr_EN high
//   until the FIFO has room, so the upstream side never has to watch `full`.
//
//   Handshake (all on clk, the FIFO's wr_clk):
//     - Put the word on data_i and raise wr_req_i.
//     - The word is taken on any rising edge where wr_req_i && ready_o.
//     - Keep wr_req_i and data_i steady until then. Back-to-back words are
//       fine: one word per clock while the FIFO isn't full.
//
//   Holds at most one word. If the FIFO is full, that word waits here and
//   ready_o stays low until the FIFO accepts it.
//
//////////////////////////////////////////////////////////////////////////////////

module fifo_writer #(parameter WIDTH = 16)(
    input  logic             clk,          // the FIFO's wr_clk
    input  logic             nrst,

    // upstream (testbench / host)
    input  logic             wr_req_i,     // data_i is valid, please write it
    input  logic [WIDTH-1:0] data_i,
    output logic             ready_o,      // a word is taken this edge if wr_req_i is high

    // to asynch_fifo write port
    input  logic             fifo_full_i,  // asynch_fifo.full
    output logic             fifo_wr_en_o, // asynch_fifo.wr_EN
    output logic [WIDTH-1:0] fifo_wr_data_o// asynch_fifo.wr_data_i
);

    logic             pending;  // holding a word the FIFO hasn't taken yet
    logic [WIDTH-1:0] hold;

    // Room for a new word if nothing is held, or the held word goes into the
    // FIFO on this same edge.
    assign ready_o        = !pending || !fifo_full_i;

    // The FIFO only writes when wr_EN && !full, so holding wr_EN high while
    // full is safe: it just waits.
    assign fifo_wr_en_o   = pending;
    assign fifo_wr_data_o = hold;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending <= 1'b0;
            hold    <= '0;
        end
        else if (wr_req_i && ready_o) begin   // take a new word
            pending <= 1'b1;
            hold    <= data_i;
        end
        else if (pending && !fifo_full_i) begin // FIFO took the held word
            pending <= 1'b0;
        end
    end

endmodule