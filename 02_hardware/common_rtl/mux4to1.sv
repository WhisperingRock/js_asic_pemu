`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP
// Jane Street Comp 2026
//////////////////////////////////////////////////////////////////////////////////

module mux4to1#(parameter WIDTH = 16)(
        input  logic [WIDTH-1:0] A,
        input  logic [WIDTH-1:0] B,
        input  logic [WIDTH-1:0] C,
        input  logic [WIDTH-1:0] D,
        input  logic [1:0] SEL,
        output logic [WIDTH-1:0] F 
    );
    
    always_comb begin
    case(SEL)
        2'b00: F = A;
        2'b01: F = B;
        2'b10: F = C;
        2'b11: F = D;
        default: F = 16'DEAD;
    endcase
end
endmodule
