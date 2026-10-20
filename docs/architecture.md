# Processor Architecture — V1

> **Purpose:** Document the V1 core as released in its current state, before FPGA/SoC integration
>
> **Primary RTL:** [`riscv_core.sv`](../rtl/riscv_core.sv) and [`riscv_pkg.sv`](../rtl/riscv_pkg.sv)

## 1. Overview

This project implements a 32-bit, single-issue, in-order RISC-V processor in SystemVerilog using a five-stage pipeline:

1. **IF — Instruction Fetch:** Fetch the current instruction and determine the next program count
2. **ID — Instruction Decode:** Decode the instruction, generate control signals and immediate values, and read source registers
3. **EX — Execute:** Execute ALU operations, calculate memory addresses, resolve branches/jumps, and detect misaligned instruction/ data accesses
4. **MEM — Memory:** Perform loads and stores, including subword access load extension
5. **WB — Writeback:** Write results to the register file and report architectural retirement

Pipeline registers seperate each stage, allowing different instructions to occupy each stage concurrently. Under ideal conditions, the processor can maintain (accept and retire) up to one instruction per cycle (IPC) after the pipeline is filled, however, hazards and redirects can introduce bubbles which decreases the IPC. 
The V1 core supports the **40 RV32I base instructions**. The integer register file contains 32 registers (`x0`—`x31`), each 32 bits wide. `x0` always reads as zero. `FENCE` is recognized as an operation with no additional hardware action in this model. `ECALL` and `EBREAK` are recognized as terminal exceptions rather than serviced by a privileged trap handler.

![Five-stage V1 processor architecture](images/pipelined-arch-diagram-1-6.svg)

| Property | V1 implementation |
| --- | --- |
| ISA / data width | RV32I / 32 bits |
| Issue and retirement | Single-issue, in-order |
| Pipeline | IF → ID → EX → MEM → WB |
| Register file | Two combinational read ports; one clocked write port |
| Control-flow resolution | EX stage |
| Data hazard handling | EX/MEM and MEM/WB forwarding, load-use stall, WB-to-ID bypass |
| Instruction memory | Internal asynchronous-read array, 256 × 32 bits by default |
| Data memory | Internal asynchronous-read / synchronous-write array, 256 × 32 bits by default |
| Architectural retirement | Custom `retire_t` bundle; adapted to RVFI for formal verification |

The memories are parameterized by depth, but the core selects a subset of the 32-bit address to index each memory. The core does **not** yet include a complete system address decoder or external memory interface.

## 2. Datapath and pipeline stages

### Instruction Fetch (IF)

**RTL:** [`if_stage.sv`](../rtl/if_stage/if_stage.sv), [`pc_reg.sv`](../rtl/if_stage/pc_reg.sv), [`instr_mem.sv`](../rtl/if_stage/instr_mem.sv)

The program counter (`PC`) holds the byte address of the instruction being fetched. For ordinary sequential execution, the next address is `PC + 4`. A taken branch or jump resolved in EX instead supplies `redirect_pc`.

The IF stage reads an instruction **combinationally** from its internal instruction memory. It prepares an `if_id_t` bundle containing `valid`, `pc`, `pc_plus4`, and `instr`. The IF/ID pipeline register captures this bundle on the next rising clock edge unless control logic stalls or flushes it.

The PC register has an enable (`pc_en`) so it can hold its current address during a load-use stall or after terminal exception handling. A valid EX redirect takes priority over an ordinary stall.

### Instruction Decode (ID)

**RTL:** [`id_stage.sv`](../rtl/id_stage/id_stage.sv), [`decoder.sv`](../rtl/id_stage/decoder.sv), [`imm_gen.sv`](../rtl/id_stage/imm_gen.sv), [`reg_file.sv`](../rtl/id_stage/reg_file.sv)

The ID stage extracts the instruction's register fields (`rs1`, `rs2`, `rd`), decodes its opcode and function fields, and generates the appropriate immediate. The decoder produces a packed `ctrl_t` bundle specifying operations such as the ALU function, operand selections, memory read/write control, result selection, branch type, and exception category.

The integer register file has two **combinational reads** and one **synchronous write**. To handle a register being read in ID while an older instruction writes it in WB, the register file bypasses the writeback data to a matching read port in the same cycle. Writes to `x0` are ignored, and reads from `x0` always return zero.

ID prepares the `id_ex_t` bundle with decoded controls, register operands, immediate, PC, and instruction information. It also carries source-register metadata used later by the retirement interface.

### Execute (EX)

**RTL:** [`ex_stage.sv`](../rtl/ex_stage/ex_stage.sv), [`alu.sv`](../rtl/ex_stage/alu.sv), [`branch_unit.sv`](../rtl/ex_stage/branch_unit.sv)

The EX stage chooses the latest correct operand values using forwarding selections from the hazard unit. Operand multiplexers then supply either registers, the PC, zero, or an immediate to the ALU, depending on the instruction.

The ALU handles arithmetic, logical operations, shifts, comparisons, and address calculations. A separate branch unit compares the forwarded source operands and computes taken branch and jump targets. In particular, the JALR target clears bit 0.

If a branch or jump is taken, EX requests a PC redirect and invalidates younger instructions. EX also checks **taken control-flow targets** for 4-byte alignment and checks load/store addresses for their required access alignment. Misaligned instructions are marked as exceptions, and their register or memory side effects are disabled.

The `ex_mem_t` bundle carries the ALU result, forwarded store data, destination register, remaining control signals, and retirement metadata to MEM.

### Memory (MEM)

**RTL:** [`mem_stage.sv`](../rtl/mem_stage/mem_stage.sv), [`data_mem.sv`](../rtl/mem_stage/data_mem.sv)

The MEM stage performs the five load instructions (`LB`, `LBU`, `LH`, `LHU`, `LW`) and three store instructions (`SB`, `SH`, `SW`). The internal data memory consists of 32-bit words, with a **combinational read** and **clocked write**. The effective address determines the target word and the byte or halfword lane within it.

For loads, MEM selects the required byte, halfword, or word and applies sign extension or zero extension as specified by the instruction. For stores, the data-memory module updates only the selected portion of the word. A valid instruction and the decoded memory-write control are required for a write to occur.

The stage also records aligned memory addresses, byte masks, read data, and write data as metadata for verification. It prepares `mem_wb_t` for the final stage.

### Writeback (WB)

**RTL:** [`wb_stage.sv`](../rtl/wb_stage/wb_stage.sv)

WB chooses the architectural destination value from three possibilities:

- **ALU result** for arithmetic, logic, address-based results, and upper-immediate instructions.
- **Loaded memory data** for a load instruction.
- **`PC + 4`** for the destination register of `JAL` and `JALR`.

Register writes are enabled only for valid, non-trapping instructions whose decoder requests a write and whose destination is not `x0`. The stage also generates the `retire_t` record with the instruction, operand/destination information, PC transition, memory activity, and trap state. A 64-bit counter records retirement order.

## 3. Pipeline registers and instruction flow

The four registered stage boundaries are:

| Register | Type in `riscv_pkg.sv` | Main contents |
| --- | --- | --- |
| IF/ID | `if_id_t` | Valid bit, PC, `PC + 4`, instruction |
| ID/EX | `id_ex_t` | Decode controls, source/destination registers, operand data, immediate, metadata |
| EX/MEM | `ex_mem_t` | ALU result, forwarded store data, controls, metadata |
| MEM/WB | `mem_wb_t` | ALU/load results, writeback controls, metadata |

For independent instructions with no stalls or redirects, stage occupancy overlaps:

| Instruction | Cycle 1 | Cycle 2 | Cycle 3 | Cycle 4 | Cycle 5 | Cycle 6 | Cycle 7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| I1 | IF | ID | EX | MEM | WB | | |
| I2 | | IF | ID | EX | MEM | WB | |
| I3 | | | IF | ID | EX | MEM | WB |

Each bundle includes a **`valid` bit**. When a stage is flushed, its pipeline register is cleared and the stage contains a *bubble* rather than a real instruction. A **stall/hold** preserves the existing instruction so it can be processed later. Correct use of valid bits ensures that flushed instructions cannot write registers, modify memory, or appear as retired instructions.

In V1, IF/ID supports both holding and flushing, ID/EX supports flushing, and EX/MEM and MEM/WB normally advance every cycle. This assumes memory reads are available combinationally. V2 will need to extend the hold/advance controls for memory requests that take multiple cycles.

## 4. Hazard handling

**RTL:** [`hazard_unit.sv`](../rtl/hazard_unit.sv), [`riscv_core.sv`](../rtl/riscv_core.sv)

### Data forwarding

Read-after-write (RAW) hazards occur when an instruction needs a register value that an older instruction has not yet written into the register file. To avoid unnecessary stalls, EX can select a result from an older instruction in **EX/MEM** or **MEM/WB** instead of using the operand captured in ID/EX.

When both forwarding sources match the same register, **EX/MEM is preferred**, because it represents the newer producer. A load cannot forward from EX/MEM: the loaded value is not available until the MEM stage. MEM/WB forwarding uses the selected WB result, including load data.

### Load-use stall

A load-use hazard exists when the instruction in EX is a load and the instruction in ID needs its destination register. The hazard unit checks source-use flags, valid bits, matching register indices, and whether the load writes a nonzero destination register.

For this case, the processor:

1. Holds the PC and IF/ID register for one cycle.
2. Flushes ID/EX to insert a bubble.
3. Allows the older load to move ahead.
4. Subsequently forwards the loaded result to the consumer in EX.

### WB-to-ID bypass

The register file also bypasses WB data to an ID-stage read when source and destination addresses match in the same cycle. This closes a dependency that could otherwise expose a stale value at the decode-stage read ports.

## 5. Control-flow redirects and pipeline flushes

Branches and jumps are resolved in **EX**. A taken branch or jump chooses a new `redirect_pc` instead of sequential `PC + 4`. Because younger instructions may already occupy IF and ID, the core flushes **IF/ID and ID/EX** on a redirect.

The control signals are derived in `riscv_core.sv`:

| Signal | V1 behavior |
| --- | --- |
| `pc_en` | Allows PC update on redirect; otherwise blocks on load-use stall or terminal exception conditions |
| `if_id_flush` | Clears IF/ID on redirect or exception-related control |
| `if_id_en` | Holds IF/ID on stall unless a flush is required |
| `id_ex_flush` | Inserts a bubble on stall, redirect, EX exception, or pending terminal exception |

Redirects are given priority over ordinary load-use stalls so wrong-path work cannot prevent the PC from being updated. The V1 pipeline uses **EX-stage branch resolution**, not branch prediction.

## 6. Exceptions and retirement

**RTL:** [`decoder.sv`](../rtl/id_stage/decoder.sv), [`ex_stage.sv`](../rtl/ex_stage/ex_stage.sv), [`riscv_core.sv`](../rtl/riscv_core.sv), [`wb_stage.sv`](../rtl/wb_stage/wb_stage.sv)

The V1 exception model recognizes:

- `ECALL` and `EBREAK`.
- Illegal or unsupported instruction encodings.
- Misaligned taken instruction targets.
- Misaligned halfword/word loads and stores.

Decoder-detected exceptions travel with the instruction's control bundle. EX-detected alignment exceptions replace the exception kind and disable the faulting instruction's register and memory writes. The core prevents younger instructions from proceeding while older instructions finish, preserving the intended in-order retirement behavior.

**V1 limitation:** An accepted exception causes fetching to stop until reset. The core does **not** yet implement machine-mode CSR state, `mtvec` trap redirection, interrupt delivery, or a return-from-trap instruction. The retirement record marks an exceptional instruction with `trap`, and this simplified design also sets `halt`.

The `retire_t` bundle is exported by `riscv_core`. Verification-specific [`rvfi_adapter.sv`](../verif/rvfi_adapter.sv) and [`rvfi_wrapper.sv`](../verif/rvfi_wrapper.sv) translate it into the RISC-V Formal Interface. These wrappers belong to the verification environment; they are not required as part of the FPGA top-level design.

## 7. V1 boundaries and upcoming V2 integration

V1 is an architectural verification milestone, **not yet a standalone FPGA computer**. In particular:

- Instruction and data memories are instantiated inside the CPU and use asynchronous reads.
- The internal memories do not fully decode the 32-bit address space; addresses can alias when upper bits are ignored.
- There are no external instruction/data request-response interfaces or general memory backpressure controls.
- There is no GPIO, UART, timer, DDR3 controller, or cache in the processor system.
- Exceptions use a simplified terminal model rather than a privileged software environment.
- Hardware execution on the Urbana FPGA has not yet been demonstrated by V1.

**V2 direction:** Preserve the proven execution datapath where possible, define instruction and data memory interfaces, support variable response latency, integrate synchronous FPGA block RAM, and introduce memory-mapped peripherals. This document should describe *implemented* functionality; update the relevant sections as those changes are verified.

## Related documentation

- [Verification and V1 results](verification.md)
- [Project README](../README.md)
