`timescale 1ns/1ps

module state_machine(
    input  logic clk,
    input  logic nrst,

    input  logic [15:0] fifo_in,
    input  logic [15:0] pc_next,

    output logic [1:0]  po_en, // this will tell us if the pins are input or output.
    inout logic  [1:0]  pins   // Assume 2 pins per state machine for now.

    output logic [15:0] fifo_o
);

typedef enum logic [1:0] {
    EXE,
    WAIT
} state_t;
state_t ps, ns;

// State Machine ID
logic [2:0]ID;

// Main Internal Registers
logic [15:0] x_reg;
logic [15:0] y_reg;

logic [15:0] osr_reg;
logic [15:0] isr_reg;

logic [15:0] pc_reg;


always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        ns <= WAIT;
    end
    else begin
        ps <= ns;
    end
end //always_ff


always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        x_reg <= '0;
        y_reg <= '0;
        osr_reg <= '0;
        isr_reg <= '0;
        pc_reg <= '0;
    end
    else begin
        case(ps)
            EXE: 
            WAIT:
            default:
        endcase
    end
end//always_ff

endmodule