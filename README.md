# RISC-V 5-Stage Pipelined Processor

A five-stage, in-order **RV32I processor written in SystemVerilog**, built to explore CPU microarchitecture, pipeline hazards, precise exceptions, and hardware verification.

The project builds on a previous project ([single-cycle RV32I processor](https://github.com/sen393/riscv-single-cycle-cpu)) and is being developed in three milestones: an architecturally verified core, FPGA integration, and performance-oriented optimizations.

> **Current status — v1.0:** The core implements all 40 RV32I base instructions, with **37 instruction-model checks**, **five architectural consistency checks**, and **one formal cover check** passing under the configured bounded verification environment. All four directed simulation regressions have also passed, covering memory operations, pipeline hazards, system instructions, and precise exceptions.

## Architecture

![RISC-V Pipelined CPU Architecture](docs/images/pipelined-arch-diagram-1-6.svg)

- **IF — Instruction Fetch:** Program counter, instruction ROM, sequential fetch, and branch/jump redirects
- **ID — Instruction Decode:** Instruction decoding, immediate generation, and two-read/one-write integer register file
- **EX — Execute:** ALU operations, forwarded operands, branch decisions, effective-address generation, and address-alignment checks
- **MEM — Memory:** Byte-, halfword-, and word-sized memory operations with sign/zero extension and write masks
- **WB — Writeback:** Register writeback and in-order architectural retirement through an RVFI-compatible interface
- **Hazard Unit:** Detects load-use hazards, controls pipeline stalls, and selects EX/MEM or MEM/WB operand forwarding to resolve data dependencies

For further documentation, see [architecture](docs/architecture.md).

### Pipeline control

- EX/MEM and MEM/WB operand forwarding, with load-use stall insertion
- WB-to-ID register-file bypass for same-cycle read/write dependencies
- Flush younger instructions on taken branches, jumps, and accepted exceptions
- Instruction- and data-address misalignment detection
- Exception propagation to retirement with faulting-instruction side effects suppressed

**Exception model:** The current core uses a simplified exception/halt mechanism for verification; it does not yet implement a complete privileged-mode trap handler or operating-system environment

## Instruction set support

The core implements the **RV32I unprivileged base instruction set**:

| Category | Instructions |
| --- | --- |
| Integer arithmetic / logic | `ADD`, `SUB`, `ADDI`, `SLT`, `SLTU`, `SLTI`, `SLTIU`, `AND`, `ANDI`, `OR`, `ORI`, `XOR`, `XORI` |
| Shifts | `SLL`, `SLLI`, `SRL`, `SRLI`, `SRA`, `SRAI` |
| Upper immediates | `LUI`, `AUIPC` |
| Branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Jumps | `JAL`, `JALR` |
| Loads | `LB`, `LBU`, `LH`, `LHU`, `LW` |
| Stores | `SB`, `SH`, `SW` |
| Synchronization / system | `FENCE`, `ECALL`, `EBREAK` |

*Implementation support is distinct from formal coverage: `FENCE`, `ECALL`, and `EBREAK` are not included in the 37 standard RV32I instruction-model checks, but are separately tested through the dedicated system and exception regression.*

## Verification

The processor exposes retirement information via a custom `retire_t` bundle. An **RVFI adapter** maps that bundle to the standard interface used by [riscv-formal](https://github.com/YosysHQ/riscv-formal). Formal checks run using **SymbiYosys, Yosys/Slang, and Boolector**; simulation and linting use **Verilator**. Further documentation can be found in [verification](docs/verification.md).

### Verification results

All **43 generated formal checks** and all four directed simulation regressions passed.

#### Formal verification — riscv-formal

- **37 RV32I instruction-model checks:** Arithmetic, logical, shift, branch, jump, load, and store instructions
- **5 architectural consistency checks:**
  - `reg` — Register consistency
  - `pc_fwd` — Program counter progression
  - `unique` — Unique retirement ordering
  - `causal` — Register-dependency causality
  - `causal_mem` — Memory-dependency causality
- **1 formal cover check:** `cover`

#### Directed simulation — Verilator

- **Basic regression:** Retirement behavior, illegal instructions, and precise exceptions
- **Memory regression:** 26 instructions testing store-to-load ordering, overlapping byte/halfword accesses, sign extension, and memory dependencies
- **Hazard regression:** 48 retired instructions testing operand forwarding, forwarding priority, load-use stalls, branch/jump redirects, and pipeline flushing
- **System regression:** 14 scenarios covering `FENCE`, `ECALL`, `EBREAK`, illegal encodings, misaligned accesses, and precise exception side-effect suppression

All four simulation regressions also pass through the combined `make test-all` target.

**Verification scope:** Formal checks use bounded model checking, with instruction checks at depth 15 and architectural consistency checks at their configured depths. A deeper `reg` check also passed at depth 20. These results establish bounded correctness under the configured assumptions, not exhaustive correctness for arbitrary-length executions.

### Bugs found through formal verification

1. **WB-to-ID read-after-write hazard:** A consumer in decode could capture an old register value while an older instruction wrote that register back. Fixed by adding register-file write-through bypass.
2. **Misaligned control-flow targets:** Taken branches and jumps could target addresses not aligned to four bytes without raising an exception. Fixed by detecting misalignment in EX and propagating a precise trap.
3. **Misaligned data accesses:** Halfword/word loads and stores could access improperly aligned addresses without reporting a trap. Fixed by checking the effective address in EX and suppressing faulting memory operations.

## Repository structure

```text
riscv-pipelined-cpu/
├── README.md
├── docs/
│   ├── pipelined-arch-diagram-1-6.drawio
│   └── pipelined-arch-diagram-1-6.svg
├── rtl/
│   ├── riscv_pkg.sv
│   ├── riscv_core.sv
│   ├── hazard_unit.sv
│   ├── if_stage/
│   ├── id_stage/
│   ├── ex_stage/
│   ├── mem_stage/
│   ├── wb_stage/
│   └── pipeline/
├── verif/
│   ├── rvfi_adapter.sv
│   ├── rvfi_wrapper.sv
│   ├── processor_basic_tb.sv
│   ├── processor_memory_tb.sv
│   ├── processor_hazard_tb.sv
│   ├── processor_system_tb.sv
│   └── programs/
│       ├── verification_assembly.txt
│       └── *.hex
├── formal/
│   ├── checks.cfg
│   ├── rtl_files.f
│   ├── formal_instr_rom.v
│   ├── formal_instr_rom_stub.sv
│   └── riscv-formal-revision.txt
└── build/
    └── Makefile
```

*Some verification configuration files are stored under `formal/` for reproducibility; the external `riscv-formal` framework itself is not vendored into this repository.*

## Building and testing

### Requirements

- Verilator (SystemVerilog simulation and lint)
- OSS CAD Suite or equivalent installation of Yosys with Slang support, SymbiYosys, and Boolector (formal verification)
- `make` and Python 3
- A separate checkout of `riscv-formal`

### Lint and simulation

From the project root:

```bash
# Run Verilator lint
make -C build lint

# Run all directed simulation regressions
make -C build test-all
```

### Formal verification

The project currently uses an external, sibling checkout of `riscv-formal`:

```text
pipeline/
  riscv-pipelined-cpu/
  riscv-formal/
```

The repository's `formal/checks.cfg` is the **saved source of truth** for the core-specific checks. Copy it into `riscv-formal/cores/pipelined/checks.cfg` and ensure its source paths match your checkout. The configuration must reference the project's RTL file list, RVFI wrapper, formal ROM stub, and formal ROM implementation.

With the toolchain available on `PATH`, generate and execute the checks from the framework directory:

```bash
cd ../riscv-formal/cores/pipelined
python3 ../../checks/genchecks.py
make -C checks -j2
```

Individual checks can be run with `sby -f checks/insn_addi_ch0.sby` (or the corresponding generated job name).

**Reproducibility note:** Absolute paths in a copied `checks.cfg` may need adjustment for a new machine.

## Roadmap

- **v1 — Architecturally verified RV32I core (complete):** Implement all 40 RV32I base instructions, integrate pipeline hazard handling and precise exceptions, and validate architectural behavior through bounded formal verification and directed simulation regressions.
- **v2 — FPGA system (planned):** Integrate the core with memory and peripherals, bring it up on the Real Digital Urbana FPGA, and explore video output and interactive programs.
- **v3 — Microarchitectural optimization (planned):** Improve performance and implementation characteristics through measured pipeline and datapath changes.

## Related project

- [Single-Cycle RISC-V CPU](https://github.com/sen393/riscv-single-cycle-cpu) — the predecessor project implementing RV32I in a single-cycle architecture.

## Project status and limitations

This is an educational hardware-design and verification project, **not** a production-ready CPU or a complete SoC. Current formal results are bounded and rely on the configured symbolic instruction-memory model and RVFI assumptions. FPGA validation and system-level software execution are future milestones.
