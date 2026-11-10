`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Basys 3 wrapper around top_level. Every port here is a real board pin
// (see basys3.xdc); the FIFO handshakes are internal.
//
//   clk      100 MHz oscillator
//   btnC     reset (hold to reset)
//   btnU     send: writes {8'b0, sw[7:0]} into the TX FIFO, one word per press
//   sw[7:0]  byte to send
//   led[7:0] last byte received (read from the RX FIFO)
//   7-seg    left two digits: sw[7:0] (byte to send), right two: last byte
//            received, both in hex. E.g. "4869" = about to send 'H', got 'i'.
//   RsRx     USB-UART, PC -> FPGA  (state machine pin_in)
//   RsTx     USB-UART, FPGA -> PC  (state machine pin_out)
//
// Load uart_tx9600.mem to send switch values to a PC terminal, or
// uart_rx9600.mem to show bytes typed in the terminal on the LEDs.
// 
//////////////////////////////////////////////////////////////////////////////////

module basys3_top #(
    parameter IMEM_INIT_FILE = "program.mem"
) (
    input  logic        clk,
    input  logic        btnC,
    input  logic        btnU,
    input  logic [7:0]  sw,
    output logic [7:0]  led,
    output logic [7:0]  CATHODES,   // {dp,a,b,c,d,e,f,g}, active low
    output logic [3:0]  ANODES,     // {d4,d3,d2,d1}, active low, d1 = rightmost
    input  logic        RsRx,
    output logic        RsTx
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

    logic        wr_req, wr_ready;
    logic [15:0] wr_data;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            wr_req  <= 1'b0;
            wr_data <= '0;
        end
        else if (press) begin
            wr_req  <= 1'b1;
            wr_data <= {8'b0, sw};
        end
        else if (wr_req && wr_ready)            // fifo_writer took it
            wr_req  <= 1'b0;
    end

    // ---------------------------------------------------------------- RX FIFO -> LEDs
    // The FIFO is first word fall through: rx_data already shows the oldest
    // word. Whenever it isn't empty, keep that word and pop it.
    logic        rx_rd_en, rx_empty;
    logic [15:0] rx_data;
    logic [7:0]  last_byte;

    assign rx_rd_en = !rx_empty;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst)          last_byte <= '0;
        else if (!rx_empty) last_byte <= rx_data[7:0];
    end
    assign led = last_byte;

    // ---------------------------------------------------------------- 7-segment display
    SevSegDisp display (
        .CLK      (clk),
        .MODE     (1'b0),                // 0 = hex
        .DATA_IN  ({sw, last_byte}),
        .CATHODES (CATHODES),
        .ANODES   (ANODES)
    );

    // ---------------------------------------------------------------- core
    logic       pin_out;
    logic [1:0] pin_dir;

    top_level_pemu #(.IMEM_INIT_FILE(IMEM_INIT_FILE)) core (
        .clk      (clk),
        .nrst     (nrst),
        .sm_en    (1'b1),
        .wr_req   (wr_req),
        .wr_data  (wr_data),
        .wr_ready (wr_ready),
        .rx_rd_en (rx_rd_en),
        .rx_data  (rx_data),
        .rx_empty (rx_empty),
        .pin_in   (RsRx),
        .pin_out  (pin_out),
        .pin_dir  (pin_dir)
    );

    // Drive RsTx only when the program made the pin an output (set pindirs, 1).
    // Otherwise hold it high, which is UART idle, so the PC doesn't see a
    // stuck-low line while the RX program runs.
    assign RsTx = pin_dir[0] ? pin_out : 1'b1;

endmodule