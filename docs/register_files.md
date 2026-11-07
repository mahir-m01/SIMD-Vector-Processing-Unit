# Register files

Files: [`rtl/vec_regfile.v`](../rtl/vec_regfile.v), [`rtl/scalar_regfile.v`](../rtl/scalar_regfile.v), test [`tb/tb_regfiles.v`](../tb/tb_regfiles.v)

Registers are the processor's own tiny, very fast storage. Memory is large but slow (one clock to read); registers can be read instantly, and an instruction usually reads two of them and writes one.

## Vector register file

* 8 registers, `v0` to `v7`, each 128 bits = 8 lanes × 16 bits.
* **Two read ports.** `VADD v3, v1, v2` needs `v1` and `v2` at the same time. Reading has no clock: the data appears as soon as the address is set.
* **One write port.** The result is stored at the rising clock edge, and only when `write_en` is 1.
* **Read-during-write.** If an instruction reads and writes the same register (`VADD v1, v1, v2`), it reads the old value. The new one is stored at the clock edge. This is what makes `v1 = v1 + v2` work.

## Scalar register file (the scalar interface)

* 8 registers, `s0` to `s7`, each 32 bits.
* `s0` always reads 0, and writes to it are dropped. Programs get a free zero: `ADDI s1, s0, 5` sets `s1` to 5, and `VMAX v2, v1, s0` compares every lane with 0.
* Two read ports and one write port, like the vector file.
* A third **debug read port** lets the outside world read any register without disturbing the program. The system testbench uses it to check the results; on the FPGA board, three switches pick a register and eight LEDs show its low byte.

Scalar registers do four jobs: memory addresses (`VLD v1, A(s1)`), loop counters (`BNE s1, s2, loop`), values broadcast to every lane (`VMUL v1, v1, s3`), and the single-number result of a reduce (`VDOT s4, v1, v2`).

## On the FPGA

Both files use about the same logic as a small memory, and the synthesis tools notice. On ECP5 and Artix-7 they are built from distributed LUT RAM rather than flip-flops, which is why the whole 8-lane design needs only 283 flip-flops.

## Test

`tb_regfiles` keeps its own copy of what every register should hold and checks 10,044 reads:

1. a different pattern written into each register, then read back through both ports in opposite orders;
2. a write with `write_en = 0` must change nothing;
3. read-during-write gives the old value before the edge and the new value after;
4. `s0` stays 0 even after a write;
5. 2,000 random cycles on each file (random write enable, addresses and data).

```bash
make tb_regfiles
```
