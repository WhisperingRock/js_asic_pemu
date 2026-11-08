# FSM simulation

Run these commands in Bash from the `js_asic_pemu` repository root. The current
`imem` implementation uses inferred FPGA RAM, so no IHP model files are needed:

```bash
rtl=(
    02_hardware/state_machine/tests/state_machine_tb.sv
    02_hardware/state_machine/state_machine.sv
    02_hardware/state_machine/decoder/decoder_sm.sv
    02_hardware/state_machine/imem/imem.sv
    02_hardware/state_machine/pc/pc.sv
    02_hardware/state_machine/ALU_EQ/alu.sv
    02_hardware/common_rtl/mux4to1.sv
)
```

With Verilator:

```bash
verilator --binary --timing --assert --trace-vcd \
    --top-module state_machine_tb "${rtl[@]}"

./obj_dir/Vstate_machine_tb \
    +PROGRAM=/path/to/program.mem +CYCLES=100 +WAVE=state_machine_tb.vcd
```

The testbench uses classes, a virtual interface, and concurrent assertions;
Icarus 12 is not a supported simulator for this testbench.

With Xcelium:

```bash
xrun -64bit -sv -access +rwc \
    -top state_machine_tb "${rtl[@]}" \
    +PROGRAM=/path/to/program.mem +CYCLES=100 +WAVE=state_machine_tb.vcd
```

Open the waveform:

```bash
gtkwave state_machine_tb.vcd
```

## Program format and execution

`+PROGRAM` is required and names a hexadecimal `$readmemh` file. Each word is
16 bits, addresses are word indices from 0 to 255, and paths are relative to
the directory where the simulator runs. Comments and hexadecimal `@address`
directives are supported. For example, this program executes two NOPs and
then loops at address 2:

```text
5000 // NOP
5000 // NOP
A002 // JMP 2
```

Unspecified locations are initialized to `5000` (NOP), rather than zero,
which would decode as PUSH. No example `.mem` file is generated automatically.

The `state_machine_test` object provides these methods:

- `reset_dut(cycles = 3)`: disables execution and holds reset low.
- `load_program(filename)`: reads the file and requests a testbench-only SRAM
  preload while reset is asserted. The DUT hierarchy appears only in the
  module's preload adapter (`dut.mem.ram`).
- `execute_program(cycles = 100)`: releases reset, enables execution for the
  requested number of clocks, and pauses the FSM afterward.

The clock period is 10 ns. `+CYCLES` defaults to 100 and includes the initial
fetch and any branch recovery cycles; it is not an instruction count.
`+WAVE` defaults to `state_machine_tb.vcd`.

For FPGA synthesis, the FSM's `IMEM_INIT_FILE` parameter defaults to
`program.mem`. The testbench overrides it with an empty string so that its
runtime loader can use `+PROGRAM` without requiring a second initialization
file at time zero.

The four existing state-transition assertions are retained. BLOCK may remain
blocked or resume execution. The decoder now controls X/Y, ISR/OSR, output-pin,
and direction-register writes through a shared data mux. X/Y decrements use
the ALU. PULL loads OSR from the current `fifo_in` word and PUSH presents ISR
on `fifo_o`; this assumes FIFO data is available before the read edge.

Inspect `dut.pc_out`, `dut.instruction`, `dut.execute`, `dut.write_data`,
`dut.alu_result`, and `dut.redirect_pending`, along with the registers and
`o_pin`. SET/MOV can drive a pin waveform. IN/OUT currently route source words
but do not perform bit-count shifting. MOV invert/bit-reverse options, delay
fields, and WAIT/BLOCK entry/resume handling remain unfinished.
