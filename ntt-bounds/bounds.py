#!/usr/bin/env python3
"""Replay and tabulate the actual CONGBOUND theorems of the ARM proof suite."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PIN = "fce78c7c17baee6a60511efe821930d4d049a6c0"
# name: number of output-rule calls, input contract, output contract
# The canonical reduce result follows from its exact remainder postcondition;
# its single CONGBOUND call is the centered intermediate, explicitly labelled.
SPECS = {
    "mlkem_basemul_k2": (256, "|x_j| <= 4096; -32768 <= y_j,y'_j <= 32767", "-32768 <= z <= 32767 (type only)"),
    "mlkem_basemul_k3": (256, "|x_j| <= 4096; -32768 <= y_j,y'_j <= 32767", "-32768 <= z <= 32767 (type only)"),
    "mlkem_basemul_k4": (256, "|x_j| <= 4096; -32768 <= y_j,y'_j <= 32767", "-32768 <= z <= 32767 (type only)"),
    "mlkem_intt": (256, "-32768 <= x <= 32767 (type only)", "|z| <= 26624"),
    "mlkem_mulcache_compute": (128, "-32768 <= x <= 32767 (type only)", "|z| <= 3328"),
    "mlkem_ntt": (256, "|x| <= 8191", "|z| <= 23594"),
    "mlkem_reduce": (1, "-32768 <= x <= 32767 (type only)", "z = x rem 3329: 0 <= z <= 3328"),
    "mlkem_tomont": (256, "-32768 <= x <= 32767 (type only)", "|z| <= 3328"),
    "mldsa_intt": (256, "|x| <= 8380416", "|z| <= 8380416"),
    "mldsa_ntt": (256, "|x| <= 8380416", "|z| <= 75423752"),
    "mldsa_pointwise": (256, "|x|,|y| <= 75423752", "|z| <= 8380416"),
    "mldsa_pointwise_acc_l4": (256, "|x| <= 8380416; |y| <= 75423752", "|z| <= 8380416"),
    "mldsa_pointwise_acc_l5": (256, "|x| <= 8380416; |y| <= 75423752", "|z| <= 8380416"),
    "mldsa_pointwise_acc_l7": (256, "|x| <= 8380416; |y| <= 75423752", "|z| <= 8380416"),
}


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def check_sources():
    """Fail closed if a proof is added, removed, or any pinned dependency drifts."""
    inventory = {p.stem for prefix in ("mlkem_", "mldsa_")
                 for p in (ROOT / "arm/proofs").glob(prefix + "*.ml")
                 if "CONGBOUND_RULE" in p.read_text()}
    if inventory != SPECS.keys():
        raise ValueError(f"CONGBOUND inventory changed: {inventory ^ SPECS.keys()}")
    run(["git", "diff", "--exit-code", PIN, "--", "common", "arm/proofs",
         "arm/mlkem", "arm/mldsa", "include"], cwd=ROOT, capture_output=True)


def instrument(name):
    source = (ROOT / "arm/proofs" / (name + ".ml")).read_text()
    marker = 'needs "common/mlkem_mldsa.ml";;'
    if source.count(marker) != 1:
        raise ValueError(f"{name}: shared machinery import changed")
    # Keep proof statements and tactics intact. The observer shadows only the
    # three public rule entrypoints, immediately after the real imports.
    source = source.replace(marker, marker + '\nneeds "ntt-bounds/tap.ml";;')
    return source + f'\nntt_bounds_finish "{name}" {SPECS[name][0]};;\n'


def fingerprint(name):
    return hashlib.sha256((PIN + instrument(name) +
                           (HERE / "tap.ml").read_text()).encode()).hexdigest()


def entry_source(name):
    if name == "mlkem_intt":
        return ('needs "ntt-bounds/generated/mlkem_intt.ml";;\n'
                'ntt_bounds_finish "mlkem_intt" 256;;\n')
    return instrument(name)


def entry_path(name):
    return HERE / "generated" / (name + ("_result" if name == "mlkem_intt" else "") + ".ml")


def generate(names):
    check_sources()
    out = HERE / "generated"
    out.mkdir(exist_ok=True)
    for name in names:
        path = out / (name + ".ml")
        text = instrument(name)
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
        if name == "mlkem_intt":
            entry_path(name).write_text(entry_source(name))
    print(f"PASS: generated {len(names)} instrumented proofs at {PIN[:12]}")


def results():
    path = HERE / "results.tsv"
    if not path.exists():
        return {}
    with path.open() as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if len({r["name"] for r in rows}) != len(rows):
        raise ValueError("duplicate result rows")
    return {r["name"]: r for r in rows}


def read_result(raw, name):
    lines = [line for line in raw.splitlines(keepends=True)
             if line.startswith("NTT_BOUND_RESULT ")]
    match = (re.fullmatch(r"NTT_BOUND_RESULT (\w+) (\d+) (-?\d+) (-?\d+)\n", lines[0])
             if len(lines) == 1 else None)
    if not match or match[1] != name:
        raise ValueError(f"{name}: missing, duplicate, or malformed bound result")
    _, count, lo, hi = match.groups()
    if int(count) != SPECS[name][0] or int(lo) > int(hi):
        raise ValueError(f"{name}: wrong call count or invalid interval")
    return count, lo, hi


def collect(hearth, run_root, name):
    info = json.loads(run([hearth, "inspect", str(run_root / name), "--json"],
                          capture_output=True).stdout)
    if info["verdict"] != "passed" or info["new_axioms"] != 0:
        raise ValueError(f"{name}: Hearth did not accept complete source with 0 new axioms")
    if info["source_sha256"] != hashlib.sha256(entry_source(name).encode()).hexdigest():
        raise ValueError(f"{name}: receipt belongs to a different source")
    receipt = Path(info["receipt"])
    raw = receipt.with_name("transcript.log.raw").read_text()
    count, lo, hi = read_result(raw, name)
    return dict(name=name, count=count, lower=lo, upper=hi,
                fingerprint=fingerprint(name), receipt=str(receipt))


def save_results(saved):
    with (HERE / "results.tsv").open("w") as f:
        writer = csv.DictWriter(f, delimiter="\t", fieldnames=[
            "name", "count", "lower", "upper", "fingerprint", "receipt"])
        writer.writeheader()
        writer.writerows(saved[n] for n in sorted(saved))


def collect_results(args):
    check_sources()
    saved = results()
    for name in args.names:
        saved[name] = collect(args.hearth, args.run_root, name)
        save_results(saved)
        print(f"PASS: {name} bounds {saved[name]['lower']}..{saved[name]['upper']}")


def replay(args):
    names = args.names or sorted(SPECS, key=lambda n: (n == "mlkem_intt", n))
    generate(names)
    saved = results()
    for name in names:
        if name in saved and saved[name]["fingerprint"] == fingerprint(name):
            print(f"PASS: {name} already extracted; source unchanged", flush=True)
            continue
        family = name.split("_")[0]
        run(["make", "-C", "arm", f"{family}/{name}.o"], cwd=ROOT)
        basis = (["--basis", str(HERE / "generated/mlkem_intt.ml"),
                  "--basis-cache-root", str(args.run_root)] if name == "mlkem_intt" else [])
        run([args.hearth, "prove", str(entry_path(name)), *basis,
             "--profile", "s2n-arm-mlkem", "--timeout", str(args.timeout),
             "--run-root", str(args.run_root / name)], cwd=ROOT)
        saved[name] = collect(args.hearth, args.run_root, name)
        save_results(saved)
        print(f"PASS: {name} bounds {saved[name]['lower']}..{saved[name]['upper']}", flush=True)


def multiples(text, q):
    return re.sub(r"\b(\d{4,})\b", lambda m: f"{int(m[0])/q:.6f}q", text)


def table():
    check_sources()
    saved = results()
    missing = [n for n in SPECS if n not in saved or saved[n]["fingerprint"] != fingerprint(n)]
    if missing:
        raise ValueError("table incomplete or stale: " + ", ".join(missing))
    lines = []
    for name in sorted(SPECS):
        _, inp, out = SPECS[name]
        q = 3329 if name.startswith("mlkem") else 8380417
        row = saved[name]
        lo, hi = int(row["lower"]), int(row["upper"])
        if int(row["count"]) != SPECS[name][0] or lo > hi:
            raise ValueError(f"{name}: saved result count or interval invalid")
        label = ""
        if name == "mlkem_reduce":
            if (lo, hi) != (-1664, 1664):
                raise ValueError("mlkem_reduce: centered lemma bounds changed")
            lo, hi = 0, 3328
            label = " (exact remainder; centered intermediate [-1664,1664])"
        cells = (name, f"{inp}; {multiples(inp, q)}", f"{out}; {multiples(out,q)}",
                 f"[{lo}, {hi}]{label}", f"{max(abs(lo),abs(hi))/q:.6f}q")
        lines.append("| " + " | ".join(c.replace("|", r"\|") for c in cells) + " |")
    print(f"PASS: table covers all {len(SPECS)} ARM CONGBOUND proofs at {PIN[:12]}; x86 NOT RUN")
    print("| Function | Input assumption (and /q) | Spec output (and /q) | Proof-derived interval | max abs /q |")
    print("|---|---|---|---|---|")
    print("\n".join(lines))
    print("| x86 mlkem_intt | NOT RUN | abs(z) < 26632 (8q) | NOT RUN; #321 reports 14939 | NOT RUN |")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("table")
    sub.add_parser("generate")
    for command in ("replay", "collect"):
        p = sub.add_parser(command)
        p.add_argument("names", nargs="*" if command == "replay" else "+")
        p.add_argument("--hearth", default=os.environ.get("HEARTH", "hearth"))
        p.add_argument("--run-root", type=Path, required=True)
        p.add_argument("--timeout", type=int, default=7200)
    args = parser.parse_args()
    try:
        if hasattr(args, "run_root"):
            args.run_root = args.run_root.resolve()
            unknown = set(args.names) - SPECS.keys()
            if unknown:
                raise ValueError("unknown functions: " + ", ".join(sorted(unknown)))
        if args.command == "table":
            table()
        elif args.command == "generate":
            generate(sorted(SPECS))
        elif args.command == "collect":
            collect_results(args)
        else:
            replay(args)
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
