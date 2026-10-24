-rogeliocorrea

In order to run a sim with verilator
verilator --binary --timing \
    -DFUNCTIONAL \
    --top-module imem_tb \
    imem.sv imem_tb.sv \
    "$SRAM_DIR/RM_IHPSG13_1P_256x16_c2_bm_bist.v" \
    "$SRAM_DIR/RM_IHPSG13_1P_core_behavioral_bm_bist.v"

with xcelium
xrun -64bit -sv +define+FUNCTIONAL \
    -top imem_tb \
    imem.sv imem_tb.sv \
    "$SRAM_DIR/RM_IHPSG13_1P_256x16_c2_bm_bist.v" \
    "$SRAM_DIR/RM_IHPSG13_1P_core_behavioral_bm_bist.v"

where $SRAM_DIR is where you have /ihp/ihp-sg13g2/libs.ref/sg13g2_sram/verilog