`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
//  SEL 0 : Add
//  SEL 1 : Sub
///////////

module alu(
    input logic [15:0] a,
    input logic [15:0] b,
    input logic sel,
    output logic [15:0] out
);

    always_comb begin
        case (sel)
            1'b0:
                a + b = out;
            1'b1:
                a - b = out;
        endcase    
    end
    

endmodule