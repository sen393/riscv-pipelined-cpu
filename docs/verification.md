# Verification — V1 Baseline

> **Status:** Verification methodology and reported results for the released V1 RV32I processor. Results are based on the V1 release; V2 RTL changes require renewed verification. Formal property checks are **bounded**, not an unbounded proof of correctness.

## 1. Verification strategy

The processor is verified using two methods:

1. **Directed simulation (Verilator):** Execute hand-selected instruction sequences and check their architectural results, pipeline events, and side effects.
2. **Bounded formal verification (riscv-formal):** Use symbolic instructions and mathematical constraints to check ISA behavior and architectural consistency over the configured execution bounds.

Both methods use **architectural retirement** as an important observation point. An instruction may stall, forward operands, or trigger a redirect while in the pipeline, but its architectural effects must be correct when it retires. Simulation also inspects selected internal signals and memory/register state to catch control and side-effect bugs not visible from retirement alone.

### Architectural retirement interface

[`rtl/wb_stage/wb_stage.sv`](../rtl/wb_stage/wb_stage.sv) emits the project's `retire_t` structure when a valid instruction reaches writeback. It includes:

| Field | What it reports |
| --- | --- |
| `valid`, `order`, `insn` | Whether an instruction retires, its sequential retirement index, and encoding |
| `rs1_addr`, `rs2_addr`, `rs1_rdata`, `rs2_rdata` | Source registers and the operand values consumed by the instruction |
| `rd_addr`, `rd_wdata` | Architecturally committed destination register and value |
| `pc_rdata`, `pc_wdata` | Instruction PC and architectural next PC |
| `mem_addr`, `mem_rmask`, `mem_wmask`, `mem_rdata`, `mem_wdata` | Memory address, active byte lanes, and data |
| `trap`, `halt`, `intr` | Exceptional retirement, terminal-halt state, and interrupt indication |

The 64-bit retirement counter increments for each valid retirement. An invalid pipeline bubble does not retire, and trapped instructions suppress unintended register/memory side effects. In V1, the simplified exception model reports `halt` together with `trap` and does not implement a privileged trap handler.

## 2. Directed simulation

Each regression runs the RTL with a specified instruction program and checks expected behavior using SystemVerilog conditions and `$fatal` on failure.

| Testbench | Important behavior verified |
| --- | --- |
| [`processor_basic_tb.sv`](../verif/processor_basic_tb.sv) | Retirement trace, illegal-instruction trap, precise exception behavior, suppression of younger side effects |
| [`processor_memory_tb.sv`](../verif/processor_memory_tb.sv) | Word/halfword/byte accesses, sign/zero extension, overlapping writes, memory ordering and metadata |
| [`processor_hazard_tb.sv`](../verif/processor_hazard_tb.sv) | EX/MEM and MEM/WB forwarding, forwarding priority, load-use stalls, branch/jump redirects, wrong-path squashing |
| [`processor_system_tb.sv`](../verif/processor_system_tb.sv) | `FENCE`, `ECALL`, `EBREAK`, illegal encodings, instruction/data misalignment, precise trap and side-effect behavior |

### Representative example: hazard regression

The hazard regression checks **48 retired instructions** against expected PC and register-write results. In addition, it expects **four load-use stall cycles** and **five redirects**, exercises both forwarding paths, checks EX/MEM priority when two older instructions write the same register, and uses sentinel memory values to detect wrong-path stores.

For example, a useful verification condition is:

```systemverilog
if (rvfi.order !== retire_count)
    $fatal(1, "Retirement order mismatch");
```

A successful test is therefore more meaningful than merely reaching the end of an assembly program: it must satisfy explicit checks on the results and behavior. These are **directed** tests, not exhaustive coverage of every instruction sequence.

### Running simulations

From the repository root, with Verilator installed:

```bash
make -C build lint
make -C build test-all
```

The second target runs all four directed regressions. The V1 release README reports all four passing. These results are **recorded V1 results**; the commands are not claimed to have been rerun as part of this documentation update.

## 3. Formal verification with RVFI

The [RISC-V Formal Interface (RVFI)](https://github.com/YosysHQ/riscv-formal) describes the architectural state transitions of retiring instructions. It allows formal properties to check *what an instruction did* without depending on the exact number of pipeline cycles it needed.

Our formal connection is:

```text
riscv_core.sv
    |
    | retire_t (from WB)
    v
rvfi_adapter.sv
    |
    | Standard rvfi_* signals
    v
rvfi_wrapper.sv (formal top)
    |
    v
riscv-formal checks + symbolic instruction ROM
    |
    v
SymbiYosys / Yosys-Slang / Boolector
```

- [`rvfi_adapter.sv`](../verif/rvfi_adapter.sv) maps custom retirement fields to the standard RVFI wires. `NRET = 1`, since the CPU retires at most one instruction per cycle.
- [`rvfi_wrapper.sv`](../verif/rvfi_wrapper.sv) instantiates the core and adapter as the formal top level.
- [`formal_instr_rom.v`](../formal/formal_instr_rom.v) models 256 symbolic, constant instruction words rather than using a predetermined program. This broadens the set of instruction combinations the solver can explore within the bounded model.
- [`formal/checks.cfg`](../formal/checks.cfg) selects the ISA, solver, proof mode, property categories, and depths.

The formal wrappers and symbolic ROM are verification infrastructure, **not necessary components of the FPGA synthesis top**.

### Instruction checks versus consistency checks

**Instruction checks** compare an instruction's retired behavior against an ISA model: the operands, destination value, PC update, and memory activity must be consistent with the instruction semantics.

**Consistency checks** examine relationships between retired instructions. For instance, a register read must be consistent with a prior register write, and two different instructions must not reuse a retirement-order number.

| Check | Meaning |
| --- | --- |
| `reg` | Values read from the register file agree with prior architectural writes |
| `pc_fwd` | The architectural next PC of one retired instruction agrees with the following instruction's PC |
| `unique` | Different retired instructions do not share the same retirement-order number |
| `causal` | Register dependencies respect the required causality/order |
| `causal_mem` | Memory dependencies respect the required causality/order |
| `cover` | Demonstrates that a selected retirement activity is reachable; **not a safety proof** |

### Reported V1 results

| Category | Reported passing jobs |
| --- | ---: |
| RV32I instruction-model checks | 37 |
| Architectural consistency/property checks | 5 |
| Reachability/cover check | 1 |
| **Total generated formal jobs** | **43** |

Thus the result is **42 passing bounded property checks plus one passing cover job**, not 43 independent unbounded proofs. The 37 instruction models do not individually cover `FENCE`, `ECALL`, or `EBREAK`; those instructions are also exercised by directed simulation.

The committed [`checks.cfg`](../formal/checks.cfg) uses `mode bmc` with Boolector, instruction-check depth 15, and individually configured bounds for the other checks. The project README additionally records a deeper passing register-consistency check at depth 20. A passing bounded check means no counterexample was found within the modeled range and assumptions; it does **not** prove behavior for arbitrary execution length, an unmodeled memory system, or physical FPGA timing.

### Why the formal cover check matters

The project's cover condition asks for a trace with at least one normally retired instruction after reset. Reaching that condition supplies a *witness* that the formal model can execute and retire an instruction. This helps assess whether the formal environment can reach meaningful behavior, although it is not a substitute for full property-coverage analysis.

## 4. Verification-driven bug fixes

Formal checking helped expose three important classes of problems in V1:

1. **WB-to-ID read-after-write hazard:** A decode-stage register read could observe stale data while an older instruction was writing the same register in WB. The register file was updated to bypass the WB value to matching read ports.
2. **Misaligned taken branch/jump targets:** The EX stage needed to detect targets that were not 4-byte aligned and report a precise instruction-address-misaligned exception instead of redirecting to them.
3. **Misaligned loads and stores:** EX now checks effective-address alignment for halfword and word accesses. Faulting accesses raise the corresponding exception and suppress unintended writes.

These examples illustrate why architectural verification complements directed simulations: a test that checks one useful program may not expose less common register or address combinations.

## 5. Reproducing the formal checks

The project records its core-specific configuration in [`formal/checks.cfg`](../formal/checks.cfg), and the [exact riscv-formal revision](../formal/riscv-formal-revision.txt) used for the saved setup. The external riscv-formal source is **not vendored** into this repository.

The documented V1 workflow assumes a sibling checkout:

```text
pipeline/
├── riscv-pipelined-cpu/
└── riscv-formal/
```

Copy the project's configuration into `riscv-formal/cores/pipelined/checks.cfg`, verify source paths, and run from the external core directory:

```bash
cd ../riscv-formal/cores/pipelined
python3 ../../checks/genchecks.py
make -C checks -j2
```

The formal flow requires an appropriate Yosys/Slang, SymbiYosys, and Boolector installation. The relative paths and generated jobs may require adjustment for a different checkout structure or toolchain version.

## Related documentation

- [Processor architecture](architecture.md)
- [Project README](../README.md)
- [riscv-formal verification procedure](https://github.com/YosysHQ/riscv-formal/blob/main/docs/source/procedure.rst)