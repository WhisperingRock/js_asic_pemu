`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Jane Street Comp
// Engineer: Michael Sullivan
// Module Name: output_shift_reg
// Description: Parameterized output shift register. Loads a DATA_WIDTH-bit word
//              (from the FIFO on PULL, or the data bus on MOV/OUT OSR), then
//              shifts out out_count bits per shift from either the LSB end
//              (shift_dir = 1, right) or the MSB end (shift_dir = 0, left).
//
// Revision:
// Revision 0.03 - out_bits is combinational (valid in the same cycle as the
//                 OUT that consumes it); added osr_word (full OSR contents)
// Revision 0.02 - Parameterized data width
// Revision 0.01 - File Created
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
    output logic [DATA_WIDTH-1:0]  out_bits,
    output logic [DATA_WIDTH-1:0]  osr_word
);

    logic [DATA_WIDTH-1:0] osr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            osr <= '0;
        end else if (load_en) begin
            osr <= fifo_data;
        end else if (shift_en) begin
            if (shift_dir == 1'b1) osr <= osr >> out_count;
            else                   osr <= osr << out_count;
        end
    end

    // The bits this shift sends out. Combinational, so OUT can write them to
    // its destination on the same clock edge that shifts the OSR.
    always_comb begin
        if (shift_dir == 1'b1)
            out_bits = (osr << (DATA_WIDTH - out_count)) >> (DATA_WIDTH - out_count);
        else
            out_bits = osr >> (DATA_WIDTH - out_count);
    end

    assign osr_word = osr; // the whole OSR (for MOV / BEQ / JMP !OSRE)

endmodule