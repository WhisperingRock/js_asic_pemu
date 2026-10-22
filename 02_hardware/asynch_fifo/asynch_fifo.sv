`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Parameterized Asynchronous FIFO
//   WIDTH = bits per entry
//   DEPTH = number of entries (must be a power of 2)
//
// First Word Fall Through (FWFT) Behavior
//
// Read Data is always on output. Read Ptr is only used to detect FULL or EMPTY
//
//////////////////////////////////////////////////////////////////////////////////

module asynch_fifo #(parameter WIDTH = 32, DEPTH = 4, NUM_SFF = 2)(
    input  logic wr_clk,
    input  logic rd_clk,

    input  logic wr_EN,
    input  logic rd_EN,

    input  logic nrst,

    input  logic [WIDTH - 1:0] wr_data_i,
    output logic [WIDTH - 1:0] rd_data_o,

    output logic full,
    output logic empty
);

    localparam CL2_D = $clog2(DEPTH);

    logic [WIDTH-1:0] sram [DEPTH-1:0];

    logic [CL2_D:0] wr_ptr; // no -1 b/c of rollover bit
    logic [CL2_D:0] rd_ptr; // no -1 b/c of rollover bit
    logic [CL2_D:0] wr_ptr_nxt; // no -1 b/c of rollover bit
    logic [CL2_D:0] rd_ptr_nxt; // no -1 b/c of rollover bit

    assign wr_ptr_nxt = wr_ptr + 1'b1;
    assign rd_ptr_nxt = rd_ptr + 1'b1;

    logic [CL2_D:0] wr_gray_ptr;
    logic [CL2_D:0] rd_gray_ptr; 

    logic [CL2_D:0] wr_gptr_synch; // synch_ptr CDC
    logic [CL2_D:0] rd_gptr_synch; // synch_ptr CDC

    logic [CL2_D:0] wptr_gray_nxt; //ouput for inst. module encoder
    logic [CL2_D:0] rptr_gray_nxt; //ouput for inst. module encoder

    bin2_to_gray_encoder #(.WIDTH(CL2_D + 1)) Wptr_b2g_encoder(
        .bin_i(wr_ptr_nxt),
        .gray_o(wptr_gray_nxt)
    );

    bin2_to_gray_encoder #(.WIDTH(CL2_D + 1)) Rptr_b2g_encoder(
        .bin_i(rd_ptr_nxt),
        .gray_o(rptr_gray_nxt)
    );

    synch_ff #(.WIDTH(CL2_D + 1), .STAGES(NUM_SFF)) wptr_to_rclk(
        .clk(rd_clk),     // DESTINATION domain clock
        .nrst(nrst),
        .d_i(wr_gray_ptr),     // from the source domain (must be registered there!)
        .q_o(wr_gptr_synch)
    );

    synch_ff #(.WIDTH(CL2_D + 1), .STAGES(NUM_SFF)) rptr_to_wclk(
        .clk(wr_clk),     // DESTINATION domain clock
        .nrst(nrst),
        .d_i(rd_gray_ptr),     // from the source domain (must be registered there!)
        .q_o(rd_gptr_synch)
    );

    // Full: top two bits inverted, all remaining bits equal (Gray code, DEPTH >= 4)
    assign full = (wr_gray_ptr[CL2_D:CL2_D-1] == ~rd_gptr_synch[CL2_D:CL2_D-1])
                    && (wr_gray_ptr[CL2_D-2:0]     ==  rd_gptr_synch[CL2_D-2:0]);
    

    //if rollover bits are equal, AND if other bits are equal
    assign empty = (wr_gptr_synch == rd_gray_ptr);


    //FWFT Behavior
    assign rd_data_o = sram[rd_ptr[CL2_D-1:0]];

    // Write Logic
    always_ff @(posedge wr_clk or negedge nrst) begin
        if (!nrst) begin
            wr_ptr <= '0;
            wr_gray_ptr <= '0;
        end
        else
            if (wr_EN && !full) begin
                sram[wr_ptr[CL2_D-1:0]] <= wr_data_i;
                wr_ptr <= wr_ptr_nxt;
                wr_gray_ptr <= wptr_gray_nxt;
            end
    end


    // Read Logic
    always_ff @(posedge rd_clk or negedge nrst) begin
        if (!nrst) begin
            rd_ptr <= '0;
            rd_gray_ptr <= '0;
        end
        else
            if (rd_EN && !empty) begin
                //Commented out b/c of FWFT change
                //rd_data_o <= sram[rd_ptr[CL2_D-1:0]];
                rd_ptr <= rd_ptr_nxt;
                rd_gray_ptr <= rptr_gray_nxt;
            end
    end

endmodule
