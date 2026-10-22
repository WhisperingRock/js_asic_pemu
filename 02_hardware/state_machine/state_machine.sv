`timescale 1ns/1ps

module state_machine(
    input  logic clk,
    input  logic nrst,

    input  logic [15:0] fifo_in,
    input  logic [15:0] pc_next,
    input  logic    o_pin   // ouput pin
    input  logic    in_pin   // input pin

    output logic [1:0]  po_en, // this will tell us if the pins are input or output.
    output logic rx_fifo_wr_en,
    output logic tx_fifo_rd_en,
    output logic [15:0] fifo_o
);

//State Machine Enum
typedef enum logic [1:0] {
    EXE,
    WAIT
} state_t;
state_t ps, ns;


// State Machine ID
logic [2:0]ID;

//Pin Shift Direction
    // 0 = right (lsb)
    // 1 = left (msb)
logic pin_dir;

// Main Internal Registers
logic [15:0] x_reg;
logic [15:0] y_reg;

logic [15:0] osr_reg;
logic [15:0] isr_reg;

logic [15:0] pc_reg;


//Instantiations
logic [15:0] pc_out;
pc #(.WIDTH(5)) sm_pc(
    .PC_rst(nrst),
    .PC_wr(),
    .PC_DataIn(),
    .PC_clk(),
    .PC_OUT(pc_out)
);

mux4to1 #(.WIDTH(16)) pc_mux(
    .A(pc_out + 1),
    .B(),
    .C(),
    .D(),
    .SEL(),
    .F()
);

decoder_sm decoder(
    .ir(),

    //Output Below
    .jmp_beq_addr(),
    .pc_sel(),
    .pc_en(),
    .x_en(),
    .y_en(),
    .isr_en(),
    .osr_en(),
    .o_pin_en(),
    .txfifo_rd_en(tx_fifo_rd_en),
    .rxfifo_wr_en(rx_fifo_wr_en),
    .out_in_mux_sel()
);

// State FF Logic
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        ps <= WAIT;
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