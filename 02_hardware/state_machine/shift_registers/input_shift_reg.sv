`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: input_shift_reg
// Description: Parameterized input shift register. Each shift takes the
//              in_count LSBs of in_data and shifts them into the ISR, entering
//              at the MSB end (shift_dir = 1, right) or the LSB end
//              (shift_dir = 0, left). load_en overwrites the ISR with in_data
//              (e.g. load 0 to clear it after a PUSH). rx_word is the full ISR.
//
// Revision:
// Revision 0.03 - Shift bits in (accumulate) instead of extracting them;
//                 rx_word is now the ISR contents
// Revision 0.02 - Parameterized data width
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////
module input_shift_reg #(
    parameter int DATA_WIDTH  = 16,
    parameter int COUNT_WIDTH = $clog2(DATA_WIDTH) + 1
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   load_en,
    input  logic [DATA_WIDTH-1:0]  in_data,
    input  logic [COUNT_WIDTH-1:0] in_count,
    input  logic                   shift_dir,
    input  logic                   shift_en,
    output logic [DATA_WIDTH-1:0]  rx_word
);

    logic [DATA_WIDTH-1:0] isr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            isr <= '0;
        end else if (load_en) begin
            isr <= in_data;
        end else if (shift_en) begin
            if (shift_dir == 1'b1) // right: new bits enter at the MSB end
                isr <= (isr >> in_count) | (in_data << (DATA_WIDTH - in_count));
            else                   // left: new bits enter at the LSB end
                isr <= (isr << in_count) |
                       ((in_data << (DATA_WIDTH - in_count)) >> (DATA_WIDTH - in_count));
        end
    end

    assign rx_word = isr; // the whole ISR, what PUSH sends to the RX FIFO

endmodule