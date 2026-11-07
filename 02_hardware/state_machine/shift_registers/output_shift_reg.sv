`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Jane Street Comp
// Engineer: Michael Sullivan
//
// Create Date: 10/29/2026 11:03:24 AM
// Design Name:
// Module Name: output_shift_reg
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Parameterized output shift register. Loads a DATA_WIDTH-bit word
//              from the FIFO, then shifts out out_count bits per shift from
//              either the LSB end (shift_dir = 1, right) or the MSB end
//              (shift_dir = 0, left).
//
// Dependencies:
//
// Revision:
// Revision 0.02 - Parameterized data width
// Revision 0.01 - File Created
// Additional Comments:
//   COUNT_WIDTH defaults to $clog2(DATA_WIDTH)+1 so out_count can represent
//   every value from 0 up to and including DATA_WIDTH.
//   out_count must not exceed DATA_WIDTH.
//
//////////////////////////////////////////////////////////////////////////////////
module output_shift_reg #(
    parameter int DATA_WIDTH  = 16,
    parameter int COUNT_WIDTH = $clog2(DATA_WIDTH) + 1
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   load_en,
    input  logic [DATA_WIDTH-1:0]  fifo_data,
    input  logic [COUNT_WIDTH-1:0] out_count,
    input  logic                   shift_en,
    input  logic                   shift_dir,
    output logic [DATA_WIDTH-1:0]  out_bits
);

    logic [DATA_WIDTH-1:0] osr; //this is the output shift register

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin //reset shift register and output to 0
            osr      <= '0;
            out_bits <= '0;
        end else if (load_en) begin //if load enable is high load register with fifo data
            osr <= fifo_data;
        end else if (shift_en) begin //if high, we are shifting the bits
            if (shift_dir == 1'b1) begin //shift_dir == 1 means shift right
                out_bits <= (osr << (DATA_WIDTH - out_count)) >> (DATA_WIDTH - out_count); //output the out_count least sig bits
                osr      <= osr >> out_count; //shift right by number of bits we extracted
            end else begin //shift_dir == 0 means shift left
                out_bits <= osr >> (DATA_WIDTH - out_count); //output the out_count most sig bits
                osr      <= osr << out_count; //shift left by number of bits we extracted
            end
        end
    end

endmodule