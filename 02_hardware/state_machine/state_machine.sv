`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// state_machine -- regular state machine: 2 input pins, 2 output pins.
//////////////////////////////////////////////////////////////////////////////////

module state_machine #(
    parameter int ID = -1, // Assign during instantiation.
    parameter IMEM_INIT_FILE = "program.mem"
) (
    input  logic        clk,
    input  logic        nrst,
    input  logic        en,
    input  logic [15:0] fifo_in,

    input  logic [1:0]  in_pins,   // this state machine's 2 input pads (raw)
    output logic [1:0]  bank_out,  
    input  logic [15:0] in_bank,   

    output logic [1:0]  o_pins,    // this state machine's 2 output pins
    output logic [1:0]  po_en,     // output enables. 1 = Output
    output logic        rx_fifo_wr_en,
    output logic        tx_fifo_rd_en,
    output logic [15:0] fifo_o
);

// WAIT (delay cycles) and BLOCK were removed with the delay field. Stalls
// (WAIT instruction, and later FIFO empty/full) hold decoder pc_en low instead.
typedef enum logic [1:0] {
    IDLE,
    EXE
} state_t;

state_t ps, ns;

// Datapath registers. ISR and OSR live in their shift register modules.
logic [15:0] x_reg;
logic [15:0] y_reg;

// The SRAM output and pc_out identify the instruction currently executing.
logic [15:0] instruction;
logic [7:0]  pc_out;
logic [7:0]  sequential_pc;
logic [7:0]  normal_next_pc;
logic [7:0]  predicted_next_pc;
logic [7:0]  fetch_addr;
logic        fetch_en;
logic        pc_wren;
logic        execute;

// Predict every branch taken; discard its target on a prediction miss.
logic [7:0]  branch_target;
logic [7:0]  fallthrough_addr;
logic        is_branch;
logic        branch_taken;
logic        redirect_pending;

// Decoder controls and branch operands.
logic        decoder_pc_en;
logic [1:0]  pc_sel;
logic        decoder_txfifo_rd_en;
logic        decoder_rxfifo_wr_en;
logic [15:0] jmp_addr_set_data;
logic [15:0] src1_imm;
logic [2:0]  src1_sel;
logic [2:0]  src2_sel;
logic [15:0] src1_data;
logic [15:0] src2_data;
logic        eq_result;

// enable signals
logic        x_en, y_en, isr_en, osr_en;
logic        o_pin_en, pindirs_en;

// Datapath: write data for X, Y, pins, pindirs, ISR and OSR.
logic [1:0]  data_mux_sel;
logic [15:0] data_bus;
logic [15:0] alu_result;

// Pins
logic        is_beq, beq_imm;
logic [3:0]  pin_index;     // instruction bits [11:8]; 0 for BEQ
logic [15:0] pins_rd;       // in_bank shifted so bit pin_index is at bit 0
logic [4:0]  wr_count;      // how many output pins a write changes
logic [1:0]  wr_base_mask;  // wr_count low bits set
logic [1:0]  pin_wmask;     // which output pins / enables a write changes
logic [1:0]  pin_wdata;     // write data lined up with those pins

// Shift registers
logic        is_out, is_in;
logic [15:0] isr_word;      // full ISR contents
logic [15:0] osr_word;      // full OSR contents
logic [15:0] osr_out_bits;  // the bits the current OUT shifts out

imem #(.INIT_FILE(IMEM_INIT_FILE)) mem (
    .clk  (clk),
    .en   (fetch_en),
    .wen  (1'b0),
    .rden (fetch_en),
    .addr (fetch_addr),
    .din  (16'b0),
    .dout (instruction)
);

pc #(.WIDTH(8)) sm_pc (
    .PC_rst    (!nrst),
    .PC_wr     (pc_wren),
    .PC_DataIn (fetch_addr),
    .PC_clk    (clk),
    .PC_OUT    (pc_out)
);

mux4to1 #(.WIDTH(8)) pc_mux (
    .A   (sequential_pc),
    .B   (8'b0), // Unused by the decoder.
    .C   (fifo_in[7:0]),
    .D   (data_bus[7:0]), // OUT PC / MOV PC
    .SEL (pc_sel),
    .F   (normal_next_pc)
);

// The current ISA uses the ALU for X-- and Y--; other writes bypass it.
alu tiny_alu (
    .a   (src1_data),
    .b   (16'd1),
    .sel (1'b1), // currently hard wired to 1: x--
    .out (alu_result)
);

decoder_sm decoder (
    .ir                (instruction),
    .eq_result         (eq_result),
    .jmp_addr_set_data (jmp_addr_set_data),
    .src1_imm          (src1_imm),
    .pc_sel            (pc_sel),
    .pc_jmp_sel        (branch_taken),
    .pc_en             (decoder_pc_en),
    .x_en              (x_en),
    .y_en              (y_en),
    .isr_en            (isr_en),
    .osr_en            (osr_en),
    .o_pin_en          (o_pin_en),
    .pindirs_en        (pindirs_en),
    .txfifo_rd_en      (decoder_txfifo_rd_en),
    .rxfifo_wr_en      (decoder_rxfifo_wr_en),
    .src1_a_mux        (src1_sel),
    .eight_one_mux_sel (src2_sel),
    .data_mux_sel      (data_mux_sel)
);

// ISR: IN shifts data_bus in; MOV ISR / OUT ISR load data_bus; PUSH clears it.
input_shift_reg in_shift_reg(
    .clk      (clk),
    .rst      (!nrst),
    .load_en  (execute && ((isr_en && !is_in) || decoder_rxfifo_wr_en)),
    .in_data  (decoder_rxfifo_wr_en ? 16'b0 : data_bus),
    .in_count (instruction[4:0]),
    .shift_dir(1'b1),                     // shift right (LSB first)
    .shift_en (execute && isr_en && is_in),
    .rx_word  (isr_word)
);

// OSR: PULL loads the TX FIFO word; MOV OSR / OUT OSR load data_bus; OUT shifts.
output_shift_reg out_shift_reg(
    .clk      (clk),
    .rst      (!nrst),
    .load_en  (execute && osr_en),
    .fifo_data(decoder_txfifo_rd_en ? fifo_in : data_bus),
    .out_count(instruction[4:0]),
    .shift_en (execute && is_out),
    .shift_dir(1'b1),                     // shift right (LSB first)
    .out_bits (osr_out_bits),
    .osr_word (osr_word)
);


assign bank_out = in_pins;

// ---------------------------------------------------------------- pin index
assign is_beq    = (instruction[15:12] == 4'b0010);
assign beq_imm   = is_beq && instruction[5];          // BEQ immediate form
assign pin_index = is_beq ? 4'd0 : instruction[11:8]; // BEQ has no index field
assign pins_rd   = in_bank >> pin_index;             // bit `index` at bit 0; past bit 15 reads 0

always_comb begin
    // Source 1: operand A (compare, ALU). For BEQ it is the ISA's Source 1 table.
    if (beq_imm)
        src1_data = src1_imm;                         // {13'b0, ir[11:9]}
    else begin
        case (src1_sel)
            // All pin reads go through pins_rd. For BEQ the index is 0, so
            // pins_rd is the whole bank; otherwise pins_rd[0] = in_bank[index].
            3'b000: src1_data = is_beq ? pins_rd                  // BEQ: whole bank
                                       : {15'b0, pins_rd[0]};     // JMP PIN / WAIT: pin `index`
            3'b001: src1_data = x_reg;
            3'b010: src1_data = y_reg;
            3'b011: src1_data = pins_rd & x_reg;      // BEQ: pins masked by X
            3'b100: src1_data = pins_rd & y_reg;      // BEQ: pins masked by Y
            3'b101: src1_data = pins_rd & osr_word;   // BEQ: pins masked by OSR
            3'b110: src1_data = isr_word;
            3'b111: src1_data = osr_word;
        endcase
    end

    case (src2_sel)
        3'b000: src2_data = pins_rd;                          // IN / MOV: pins from index
        3'b001: src2_data = x_reg;
        3'b010: src2_data = y_reg;
        3'b100: src2_data = {14'b0, po_en};
        3'b101: src2_data = {8'b0, pc_out};
        3'b110: src2_data = isr_word;
        3'b111: src2_data = is_out ? osr_out_bits : osr_word; // OUT reads the shifted-out bits
        default: src2_data = '0;                              // 011 = NULL
    endcase

    case (data_mux_sel)
        2'b00:   data_bus = src2_data;          // 8 to 1 mux
        2'b01:   data_bus = jmp_addr_set_data;  // SET immediate {11'b0, ir[4:0]}
        2'b10:   data_bus = alu_result;         // X-- / Y-- (src1 - 1)
        default: data_bus = '0;
    endcase
end

assign eq_result         = (src1_data == src2_data);
assign sequential_pc     = pc_out + 8'd1;
assign branch_target     = jmp_addr_set_data[7:0];
assign is_branch         = (instruction[14:12] == 3'b010);
assign predicted_next_pc = is_branch ? branch_target : normal_next_pc;
assign pc_wren           = fetch_en && (ps == EXE);
assign is_out = (instruction[15:12] == 4'b0001);
assign is_in  = (instruction[15:12] == 4'b1001);

// ---------------------------------------------------------------- pin writes
// OUT changes `count` pins; SET and MOV change every pin from the index up.
// Data bit 0 goes to output pin `index`. Index 2-15 is past this state
// machine's 2 outputs, so nothing changes.
assign wr_count = is_out ? instruction[4:0] : 5'd2;

always_comb begin
    case (wr_count)
        5'd0:    wr_base_mask = 2'b00;
        5'd1:    wr_base_mask = 2'b01;
        default: wr_base_mask = 2'b11;
    endcase

    if (pin_index > 4'd1)
        pin_wmask = 2'b00;
    else
        pin_wmask = wr_base_mask << pin_index[0];

    pin_wdata = data_bus[1:0] << pin_index[0];
end
assign fifo_o = isr_word;

// Qualify every architectural write, including FIFO side effects.
assign execute        = nrst && en && (ps == EXE) &&
                        !redirect_pending && decoder_pc_en;
assign tx_fifo_rd_en = execute && decoder_txfifo_rd_en;
assign rx_fifo_wr_en = execute && decoder_rxfifo_wr_en;

always_comb begin
    ns         = ps;
    fetch_en   = 1'b0;
    fetch_addr = pc_out;

    if (nrst && en) begin
        case (ps)
            IDLE: begin
                // Prime the SRAM once before executing its registered output.
                fetch_en = 1'b1;
                ns       = EXE;
            end

            EXE: begin
                if (redirect_pending) begin
                    fetch_en   = 1'b1;
                    fetch_addr = fallthrough_addr;
                end
                else if (execute) begin
                    fetch_en   = 1'b1;
                    fetch_addr = predicted_next_pc;
                end
            end

            default: ns = IDLE;
        endcase
    end
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst)
        ps <= IDLE;
    else
        ps <= ns;
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        redirect_pending <= 1'b0;
        fallthrough_addr <= '0;
    end
    else if (en && ps == EXE) begin
        if (redirect_pending)
            redirect_pending <= 1'b0;
        else if (execute) begin
            // The target is fetched on this edge. If not taken, suppress its
            // execution and fetch the saved fall-through on the next edge.
            redirect_pending <= is_branch && !branch_taken;
            if (is_branch)
                fallthrough_addr <= sequential_pc;
        end
    end
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        x_reg  <= '0;
        y_reg  <= '0;
        o_pins <= '0;
        po_en  <= '0;                          // outputs released after reset
    end
    else if (execute) begin
        if (x_en)       x_reg  <= data_bus;
        if (y_en)       y_reg  <= data_bus;
        if (o_pin_en)   o_pins <= (o_pins & ~pin_wmask) | (pin_wdata & pin_wmask);
        if (pindirs_en) po_en  <= (po_en  & ~pin_wmask) | (pin_wdata & pin_wmask);
    end
end

endmodule