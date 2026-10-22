`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP 2026
// Jane Street Team 
//////////////////////////////////////////////////////////////////////////////////


module pc #(parameter WIDTH = 5)(
    input  PC_rst,
    input  PC_wr,
    input  [WIDTH-1:0] PC_DataIn,
    input  PC_clk,
    output [WIDTH-1:0] PC_OUT
    );

logic [WIDTH-1:0] PC_Output;

always_ff @(posedge PC_clk) begin
    if (PC_rst)
        PC_Output <= 16'h0000;
    else if (PC_wr)
        PC_Output <= PC_DataIn; 
end

assign PC_OUT = PC_Output;

endmodule
