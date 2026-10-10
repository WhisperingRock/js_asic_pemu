`timescale 1ns/1ps

module synch_ff #(
    parameter WIDTH  = 1,   // FIX: default back to 1 (most common use: single-bit sync)
    parameter STAGES = 2    // flops in the chain
)(
    input  logic             clk,     // DESTINATION domain clock
    input  logic             nrst,
    input  logic [WIDTH-1:0] d_i,     // from the source domain (must be registered there!)
    output logic [WIDTH-1:0] q_o      // safe to use in the destination domain
);

    // Option B: slot 0 = input, slots 1..STAGES = flops
        (* ASYNC_REG = "TRUE" *)
    logic [WIDTH-1:0] sync [1:STAGES];      // only flops now, no input slot

    genvar i;
    generate
        for (i = 1; i <= STAGES; i++) begin : g_stage
            always_ff @(posedge clk or negedge nrst) begin
                if (!nrst)       sync[i] <= '0;
                else if (i == 1) sync[i] <= d_i;       // first flop reads the input
                else             sync[i] <= sync[i-1];
            end
        end
    endgenerate

    assign q_o = sync[STAGES];

endmodule
