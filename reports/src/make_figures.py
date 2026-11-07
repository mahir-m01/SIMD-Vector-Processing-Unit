"""make_figures.py - draws the result figures for the IEEE report.

Reads the measured results in results/*.csv and writes two vector PDFs
into reports/src/figures/:

    perf.pdf   scalar vs SIMD: cycles, speed-up, and speed-up against N
    fpga.pdf   FPGA size, clock speed and throughput against lane count

Run from the repository root (make report does this for you):
    uv run --python 3.12 --with matplotlib python reports/src/make_figures.py
"""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "figures"

LANES = [1, 2, 4, 8]
KERNELS = ["vadd", "saxpy", "relu", "threshold", "dot"]
# Colours shared with the diagrams: orange = scalar (1 lane), blue = SIMD.
ORANGE, BLUE, GREY = "#ef6f3c", "#3f7fdc", "#555555"
LANE_COLOURS = {1: ORANGE, 2: "#a9c8f0", 4: "#6fa3e8", 8: BLUE}
FULL_WIDTH, HEIGHT = 7.16, 1.95          # inches: IEEE two-column text width

# vadd: 2 set-up instructions, 8 cycles per pass (6 instructions + 2 loads), then HALT.
VADD_SETUP, VADD_PER_PASS = 2, 8


def style():
    """Times text at 8 pt, light grid, no box around the plots (as in the reference report)."""
    plt.rcParams.update({
        "font.family": "serif", "font.size": 8,
        "font.serif": ["Times New Roman", "Times", "Nimbus Roman", "STIXGeneral"],
        "mathtext.fontset": "stix", "pdf.fonttype": 42,
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.edgecolor": GREY, "axes.linewidth": 0.6,
        "axes.grid": True, "grid.color": "#e4e4e4", "grid.linewidth": 0.5,
        "axes.axisbelow": True, "legend.frameon": False, "legend.fontsize": 7,
        "xtick.color": GREY, "ytick.color": GREY,
        "xtick.major.width": 0.6, "ytick.major.width": 0.6,
    })


def read(name):
    with open(ROOT / "results" / name) as f:
        return list(csv.DictReader(f))


def lane_axis(ax):
    """x axis showing exactly 1, 2, 4, 8 lanes on a log2 scale."""
    ax.set_xscale("log", base=2)
    ax.set_xticks(LANES, [str(n) for n in LANES])
    ax.minorticks_off()
    ax.set_xlabel("lanes $L$")


def cycles_panel(ax, perf):
    """Grouped bars: clock cycles of every kernel at 1, 2, 4 and 8 lanes."""
    width = 0.2
    for j, lanes in enumerate(LANES):
        heights = [perf[(k, lanes)]["cycles"] for k in KERNELS]
        xs = [i + (j - 1.5) * width for i in range(len(KERNELS))]
        label = "1 lane (scalar)" if lanes == 1 else f"{lanes} lanes"
        ax.bar(xs, heights, width, color=LANE_COLOURS[lanes], label=label)
        if lanes == 8:                               # speed-up above the 8-lane bar
            for x, k in zip(xs, KERNELS):
                ax.text(x, perf[(k, 8)]["cycles"] + 40, f"{perf[(k, 8)]['speedup']:.2f}$\\times$",
                        ha="center", va="bottom", fontsize=6, rotation=90, color=GREY)
    ax.set_xticks(range(len(KERNELS)), KERNELS)
    ax.grid(axis="x", visible=False)
    ax.set_ylabel("clock cycles ($N = 256$)")
    ax.legend(loc="upper right", ncol=2, handlelength=1, columnspacing=0.8)
    ax.set_ylim(0, 2900)


def speedup_panel(ax, perf, fmax):
    """Mean speed-up over the five kernels, in cycles and in real (wall-clock) time."""
    cyc = [sum(perf[(k, n)]["speedup"] for k in KERNELS) / len(KERNELS) for n in LANES]
    wall = [s * fmax[n] / fmax[1] for s, n in zip(cyc, LANES)]
    ax.plot(LANES, LANES, "--", color="#9a9a9a", lw=0.8, zorder=3, label="ideal ($L\\times$)")
    ax.plot(LANES, cyc, "o-", color=BLUE, ms=4, lw=1.2, label="clock cycles")
    ax.plot(LANES, wall, "s-", color=ORANGE, ms=4, lw=1.2, label="wall-clock (ECP5 $F_{\\max}$)")
    ax.annotate(f"{cyc[-1]:.2f}$\\times$", (8, cyc[-1]), xytext=(-4, 4), textcoords="offset points",
                ha="right", color=BLUE)
    ax.annotate(f"{wall[-1]:.2f}$\\times$", (8, wall[-1]), xytext=(-4, -9), textcoords="offset points",
                ha="right", color=ORANGE)
    lane_axis(ax)
    ax.set_ylabel("speed-up over 1 lane")
    ax.set_ylim(0, 8.6)
    ax.legend(loc="upper left")


def size_panel(ax, perf):
    """Speed-up of vadd against problem size N, from the cycle formula, with measured points."""
    def cycles(lanes, n):
        return VADD_SETUP + (n // lanes) * VADD_PER_PASS + 1

    sizes = [2 ** e for e in range(3, 13)]           # N = 8 ... 4096
    for lanes, shade in ((8, BLUE), (4, "#6fa3e8"), (2, "#a9c8f0")):
        ns = [n for n in sizes if n >= lanes]
        ax.plot(ns, [cycles(1, n) / cycles(lanes, n) for n in ns], "-", color=shade, lw=1.2,
                label=f"$L = {lanes}$")
        ax.axhline(lanes, color="#d0d0d0", lw=0.6, ls=":")
    measured = [perf[("vadd", n)]["speedup"] for n in (2, 4, 8)]
    ax.plot([256] * 3, measured, "D", color="black", ms=3.5, label="measured (RTL)")
    ax.set_xscale("log", base=2)
    ax.set_xticks([8, 32, 128, 512, 2048], ["8", "32", "128", "512", "2048"])
    ax.minorticks_off()
    ax.set_xlabel("elements $N$ (vadd)")
    ax.set_ylabel("speed-up over 1 lane")
    ax.set_ylim(0, 8.6)
    ax.legend(loc="lower right", bbox_to_anchor=(1, 0.5), ncol=2, columnspacing=0.8)


def perf_figure(perf, fmax):
    fig, axes = plt.subplots(1, 3, figsize=(FULL_WIDTH, HEIGHT),
                             gridspec_kw={"width_ratios": [1.35, 1, 1]})
    cycles_panel(axes[0], perf)
    speedup_panel(axes[1], perf, fmax)
    size_panel(axes[2], perf)
    fig.tight_layout(w_pad=1.5)
    fig.savefig(OUT / "perf.pdf")


def resources_panel(ax, ecp5, artix):
    """Logic used against lane count, on both FPGA families."""
    cells = [ecp5[n]["logic_cells"] for n in LANES]
    ax.plot(LANES, cells, "o-", color=BLUE, ms=4, lw=1.2, label="ECP5 logic cells (P&R)")
    ax.plot(LANES, [artix[n]["luts"] for n in LANES], "s-", color=ORANGE, ms=4, lw=1.2,
            label="Artix-7 LUTs (Yosys)")
    for n, v in zip(LANES, cells):
        ax.annotate(f"{v:,.0f}", (n, v), xytext=(3, 5), textcoords="offset points",
                    ha="center", fontsize=6.5, color=BLUE)
    lane_axis(ax)
    ax.set_ylabel("logic cells / LUTs")
    ax.set_ylim(0, 7200)                              # room for the legend above the data
    ax.legend(loc="upper left")


def fmax_panel(ax, ecp5):
    """Median Fmax of three placement seeds; the bars show the lowest and highest seed."""
    med = [ecp5[n]["fmax_mhz_median"] for n in LANES]
    low = [m - ecp5[n]["fmax_mhz_min"] for m, n in zip(med, LANES)]
    high = [ecp5[n]["fmax_mhz_max"] - m for m, n in zip(med, LANES)]
    ax.errorbar(LANES, med, yerr=[low, high], fmt="o-", color=BLUE, ms=4, lw=1.2, capsize=2.5)
    for n, v in zip(LANES, med):
        ax.annotate(f"{v:.1f}", (n, v), xytext=(5, 3), textcoords="offset points", fontsize=6.5,
                    color=BLUE)
    lane_axis(ax)
    ax.set_ylabel("$F_{\\max}$ on ECP5-25F (MHz)")
    ax.set_ylim(0, 60)


def throughput_panel(ax, perf, ecp5):
    """Elements per second (mean over the kernels) and the same per 1,000 logic cells."""
    rate = [sum(perf[(k, n)]["elements_per_cycle"] for k in KERNELS) / len(KERNELS)
            * ecp5[n]["fmax_mhz_median"] for n in LANES]
    per_kcell = [r / ecp5[n]["logic_cells"] * 1000 for r, n in zip(rate, LANES)]
    xs = range(len(LANES))
    ax.bar(xs, rate, 0.55, color=[LANE_COLOURS[n] for n in LANES])
    for x, v in zip(xs, rate):                       # value inside the top of each bar
        ax.text(x, v - 0.8, f"{v:.1f}", ha="center", va="top", fontsize=6.5, color="white")
    ax.set_xticks(xs, [str(n) for n in LANES])
    ax.set_xlabel("lanes $L$")
    ax.set_ylabel("throughput (million elements/s)")
    ax.set_ylim(0, 40)
    ax.grid(axis="x", visible=False)
    twin = ax.twinx()
    twin.plot(xs, per_kcell, "D-", color=GREY, ms=3, lw=0.9)
    twin.set_ylim(0, 10)
    twin.set_ylabel("per 1,000 logic cells (line)", color=GREY)
    twin.grid(False)
    twin.spines["right"].set_visible(True)


def fpga_figure(perf, ecp5, artix):
    fig, (a, b, c) = plt.subplots(1, 3, figsize=(FULL_WIDTH, HEIGHT))
    resources_panel(a, ecp5, artix)
    fmax_panel(b, ecp5)
    throughput_panel(c, perf, ecp5)
    fig.tight_layout(w_pad=1.5)
    fig.savefig(OUT / "fpga.pdf")


def main():
    style()
    perf = {(r["workload"], int(r["lanes"])): {k: float(r[k]) for k in
            ("cycles", "speedup", "elements_per_cycle")} for r in read("perf.csv")}
    ecp5 = {int(r["lanes"]): {k: float(v) for k, v in r.items()} for r in read("fpga_ecp5.csv")}
    artix = {int(r["lanes"]): {k: float(v) for k, v in r.items()} for r in read("fpga_artix7.csv")}
    fmax = {n: ecp5[n]["fmax_mhz_median"] for n in LANES}
    OUT.mkdir(exist_ok=True)
    perf_figure(perf, fmax)
    fpga_figure(perf, ecp5, artix)
    print("wrote", OUT / "perf.pdf", "and", OUT / "fpga.pdf")


if __name__ == "__main__":
    main()
