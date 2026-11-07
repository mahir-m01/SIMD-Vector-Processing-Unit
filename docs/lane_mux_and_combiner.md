# Lane MUX and result combiner

Files: [`rtl/lane_mux.v`](../rtl/lane_mux.v), [`rtl/result_combiner.v`](../rtl/result_combiner.v), test [`tb/tb_lane_combiner.v`](../tb/tb_lane_combiner.v)

These two blocks sit on either side of the lanes. The lane MUX decides what goes **into** each lane; the result combiner decides what comes **out**.

## Lane MUX: vector or broadcast

Every lane needs a second number (operand B), and it can come from two places:

| `use_scalar` | Each lane gets | Example |
| --- | --- | --- |
| 0 | its own element of vector register `vb` | `VADD v3, v1, v2`: lane *i* computes `v1[i] + v2[i]` |
| 1 | the same scalar value, copied to every lane | `VMUL v3, v1, s2`: lane *i* computes `v1[i] × s2` |

Copying one value into every lane is called a **broadcast**. In Verilog, `{LANES{scalar_b}}` glues 8 copies of the 16-bit value side by side. The hardware is 8 small two-way switches (multiplexers), one per lane, all flipped by the same signal.

Without broadcast, multiplying a vector by 3 would first need a vector full of 3s, which costs an extra instruction and a register.

## Result combiner: vector and sum

The lane outputs are combined in two ways at the same time:

1. **`vector_result`**: the 8 outputs side by side as one 128-bit vector. This is what `VADD`, `VMUL` and the other vector instructions write back.
2. **`sum_result`**: all 8 outputs added into one 32-bit number. This is what the reduce instructions write to a scalar register. With the lanes multiplying, `VDOT s4, v1, v2` computes `Σ v1[i] × v2[i]`, a dot-product step in one instruction.

The sum uses an **adder tree** rather than a chain:

```text
lane:   0   1   2   3   4   5   6   7
         \ /     \ /     \ /     \ /       round 1: 4 adders
          +       +       +       +
            \   /           \   /          round 2: 2 adders
              +               +
                  \       /                round 3: 1 adder
                      +
```

A chain of 8 numbers needs 7 adders one after another; the tree needs only 3 rounds (log₂ 8). The answer is ready sooner, so the clock can be faster, and the tree still uses 7 adders in total. Each 16-bit element is sign-extended to 32 bits first, so −1 stays −1 and the sum cannot overflow (8 × 32,767 fits easily).

## Test

`tb_lane_combiner` runs for **1, 2, 4 and 8 lanes**, with 11,008 checks each:

1. 1,000 random lane-MUX cases, half vector and half broadcast;
2. the combiner's extremes: every lane 32,767, every lane −32,768, every lane −1, every lane 0;
3. 5,000 random vectors. The tree's sum is compared with a plain one-by-one loop, so the tree is checked against the simplest possible method.

```bash
make tb_lane_combiner
```
