// By rogelio

`default_nettype none

module state_machine_tb;

    //DUT IO
    logic clk;
    logic nrst;
    logic en;

    logic [15:0] fifo_in;
    logic [15:0] pc_next;
    logic    o_pin;   // ouput pin
    logic    in_pin;   // input pin

    logic [1:0]  po_en; // this will tell us if the pins are input or output.
    logic rx_fifo_wr_en;
    logic tx_fifo_rd_en;
    logic [15:0] fifo_o;

    state_machine #(.ID(0))
    (
        .(*)
    );

    

endmodule