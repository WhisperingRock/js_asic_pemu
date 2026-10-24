// By rogelio

`default_nettype none

module state_machine_tb;

    //DUT IO
    logic clk;
    logic nrst;
    logic en;

    logic [15:0] fifo_in;
    logic    o_pin;   // ouput pin
    logic    in_pin;   // input pin

    logic [1:0]  po_en; // this will tell us if the pins are input or output.
    logic rx_fifo_wr_en;
    logic tx_fifo_rd_en;
    logic [15:0] fifo_o;

    state_machine #(.ID(0)) dut
    (
        .*
    );

    assert_idle_trans: assert property
    (
        @(posedge clk) disable iff(!nrst)
        (dut.ps == dut.IDLE) |=> (dut.ps inside {dut.IDLE, dut.EXE})
    ) else $error("Illegal transition from IDLE");

    assert_execute_transition: assert property 
    (
        @(posedge clk) disable iff (!nrst)
        (dut.ps == dut.EXE) |=> (dut.ps inside {dut.WAIT, dut.EXE, dut.BLOCK})
    ) else $error("Illegal transition from WAIT");

    assert_wait_transition: assert property 
    (
        @(posedge clk) disable iff (!nrst)
        (dut.ps == dut.WAIT) |=> (dut.ps inside {dut.WAIT, dut.EXE})
    ) else $error("Illegal transition from WAIT");

    assert_block_trans: assert property
    (
        @(posedge clk) disable iff(!nrst)
        (dut.ps == dut.BLOCK) |=> (dut.ps inside{dut.EXE})
    ) else $error("Illegal transition from BLOCK");

endmodule