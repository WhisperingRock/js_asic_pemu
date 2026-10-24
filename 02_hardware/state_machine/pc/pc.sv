`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP 2026
// Jane Street Team 
//////////////////////////////////////////////////////////////////////////////////


module pc #(parameter WIDTH = 5)(
    input  logic PC_rst,
    input  logic PC_wr,
    input  logic [WIDTH-1:0] PC_DataIn,
    input  logic PC_clk,
    output logic [WIDTH-1:0] PC_OUT
    );

logic [WIDTH-1:0] PC_Output;

always_ff @(posedge PC_clk) begin
    if (PC_rst)
        PC_Output <= 'b0;
    else if (PC_wr)
        PC_Output <= PC_DataIn; 
end

assign PC_OUT = PC_Output;

endmodule
