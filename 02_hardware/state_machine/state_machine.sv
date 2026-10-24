`timescale 1ns/1ps

module state_machine
#(
    parameter int ID = -1; //should be assigned during instantiation
)
(
    input  logic clk,
    input  logic nrst,
    input  logic en,

    input  logic [15:0] fifo_in,
    input  logic    in_pin,   // input pin

    output  logic    o_pin,   // ouput pin
    output logic [1:0]  po_en, // this will tell us if the pins are input or output.
    output logic rx_fifo_wr_en,
    output logic tx_fifo_rd_en,
    output logic [15:0] fifo_o
);

//State Machine Enum
typedef enum logic [1:0] {
    IDLE,
    EXE,
    WAIT,
    BLOCK
} state_t;
state_t ps, ns;


// State Machine ID set in the parameters
wire [3:0] my_id = ID;

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

logic [15:0] wait_counter;


//Instantiations
logic [7:0] pc_out;

logic pc_wren;
logic [7:0]pc_addr_in;
logic [1:0]pc_sel;
logic [7:0] jump_addr;
logic [7:0] branch_addr;
logic [7:0] interrupt_addr;

pc #(.WIDTH(8)) sm_pc(
    .PC_rst(nrst),
    .PC_wr(pc_wren),
    .PC_DataIn(pc_addr_in),
    .PC_clk(clk),
    .PC_OUT(pc_out)
);

mux4to1 #(.WIDTH(8)) pc_mux(
    .A(pc_out + 1),
    .B(jump_addr),
    .C(branch_addr),
    .D(interrupt_addr),
    .SEL(pc_sel),
    .F(pc_addr_in)
);

decoder_sm decoder(
    .ir(),

    //Output Below
    .jmp_beq_addr(),
    .pc_sel(),
    //.pc_en(),
    .x_en(),
    .y_en(),
    .isr_en(),
    .osr_en(),
    .o_pin_en(),
    .txfifo_rd_en(tx_fifo_rd_en),
    .rxfifo_wr_en(rx_fifo_wr_en),
    .out_in_mux_sel()
);

// memory

// State FF Logic
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        ps <= IDLE;
    end
    else begin
        ps <= ns;
    end
end //always_ff


always_comb
begin
    if (!nrst) begin
        x_reg = '0;
        y_reg = '0;
        osr_reg = '0;
        isr_reg = '0;
        pc_reg = '0;
    end
    else begin
        case(ps)
            // Default state for unused FSMs
            IDLE:
            begin
                pc_wren = 'b0;
                if (en) ns = EXE;
                else ns = IDLE;
            end

            // Where the FSM should be most of the time, read instruction and execute
            EXE:
            begin
                pc_wren = 'b1;

                // !!!need to have a way of getting to wait or block
                ns = EXE;
            end

            // For timing, there are often delays in programs so this is where the FSM will be while it counts down
            WAIT:
            begin
                pc_wren = 'b0;
                if (wait_counter == 'b0) ns = EXE;
                else ns = WAIT;
            end

            BLOCK:
            begin
                // !!! need a way to get out through interrupts
                ns = BLOCK;
            end
            default:
        endcase
    end
end//always_ff

//counter block
always_ff @ (posedge clk or negedge nrst)
begin
    if(!nrst) wait_counter <= 'b0;
    else if (ps == WAIT) wait_counter <= wait_counter - 'b1;
end

endmodule