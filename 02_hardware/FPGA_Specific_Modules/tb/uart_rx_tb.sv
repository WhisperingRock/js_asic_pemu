`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// uart_rx_tb -- simulates another device sending UART bytes to the state
// machine running the receive program (receive.mem), and checks every byte
// that comes out of the RX FIFO.
//
//   100 MHz clock, 9600 baud, 8N1, LSB first.
//   One byte takes ~1.04 ms of simulated time; the whole test is ~12 ms.
//   In Vivado use "run all" (the test ends itself with $finish).
//
// Tests:
//   1. a few bytes with idle gaps between them
//   2. bytes back to back (stop bit straight into the next start bit)
//   3. a sender that is 2% fast and one that is 2% slow
//   4. a 1 us low glitch on an idle line -- must NOT produce a byte
//
//////////////////////////////////////////////////////////////////////////////////

module uart_rx_tb;

    parameter MEM_FILE = "program.mem";

    localparam real CLK_PERIOD = 10.0;            // ns, 100 MHz
    localparam int  BAUD       = 9600;
    localparam real BIT_TIME   = 1.0e9 / BAUD;    // ns, ~104166.7

    // ---------------------------------------------------------------- DUT signals
    logic        clk   = 1'b0;
    logic        nrst  = 1'b0;
    logic        sm_en = 1'b0;

    logic        wr_req  = 1'b0;                  // TX side unused here
    logic [15:0] wr_data = '0;
    logic        wr_ready;

    logic        rx_rd_en;
    logic [15:0] rx_data;
    logic        rx_empty;

    logic        pin_in = 1'b1;                   // UART line idles high
    logic        pin_out;
    logic [1:0]  pin_dir;

    always #(CLK_PERIOD / 2) clk = ~clk;

    top_level_pemu #(.IMEM_INIT_FILE(MEM_FILE)) dut (
        .clk      (clk),
        .nrst     (nrst),
        .sm_en    (sm_en),
        .wr_req   (wr_req),
        .wr_data  (wr_data),
        .wr_ready (wr_ready),
        .rx_rd_en (rx_rd_en),
        .rx_data  (rx_data),
        .rx_empty (rx_empty),
        .pin_in   (pin_in),
        .pin_out  (pin_out),
        .pin_dir  (pin_dir)
    );

    // ---------------------------------------------------------------- checker state
    logic [7:0] expected [$];                     // bytes sent, not yet received
    logic [7:0] exp_b;
    int         received = 0;
    int         errors   = 0;

    // ---------------------------------------------------------------- the other device
    // Send one 8N1 frame on pin_in. baud_scale > 1 makes the sender slower.
    task automatic uart_send(input logic [7:0] b, input real baud_scale = 1.0);
        real bt;
        bt = BIT_TIME * baud_scale;
        expected.push_back(b);
        $display("[%0t ns] send   0x%02h '%s'", $time, b, printable(b));

        pin_in = 1'b0;                            // start bit
        #(bt);
        for (int i = 0; i < 8; i++) begin         // data, LSB first
            pin_in = b[i];
            #(bt);
        end
        pin_in = 1'b1;                            // stop bit
        #(bt);
    endtask

    task automatic idle(input real bits);
        pin_in = 1'b1;
        #(BIT_TIME * bits);
    endtask

    function automatic string printable(input logic [7:0] b);
        return (b >= 8'h20 && b < 8'h7F) ? $sformatf("%c", b) : ".";
    endfunction

    // ---------------------------------------------------------------- checker
    // The RX FIFO is first word fall through: rx_data already shows the oldest
    // word. Pop every word as soon as it appears and compare it.
    assign rx_rd_en = !rx_empty;

    always @(posedge clk) begin
        if (nrst && !rx_empty) begin
            received++;
            if (expected.size() == 0) begin
                $error("[%0t ns] got 0x%04h but nothing was sent", $time, rx_data);
                errors++;
            end
            else begin
                exp_b = expected.pop_front();
                if (rx_data !== {8'h00, exp_b}) begin
                    $error("[%0t ns] got 0x%04h, expected 0x%04h", $time, rx_data, {8'h00, exp_b});
                    errors++;
                end
                else
                    $display("[%0t ns] recv   0x%02h '%s'  ok", $time, rx_data[7:0], printable(rx_data[7:0]));
            end
        end
    end

    // ---------------------------------------------------------------- test sequence
    initial begin
        $display("uart_rx_tb: %0d baud, bit time %0.1f ns, program %s", BAUD, BIT_TIME, MEM_FILE);

        // reset, then start the state machine
        repeat (10) @(posedge clk);
        nrst  = 1'b1;
        sm_en = 1'b1;
        #1000;               
        $display("D: isr=%0d osr=%0d (both should be 10411)", dut.sm_0.isr_word, dut.sm_0.osr_word);                     // let the program build its delay constant

        // 1. bytes with idle gaps
        $display("--- bytes with gaps");
        uart_send("H");  idle(3);
        uart_send("i");  idle(3);
        uart_send(8'h00); idle(1);
        uart_send(8'hFF); idle(1);

        // 2. back to back
        $display("--- back to back");
        uart_send(8'h55);
        uart_send(8'hA5);
        uart_send("!");
        idle(2);

        // 3. sender clock off by 2%
        $display("--- sender 2%% fast, then 2%% slow");
        uart_send(8'h3C, 0.98); idle(2);
        uart_send(8'hC3, 1.02); idle(2);

        // 4. glitch on an idle line: 1 us low, much shorter than half a bit
        $display("--- 1 us glitch (should be ignored)");
        pin_in = 1'b0; #1000; pin_in = 1'b1;
        idle(12);

        // done: everything sent must have come back, nothing extra
        idle(2);
        if (expected.size() != 0) begin
            $error("%0d byte(s) never arrived", expected.size());
            errors += expected.size();
        end

        if (errors == 0)
            $display("PASS: %0d bytes received correctly", received);
        else
            $display("FAIL: %0d error(s), %0d bytes received", errors, received);
        $finish;
    end

    // watchdog: if the program hangs, don't run forever
    initial begin
        #(BIT_TIME * 200);
        $fatal(1, "timeout: test didn't finish");
    end

endmodule