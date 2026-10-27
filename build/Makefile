
# ============================================================
# RISC-V Pipelined Processor V2 Build Makefile
# ============================================================

.DEFAULT_GOAL := lint

VERILATOR := verilator

# ------------------------------------------------------------
# Directories
# ------------------------------------------------------------

ROOT      := ..
RTL_DIR   := $(ROOT)/rtl
IP_DIR    := $(ROOT)/ip
VERIF_DIR := $(ROOT)/verif

# ------------------------------------------------------------
# RTL sources
# ------------------------------------------------------------

# Package and interface definitions must come first
PKG    := $(RTL_DIR)/riscv_pkg.sv
BUS_IF := $(IP_DIR)/memory/mem_bus_if.sv

# Automatically discover remaining RTL and IP sources
RTL_FILES := $(shell find $(RTL_DIR) -name "*.sv" \
             ! -name "riscv_pkg.sv" | sort)

IP_FILES := $(shell find $(IP_DIR) -name "*.sv" \
            ! -name "mem_bus_if.sv" | sort)

# Complete source list
RTL_SRCS := $(PKG) $(BUS_IF) $(RTL_FILES) $(IP_FILES)

# ------------------------------------------------------------
# Top-level modules
# ------------------------------------------------------------

SYSTEM_TOP    := riscv_system
CORE_LINT_TOP := riscv_core_ifbus_lint_top
CORE_LINT_SRC := $(VERIF_DIR)/$(CORE_LINT_TOP).sv

# BRAM system testbench
BRAM_TB_TOP  := processor_bram_tb
BRAM_TB_SRC  := $(VERIF_DIR)/$(BRAM_TB_TOP).sv
BRAM_OBJ_DIR := obj_dir_bram
BRAM_SIM_BIN := $(BRAM_OBJ_DIR)/V$(BRAM_TB_TOP)

# ------------------------------------------------------------
# Verilator flags
# ------------------------------------------------------------

LINT_FLAGS := \
    --lint-only \
    --sv \
    -Wall \
    -Wno-fatal

SIM_FLAGS := \
    --binary \
    --timing \
    --sv \
    -Wall \
    -Wno-fatal

# ------------------------------------------------------------
# Lint
# ------------------------------------------------------------

.PHONY: lint lint-system lint-core test-bram clean

# Default: Complete processor + BRAM
lint: lint-system

lint-system:
	$(VERILATOR) $(LINT_FLAGS) \
		--top-module $(SYSTEM_TOP) \
		$(RTL_SRCS)

# Standalone bus-enabled core
lint-core:
	$(VERILATOR) $(LINT_FLAGS) \
		--top-module $(CORE_LINT_TOP) \
		$(RTL_SRCS) \
		$(CORE_LINT_SRC)

# ------------------------------------------------------------
# BRAM system simulation
# ------------------------------------------------------------

$(BRAM_SIM_BIN): $(RTL_SRCS) $(BRAM_TB_SRC) Makefile
	$(VERILATOR) $(SIM_FLAGS) \
		--top-module $(BRAM_TB_TOP) \
		--Mdir $(BRAM_OBJ_DIR) \
		$(RTL_SRCS) \
		$(BRAM_TB_SRC)

test-bram: $(BRAM_SIM_BIN)
	./$(BRAM_SIM_BIN)

# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------

clean:
	rm -rf $(BRAM_OBJ_DIR)
