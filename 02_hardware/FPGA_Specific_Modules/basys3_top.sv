`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Basys 3 wrapper around top_level_pemu: SPI slave test.
//
//   SM0 (regular, spi_tx.mem): sends bytes to the master on MISO
//   SM1 (bi,      spi_rx.mem): receives bytes from the master on MOSI
//
//   Pmod JB = SM0 (regular)                    Pmod JC = SM1 (bidirectional)
//     JB1  sm0_in[0]   bank 0  CS              JC1  sm1_pins[0]  bank 2  MOSI
//     JB2  sm0_in[1]   bank 1  SCK             JC2  sm1_pins[1]  bank 3
//     JB3  sm0_out[0]  MISO                    JC3  sm1_pins[2]  bank 4
//     JB4  sm0_out[1]  (unused in the demo)    JC4  sm1_pins[3]  bank 5
//   SM0's outputs are driven only while that output's pindirs bit is 1,
//   otherwise they float (Z). Unused JC pins are pulled down in the XDC.
//////////////////////////////////////////////////////////////////////////////////

module basys3_top #(
    parameter SM0_IMEM_INIT_FILE = "spi_tx.mem",
    parameter SM1_IMEM_INIT_FILE = "spi_rx.mem"
) (
    input  logic        clk,
    input  logic        btnC,
    input  logic        btnU,
    input  logic [7:0]  sw,
    input  logic        sw15,      // run SM0
    output logic [7:0]  LED,
    output logic [7:0]  seg,       // {dp,a,b,c,d,e,f,g}, active low. Cathode. seg in XDC
    output logic [3:0]  an,        // {d4,d3,d2,d1}, active low, d1 = rightmost. Anode.

    input  logic [1:0]  sm0_in,    // JB1, JB2
    output wire  [1:0]  sm0_out,   // JB3, JB4
    inout  wire  [3:0]  sm1_pins   // JC1-JC4
);

    // ---------------------------------------------------------------- reset
    // btnC is active high and asynchronous. Assert reset right away, release
    // it in step with clk so every flop leaves reset on the same edge.
    logic [1:0] rst_sync;
    logic       nrst;

    always_ff @(posedge clk or posedge btnC) begin
        if (btnC) rst_sync <= 2'b00;
        else      rst_sync <= {rst_sync[0], 1'b1};
    end
    assign nrst = rst_sync[1];

    // ---------------------------------------------------------------- send button
    // Synchronize btnU, debounce it (~10 ms), and turn each press into one
    // write request that stays up until fifo_writer takes it.
    logic [1:0]  btn_sync;
    logic [19:0] db_cnt;
    logic        btn_stable, btn_prev, press;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            btn_sync   <= '0;
            db_cnt     <= '0;
            btn_stable <= 1'b0;
            btn_prev   <= 1'b0;
        end
        else begin
            btn_sync <= {btn_sync[0], btnU};
            btn_prev <= btn_stable;
            if (btn_sync[1] == btn_stable)
                db_cnt <= '0;                     // no change: keep counting from 0
            else if (&db_cnt) begin               // changed and held ~10.5 ms
                btn_stable <= btn_sync[1];
                db_cnt     <= '0;
            end
            else
                db_cnt <= db_cnt + 1'b1;
        end
    end
    assign press = btn_stable && !btn_prev;

    // SM0's TX FIFO gets the MISO bytes
    logic        sm0_wr_req, sm0_wr_ready;
    logic [15:0] sm0_wr_data;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            sm0_wr_req  <= 1'b0;
            sm0_wr_data <= '0;
        end
        else if (press) begin
            sm0_wr_req  <= 1'b1;
            sm0_wr_data <= {8'b0, sw};
        end
        else if (sm0_wr_req && sm0_wr_ready)    // fifo_writer took it
            sm0_wr_req  <= 1'b0;
    end

    // run switch: synchronize it (it's a switch, not clk-aligned)
    logic [1:0] run_sync;
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) run_sync <= '0;
        else       run_sync <= {run_sync[0], sw15};
    end

    // ---------------------------------------------------------------- core ports
    // top_level_pemu uses [n] = state machine n
    logic [1:0]       wr_req, wr_ready;
    logic [1:0][15:0] wr_data;
    logic [1:0]       rx_rd_en, rx_empty;
    logic [1:0][15:0] rx_data;
    logic [1:0]       sm0_val, sm0_oe;
    logic [3:0]       sm1_oe;

    assign wr_req       = {1'b0, sm0_wr_req};   // SM1's TX FIFO is not used
    assign wr_data[0]   = sm0_wr_data;
    assign wr_data[1]   = '0;
    assign sm0_wr_ready = wr_ready[0];

    // ---------------------------------------------------------------- RX FIFOs -> LEDs
    logic [7:0] last_byte;

    assign rx_rd_en = ~rx_empty;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst)             last_byte <= '0;
        else if (!rx_empty[1]) last_byte <= rx_data[1][7:0];
    end
    assign LED = last_byte;

    // ---------------------------------------------------------------- 7-segment display
    SevSegDisp display (
        .CLK      (clk),
        .MODE     (1'b0),                // 0 = hex
        .DATA_IN  ({sw, last_byte}),
        .CATHODES (seg),
        .ANODES   (an)
    );

    // ---------------------------------------------------------------- core
    top_level_pemu #(
        .SM0_IMEM_INIT_FILE (SM0_IMEM_INIT_FILE),
        .SM1_IMEM_INIT_FILE (SM1_IMEM_INIT_FILE)
    ) core (
        .clk      (clk),
        .nrst     (nrst),
        .sm_en    (2'b11),
        .wr_req   (wr_req),
        .wr_data  (wr_data),
        .wr_ready (wr_ready),
        .rx_rd_en (rx_rd_en),
        .rx_data  (rx_data),
        .rx_empty (rx_empty),
        .sm0_in   (sm0_in),                  // bank 0 = JB1, bank 1 = JB2
        .sm0_out  (sm0_val),
        .sm0_oe   (sm0_oe),
        .sm1_pins (sm1_pins),                // straight to the pads (inout)
        .sm1_oe   (sm1_oe)
    );

    assign sm0_out[0] = sm0_val[0]; // JB3 (MISO)
    assign sm0_out[1] = sm0_val[1]; // JB4

endmodule