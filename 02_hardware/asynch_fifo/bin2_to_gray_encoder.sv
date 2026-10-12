`timescale 1ns/1ps

//////////////////////////////////////////////////////////////
//  CARP Club at Calpoly SLO
//  JaneStreet 2026
//  Binary to Gray Encoder
//
//////////////////////////////////////////////////////////////

module bin2_to_gray_encoder #(parameter WIDTH = 32)(
    input  logic [WIDTH -1:0] bin_i,
    output logic [WIDTH -1:0] gray_o
);
    genvar i;
    generate
        for (i = 0; i < WIDTH -1; i++)begin
            assign gray_o[i] = bin_i[i] ^ bin_i[i + 1];
        end        
    endgenerate

// last bit needs a statement. For loop doesn't cover it.
    assign gray_o[WIDTH-1] = bin_i[WIDTH-1];
endmodule
