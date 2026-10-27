# Verification — v2.0

> **Scope:** Recorded verification results for the v1.0 architectural core and the v2.0 bus/BRAM FPGA system. The v1.0 formal results are **bounded** and do not constitute formal verification of the complete v2.0 implementation. The v2.0 hardware test is a focused smoke test, not an exhaustive ISA regression.

## 1. Verification approach

The project uses three complementary forms of verification:

1. **Architectural simulation (Verilator):** Directed programs check retirement results, hazards, memory operations, control flow, and exception behavior.
2. **Bounded formal verification (riscv-formal):** ISA instruction models and architectural consistency properties check the v1.0 core under a configured symbolic instruction-memory environment.
3. **FPGA system validation (Vivado and Urbana):** Bus/BRAM simulation, FPGA memory inference, static timing analysis, and physical execution of a known test program validate the v2.0 integration.

Verification is organized around the CPU's architectural retirement interface. A completed instruction emits a `retire_t` record from [`wb_stage.sv`](../rtl/wb_stage/wb_stage.sv), including:

| Fields | Information |
| --- | --- |
| `valid`, `order`, `insn` | Retirement validity, 64-bit retirement order, and instruction encoding |
| `rs1_addr`, `rs2_addr`, `rs1_rdata`, `rs2_rdata` | Source register addresses and operand values |
| `rd_addr`, `rd_wdata` | Destination register and committed value |
| `pc_rdata`, `pc_wdata` | Instruction PC and next architectural PC |
| `mem_addr`, `mem_rmask`, `mem_wmask`, `mem_rdata`, `mem_wdata` | Aligned memory address, byte lanes, and memory data |
| `trap`, `halt`, `intr` | Exception/terminal-state metadata and interrupt indication |

Only valid instructions retire; bubbles and flushed wrong-path instructions must not cause architectural side effects. The same retirement bundle is used for simulation checks, the formal adapter, and the FPGA smoke-test result capture.

## 2. v2.0 — Bus and BRAM simulation

v2.0 replaces the v1.0 internal asynchronous-read memory model with independent instruction and data request/response interfaces and synchronous BRAM adapters. The principal integration checks performed during development were:

| Test / verification area | Behavior exercised |
| --- | --- |
| `processor_bram_tb.sv` | Initialized instruction BRAM, bus-connected instruction fetch, retirement, and data-memory store/load behavior |
| `processor_bus_tb.sv` | Core operation with request/response memory interfaces and their handshakes |
| `id_ex_hold_tb.sv` | ID/EX hold behavior, writeback snooping while held, hold preservation, and flush priority |
| Vivado synthesis | Inference of on-chip block RAM for the FPGA memory subsystem |

The BRAM smoke-program simulation passed, including the expected retirement sequence and a store followed by a load of the stored value. The ID/EX hold and writeback-snooping test also passed. These results check important integration cases, but they do not establish that every possible bus latency, fault, or branch/stall interleaving has been covered.

### Running the BRAM system simulation

From the repository root, with Verilator and the build tools installed:

```bash
make -C build test-bram
```

Other supported targets should be checked against the current [`build/Makefile`](../build/Makefile). The four v1.0 regression testbenches listed below are historical v1.0 results; do not assume the v2.0 Makefile still exposes their original `test-all` target.

### Instruction memory initialization

The FPGA smoke-test image is kept at [`fpga/programs/bram_smoke.mem`](../fpga/programs/bram_smoke.mem) and contains **1,024 32-bit words**, padded with RISC-V NOPs (`00000013`). The FPGA wrapper uses the parameter value `"bram_smoke.mem"` to select this image. **The file must be explicitly available to each tool:** add it as a memory-initialization source in Vivado, and ensure the simulation target makes it accessible to `$readmemh` under the simulator's working directory. Moving the file on disk alone does not update an existing Vivado project or simulator invocation.

## 3. v2.0 — FPGA timing and physical verification

The target platform is the **Real Digital Urbana**, using a **Spartan-7 XC7S50-CSGA324-1** FPGA and **Vivado 2026.1**. The physical board provides a 100 MHz oscillator; a Clocking Wizard MMCM produces an **80 MHz CPU clock** with a **12.5 ns period**. A reset synchronizer holds the CPU in reset until the clock is locked and releases reset synchronously.

| Post-route metric | Measured result |
| --- | ---: |
| Generated CPU clock | **80 MHz** |
| Worst setup slack (WNS) | **+0.181 ns** |
| Worst hold slack (WHS) | **+0.111 ns** |
| Timing result | **Setup and hold timing met** |

These are results from the implementation **after** adding the reset synchronizer. The clock constraint remains 10 ns for the external 100 MHz input, while Vivado derives the 12.5 ns CPU clock from the MMCM. The timing figures apply to the implemented, constrained design; they are not an unrestricted maximum-frequency characterization.

### Physical BRAM smoke test

The instruction BRAM runs the following program:

| PC | Encoding | RISC-V assembly | Expected behavior |
| --- | --- | --- | --- |
| `0x00` | `02a00093` | `addi x1, x0, 42` | `x1 = 42` |
| `0x04` | `00108113` | `addi x2, x1, 1` | `x2 = 43` (RAW dependency) |
| `0x08` | `00202023` | `sw x2, 0(x0)` | Store `43` to data-memory word 0 |
| `0x0C` | `00002183` | `lw x3, 0(x0)` | Load `43` into `x3` |
| `0x10` | `0000006f` | `jal x0, 0` | Loop at `0x10` |

The remaining memory words are NOP padding. The FPGA wrapper identifies the retirement of `lw x3, 0(x0)` at PC `0x0C` through `retire_t`, then latches the low eight bits of the result and sets a persistent completion indicator. Error indicators latch any observed instruction-fetch or data-access fault.

**Observed on the programmed Urbana board:**

| FPGA LED | Observation | Interpretation |
| --- | --- | --- |
| LEDs 7–0 | `00101011` (`0x2B`, decimal **43**) | Expected load result |
| LED 8 (`test_done`) | **ON** | Expected load retired |
| LED 9 (`fetch_error`) | **OFF** | No fetch fault observed |
| LED 10 (`data_access_fault`) | **OFF** | No data-access fault observed |

Pressing **BTN0** resets the processor; the board's `BLE_RST` button is not connected to the CPU reset. The pin mappings are in [`fpga/riscv_fpga.xdc`](../fpga/riscv_fpga.xdc).

This test demonstrates instruction fetch from initialized BRAM, dependent arithmetic/forwarding, data-memory store/load, and architectural retirement **on real hardware**. It does not prove full ISA correctness, exercise every exception case on hardware, or establish a benchmarked IPC improvement over the earlier single-cycle CPU.

### Recreating the FPGA build

Use [`riscv_fpga_top.sv`](../fpga/riscv_fpga_top.sv) as the top module and add the RTL, memory IP, board XDC, and memory-initialization image to the Vivado project. Configure `clk_wiz_0` for a **100 MHz input** and **80 MHz output**, with `reset` and `locked` ports enabled. Ensure the Clocking Wizard's constraint is not duplicated by an additional `create_clock` on the same top-level input.

The Clocking Wizard configuration must also be saved reproducibly (for example, by tracking its `.xci` file or a Tcl script that recreates the IP); the `clk_wiz_0` instantiation alone does not define that IP's settings. After synthesis and routing, check `report_clocks` and `report_timing_summary`, generate a bitstream, and program the board over USB/JTAG.

## 4. v1.0 — Directed architectural simulation (recorded results)

The v1.0 core passed four directed Verilator regressions. These results are preserved as the **v1.0 verification baseline**, not presented as a fresh run against the v2.0 bus-connected core.

| Historical v1.0 regression | Behavior checked |
| --- | --- |
| Basic | Retirement trace, illegal instruction, precise exception, younger side-effect suppression |
| Memory | 26 instructions testing byte/halfword/word accesses, sign extension, overlapping writes, ordering, and metadata |
| Hazard | 48 retired instructions testing EX/MEM and MEM/WB forwarding, load-use stalls, branch/jump redirects, and wrong-path squashing |
| System | 14 scenarios testing `FENCE`, `ECALL`, `EBREAK`, illegal encodings, misalignment, and precise exception behavior |

In the v1.0 hazard regression, the test expected **four load-use stall cycles** and **five redirects**, checked forwarding priority, and used sentinel values to detect wrong-path stores. These are directed tests rather than comprehensive instruction-sequence coverage.

## 5. v1.0 — Bounded formal verification

The [RISC-V Formal Interface (RVFI)](https://github.com/YosysHQ/riscv-formal) describes architectural transitions at retirement. The project's [`rvfi_adapter.sv`](../verif/rvfi_adapter.sv) maps the custom `retire_t` record to RVFI (`NRET = 1`); [`rvfi_wrapper.sv`](../verif/rvfi_wrapper.sv) provides a formal top level. The symbolic [`formal_instr_rom.v`](../formal/formal_instr_rom.v) models 256 constant symbolic instruction words. The external `riscv-formal` framework, SymbiYosys, Yosys/Slang, and Boolector execute the checks.

| v1.0 formal category | Passing jobs |
| --- | ---: |
| RV32I instruction-model checks | 37 |
| Architectural consistency checks | 5 |
| Cover/reachability job | 1 |
| **Total** | **43** |

The five consistency checks are `reg` (register consistency), `pc_fwd` (PC continuity), `unique` (retirement-order uniqueness), `causal` (register causality), and `causal_mem` (memory causality). The `cover` job demonstrates that a selected retirement state is reachable; it is **not** a safety proof. The 37 standard instruction models exclude `FENCE`, `ECALL`, and `EBREAK`, which were tested separately in simulation.

The saved [`formal/checks.cfg`](../formal/checks.cfg) uses bounded model checking (`mode bmc`), with instruction checks at depth **15** and other checks at individually configured depths; an additional register-consistency check passed at depth **20**. The result is **42 passing bounded property checks plus one passing cover job**, not 43 unbounded mathematical proofs. It does not establish arbitrary-length correctness or verify the new BRAM/bus/FPGA implementation formally.

### Formal-verification-driven fixes

1. **WB-to-ID register dependency:** Decode could read a stale register value during a simultaneous WB write; fixed by write-through bypass.
2. **Misaligned branch/jump targets:** EX now checks taken control-flow targets and reports an instruction-address-misaligned exception.
3. **Misaligned data accesses:** EX checks halfword/word effective-address alignment and suppresses faulting side effects.

### Reproducing the saved v1.0 formal setup

The `riscv-formal` source is not vendored. The recorded workflow used a sibling checkout:

```text
pipeline/
├── riscv-pipelined-cpu/
└── riscv-formal/
```

Copy `formal/checks.cfg` into `riscv-formal/cores/pipelined/checks.cfg`, adjust its source paths and RTL file list as needed to point to the v1.0 snapshot, then run:

```bash
cd ../riscv-formal/cores/pipelined
python3 ../../checks/genchecks.py
make -C checks -j2
```

The exact external revision is documented in [`formal/riscv-formal-revision.txt`](../formal/riscv-formal-revision.txt). Reproducing the original checks may require the v1.0 Git tag and toolchain versions used by that release.

## 6. Verification limitations and next steps

- **Formal boundary:** v1.0 bounded properties are not a formal proof of the v2.0 bus/BRAM system.
- **Simulation boundary:** Directed programs and targeted bus/hold checks do not cover every possible memory-latency, redirect, or exception interleaving.
- **Hardware boundary:** The Urbana smoke test proves the observed five-instruction program completed correctly; it is not a full physical RV32I compliance test.
- **Timing boundary:** Positive routed slack is measured under the supplied constraints; it does not replace functional verification or I/O interface timing requirements for future peripherals.

The next verification expansion should follow new v3 features with targeted simulation and, where applicable, renewed RVFI/formal checks.

## Related documentation

- [Processor architecture](architecture.md)
- [Project README](../README.md)
- [FPGA constraints](../fpga/riscv_fpga.xdc)
