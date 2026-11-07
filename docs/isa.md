# Instruction set

The processor has 48 instructions: 14 ALU jobs, each in three forms (vector–vector, vector–scalar and reduce), plus 6 for memory, scalar maths and program flow. Every instruction is one 32-bit word.

## Registers

| Name | Count | Width | Holds |
| --- | --- | --- | --- |
| `v0`–`v7` | 8 | 128 bits = 8 lanes × 16 bits | vectors: 8 numbers at once |
| `s0`–`s7` | 8 | 32 bits | single numbers: addresses, loop counters, broadcast values, sums |

`s0` always reads as 0, and writes to it are ignored. That gives programs a free zero: `ADDI s1, s0, 5` means `s1 = 5`.

All arithmetic is on **16-bit two's-complement integers**: −32768 to 32767. A result that does not fit wraps around (`32767 + 1 = −32768`), like a car odometer. There is no saturation and no error flag.

## Encoding

```text
 31      26 25  23 22  20 19  17 16 15                0
+----------+------+------+------+--+-------------------+
|  opcode  |  rd  |  ra  |  rb  |--|   imm (16 bits)   |
+----------+------+------+------+--+-------------------+
```

The top two opcode bits give the instruction class. For classes `00`, `01` and `10`, the low four opcode bits pick the ALU job.

| Class | Opcode | Meaning | Example |
| --- | --- | --- | --- |
| `00` vector–vector | `0x00`–`0x0D` | `vd[i] = va[i] op vb[i]` for every lane `i` | `VADD v3, v1, v2` |
| `01` vector–scalar | `0x10`–`0x1D` | `vd[i] = va[i] op s[rb]`: the low 16 bits of the scalar are broadcast to every lane | `VMUL v3, v1, s2` |
| `10` reduce | `0x20`–`0x2D` | `sd = Σ (va[i] op vb[i])` over all lanes | `VDOT s4, v1, v2` |
| `11` memory, scalar, control | `0x30`–`0x3F` | see below | |

The assembler picks class `00` or `01` from the third operand. A `v` register gives vector–vector; an `s` register gives vector–scalar.

## ALU jobs (low 4 opcode bits)

| Code | Job | Result per lane |
| --- | --- | --- |
| 0 | `ADD` | `a + b` |
| 1 | `SUB` | `a − b` |
| 2 | `AND` | bitwise AND |
| 3 | `OR` | bitwise OR |
| 4 | `XOR` | bitwise XOR |
| 5 | `SLL` | `a` shifted left by `b mod 16`, zeros in |
| 6 | `SRL` | `a` shifted right by `b mod 16`, zeros in |
| 7 | `SRA` | `a` shifted right by `b mod 16`, sign bit copied in |
| 8 | `MUL` | low 16 bits of `a × b` |
| 9 | `SEQ` | all ones if `a = b`, else 0 |
| 10 | `SLT` | all ones if `a < b` (signed), else 0 |
| 11 | `SLTU` | all ones if `a < b` (unsigned), else 0 |
| 12 | `MIN` | smaller of `a`, `b` (signed) |
| 13 | `MAX` | larger of `a`, `b` (signed) |

Comparisons write all ones (`0xFFFF`) for true, because that value works directly as a mask: `VAND` with it keeps a lane and `VAND` with 0 clears it. Intel SSE and ARM NEON use the same convention.

## Memory, scalar and control (class `11`)

| Opcode | Instruction | Meaning | Cycles |
| --- | --- | --- | --- |
| `0x30` | `VLD vd, imm(sa)` | `vd = memory[sa + imm]` (one 128-bit word) | 2 |
| `0x31` | `VST vb, imm(sa)` | `memory[sa + imm] = vb` (the stored register goes in the `rb` field; `rd` is unused) | 1 |
| `0x38` | `ADDI sd, sa, imm` | `sd = sa + imm` | 1 |
| `0x39` | `ADD sd, sa, sb` | `sd = sa + sb` | 1 |
| `0x3C` | `BNE sa, sb, label` | if `sa ≠ sb`, jump to `label`; `imm` = label address − address of this `BNE` | 1 |
| `0x3F` | `HALT` | stop | 1 |

Every instruction except `VLD` takes one clock cycle. `VLD` takes two, because block RAM returns data one clock after it receives the address. Taken branches cost no extra cycle (see [architecture.md](architecture.md#timing)).

## Wrap-around and unused op codes

* **Addresses wrap.** `VLD` and `VST` use `(sa + imm)` modulo the data-memory size: 1,024 words, in simulation and on the FPGA. Address −1 is the last word.
* **The program counter wraps.** After instruction 255 comes instruction 0, and a branch offset that goes below 0 or above 255 wraps the same way.
* **Unused op codes.** `0x0E`, `0x0F`, `0x1E` and `0x1F` write 0 into `vd`; `0x2E` and `0x2F` write 0 into `sd`. Every other unused code in class `11` does nothing for one cycle. The assembler never produces these codes; the directed tests in `sw/directed_tests.py` check that the hardware and the golden model agree on them.
* **Reset.** Reset starts the program again from address 0 and clears the halt flag and the two counters. It does not clear the registers or the data memory: the registers are zero only at power-up (the register files start at zero when the chip is programmed, which is the state the golden model starts from), and the memory keeps whatever the last run left in it. A program that relies on starting values should set them itself.

## Reduce mnemonics

`VRED<job> sd, va, vb` adds up all lanes of `va <job> vb` into a scalar register. For example, `VREDADD s5, v1, v2` gives `Σ(v1[i] + v2[i])`. `VDOT` is another name for `VREDMUL`: the dot product of two vectors in one instruction. Each lane result is read as a signed 16-bit number and widened to 32 bits before the adding, so the sum itself does not overflow. For `VDOT` this means each product keeps only its low 16 bits, exactly as `VMUL` does, so the result is the true dot product only while every product fits in 16 bits (−32768 to 32767). A multiply that keeps the full 32-bit product is a Phase 2 candidate.

## Memory layout

Data memory words are 128 bits wide, so one `VLD` moves 8 elements. Element `i` of an array that starts at word `base` lives in word `base + i / LANES`, lane `i mod LANES`. With one lane, each word holds one element; that is how the scalar baseline runs the same program.
