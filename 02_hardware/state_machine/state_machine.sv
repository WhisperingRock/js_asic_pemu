`timescale 1ns/1ps

module state_machine #(
    parameter int ID = -1 // Assign during instantiation.
) (
    input  logic        clk,
    input  logic        nrst,
    input  logic        en,
    input  logic [15:0] fifo_in,
    input  logic        in_pin,

    output logic        o_pin,
    output logic [1:0]  po_en,
    output logic        rx_fifo_wr_en,
    output logic        tx_fifo_rd_en,
    output logic [15:0] fifo_o
);

typedef enum logic [1:0] {
    IDLE,
    EXE,
    WAIT,
    BLOCK
} state_t;

state_t ps, ns;

// Datapath register writes are still TODO.
logic [15:0] x_reg;
logic [15:0] y_reg;
logic [15:0] osr_reg;
logic [15:0] isr_reg;
logic [15:0] wait_counter;

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

imem mem (
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
    .D   (src2_data[7:0]),
    .SEL (pc_sel),
    .F   (normal_next_pc)
);

decoder_sm decoder (
    .ir                (instruction),
    .eq_result         (eq_result),
    .jmp_addr_set_data (jmp_addr_set_data),
    .src1_imm          (src1_imm),
    .pc_sel            (pc_sel),
    .pc_jmp_sel        (branch_taken),
    .pc_en             (decoder_pc_en),
    .x_en              (),
    .y_en              (),
    .isr_en            (),
    .osr_en            (),
    .o_pin_en          (),
    .pindirs_en        (),
    .txfifo_rd_en      (decoder_txfifo_rd_en),
    .rxfifo_wr_en      (decoder_rxfifo_wr_en),
    .src1_a_mux        (src1_sel),
    .eight_one_mux_sel (src2_sel),
    .data_mux_sel      ()
);

always_comb begin
    case (src1_sel)
        3'b000: src1_data = {15'b0, in_pin};
        3'b001: src1_data = x_reg;
        3'b010: src1_data = y_reg;
        3'b101: src1_data = src1_imm;
        3'b110: src1_data = isr_reg;
        3'b111: src1_data = osr_reg;
        default: src1_data = '0;
    endcase

    case (src2_sel)
        3'b000: src2_data = {15'b0, in_pin};
        3'b001: src2_data = x_reg;
        3'b010: src2_data = y_reg;
        3'b100: src2_data = {14'b0, po_en};
        3'b101: src2_data = {8'b0, pc_out};
        3'b110: src2_data = isr_reg;
        3'b111: src2_data = osr_reg;
        default: src2_data = '0;
    endcase
end

assign eq_result         = (src1_data == src2_data);
assign sequential_pc     = pc_out + 8'd1;
assign branch_target     = jmp_addr_set_data[7:0];
assign is_branch         = (instruction[14:12] == 3'b010);
assign predicted_next_pc = is_branch ? branch_target : normal_next_pc;
assign pc_wren           = fetch_en && (ps == EXE);

// Use execute for every future datapath write as well as FIFO side effects.
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

            WAIT: begin
                if (wait_counter == '0)
                    ns = EXE;
            end

            BLOCK: ; // TODO: Resume when an interrupt arrives.
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
        x_reg   <= '0;
        y_reg   <= '0;
        osr_reg <= '0;
        isr_reg <= '0;
    end
    // TODO: Add datapath writes qualified by execute.
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst)
        wait_counter <= '0;
    else if (en && ps == WAIT && wait_counter != '0)
        wait_counter <= wait_counter - 16'd1;
end

endmodule
