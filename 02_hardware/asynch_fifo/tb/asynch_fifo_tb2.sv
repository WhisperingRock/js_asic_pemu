`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// CARP at Calpoly SLO
//
// Testbench: asynch_fifo_tb2
//
//   Structure:
//     - Two free-running, unrelated clocks (wr_clk, rd_clk)
//     - A scoreboard (reference model) that records every word the DUT
//       ACCEPTS and checks every word the DUT RETURNS, in order
//     - Directed tests for reset, full, overflow, drain, and empty latency
//     - Random tests biased toward full and toward empty
//
//   Stimulus is driven on NEGEDGES and the DUT samples on POSEDGES, so there
//   are no races between the testbench and the design.
//
//   Run with:  make tb2
//////////////////////////////////////////////////////////////////////////////////

// ---------------------------------------------------------------------------
// Lint waivers (testbench only, never do this in RTL):
//   BLKSEQ       - the clock generator and scoreboard monitors use blocking
//                  '=' on purpose; the scoreboard must update immediately
//   SYNCASYNCNET - the monitors check nrst on a clock edge, while the DUT
//                  uses it as an async reset; harmless in a testbench
// ---------------------------------------------------------------------------
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */

module asynch_fifo_tb2;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam int  WIDTH     = 32;
    localparam int  DEPTH     = 4;
    localparam int  NUM_SFF   = 2;

    localparam real WR_PERIOD = 10.0;   // same as fifo.xdc
    localparam real RD_PERIOD = 7.0;
    localparam real RD_PHASE  = 3.0;    // start rd_clk offset so edges drift

    localparam int  N_RANDOM  = 500;    // cycles per random phase
    localparam int  SB_SIZE   = 4096;   // scoreboard storage (circular)

    // ------------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------------
    logic             wr_clk = 1'b0;
    logic             rd_clk = 1'b0;
    logic             nrst;
    logic             wr_EN;
    logic             rd_EN;
    logic [WIDTH-1:0] wr_data_i;
    logic [WIDTH-1:0] rd_data_o;
    logic             full;
    logic             empty;

    asynch_fifo #(
        .WIDTH   (WIDTH),
        .DEPTH   (DEPTH),
        .NUM_SFF (NUM_SFF)
    ) dut (
        .wr_clk    (wr_clk),
        .rd_clk    (rd_clk),
        .wr_EN     (wr_EN),
        .rd_EN     (rd_EN),
        .nrst      (nrst),
        .wr_data_i (wr_data_i),
        .rd_data_o (rd_data_o),
        .full      (full),
        .empty     (empty)
    );

    // ------------------------------------------------------------------
    // Clocks: unrelated periods plus a phase offset, so the edges slide
    // past each other over time (that is what makes CDC bugs show up)
    // ------------------------------------------------------------------
    always #(WR_PERIOD/2.0) wr_clk = ~wr_clk;

    initial begin
        #(RD_PHASE);
        forever #(RD_PERIOD/2.0) rd_clk = ~rd_clk;
    end

    // ------------------------------------------------------------------
    // Waveforms (gtkwave wave.vcd)
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, asynch_fifo_tb2);   // must match this module's name
    end

    // ------------------------------------------------------------------
    // Scoreboard
    //   sb_wr = total words the DUT accepted
    //   sb_rd = total words the DUT returned
    //   occupancy = sb_wr - sb_rd
    // ------------------------------------------------------------------
    logic [WIDTH-1:0] sb [0:SB_SIZE-1];
    int sb_wr  = 0;
    int sb_rd  = 0;
    int errors = 0;

    // Coverage-style counters: did we actually exercise the boundaries?
    int full_cycles  = 0;
    int empty_cycles = 0;

    // Write monitor: record every word the DUT accepts
    always @(posedge wr_clk) begin
        if (nrst) begin
            if (full) full_cycles++;
            if (wr_EN && !full) begin
                if (sb_wr - sb_rd >= DEPTH) begin
                    $display("[%0t] ERROR: write accepted while FIFO already held %0d words (overflow, full should have been 1)",
                             $time, DEPTH);
                    errors++;
                end
                sb[sb_wr % SB_SIZE] = wr_data_i;
                sb_wr++;
            end
        end
    end

    // Read monitor: rd_data_o is registered, so a read on this posedge
    // shows up on rd_data_o after the edge. Check it on the next negedge.
    logic             rd_pending  = 1'b0;
    logic [WIDTH-1:0] rd_expected = '0;

    always @(posedge rd_clk) begin
        rd_pending <= 1'b0;
        if (nrst) begin
            if (empty) empty_cycles++;
            if (rd_EN && !empty) begin
                if (sb_wr == sb_rd) begin
                    $display("[%0t] ERROR: read accepted while FIFO held no data (underflow, empty should have been 1)",
                             $time);
                    errors++;
                end
                else begin
                    rd_expected <= sb[sb_rd % SB_SIZE];
                    rd_pending  <= 1'b1;
                    sb_rd++;
                end
            end
        end
    end

    always @(negedge rd_clk) begin
        if (rd_pending && (rd_data_o !== rd_expected)) begin
            $display("[%0t] ERROR: read data mismatch. expected %h, got %h",
                     $time, rd_expected, rd_data_o);
            errors++;
        end
    end

    // ------------------------------------------------------------------
    // Helper tasks
    // ------------------------------------------------------------------

    // Present n random words on back-to-back write cycles
    task automatic write_burst(input int n);
        for (int k = 0; k < n; k++) begin
            @(negedge wr_clk);
            wr_EN     = 1'b1;
            wr_data_i = $random;
        end
        @(negedge wr_clk);
        wr_EN = 1'b0;
    endtask

    // Hold rd_EN high until the scoreboard AND the DUT both say empty
    task automatic drain();
        int guard;
        guard = 0;
        @(negedge rd_clk);
        rd_EN = 1'b1;
        while (!((sb_rd == sb_wr) && empty) && (guard < 200)) begin
            @(negedge rd_clk);
            guard++;
        end
        rd_EN = 1'b0;
        @(negedge rd_clk);   // let the last read's data check run
        if (guard >= 200) begin
            $display("[%0t] ERROR: drain timed out (%0d words never came out)",
                     $time, sb_wr - sb_rd);
            errors++;
        end
    endtask

    task automatic check(input logic cond, input string msg);
        if (cond) $display("  PASS: %s", msg);
        else begin
            $display("  FAIL: %s", msg);
            errors++;
        end
    endtask

    // ------------------------------------------------------------------
    // Watchdog: never hang forever
    // ------------------------------------------------------------------
    initial begin
        #(2_000_000);
        $display("ERROR: simulation timeout");
        $finish;
    end

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    int lat;

    initial begin
        nrst      = 1'b0;
        wr_EN     = 1'b0;
        rd_EN     = 1'b0;
        wr_data_i = '0;

        // ---------------- Test 1: reset ----------------
        $display("\n--- Test 1: reset ---");
        #50;
        nrst = 1'b1;
        repeat (5) @(negedge wr_clk);
        check(empty == 1'b1, "empty is 1 after reset");
        check(full  == 1'b0, "full is 0 after reset");

        // ---------------- Test 2: fill to full ----------------
        $display("\n--- Test 2: write %0d words with no reads ---", DEPTH);
        write_burst(DEPTH);
        check(full == 1'b1, $sformatf("full is 1 after %0d writes", DEPTH));

        // ---------------- Test 3: overflow attempt ----------------
        $display("\n--- Test 3: keep writing while full (must be ignored) ---");
        @(negedge wr_clk);
        wr_EN     = 1'b1;
        wr_data_i = 32'hDEAD_BEEF;
        repeat (3) @(negedge wr_clk);
        wr_EN = 1'b0;
        check(sb_wr == DEPTH, "no extra words accepted while full");

        // ---------------- Test 4: drain ----------------
        $display("\n--- Test 4: read everything back ---");
        drain();
        check(sb_rd == DEPTH, $sformatf("read back %0d words in order", DEPTH));
        check(empty == 1'b1, "empty is 1 after draining");

        // ---------------- Test 5: empty release latency ----------------
        $display("\n--- Test 5: how long until the reader sees a new word? ---");
        @(negedge wr_clk);
        wr_EN     = 1'b1;
        wr_data_i = 32'hA5A5_0001;
        @(negedge wr_clk);
        wr_EN = 1'b0;
        lat = 0;
        while (empty && lat < 50) begin
            @(posedge rd_clk);
            lat++;
        end
        $display("  INFO: empty released %0d rd_clk edges after the write (synchronizer delay, NUM_SFF = %0d)",
                 lat, NUM_SFF);
        check(lat < 50, "empty eventually released");
        drain();

        // ---------------- Test 6: random, writer-heavy ----------------
        $display("\n--- Test 6: random, writes 75%% / reads 25%% (hits full) ---");
        fork
            begin
                repeat (N_RANDOM) begin
                    @(negedge wr_clk);
                    wr_EN     = (($random & 3) != 0);
                    wr_data_i = $random;
                end
                @(negedge wr_clk);
                wr_EN = 1'b0;
            end
            begin
                repeat (N_RANDOM) begin
                    @(negedge rd_clk);
                    rd_EN = (($random & 3) == 0);
                end
                @(negedge rd_clk);
                rd_EN = 1'b0;
            end
        join
        drain();

        // ---------------- Test 7: random, reader-heavy ----------------
        $display("\n--- Test 7: random, writes 25%% / reads 75%% (hits empty) ---");
        fork
            begin
                repeat (N_RANDOM) begin
                    @(negedge wr_clk);
                    wr_EN     = (($random & 3) == 0);
                    wr_data_i = $random;
                end
                @(negedge wr_clk);
                wr_EN = 1'b0;
            end
            begin
                repeat (N_RANDOM) begin
                    @(negedge rd_clk);
                    rd_EN = (($random & 3) != 0);
                end
                @(negedge rd_clk);
                rd_EN = 1'b0;
            end
        join
        drain();

        // ---------------- Summary ----------------
        $display("\n==============================================");
        $display("  words written : %0d", sb_wr);
        $display("  words read    : %0d", sb_rd);
        $display("  full cycles   : %0d (should be > 0)", full_cycles);
        $display("  empty cycles  : %0d (should be > 0)", empty_cycles);
        check(sb_wr == sb_rd, "every accepted word came back out");
        if (errors == 0) $display("  RESULT: PASS");
        else             $display("  RESULT: FAIL (%0d errors)", errors);
        $display("==============================================\n");
        $finish;
    end

endmodule

/* verilator lint_on SYNCASYNCNET */
/* verilator lint_on BLKSEQ */
