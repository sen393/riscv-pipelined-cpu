
# ============================================================
# RISC-V Pipelined Processor Build Makefile
# ============================================================

VERILATOR := verilator

ROOT := ..
RTL_DIR := $(ROOT)/rtl
VERIF_DIR := $(ROOT)/verif

OBJ_DIR := obj_dir

# Package must be compiled before modules that import it
PKG := $(RTL_DIR)/riscv_pkg.sv

# Find all remaining SystemVerilog RTL sources
RTL_SRCS := $(PKG) \
            $(shell find $(RTL_DIR) -name "*.sv" ! -name "riscv_pkg.sv" | sort)

# Basic testbench
TB_TOP := processor_basic_tb
TB_SRC := $(VERIF_DIR)/$(TB_TOP).sv
SIM_BIN := $(OBJ_DIR)/V$(TB_TOP)


# ------------------------------------------------------------
# Lint
# ------------------------------------------------------------

.PHONY: lint sim test-basic clean

lint:
	$(VERILATOR) --lint-only \
		--sv \
		-Wall \
		-Wno-fatal \
		--top-module riscv_core \
		$(RTL_SRCS)


# ------------------------------------------------------------
# Simulation compilation
# ------------------------------------------------------------

sim: $(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(TB_SRC) Makefile
	$(VERILATOR) --binary \
		--timing \
		--sv \
		-Wno-fatal \
		--top-module $(TB_TOP) \
		--Mdir $(OBJ_DIR) \
		$(RTL_SRCS) \
		$(TB_SRC)


# ------------------------------------------------------------
# Basic test
# ------------------------------------------------------------

test-basic: sim
	./$(SIM_BIN)


# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------

clean:
	rm -rf $(OBJ_DIR)

