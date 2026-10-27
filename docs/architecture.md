# Processor Architecture — v2.0

> **Purpose:** Describe the implemented five-stage RV32I processor, bus-connected memory system, and Real Digital Urbana FPGA integration at the v2.0 milestone.
>
> **Primary RTL:** [`riscv_core.sv`](../rtl/riscv_core.sv), [`riscv_system.sv`](../rtl/riscv_system.sv), [`riscv_fpga_top.sv`](../fpga/riscv_fpga_top.sv), and [`riscv_pkg.sv`](../rtl/riscv_pkg.sv).

## 1. Overview

The processor is a **32-bit, single-issue, in-order RV32I implementation** written in SystemVerilog. It retains the five-stage datapath established in v1.0 while adding request/response memory interfaces, synchronous FPGA block RAM, memory-backpressure handling, and a timing-closed hardware implementation.

1. **IF — Instruction Fetch:** Request instructions through the instruction bus, handle responses and redirects, and discard wrong-path responses.
2. **ID — Instruction Decode:** Decode instructions, generate immediates and control signals, and read the integer register file.
3. **EX — Execute:** Select forwarded operands, perform ALU operations, resolve branches/jumps, calculate addresses, and detect misalignment.
4. **MEM — Memory:** Issue data-bus requests, wait for responses, and perform byte/halfword/word load and store handling.
5. **WB — Writeback:** Commit register results and produce in-order architectural retirement records.

![Five-stage processor datapath](images/pipelined-arch-diagram-1-6.svg)

*The diagram illustrates the five-stage datapath and forwarding/redirect paths. It originated with v1.0 and does not depict every v2.0 bus, BRAM, or clocking component.*

| Property | v2.0 implementation |
| --- | --- |
| ISA / datapath | RV32I / 32 bits; 40 implemented base instructions |
| Execution | Single-issue, in-order, five-stage pipeline |
| Register file | 32 × 32-bit (`x0` hardwired to zero); two combinational reads, one clocked write |
| Branch/jump resolution | EX stage; no branch prediction |
| Data hazards | EX/MEM and MEM/WB forwarding, load-use bubbles, WB-to-ID bypass |
| Memory interfaces | Separate instruction and data `mem_bus_if` request/response ports |
| FPGA memory | Separate, synchronous, inferred BRAMs; 1,024 × 32-bit words each by default |
| Architectural retirement | `retire_t` bundle, adaptable to RVFI for verification |
| Target hardware | Real Digital Urbana, Spartan-7 XC7S50-CSGA324-1 |
| FPGA CPU clock | 80 MHz, generated from the board's 100 MHz oscillator |

The pipeline can retire **at most one instruction per cycle**. Fetch and data-memory handshakes, load-use hazards, redirects, and exceptions reduce the achieved instruction rate. No sustained IPC claim is made for the v2.0 FPGA implementation.

## 2. System hierarchy and memory interfaces

**RTL:** [`riscv_core.sv`](../rtl/riscv_core.sv), [`riscv_system.sv`](../rtl/riscv_system.sv), [`mem_bus_if.sv`](../ip/memory/mem_bus_if.sv), [`bram_adapter.sv`](../ip/memory/bram_adapter.sv), [`bram.sv`](../ip/memory/bram.sv).

The processor datapath is separated from the memory implementation:

```text
riscv_fpga_top
├── clk_wiz_0                 100 MHz board clock → 80 MHz CPU clock
├── reset synchronizer
└── riscv_system
    ├── riscv_core      IF → ID → EX → MEM → WB
    │   ├── instruction bus ─────────────────┐
    │   └── data bus ─────────────────────┐  │
    ├── data bram_adapter  <──────────────┘  │
    │   └── data bram                        │
    └── instruction bram_adapter <───────────┘
        └── instruction bram
```

`riscv_core` is the bus-connected processor. `riscv_system` instantiates it with independent instruction and data BRAM adapters. The instruction side is **read-only**; the data side supports reads and byte-masked writes. The buses do not require a shared-memory arbiter in this configuration.

The `mem_bus_if` interface provides:

| Channel | Signals | Meaning |
| --- | --- | --- |
| Request | `req_valid`, `req_ready` | A request is accepted when both are asserted |
| Request address/control | `req_addr`, `req_write` | Byte address and read/write direction |
| Write payload | `req_wdata`, `req_wstrb` | Write data and byte enables |
| Response | `rsp_valid`, `rsp_rdata`, `rsp_err` | Response completion, read data, and error status |

These interfaces allow the core to wait for a memory operation rather than assuming an asynchronous, zero-latency array. The current system uses local BRAM adapters; it does **not** implement caches, an external DRAM controller, or a general peripheral interconnect.

### BRAM and address mapping

The underlying `bram.sv` is a parameterized, single-port, **synchronous-read, read-first** memory with optional initialization from a file. `bram_adapter.sv` translates the request/response bus into BRAM accesses and supplies a registered response. Its `DEPTH_WORDS`, `BASE_ADDR`, `INIT_FILE`, and `READ_ONLY` parameters control the address window and access behavior; out-of-range or disallowed accesses can generate response errors.

The default instruction and data memories are each **1,024 32-bit words (4 KiB)**. Their address windows are independently configured. In the current Harvard-style system, instruction fetches and data accesses use separate physical memories even when their numeric addresses overlap.

This replaces the v1.0 model in which memories were accessed internally through asynchronous-read arrays and only part of the address was used for indexing.

## 3. Datapath and pipeline stages

### Instruction Fetch (IF)

**RTL:** [`if_stage.sv`](../rtl/if_stage/if_stage.sv).

The IF stage requests 32-bit instructions through the instruction bus. Its control FSM uses `FETCH_IDLE`, `FETCH_REQ`, `FETCH_RSP`, and `FETCH_HALT` states to manage requests, responses, and terminal fetch conditions. It tracks request and next-PC state (`req_pc_q` and `next_pc_q`) and forms an `if_id_t` bundle containing instruction validity, PC, `PC + 4`, and instruction bits.

A taken branch or jump resolved in EX supplies a redirect address. When an instruction request or response is already in flight, fetch logic marks wrong-path data for discard instead of allowing it to enter the architectural pipeline. `decode_ready` provides backpressure when downstream stages cannot accept another instruction, while `stop_fetch` handles terminal conditions.

The v2.0 timing improvements include independently computed sequential/redirect `PC + 4` values and PC bookkeeping decoupled from terminal halt control. Unlike v1.0, IF does **not** assume combinational instruction-memory reads.

### Instruction Decode (ID)

**RTL:** [`id_stage.sv`](../rtl/id_stage/id_stage.sv), [`decoder.sv`](../rtl/id_stage/decoder.sv), [`imm_gen.sv`](../rtl/id_stage/imm_gen.sv), [`reg_file.sv`](../rtl/id_stage/reg_file.sv).

ID extracts `rs1`, `rs2`, and `rd`, decodes the instruction, computes the immediate, and builds a `ctrl_t` control bundle for downstream stages. The register file has two combinational read ports and a synchronous write port. Writes to `x0` are ignored, and reads of `x0` return zero.

A WB-to-ID bypass returns newly written data to a matching decode-stage read in the same cycle. The resulting `id_ex_t` bundle carries the operands, controls, PC, instruction, and metadata used by later retirement reporting.

### Execute (EX)

**RTL:** [`ex_stage.sv`](../rtl/ex_stage/ex_stage.sv), [`alu.sv`](../rtl/ex_stage/alu.sv), [`branch_unit.sv`](../rtl/ex_stage/branch_unit.sv).

EX selects source operands from ID/EX, EX/MEM forwarding, or MEM/WB forwarding. It performs arithmetic, logical operations, shifts, comparisons, effective-address generation, and branch/jump resolution. The JALR target clears bit 0 before instruction-address alignment is checked.

Branches are compared in EX using the forwarded source values. The branch logic includes parallel subword comparison logic for timing, but the branch outcome still feeds the same-cycle redirect/flush path. Address-alignment checking uses the low address bits computed from the forwarded base register plus immediate, without waiting for the full ALU result.

EX marks misaligned taken control-flow targets and misaligned halfword/word data accesses as exceptions and disables the faulting instruction's register/memory side effects. Its `ex_mem_t` bundle carries the result, forwarded store data, controls, and retirement metadata.

### Memory (MEM)

**RTL:** [`mem_stage.sv`](../rtl/mem_stage/mem_stage.sv).

MEM executes `LB`, `LBU`, `LH`, `LHU`, `LW`, `SB`, `SH`, and `SW` through the **data request/response bus**, rather than an internal asynchronous memory array.

A controller with `MEM_IDLE`, `MEM_REQ`, `MEM_RSP`, and `MEM_ERROR` states presents memory requests, waits for acceptance and response, and reports access faults. `mem_stall` prevents the pipeline from advancing while a transaction is unfinished. Byte strobes select store lanes; returned load data is extracted and sign- or zero-extended according to the instruction.

The stage carries the aligned memory address, read/write masks, data, and controls needed for retirement reporting. The BRAM adapter supplies the synchronous-memory latency transparently through the response handshake.

### Writeback (WB)

**RTL:** [`wb_stage.sv`](../rtl/wb_stage/wb_stage.sv).

WB selects the architectural register result from the **ALU result**, **loaded data**, or **`PC + 4`** for jumps. Only valid, non-trapping instructions requesting a register write may modify a nonzero destination register. In-order retirement metadata is exported through `retire_t`, including instruction, PC transition, source/destination values, memory activity, trap state, and a 64-bit retirement order.

## 4. Pipeline registers, stalls, and hazards

The four inter-stage bundles are defined in `riscv_pkg.sv`:

| Boundary | Bundle | Main contents |
| --- | --- | --- |
| IF/ID | `if_id_t` | Validity, PC, `PC + 4`, instruction |
| ID/EX | `id_ex_t` | Decode controls, register addresses/data, immediate, metadata |
| EX/MEM | `ex_mem_t` | ALU result, store data, controls, metadata |
| MEM/WB | `mem_wb_t` | Results, writeback controls, retirement metadata |

Every stage carries a validity indication. A **flush** invalidates younger instructions by inserting bubbles, whereas a **hold** preserves state until work can proceed.

**RTL:** [`hazard_unit.sv`](../rtl/hazard_unit.sv), [`id_ex_reg.sv`](../rtl/pipeline/id_ex_reg.sv), [`riscv_core.sv`](../rtl/riscv_core.sv).

### Forwarding and load-use hazards

The hazard unit compares source registers in EX against destination registers in EX/MEM and MEM/WB. It prioritizes **EX/MEM** (newer producer) over **MEM/WB** (older producer). EX/MEM loads cannot forward their unavailable read result; loads instead become forwarding candidates when their result reaches writeback.

For a load-use dependency, the consumer is held while a bubble is inserted so the load can proceed. The WB-to-ID register-file bypass also covers same-cycle decode/read and writeback dependencies.

### Variable-latency memory stalls

A data-memory transaction may remain pending across multiple clock cycles. `mem_stall` freezes the necessary pipeline state rather than allowing a dependent instruction to advance with missing data. The ID/EX register includes **WB snooping while held**: if an older instruction writes a source register during a hold, the saved source operand is refreshed to prevent using a stale value when execution resumes.

Memory stalls are distinct from load-use bubbles: a load-use bubble resolves a data dependency, while a memory stall waits for an outstanding transaction. Redirect and flush behavior is coordinated with these holds to preserve instruction ordering.

## 5. Control-flow, redirects, and exceptions

Branches and jumps are resolved in EX, so a taken transfer must redirect fetch and discard younger wrong-path instructions. The top-level core coordinates `redirect_fire`, `if_id_flush`, `id_ex_flush`, `if_id_en`, `id_ex_en`, and memory-stall handling. A pending memory response can be discarded if it belongs to the wrong path.

This design has **no branch predictor**. The EX-to-fetch redirect path—including forwarding, branch comparison, and flush control—was identified as the principal timing-critical path during v2.0 FPGA implementation. Several local combinational optimizations were retained, while a larger pipeline redesign was deferred to v3.

The simplified exception model recognizes:

- `ECALL` and `EBREAK`.
- Illegal or unsupported instruction encodings.
- Misaligned taken instruction targets.
- Misaligned halfword and word data accesses.

The pipeline suppresses architectural side effects from faulting instructions and prevents younger wrong-path work from retiring. Accepted terminal exceptions stop further instruction fetching; the retirement record reports `trap`/`halt` as applicable. The core does not implement machine-mode CSRs, an `mtvec` trap handler, interrupts, or `MRET`.

The v2.0 bus-based system also exposes **`fetch_error`** and **`data_access_fault`** signals for instruction/data memory failures. These hardware fault outputs should not be confused with a fully implemented privileged exception/interrupt subsystem.

## 6. FPGA integration and physical bring-up

**RTL:** [`riscv_fpga_top.sv`](../fpga/riscv_fpga_top.sv) and [`riscv_system.sv`](../rtl/riscv_system.sv). **FPGA sources:** [`riscv_fpga.xdc`](../fpga/riscv_fpga.xdc) and [`bram_smoke.mem`](../fpga/programs/bram_smoke.mem).

The Real Digital Urbana supplies a **100 MHz board clock**. The Vivado Clocking Wizard (`clk_wiz_0`) generates an **80 MHz CPU clock** (12.5 ns period). The external clock is constrained to 10 ns; the MMCM-derived CPU clock is constrained automatically as a generated clock.

Reset is asserted when the user reset input is high or the MMCM is not locked. A two-flip-flop reset synchronizer provides asynchronous assertion and synchronous release into the CPU clock domain. The FPGA wrapper exposes a latched smoke-test result, completion indicator, and sticky fetch/data-access fault indicators on discrete LEDs.

| FPGA implementation result | v2.0 measurement |
| --- | --- |
| Board / FPGA | Urbana / Spartan-7 XC7S50-CSGA324 (-1) |
| Toolchain | Vivado 2026.1 |
| CPU clock | **80 MHz** |
| Post-route worst setup slack | **+0.181 ns** |
| Post-route worst hold slack | **+0.111 ns** |
| On-board smoke test | **PASS** |

### Hardware smoke test

The instruction BRAM is initialized from [`fpga/programs/bram_smoke.mem`](../fpga/programs/bram_smoke.mem) with a five-instruction program (followed by NOP padding):

```asm
addi x1, x0, 42      # x1 = 42
addi x2, x1, 1       # x2 = 43
sw   x2, 0(x0)       # data memory word 0 = 43
lw   x3, 0(x0)       # x3 = 43
jal  x0, 0           # loop at PC 0x10
```

The wrapper recognizes retirement of the load at `PC = 0x0C` and latches its 8-bit result. Physical observation confirmed **LEDs 7–0 = `00101011` (`0x2B`, decimal 43)**, **LED 8 = ON** (completion), and **LEDs 9–10 = OFF** (no observed fetch/data fault). BTN0 is connected to the CPU reset input.

This demonstrates basic instruction BRAM fetch, register dependency handling, data BRAM store/load, and architectural retirement on real hardware. It is **not** a full on-board regression of every RV32I instruction or timing behavior.

## 7. Verification scope and limitations

The architectural `retire_t` bundle is connected to the RISC-V Formal Interface by [`rvfi_adapter.sv`](../verif/rvfi_adapter.sv) and [`rvfi_wrapper.sv`](../verif/rvfi_wrapper.sv). The v1.0 core passed **37 bounded RV32I instruction-model checks, five architectural consistency checks, and one cover check**; v1 directed regressions covered memory, hazards, system instructions, and exceptions.

For v2.0, Verilator simulations exercised the bus-connected core, BRAM initialization, memory transactions, and relevant pipeline holds. Vivado confirmed FPGA BRAM inference and 80 MHz timing closure, followed by the physical smoke test above. **The v1 formal results are not a formal proof of the complete v2 memory/FPGA system.**

Current architectural boundaries include local BRAM rather than DDR3, no cache or general MMIO peripheral fabric, a terminal exception model rather than privileged trap handling, and no UART, timer, or video output. Performance-oriented changes to branch handling and additional peripherals are left for v3 development.

## Related documentation

- [Verification and results](verification.md)
- [Project README](../README.md)
