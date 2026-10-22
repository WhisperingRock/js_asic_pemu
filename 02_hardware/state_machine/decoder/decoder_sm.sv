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

    output logic [15:0] jmp_beq_addr,
    output logic [1:0] pc_sel,
    output logic pc_en,
    output logic x_en,
    output logic y_en,
    output logic isr_en,
    output logic osr_en,
    output logic o_pin_en,
    output logic txfifo_rd_en,
    output logic rxfifo_wr_en,
    output logic [2:0]out_in_mux_sel
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
    assign jmp_beq_addr = ir[4:0];

    always_comb begin
        //default
        txfifo_rd_en = 1'b0;
        rxfifo_wr_en = 1'b0;
        out_in_mux_sel = 3'b011; // default NULL
        pc_sel = 2'b00;
        pc_en = 1'b1;
        x_en = 1'b0;
        y_en = 1'b0;
        isr_en = 1'b0;
        osr_en = 1'b0;
        o_pin_en = 1'b0;

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
            out_in_mux_sel = dest;

            if(ir[15] == 0) begin // OUT: OSR -> Dest
                isr_en = 1'b0;
                osr_en = 1'b0;
                case(dest):
                    3'b000: //pins
                        o_pin_en = 1'b1;
                    3'b001: //X (scratch register X)
                        x_en = 1'b1;
                    3'b010: //Y (scratch register Y)
                        y_en = 1'b1;
                    3'b011: //NULL (discard data)
                        out_in_mux_sel = 3'b011;
                    3'b100: //PINDIRS // !Inout StateMachine only!
                    ; // FIX_ME
                    3'b101: //PC
                        pc_en = 1'b1;
                        pc_sel = 2'b11;
                    3'b110: //ISR (also sets ISR shift counter to Bit count)
                    ; // FIX_ME
                    3'b111: //OSR
                    ; // FIX_ME
                endcase
            end
            if(ir[15] == 1) begin // IN: ISR <- SRC/Dest
                isr_en = 1'b1;
            end
        end

        // ---------- Jmp and Beq ---------- //
        3'b010: begin 
            //if (COND TRUE) begin
                pc_sel = 2'b01;
                pc_en = 1'b1;
            //end

        end
        3'b100: begin // wait

        end

        endcase
    end // always comb

    
endmodule