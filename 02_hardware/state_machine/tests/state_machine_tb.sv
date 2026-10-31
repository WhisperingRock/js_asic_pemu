// By rogelio

`timescale 1ns/1ps
`default_nettype none

interface state_machine_tb_if(input logic clk);
    logic nrst = 1'b0;
    logic en = 1'b0;
    logic [15:0] fifo_in = '0;
    logic in_pin = 1'b0;

    logic [15:0] program_image [0:255];
    event program_loaded;

    function void drive_controls(input logic reset_n, input logic enable);
        nrst = reset_n;
        en = enable;
    endfunction
endinterface

class state_machine_test;
    local virtual state_machine_tb_if vif;
    local logic [15:0] program_image [0:255];
    local bit loaded = 1'b0;

    function new(virtual state_machine_tb_if vif);
        this.vif = vif;
    endfunction

    // Leave reset asserted so program loading cannot race instruction fetches.
    task reset_dut(input int unsigned cycles = 3);
        if (cycles == 0)
            $fatal(1, "Reset must span at least one clock cycle");

        @(negedge vif.clk);
        vif.drive_controls(1'b0, 1'b0);
        loaded = 1'b0;
        repeat (cycles) @(negedge vif.clk);
    endtask

    task load_program(input string filename);
        int fd;

        if (vif.nrst !== 1'b0 || vif.en !== 1'b0)
            $fatal(1, "Load the program while reset is asserted and en is low");

        fd = $fopen(filename, "r");
        if (fd == 0)
            $fatal(1, "Cannot open program file: %s", filename);
        $fclose(fd);

        // Unused addresses contain NOPs; zero would decode as a FIFO PUSH.
        foreach (program_image[a])
            program_image[a] = 16'h5000;
        $readmemh(filename, program_image);

        foreach (program_image[a])
            vif.program_image[a] = program_image[a];
        -> vif.program_loaded;
        loaded = 1'b1;
        $display("Loaded program: %s", filename);
    endtask

    task execute_program(input int unsigned cycles = 100);
        if (!loaded)
            $fatal(1, "Load a program before executing it");
        if (cycles == 0)
            $fatal(1, "Execution must span at least one clock cycle");

        // Drive away from the DUT's rising edge to avoid simulation races.
        @(negedge vif.clk);
        vif.drive_controls(1'b1, 1'b1);
        repeat (cycles) @(negedge vif.clk);
        vif.drive_controls(1'b1, 1'b0);
        @(negedge vif.clk);
    endtask
endclass

module state_machine_tb;

    localparam time CLK_PERIOD = 10ns;
    // Match the DUT's state_t encoding without hierarchical enum references.
    localparam bit [1:0] SM_IDLE  = 2'd0;
    localparam bit [1:0] SM_EXE   = 2'd1;
    localparam bit [1:0] SM_WAIT  = 2'd2;
    localparam bit [1:0] SM_BLOCK = 2'd3;

    // DUT IO
    logic clk = 1'b0;
    logic nrst;
    logic en;

    logic [15:0] fifo_in;
    logic    o_pin;   // output pin
    logic    in_pin;   // input pin

    logic [1:0] po_en; // Pin direction controls.
    logic rx_fifo_wr_en;
    logic tx_fifo_rd_en;
    logic [15:0] fifo_o;

    state_machine_tb_if tb_if(clk);
    state_machine_test test;
    string program_file;
    string wave_file = "state_machine_tb.vcd";
    int run_cycles = 100;

    assign nrst = tb_if.nrst;
    assign en = tb_if.en;
    assign fifo_in = tb_if.fifo_in;
    assign in_pin = tb_if.in_pin;

    always #(CLK_PERIOD / 2) clk = ~clk;

    state_machine #(.ID(0)) dut
    (
        .*
    );

    // Testbench-only backdoor: this is the only place coupled to the PDK's
    // hierarchy. Replace this adapter when a programming interface exists.
    always @(tb_if.program_loaded) begin
        foreach (tb_if.program_image[a])
            dut.mem.u_sram.i_SRAM_1P_behavioral_bm_bist.memory[a] =
                tb_if.program_image[a];
    end

    initial begin
        if (!$value$plusargs("PROGRAM=%s", program_file))
            $fatal(1, "Supply +PROGRAM=path/to/program.mem (16-bit hexadecimal words)");
        void'($value$plusargs("CYCLES=%d", run_cycles));
        void'($value$plusargs("WAVE=%s", wave_file));
        if (run_cycles <= 0)
            $fatal(1, "+CYCLES must be positive");

        $dumpfile(wave_file);
        $dumpvars(0, state_machine_tb);

        test = new(tb_if);
        test.reset_dut();
        test.load_program(program_file);
        test.execute_program(run_cycles);

        $display("Completed %0d clock cycles; PC=%0d, instruction=%h; waveform: %s",
                 run_cycles, dut.pc_out, dut.instruction, wave_file);
        $finish;
    end

    assert_idle_trans: assert property
    (
        @(posedge clk) disable iff(!nrst)
        (dut.ps == SM_IDLE) |=> (dut.ps inside {SM_IDLE, SM_EXE})
    ) else $error("Illegal transition from IDLE");

    assert_execute_transition: assert property 
    (
        @(posedge clk) disable iff (!nrst)
        (dut.ps == SM_EXE) |=> (dut.ps inside {SM_WAIT, SM_EXE, SM_BLOCK})
    ) else $error("Illegal transition from EXE");

    assert_wait_transition: assert property 
    (
        @(posedge clk) disable iff (!nrst)
        (dut.ps == SM_WAIT) |=> (dut.ps inside {SM_WAIT, SM_EXE})
    ) else $error("Illegal transition from WAIT");

    assert_block_trans: assert property
    (
        @(posedge clk) disable iff(!nrst)
        (dut.ps == SM_BLOCK) |=> (dut.ps inside {SM_BLOCK, SM_EXE})
    ) else $error("Illegal transition from BLOCK");

endmodule

`default_nettype wire
