`timescale 1ns/1ps


    //----------
    // PC SEL
    // 00 = pc + 4
    // 01 = Jmp / Beq
    // 10 = Fifo
    // 11 = unused?
    //------

module decoder_sm(
    input  logic [15:0] ir,
    input logic alu_result,
    input logic [2:0] ID,

    output logic [15:0] jmp_addr_set_data,
    output logic [1:0] pc_sel,
    output logic pc_en,
    output logic jmp_take, // jump_mux_sel


    output logic x_en,
    output logic y_en,
    output logic isr_en,
    output logic osr_en,
    output logic o_pin_en,
    output logic pindirs_en, //bi-direction st_mch only
    output logic txfifo_rd_en,
    output logic rxfifo_wr_en,
    output logic [2:0]eight_one_mux_sel,
    output logic data_mux_sel,

    output logic [1:0] ALU_FUN,
    output logic [1:0] alu_a_mux,
    output logic alu_b_mux
);
    /*
        Destination 3 bits
        000: pins
        001: X (scratch register X)
        010: Y (scratch register Y)
        011: NULL (discard data)
        100: PINDIRS // !Inout StateMachine only!
        101: PC
        110: ISR (also sets ISR shift counter to Bit count)
        111: OSR
    */
    logic [2:0] dest;

    assign dest = ir[7:5];
    assign jmp_addr_set_data = ir[4:0];

    always_comb begin
        //default
        txfifo_rd_en = 1'b0;
        rxfifo_wr_en = 1'b0;
        eight_one_mux_sel = 3'b011; // default NULL
        pc_sel = 2'b00;
        pc_en = 1'b1;
        x_en = 1'b0;
        y_en = 1'b0;
        isr_en = 1'b0;
        osr_en = 1'b0;
        o_pin_en = 1'b0;
        data_mux_sel = 1'b0;
        pindirs_en = 1'b0;
        pc_jmp_sel = 1'b0;

        case(ir[14:12])

        // ---------- Push and Pull ---------- //
        3'b000: begin
            pc_sel = 2'b01;
            if(ir[15] == 0) begin // PUSH
                txfifo_rd_en = 1'b0;

                rxfifo_wr_en = 1'b1;
                isr_en = 1'b0;
                osr_en = 1'b0;
            end
            if(ir[15] == 1) begin // PULL
                txfifo_rd_en = 1'b1;

                rxfifo_wr_en = 1'b0;
                isr_en = 1'b0;
                osr_en = 1'b1;
            end
        end

        // ---------- Out and In ---------- //
        3'b001: begin

            if(ir[15] == 0) begin // OUT: OSR -> Dest
                eight_one_mux_sel = 3'b111; // OSR SEL
                isr_en = 1'b0;
                osr_en = 1'b0;
                case(dest)
                    3'b000: //pins
                        o_pin_en = 1'b1;
                    3'b001: //X (scratch register X)
                        x_en = 1'b1;
                    3'b010: //Y (scratch register Y)
                        y_en = 1'b1;
                    3'b011: //NULL (discard data)
                        eight_one_mux_sel = 3'b011;
                    // 3'b100: //PINDIRS // !Inout StateMachine only!
                    // ; // FIX_ME! TEMP NULL
                    3'b101: begin //PC
                        pc_en = 1'b1;
                        pc_sel = 2'b11;
                    end
                    3'b110: begin //ISR (also sets ISR shift counter to Bit count)
                        isr_en = 1'b1;
                        osr_en = 1'b0;
                    end
                    3'b111: begin //OSR
                        isr_en = 1'b0;
                        osr_en = 1'b1;
                    end
                endcase
            end
            if(ir[15] == 1) begin // IN: ISR <- SRC/Dest
                eight_one_mux_sel = dest; // Source!
                isr_en = 1'b1;
            end
        end


        // ---------- Jmp and Beq ---------- //
3'b010: begin
    if (ir[15] == 1'b1) begin // JMP
        ALU_FUN = 2'b00; // eq for every condition
        case (ir[7:5]) // Condition
            3'b000: jmp_take = 1'b1;          // always
            3'b001: begin                     // !X : X == 0
                alu_a_mux = 2'b00;            // x
                alu_b_mux = 1'b0;             // 0
                jmp_take  = alu_result;
            end
            3'b010: begin                     // X-- : X != 0 (prior to decrement)
                alu_a_mux = 2'b00;            // x
                alu_b_mux = 1'b0;             // 0
                jmp_take  = !alu_result;
                x_dec     = 1'b1;             // decrement whether or not taken
            end
            3'b011: begin                     // !Y : Y == 0
                alu_a_mux = 2'b01;            // y
                alu_b_mux = 1'b0;             // 0
                jmp_take  = alu_result;
            end
            3'b100: begin                     // Y-- : Y != 0 (prior to decrement)
                alu_a_mux = 2'b01;            // y
                alu_b_mux = 1'b0;             // 0
                jmp_take  = !alu_result;
                y_dec     = 1'b1;
            end
            3'b101: begin                     // X != Y
                alu_a_mux = 2'b00;            // x
                alu_b_mux = 1'b1;             // y
                jmp_take  = !alu_result;
            end
            3'b110: begin                     // PIN high : pins != 0
                alu_a_mux = 2'b10;            // pins
                alu_b_mux = 1'b0;             // 0
                jmp_take  = !alu_result;
            end
            3'b111: begin                     // !OSRE : OSR != 0
                alu_a_mux = 2'b11;            // osr
                alu_b_mux = 1'b0;             // 0
                jmp_take  = !alu_result;
            end
        endcase

        if (jmp_take)
            pc_sel = 2'b01;                   // jump to ir[4:0]
        // else pc_sel stays 2'b00 -> next instruction
        end

    else begin // BEQ

    end



    end
        3'b100: begin // wait

        end

        // ---------- Set and Mov ---------- //
        3'b011: begin 
            eight_one_mux_sel = dest;

            // invalid dest check
            if(ir[15] == 1) begin // SET
                data_mux_sel = 1'b1;

                case (dest)
                    3'b000: o_pin_en   = 1'b1; // PINS
                    3'b001: x_en       = 1'b1; // X: 5 LSBs = Data, rest cleared
                    3'b010: y_en       = 1'b1; // Y: 5 LSBs = Data, rest cleared
                    3'b100: pindirs_en = 1'b1; // PINDIRS
                    default: ;                 // 011 reserved, 101-111 undefined
                endcase
            end // if statement
            else begin // Mov
                data_mux_sel = 1'b0;
                // Source
                eight_one_mux_sel = ir[2:0];

                case(dest)
                    3'b000: //pins
                        o_pin_en = 1'b1;
                    3'b001: //X (scratch register X)
                        x_en = 1'b1;
                    3'b010: //Y (scratch register Y)
                        y_en = 1'b1;
                    // 3'b011: //NULL (discard data)
                    //     ;
                    // 3'b100: //PINDIRS // !Inout StateMachine only!
                    // ; // FIX_ME
                    3'b101: begin //PC
                        pc_en = 1'b1;
                        pc_sel = 2'b11;
                    end
                    3'b110: begin //ISR (also sets ISR shift counter to Bit count)
                        isr_en = 1'b1;
                        osr_en = 1'b0;
                    end
                    3'b111: begin //OSR
                        isr_en = 1'b0;
                        osr_en = 1'b1;
                    end
                endcase
            end // else statement
        end

        endcase // Big Case (OP CODE)
    end // always comb

    
endmodule