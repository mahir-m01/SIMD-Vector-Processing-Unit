"""
fuzz.py - random programs on the hardware and the golden model.

The test programs are written by hand, so they only try what we thought of.
This script makes up random programs instead: every op code (used and
unused), random register fields, the spare bit 16 set at random, random
constants, random branches and random memory contents. Each program runs on
the golden model and on the RTL (tb/tb_simd_core.v), and the two must agree
on every memory word, every register, the instruction count and the cycle
count.

A program that would loop forever is thrown away and a new one is made.

Run:  python3 sw/fuzz.py                       # 25 programs per lane count (part of make test)
      python3 sw/fuzz.py --programs 1000       # a longer run (make fuzz)
"""

import argparse
import random
import shutil
import sys

import golden
import run_workloads

W = 16
MAX_STEPS = 20000          # a program that runs longer than this is thrown away
HALT = 0x3F << 26


def random_word(rng):
    """One random 32-bit instruction, biased towards the interesting ones."""
    roll = rng.random()
    if roll < 0.45:
        opcode = rng.randrange(0x00, 0x30)              # vector ALU and reduce, unused jobs too
    elif roll < 0.60:
        opcode = rng.choice([0x30, 0x30, 0x31])         # loads and stores
    elif roll < 0.80:
        opcode = rng.choice([0x38, 0x38, 0x39])         # scalar maths
    elif roll < 0.90:
        opcode = 0x3C                                   # branch
    else:
        opcode = rng.randrange(0x30, 0x40)              # any class-11 code, used or not
    rd, ra, rb = rng.randrange(8), rng.randrange(8), rng.randrange(8)
    spare = rng.randrange(2)                            # bit 16 must make no difference
    if opcode == 0x3C:                                  # mostly forward jumps, some back
        imm = rng.randint(1, 12) if rng.random() < 0.75 else rng.randint(-12, -1)
    elif rng.random() < 0.5:
        imm = rng.randint(-40, 40)                      # small: lands inside memory often
    else:
        imm = rng.randrange(1 << 16)                    # anything: tests wrap-around
    return (opcode << 26) | (rd << 23) | (ra << 20) | (rb << 17) | (spare << 16) | (imm & 0xFFFF)


def make_case(rng, lanes):
    """A random program that reaches HALT, with its golden-model run."""
    while True:
        words = [random_word(rng) for _ in range(rng.randint(10, 120))]
        if rng.random() < 0.3:          # otherwise the program runs into the HALT padding
            words.append(HALT)
        model = golden.SimdModel(lanes, W)
        for i in range(len(model.mem)):
            model.mem[i] = [rng.randrange(1 << W) for _ in range(lanes)]
        start_memory = golden.memory_hex_lines(model)
        try:
            instructions, cycles = model.run(words, max_steps=MAX_STEPS)
        except RuntimeError:            # the golden model says it never reached HALT
            continue
        return dict(words=words, start_memory=start_memory, model=model,
                    instructions=instructions, cycles=cycles, elements=0)


def main():
    parser = argparse.ArgumentParser(description="Random programs: RTL against the golden model.")
    parser.add_argument("--programs", type=int, default=25, help="programs per lane count")
    parser.add_argument("--lanes", type=int, nargs="+", default=[1, 2, 4, 8])
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    failures = 0
    for lanes in args.lanes:
        vvp = run_workloads.compile_tb(lanes)
        rng = random.Random(f"fuzz-{args.seed}-{lanes}")
        for n in range(args.programs):
            run = make_case(rng, lanes)
            folder = run_workloads.BUILD / f"fuzz_L{lanes}_{n}"
            run_workloads.write_files(folder, run)
            passed, _ = run_workloads.run_rtl(vvp, folder, False)
            if passed:
                shutil.rmtree(folder)               # keep only the files of a failing program
            else:
                failures += 1
                print(f"MISMATCH lanes={lanes} program {n}: files in {folder}")
        print(f"fuzz lanes={lanes}: {args.programs} random programs, {failures} mismatches so far")
    if failures:
        sys.exit(f"{failures} random program(s) FAILED")


if __name__ == "__main__":
    main()
