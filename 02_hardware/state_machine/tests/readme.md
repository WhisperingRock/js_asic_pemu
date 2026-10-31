# FSM simulation

Run these commands in Bash from the `js_asic_pemu` repository root. Set
`SRAM_DIR` to your IHP PDK's `sg13g2_sram/verilog` directory:

```bash
SRAM_DIR="$PDK_ROOT/ihp-sg13g2/libs.ref/sg13g2_sram/verilog"

rtl=(
    02_hardware/state_machine/tests/state_machine_tb.sv
    02_hardware/state_machine/state_machine.sv
    02_hardware/state_machine/decoder/decoder_sm.sv
    02_hardware/state_machine/imem/imem.sv
    02_hardware/state_machine/pc/pc.sv
    02_hardware/common_rtl/mux4to1.sv
    "$SRAM_DIR/RM_IHPSG13_1P_256x16_c2_bm_bist.v"
    "$SRAM_DIR/RM_IHPSG13_1P_core_behavioral_bm_bist.v"
)
```

With Verilator:

```bash
verilator --binary --timing --assert --trace-vcd \
    -DFUNCTIONAL -Wno-ZERODLY \
    --top-module state_machine_tb "${rtl[@]}"

./obj_dir/Vstate_machine_tb \
    +PROGRAM=/path/to/program.mem +CYCLES=100 +WAVE=state_machine_tb.vcd
```

`-Wno-ZERODLY` permits the IHP model's time-zero `A_DLY` check on older
Verilator versions; the wrapper ties `A_DLY` to a constant high value.
The testbench uses classes, a virtual interface, and concurrent assertions;
Icarus 12 is not a supported simulator for this testbench.

With Xcelium:

```bash
xrun -64bit -sv +define+FUNCTIONAL -access +rwc \
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
  module's preload adapter.
- `execute_program(cycles = 100)`: releases reset, enables execution for the
  requested number of clocks, and pauses the FSM afterward.

The clock period is 10 ns. `+CYCLES` defaults to 100 and includes the initial
fetch and any branch recovery cycles; it is not an instruction count.
`+WAVE` defaults to `state_machine_tb.vcd`.

The four existing state-transition assertions are retained. BLOCK may remain
blocked or resume execution. The execution datapath is still unfinished, so
start by inspecting `dut.pc_out`, `dut.instruction`, `dut.fetch_addr`,
`dut.execute`, and `dut.redirect_pending`; pin-level UART output is not yet
implemented.
