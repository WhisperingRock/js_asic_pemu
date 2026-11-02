`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/29/2026 11:03:24 AM
// Design Name: 
// Module Name: input_shift_reg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Parameterized input shift register. Loads a DATA_WIDTH-bit word,
//              then extracts in_count bits per shift from either the LSB end
//              (shift_dir = 1, right) or the MSB end (shift_dir = 0, left).
// 
// Dependencies: 
// 
// Revision:
// Revision 0.02 - Parameterized data width
// Revision 0.01 - File Created
// Additional Comments:
//   COUNT_WIDTH defaults to $clog2(DATA_WIDTH)+1 so in_count can represent
//   every value from 0 up to and including DATA_WIDTH.
//   in_count must not exceed DATA_WIDTH.
// 
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
        if (rst) begin //reset shift register and output to 0
            isr     <= '0;
            rx_word <= '0;
        end else if (load_en) begin //if load enable is high then we load register with input data
            isr <= in_data;
        end else if (shift_en) begin //if high we are shifting bits
            if (shift_dir == 1'b1) begin //shift_dir = 1 means shift direction is right
                rx_word <= (isr << (DATA_WIDTH - in_count)) >> (DATA_WIDTH - in_count); //output the in_count least sig bits
                isr     <= isr >> in_count; //shift right by the in_count bits extracted
            end else begin //shift_dir = 0 means shift direction is left
                rx_word <= isr >> (DATA_WIDTH - in_count); //output the in_count most sig bits
                isr     <= isr << in_count; //shift left by the in_count bits extracted
            end
        end
    end

endmodule