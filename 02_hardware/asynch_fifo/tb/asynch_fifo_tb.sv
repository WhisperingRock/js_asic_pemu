`timescale 1ns / 1ps

module asynch_fifo_tb;

    // ============================================================
    // Parameters
    // ============================================================
    localparam int WIDTH   = 32;
    localparam int DEPTH   = 4;
    localparam int NUM_SFF = 2;

    // ============================================================
    // DUT Signals
    // ============================================================
    logic wr_clk;
    logic rd_clk;

    logic wr_EN;
    logic rd_EN;

    logic nrst;

    logic [WIDTH-1:0] wr_data_i;
    logic [WIDTH-1:0] rd_data_o;

    logic full;
    logic empty;

    // ============================================================
    // DUT
    // ============================================================
    asynch_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .NUM_SFF(NUM_SFF)
    ) dut (
        .wr_clk     (wr_clk),
        .rd_clk     (rd_clk),

        .wr_EN      (wr_EN),
        .rd_EN      (rd_EN),

        .nrst       (nrst),

        .wr_data_i  (wr_data_i),
        .rd_data_o  (rd_data_o),

        .full       (full),
        .empty      (empty)
    );


    initial begin
    $dumpfile("wave_tb.vcd");
    $dumpvars(0, asynch_fifo_tb);
    end
    
    // ============================================================
    // Asynchronous Clocks
    //
    // Write clock = 100 MHz
    // Read clock  = ~71.4 MHz
    //
    // Different periods are intentional.
    // ============================================================
    initial begin
        wr_clk = 1'b0;
        forever #5 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #7 rd_clk = ~rd_clk;
    end

    // ============================================================
    // Write Task
    // ============================================================
    task automatic fifo_write(input logic [WIDTH-1:0] data);
        begin
            // Wait until FIFO has room
            while (full)
                @(posedge wr_clk);

            @(negedge wr_clk);
            wr_data_i = data;
            wr_EN     = 1'b1;

            @(negedge wr_clk);
            wr_EN     = 1'b0;
        end
    endtask

    // ============================================================
    // Read Task
    // ============================================================
    task automatic fifo_read;
        begin
            // Wait until FIFO has data
            while (empty)
                @(posedge rd_clk);

            @(negedge rd_clk);
            rd_EN = 1'b1;

            @(negedge rd_clk);
            rd_EN = 1'b0;
        end
    endtask

    // ============================================================
    // Test Sequence
    // ============================================================
    initial begin

        // Initial values
        nrst      = 1'b0;
        wr_EN     = 1'b0;
        rd_EN     = 1'b0;
        wr_data_i = '0;

        // Hold reset for several clock cycles
        repeat (4) @(posedge wr_clk);

        nrst = 1'b1;

        $display("=================================================");
        $display("Starting Asynchronous FIFO Testbench");
        $display("=================================================");

        // Give synchronization logic some time after reset
        repeat (4) @(posedge wr_clk);

        // ========================================================
        // TEST 1: Initial FIFO state
        // ========================================================
        $display("\nTEST 1: Checking FIFO after reset");

        if (empty)
            $display("PASS: FIFO is empty after reset");
        else
            $error("FAIL: FIFO should be empty after reset");

        if (!full)
            $display("PASS: FIFO is not full after reset");
        else
            $error("FAIL: FIFO should not be full after reset");


        // ========================================================
        // TEST 2: Single Write / Single Read
        // ========================================================
        $display("\nTEST 2: Single write/read");

        fifo_write(32'hDEADBEEF);

        // Allow empty flag to synchronize into read clock domain
        repeat (NUM_SFF + 2) @(posedge rd_clk);

        fifo_read();

        // Depending on FIFO implementation, rd_data_o may update
        // on the read clock edge, so wait one additional edge.
        @(posedge rd_clk);
        #1;

        if (rd_data_o == 32'hDEADBEEF)
            $display("PASS: Read DEADBEEF correctly");
        else
            $error(
                "FAIL: Expected DEADBEEF, received %h",
                rd_data_o
            );


        // ========================================================
        // TEST 3: Fill the FIFO
        // ========================================================
        $display("\nTEST 3: Filling FIFO");

        fifo_write(32'h11111111);
        fifo_write(32'h22222222);
        fifo_write(32'h33333333);
        fifo_write(32'h44444444);

        // Give full flag time to update
        repeat (NUM_SFF + 2) @(posedge wr_clk);

        if (full)
            $display("PASS: FIFO asserted FULL");
        else
            $error("FAIL: FIFO should be FULL");


        // ========================================================
        // TEST 4: Empty the FIFO
        // ========================================================
        $display("\nTEST 4: Reading all FIFO entries");

        fifo_read();
        @(posedge rd_clk);
        #1;
        $display("Read Data = %h", rd_data_o);

        fifo_read();
        @(posedge rd_clk);
        #1;
        $display("Read Data = %h", rd_data_o);

        fifo_read();
        @(posedge rd_clk);
        #1;
        $display("Read Data = %h", rd_data_o);

        fifo_read();
        @(posedge rd_clk);
        #1;
        $display("Read Data = %h", rd_data_o);

        // Allow empty flag to propagate
        repeat (NUM_SFF + 2) @(posedge rd_clk);

        if (empty)
            $display("PASS: FIFO asserted EMPTY");
        else
            $error("FAIL: FIFO should be EMPTY");


        // ========================================================
        // TEST 5: Simultaneous Asynchronous Reads/Writes
        // ========================================================
        $display("\nTEST 5: Simultaneous asynchronous read/write");

        fork

            begin : WRITE_PROCESS
                fifo_write(32'hA0000001);
                fifo_write(32'hA0000002);
                fifo_write(32'hA0000003);
                fifo_write(32'hA0000004);
                fifo_write(32'hA0000005);
                fifo_write(32'hA0000006);
                fifo_write(32'hA0000007);
                fifo_write(32'hA0000008);
            end

            begin : READ_PROCESS
                // Delay reads slightly so FIFO gets some data
                repeat (4) @(posedge rd_clk);

                repeat (8) begin
                    fifo_read();

                    @(posedge rd_clk);
                    #1;

                    $display(
                        "Time = %0t | Read Data = %h",
                        $time,
                        rd_data_o
                    );
                end
            end

        join


        // ========================================================
        // Finish
        // ========================================================
        repeat (10) @(posedge wr_clk);

        $display("\n=================================================");
        $display("Asynchronous FIFO Testbench Complete");
        $display("=================================================");

        $finish;
    end


    // ============================================================
    // Optional Signal Monitor
    // ============================================================
    initial begin
        $monitor(
            "t=%0t | wr_EN=%b wr_data=%h full=%b | rd_EN=%b rd_data=%h empty=%b",
            $time,
            wr_EN,
            wr_data_i,
            full,
            rd_EN,
            rd_data_o,
            empty
        );
    end

endmodule
