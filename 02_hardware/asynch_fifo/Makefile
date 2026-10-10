.PHONY: all no-icarus lint lint-rtl icarus run sim vsim tb1 tb2 sim-all clean

RTL = bin2_to_gray_encoder.sv synch_ff.sv asynch_fifo.sv

# Pick a testbench (default is tb1):
#   make all                        -> tb/asynch_fifo_tb.sv
#   make all TB_TOP=asynch_fifo_tb2 -> tb/asynch_fifo_tb2.sv
# Or use the shortcuts: make tb1 / make tb2
TB_TOP ?= asynch_fifo_tb
TB      = tb/$(TB_TOP).sv
WAVE   ?= wave.vcd

BUILD = build

all: lint icarus sim

no-icarus: lint vsim

# ---------------- Testbench shortcuts ----------------

tb1:
	@echo "==== Testbench 1: asynch_fifo_tb ===="
	$(MAKE) all TB_TOP=asynch_fifo_tb WAVE=wave_tb.vcd

tb2:
	@echo "==== Testbench 2: asynch_fifo_tb2 ===="
	$(MAKE) all TB_TOP=asynch_fifo_tb2 WAVE=wave.vcd

# Run both testbenches back to back (no waveform windows)
sim-all:
	@echo "==== Running all testbenches ===="
	$(MAKE) icarus run TB_TOP=asynch_fifo_tb
	$(MAKE) icarus run TB_TOP=asynch_fifo_tb2
	@echo "==== End all testbenches ===="

# ---------------- Lint ----------------

lint:
	@echo "Linting with Verilator ($(TB_TOP))...."
	verilator --lint-only --timing -Wall --top-module $(TB_TOP) $(RTL) $(TB)
	@echo ".... End Lint."

# Design only, no testbench warnings
lint-rtl:
	@echo "Linting RTL with Verilator...."
	verilator --lint-only -Wall --top-module asynch_fifo $(RTL)
	@echo ".... End Lint."

# ---------------- Icarus ----------------

icarus:
	@echo "Running Icarus ($(TB_TOP))...."
	mkdir -p $(BUILD)
	iverilog -g2012 -s $(TB_TOP) -o $(BUILD)/$(TB_TOP) $(RTL) $(TB)
	@echo ".... End Icarus."

run:
	@echo "Running Sim ($(TB_TOP))...."
	vvp $(BUILD)/$(TB_TOP)
	@echo ".... End Sim."

sim: run
	@echo "Opening WaveForm...."
	gtkwave $(WAVE)

# ---------------- Verilator sim ----------------

vsim:
	@echo "Running V-Sim ($(TB_TOP))...."
	verilator --binary --timing --top-module $(TB_TOP) -Mdir $(BUILD)/obj_dir $(RTL) $(TB)
	./$(BUILD)/obj_dir/V$(TB_TOP)
	@echo "Opening WaveForm...."
	gtkwave $(WAVE)

# ---------------- Cleanup ----------------

clean:
	rm -rf $(BUILD) obj_dir
	rm -f *.vcd