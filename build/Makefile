# ============================================================
# RISC-V Pipelined Processor Build Makefile
# ============================================================

VERILATOR := verilator

ROOT := ..
RTL_DIR := $(ROOT)/rtl

# Package must be compiled before modules that import it
PKG := $(RTL_DIR)/riscv_pkg.sv

# Find all remaining SystemVerilog RTL sources
RTL_SRCS := $(PKG) \
            $(shell find $(RTL_DIR) -name "*.sv" ! -name "riscv_pkg.sv" | sort)


# ------------------------------------------------------------
# Lint
# ------------------------------------------------------------

.PHONY: lint clean

lint:
	$(VERILATOR) --lint-only \
		--sv \
		-Wall \
		-Wno-fatal \
		$(RTL_SRCS)


# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------

clean:
	rm -rf obj_dir