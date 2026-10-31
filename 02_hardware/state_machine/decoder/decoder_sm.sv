`timescale 1ns/1ps


    //----------
    // PC SEL
    // 00 = pc + 1
    // 01 = unused (jumps use pc_jmp_sel)
    // 10 = Fifo
    // 11 = data bus (OUT PC / MOV PC)
    //
    // PC JMP SEL
    // 0 = pc_sel mux output
    // 1 = jump address ir[4:0] (JMP / BEQ taken)
    //------

    //----------
    // DATA MUX SEL (write data for X, Y, pins, pindirs)
    // 00 = 8 to 1 mux output
    // 01 = SET immediate {11'b0, ir[4:0]}
    // 10 = subtractor (src1 mux output - 1)  -> X-- / Y--
    // 11 = unused
    //------

    //----------
    // SOURCE 1 MUX (src1_a_mux) -> ALU / subtractor and EQ input A
    // 000 = Pins
    // 001 = X
    // 010 = Y
    // 011 = ??
    // 100 = ??
    // 101 = Imm {13'b0, ir[11:9]}
    // 110 = ISR
    // 111 = OSR
    //------

module decoder_sm(
    input  logic [15:0] ir,
    input  logic eq_result,

    output logic [15:0] jmp_addr_set_data,
    output logic [15:0] src1_imm,
    output logic [1:0] pc_sel,
    output logic pc_jmp_sel,
    output logic pc_en,

    output logic x_en,
    output logic y_en,
    output logic isr_en,
    output logic osr_en,
    output logic o_pin_en,
    output logic pindirs_en, //bi-direction st_mch only
    output logic txfifo_rd_en,
    output logic rxfifo_wr_en,

    output logic [2:0] src1_a_mux,
    output logic [2:0] eight_one_mux_sel,
    output logic [1:0] data_mux_sel
);
    /*
        Destination 3 bits (also the 8 to 1 mux encoding)
        000: pins
        001: X (scratch register X)
        010: Y (scratch register Y)
        011: NULL (discard data / 16'd0)
        100: PINDIRS // !Inout StateMachine only!
        101: PC
        110: ISR (also sets ISR shift counter to Bit count)
        111: OSR
    */
    logic [2:0] dest;
    logic jmp_take;

    assign dest = ir[7:5];
    assign jmp_addr_set_data = {11'b0, ir[4:0]};
    assign src1_imm = {13'b0, ir[11:9]}; // BEQ immediate

    always_comb begin
        //default
        txfifo_rd_en      = 1'b0;
        rxfifo_wr_en      = 1'b0;
        eight_one_mux_sel = 3'b011; // NULL
        src1_a_mux        = 3'b000; // don't care
        data_mux_sel      = 2'b00;  // 8 to 1 mux
        pc_sel            = 2'b00;  // pc + 1
        pc_jmp_sel        = 1'b0;
        pc_en             = 1'b1;
        x_en              = 1'b0;
        y_en              = 1'b0;
        isr_en            = 1'b0;
        osr_en            = 1'b0;
        o_pin_en          = 1'b0;
        pindirs_en        = 1'b0;
        jmp_take          = 1'b0;

        case(ir[14:12])

        // ---------- Push and Pull ---------- //
        3'b000: begin
            if(ir[15] == 0) begin // PUSH: ISR -> RX FIFO
                rxfifo_wr_en = 1'b1;
            end
            else begin            // PULL: TX FIFO -> OSR
                txfifo_rd_en = 1'b1;
                osr_en       = 1'b1;
            end
        end

        // ---------- Out and In ---------- //
        3'b001: begin
            if(ir[15] == 0) begin // OUT: OSR -> Dest
                eight_one_mux_sel = 3'b111; // OSR SEL
                case(dest)
                    3'b000: o_pin_en   = 1'b1; // pins
                    3'b001: x_en       = 1'b1; // X
                    3'b010: y_en       = 1'b1; // Y
                    3'b011: ;                  // NULL (discard data)
                    3'b100: pindirs_en = 1'b1; // PINDIRS
                    3'b101: pc_sel     = 2'b11;// PC
                    3'b110: isr_en     = 1'b1; // ISR (also sets ISR shift counter to Bit count)
                    3'b111: osr_en     = 1'b1; // OSR
                endcase
            end
            else begin            // IN: ISR <- Src
                eight_one_mux_sel = dest; // Source!
                isr_en = 1'b1;
            end
        end

        // ---------- Jmp and Beq ---------- //
        3'b010: begin
            if (ir[15] == 1'b1) begin // JMP
                case (ir[7:5]) // Condition
                    3'b000: jmp_take = 1'b1;              // always
                    3'b001: begin                         // !X : X == 0
                        src1_a_mux        = 3'b001;       // A = X
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = eq_result;
                    end
                    3'b010: begin                         // X-- : X != 0 (prior to decrement)
                        src1_a_mux        = 3'b001;       // A = X
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = !eq_result;
                        data_mux_sel      = 2'b10;        // X <- X - 1
                        x_en              = 1'b1;         // decrement whether or not taken
                    end
                    3'b011: begin                         // !Y : Y == 0
                        src1_a_mux        = 3'b010;       // A = Y
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = eq_result;
                    end
                    3'b100: begin                         // Y-- : Y != 0 (prior to decrement)
                        src1_a_mux        = 3'b010;       // A = Y
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = !eq_result;
                        data_mux_sel      = 2'b10;        // Y <- Y - 1
                        y_en              = 1'b1;         // decrement whether or not taken
                    end
                    3'b101: begin                         // X != Y
                        src1_a_mux        = 3'b001;       // A = X
                        eight_one_mux_sel = 3'b010;       // B = Y
                        jmp_take          = !eq_result;
                    end
                    3'b110: begin                         // PIN high : pins != 0
                        src1_a_mux        = 3'b000;       // A = Pins
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = !eq_result;
                    end
                    3'b111: begin                         // !OSRE : OSR != 0
                        src1_a_mux        = 3'b111;       // A = OSR
                        eight_one_mux_sel = 3'b011;       // B = NULL (0)
                        jmp_take          = !eq_result;
                    end
                endcase
            end
            else begin // BEQ: branch if Src1/Imm == Src2
                if (ir[5])                                // bit 5 = 1: Imm
                    src1_a_mux = 3'b101;                  // A = Imm {13'b0, ir[11:9]}
                else                                      // bit 5 = 0: Src_1
                    src1_a_mux = ir[11:9];                // A = Source 1 table

                eight_one_mux_sel = ir[8:6];              // B = Src 2 (8 to 1 mux)
                jmp_take          = eq_result;
            end

            pc_jmp_sel = jmp_take;                        // jump to ir[4:0], else pc + 1
        end

        // ---------- Mov and Set ---------- //
        3'b011: begin
            if(ir[15] == 1) begin // SET: dest <- {11'b0, ir[4:0]}
                data_mux_sel = 2'b01;
                case (dest)
                    3'b000: o_pin_en   = 1'b1; // PINS
                    3'b001: x_en       = 1'b1; // X: 5 LSBs = Data, rest cleared
                    3'b010: y_en       = 1'b1; // Y: 5 LSBs = Data, rest cleared
                    3'b100: pindirs_en = 1'b1; // PINDIRS
                    default: ;                 // 011 reserved (NULL), 101-111 undefined
                endcase
            end
            else begin            // MOV: dest <- Source (8 to 1 mux)
                eight_one_mux_sel = ir[2:0];
                case(dest)
                    3'b000: o_pin_en   = 1'b1; // pins
                    3'b001: x_en       = 1'b1; // X
                    3'b010: y_en       = 1'b1; // Y
                    3'b011: ;                  // NULL (discard data)
                    3'b100: pindirs_en = 1'b1; // PINDIRS
                    3'b101: pc_sel     = 2'b11;// PC
                    3'b110: isr_en     = 1'b1; // ISR
                    3'b111: osr_en     = 1'b1; // OSR
                endcase
            end
        end

        // ---------- Wait ---------- //
        3'b100: begin
            // FIX_ME: hold PC (pc_en = 0) until the wait condition is met
        end

        default: ; // unused opcodes: defaults above (NOP)

        endcase // Big Case (OP CODE)
    end // always comb

endmodule