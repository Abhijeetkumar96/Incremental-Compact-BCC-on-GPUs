#!/usr/bin/env python3
"""Build everything for the local GPU, then run ./run_all and the static-compact-bcc baseline.

Example:
    python3 run.py datasets/medium_datasets/road_usa.egr -k 1000
    python3 run.py datasets/small_datasets/input_100.txt -k 10 -o output/
    CUDA_VISIBLE_DEVICES=1 python3 run.py datasets/small_datasets/input_100.txt -k 10
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

# Fallback when nvidia-smi cannot report compute_cap (older drivers).
NAME_TO_SM = [
    ("H200", "90"), ("H100", "90"), ("GH200", "90"),
    ("L40", "89"), ("L4", "89"), ("RTX 40", "89"), ("RTX 6000 ADA", "89"),
    ("A100", "80"), ("A30", "80"),
    ("A40", "86"), ("A10", "86"), ("RTX A", "86"), ("RTX 30", "86"),
    ("T4", "75"), ("RTX 20", "75"),
    ("V100", "70"),
]


def visible_device():
    """First GPU in CUDA_VISIBLE_DEVICES (index or UUID); nvidia-smi does not honour that variable itself."""
    visible = os.environ.get("CUDA_VISIBLE_DEVICES", "").split(",")[0].strip()
    return visible or "0"


def detect_gpu(device):
    """Return (name, sm) for the given nvidia-smi device id."""
    try:
        out = subprocess.run(
            ["nvidia-smi", "-i", str(device),
             "--query-gpu=name,compute_cap", "--format=csv,noheader"],
            check=True, capture_output=True, text=True).stdout.strip()
        name, cap = [s.strip() for s in out.splitlines()[0].split(",", 1)]
        if cap.replace(".", "").isdigit():
            return name, cap.replace(".", "")
    except (OSError, subprocess.CalledProcessError, ValueError, IndexError):
        # Older drivers reject compute_cap; retry with name only.
        try:
            name = subprocess.run(
                ["nvidia-smi", "-i", str(device),
                 "--query-gpu=name", "--format=csv,noheader"],
                check=True, capture_output=True, text=True).stdout.strip().splitlines()[0]
        except (OSError, subprocess.CalledProcessError, IndexError):
            sys.exit("error: no NVIDIA GPU detected (nvidia-smi failed); pass --sm explicitly")

    upper = name.upper()
    for key, sm in NAME_TO_SM:
        if key in upper:
            return name, sm
    sys.exit(f"error: unknown GPU '{name}'; pass --sm explicitly (e.g. --sm 80)")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("graph", help="input graph file")
    p.add_argument("-k", "--batch", type=int, default=0, help="batch size (default 0)")
    p.add_argument("-o", "--output", help="directory for GPU result files")
    p.add_argument("--sm", help="override detected compute capability, e.g. 80 or 89")
    p.add_argument("--no-build", action="store_true", help="skip make")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    args = p.parse_args()

    if args.sm:
        name, sm = "user override", args.sm
    else:
        name, sm = detect_gpu(visible_device())
    print(f"GPU {visible_device()}: {name} -> sm_{sm}", flush=True)

    if not args.no_build:
        subprocess.run(["make", f"-j{args.jobs}", f"SM={sm}"], cwd=ROOT, check=True)

    cmd = [os.path.join(ROOT, "run_all"), "-i", args.graph, "-k", str(args.batch)]
    if args.output:
        os.makedirs(args.output, exist_ok=True)
        cmd += ["-o", args.output]

    static_cmd = [os.path.join(ROOT, "baseline", "static-compact-bcc", "bin", "cuda_bcc"),
                  "-i", args.graph]

    ret = 0
    for c in (cmd, static_cmd):
        print("\n$ " + " ".join(c), flush=True)
        ret = subprocess.run(c).returncode or ret
    sys.exit(ret)


if __name__ == "__main__":
    main()
