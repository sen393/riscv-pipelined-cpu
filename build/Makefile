
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

# Memory testbench
MEM_TB_TOP := processor_memory_tb
MEM_TB_SRC := $(VERIF_DIR)/$(MEM_TB_TOP).sv
MEM_OBJ_DIR := obj_dir_memory
MEM_SIM_BIN := $(MEM_OBJ_DIR)/V$(MEM_TB_TOP)

# Hazard testbench
HAZ_TB_TOP := processor_hazard_tb
HAZ_TB_SRC := $(VERIF_DIR)/$(HAZ_TB_TOP).sv
HAZ_OBJ_DIR := obj_dir_hazard
HAZ_SIM_BIN := $(HAZ_OBJ_DIR)/V$(HAZ_TB_TOP)

# System testbench
SYS_TB_TOP := processor_system_tb
SYS_TB_SRC := $(VERIF_DIR)/$(SYS_TB_TOP).sv
SYS_OBJ_DIR := obj_dir_system
SYS_SIM_BIN := $(SYS_OBJ_DIR)/V$(SYS_TB_TOP)

SYS_CASES := fence ecall ebreak illegal illegal_system illegal_load illegal_fence_i \
             lw_misaligned lh_misaligned sw_misaligned sh_misaligned \
             jal_misaligned jalr_misaligned branch_misaligned

# ------------------------------------------------------------
# Lint
# ------------------------------------------------------------

.PHONY: lint sim test-basic test-memory test-system test-all clean

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
# Memory test
# ------------------------------------------------------------

$(MEM_SIM_BIN): $(RTL_SRCS) $(MEM_TB_SRC) Makefile
	$(VERILATOR) --binary \
		--timing \
		--sv \
		-Wno-fatal \
		--top-module $(MEM_TB_TOP) \
		--Mdir $(MEM_OBJ_DIR) \
		$(RTL_SRCS) \
		$(MEM_TB_SRC)

test-memory: $(MEM_SIM_BIN)
	./$(MEM_SIM_BIN)


# ------------------------------------------------------------
# Hazard test
# ------------------------------------------------------------

$(HAZ_SIM_BIN): $(RTL_SRCS) $(HAZ_TB_SRC) Makefile
	$(VERILATOR) --binary \
		--timing \
		--sv \
		-Wno-fatal \
		--top-module $(HAZ_TB_TOP) \
		--Mdir $(HAZ_OBJ_DIR) \
		$(RTL_SRCS) \
		$(HAZ_TB_SRC)

test-hazard: $(HAZ_SIM_BIN)
	./$(HAZ_SIM_BIN)


# ------------------------------------------------------------
# System / Exception test
# ------------------------------------------------------------

$(SYS_SIM_BIN): $(RTL_SRCS) $(SYS_TB_SRC) Makefile
	$(VERILATOR) --binary \
		--timing \
		--sv \
		-Wno-fatal \
		--top-module $(SYS_TB_TOP) \
		--Mdir $(SYS_OBJ_DIR) \
		$(RTL_SRCS) \
		$(SYS_TB_SRC)

test-system: $(SYS_SIM_BIN)
	@set -e; for c in $(SYS_CASES); do \
		echo "== system case: $$c =="; \
		./$(SYS_SIM_BIN) +CASE=$$c; \
	done


# ------------------------------------------------------------
# Full simulation regression
# ------------------------------------------------------------

test-all: test-basic test-memory test-hazard test-system
	@echo "========================================"
	@echo " ALL SIMULATION REGRESSIONS PASSED"
	@echo "========================================"


# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------

clean:
	rm -rf $(OBJ_DIR) $(MEM_OBJ_DIR) $(HAZ_OBJ_DIR) $(SYS_OBJ_DIR)