#!/usr/bin/env python3
"""Cold upstream replay using s2n-bignum's existing native proof builder."""
import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import time

import bounds

CLAIMS = re.compile(r"^let ([A-Z0-9_]+_(?:CORRECT|SAFE)) = (?:time )?prove\s*\(\s*`([^`]+)`", re.M)
ORDER = ["mlkem_tomont", "mlkem_reduce", "mlkem_mulcache_compute",
         "mldsa_pointwise", "mlkem_basemul_k2", "mlkem_basemul_k3",
         "mlkem_basemul_k4", "mlkem_intt", "mlkem_ntt",
         "mldsa_pointwise_acc_l4", "mldsa_pointwise_acc_l5",
         "mldsa_ntt", "mldsa_pointwise_acc_l7", "mldsa_intt"]


def instrument(source, name):
    marker = 'needs "common/mlkem_mldsa.ml";;'
    if source.count(marker) != 1:
        raise ValueError(f"{name}: shared machinery import changed")
    return source.replace(marker, marker + '\nneeds "ntt-bounds/tap.ml";;') + (
        f'\nntt_bounds_finish "{name}" {bounds.SPECS[name][0]};;\n')


def probes(source, name):
    claims = CLAIMS.findall(source)
    expected = {name.upper() + suffix for suffix in
                ("_CORRECT", "_SUBROUTINE_CORRECT", "_SUBROUTINE_SAFE")}
    if len(claims) != 3 or {c[0] for c in claims} != expected:
        raise ValueError(f"{name}: expected three quoted correctness/safety claims")
    return "\n".join(
        f'if hyp {binding} <> [] || not (aconv (concl {binding}) `{statement}`) '
        f'then failwith "Cold claim mismatch: {binding}";;\n'
        f'print_endline "NTT_COLD_BINDING {binding}";;'
        for binding, statement in claims) + (
        f'\ncheck_axioms ();;\nprint_endline "NTT_COLD_PASS {name} 3 0";;\n')


def judge(raw, name):
    count, lo, hi = bounds.read_result(raw, name)
    markers = [line for line in raw.splitlines() if line.startswith("NTT_COLD_")]
    if name == "mlkem_intt":
        markers = [line for line in markers if line != "NTT_COLD_REDUCTION_PASS 0"]
    expected = {"NTT_COLD_BINDING " + name.upper() + suffix for suffix in
                ("_CORRECT", "_SUBROUTINE_CORRECT", "_SUBROUTINE_SAFE")}
    expected.add(f"NTT_COLD_PASS {name} 3 0")
    if len(markers) != 4 or set(markers) != expected:
        raise ValueError(f"{name}: missing or duplicate complete-proof markers")
    if re.search(r"(?im)^(?:Fatal error:|Exception:|Error in included file)", raw):
        raise ValueError(f"{name}: proof log contains an error")
    return int(count), int(lo), int(hi)


def comparison(warm_row, lower, upper):
    # results.tsv stores the centered CONGBOUND interval for mlkem_reduce;
    # only the displayed table converts the exact remainder to canonical form.
    same = (lower, upper) == (int(warm_row["lower"]), int(warm_row["upper"]))
    return "PASS (same number)" if same else "PASS (NUMBER CHANGED)"


def judge_reduction(raw):
    lo, hi = bounds.reduction_values(raw)
    markers = re.findall(r"^NTT_REDUCTION_WRAPPED_NODES (\d+)$", raw, re.M)
    if len(markers) != 1 or raw.splitlines().count("NTT_COLD_REDUCTION_PASS 0") != 1:
        raise ValueError("reduction: missing complete calculation markers")
    return int(lo), int(hi), int(markers[0])


def execute(command, cwd, log, timeout, env):
    """Bound and reap the whole subprocess group, including native compilation."""
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=max(0.01, timeout))
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            return 124


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def validate_inputs(root, hol):
    s2n_commit = git(root, "rev-parse", "HEAD")
    hol_commit = git(hol, "rev-parse", "HEAD")
    workflow = (root / ".github/workflows/ci.yml").read_text()
    pins = re.findall(r'HOLLIGHT_COMMIT:\s*"([0-9a-f]{40})"', workflow)
    if pins != [hol_commit]:
        raise ValueError("HOL checkout does not match upstream's workflow pin")
    for checkout in (root, hol):
        subprocess.run(["git", "-C", str(checkout), "diff", "--exit-code", "HEAD"],
                       check=True, capture_output=True)
    inventory = {p.stem for p in (root / "arm/proofs").glob("*.ml")
                 if p.stem.startswith(("mlkem_", "mldsa_")) and
                 "CONGBOUND_RULE" in p.read_text()}
    if inventory != bounds.SPECS.keys():
        raise ValueError(f"upstream CONGBOUND inventory changed: {inventory ^ bounds.SPECS.keys()}")
    if not (hol / "hol_lib.cmxa").exists():
        raise ValueError("build fresh HOL with HOLLIGHT_USE_MODULE=1 make first")
    return s2n_commit, hol_commit


def entry_source(source, name):
    suffix = ""
    if name == "mlkem_intt":
        suffix = ('needs "ntt-bounds/intt_reduction.ml";;\n'
                  'if hyp NTT_INTT_WITHOUT_LATE_BARRETT_BOUNDS <> [] then\n'
                  ' failwith "Cold reduction: hypotheses remain";;\n'
                  'check_axioms ();;\n'
                  'print_endline "NTT_COLD_REDUCTION_PASS 0";;\n')
    return f'needs "ntt-bounds/generated/{name}.ml";;\n' + suffix + probes(source, name)


def reduction_row(raw, receipt):
    lower, upper, nodes = judge_reduction(raw)
    maximum = max(abs(lower), abs(upper))
    verdict = "PASS" if maximum > 26624 else "NUMBER CHANGED (refutation no longer holds)"
    interval = f"[{lower},{upper}]; max {maximum}; spec 26624; {nodes} widened nodes"
    return ("late-v21 reduction", "[-32768,32767]; max 32768 > 26624",
            interval, verdict, str(receipt))


def summarize(rows):
    incomplete = [row for row in rows if row[3].startswith(("FAIL", "NUMBER CHANGED", "NOT STARTED"))]
    print(f"{'FAIL' if incomplete else 'PASS'}: cold replay report covers 14 ARM rows and the reduction; "
          f"{sum(row[3].startswith('PASS') for row in rows)}/15 replayed; "
          f"{sum(row[3].startswith('NOT REPLAYED') for row in rows)} budget exclusions", flush=True)
    return 1 if incomplete else 0


def collect(args):
    """Recheck saved terminal receipts and logs without running a proof."""
    root, hol, receipts = args.checkout.resolve(), args.hol.resolve(), args.run_root.resolve()
    s2n, hol_commit = validate_inputs(root, hol)
    generated = root / "ntt-bounds/generated"
    for file in ("tap.ml", "intt_reduction.ml"):
        if (generated.parent / file).read_bytes() != (bounds.HERE / file).read_bytes():
            raise ValueError(f"cold observer/dependency changed: {file}")
    warm = bounds.results()
    rows = []
    reduction = ("late-v21 reduction", "[-32768,32767]; max 32768 > 26624",
                 "—", "NOT STARTED", "—")
    for name in ORDER:
        receipt = receipts / (name + ".receipt.md")
        raw_path = receipts / (name + ".log")
        cold, verdict = "—", "NOT STARTED"
        if receipt.exists():
            text = receipt.read_text()
            if f"s2n-bignum {s2n}\nHOL Light {hol_commit}\n" not in text:
                raise ValueError(f"{name}: receipt commit mismatch")
            exit_match = re.search(r"; elapsed [0-9.]+ s; exit (-?\d+)\n", text)
            if not exit_match:
                raise ValueError(f"{name}: missing terminal exit status")
            code = int(exit_match[1])
            if code == 124:
                verdict = f"NOT REPLAYED COLD ({args.timeout}s budget)"
            elif code != 0:
                verdict = f"FAIL (exit {code})"
            else:
                source = (root / "arm/proofs" / (name + ".ml")).read_text()
                if (generated / (name + ".ml")).read_text() != instrument(source, name):
                    raise ValueError(f"{name}: instrumented proof changed")
                if (generated / (name + "_cold.ml")).read_text() != entry_source(source, name):
                    raise ValueError(f"{name}: claim probes changed")
                raw = raw_path.read_text()
                try:
                    _, lo, hi = judge(raw, name)
                    cold = f"[{lo},{hi}]"
                    verdict = comparison(warm[name], lo, hi)
                    if name == "mlkem_intt":
                        reduction = reduction_row(raw, receipt)
                except ValueError as error:
                    verdict = f"FAIL ({error})"
            if name == "mlkem_intt" and reduction[3] == "NOT STARTED":
                reduction = (reduction[0], reduction[1], "—",
                             "NOT REPLAYED COLD (inverse replay incomplete)" if code == 124
                             else "FAIL (inverse replay incomplete)", str(receipt))
            # Preserve original commands and raw exit status; correct only the
            # summary line after independently judging the terminal transcript.
            first, rest = text.split("\n", 1)
            elapsed = first[first.index("; elapsed "):]
            if name == "mlkem_intt":
                rest = re.sub(r"(?m)^Reduction:.*\n?", "", rest)
                rest += f"\nReduction: {reduction[3]}; {reduction[2]}\n"
            receipt.write_text(f"{verdict}: {name}; cold {cold}{elapsed}\n" + rest)
        rows.append((name, f"[{warm[name]['lower']},{warm[name]['upper']}]",
                     cold, verdict, str(receipt) if receipt.exists() else "—"))
        print(f"{verdict}: {name} {cold}", flush=True)
    rows.append(reduction)
    report(args.report, rows, s2n, hol_commit, args.timeout, root, hol, receipts)
    return summarize(rows)


def report(path, rows, s2n, hol, timeout, root, holdir, receipt_root):
    header = f"""# Cold replay of the #328 claims

Upstream s2n-bignum: `{s2n}` (fresh main checkout).
Warm reference: `{bounds.PIN}`.
HOL Light: `{hol}` (the upstream workflow's HOLLIGHT_COMMIT).
System toolchain: OCaml 5.4.0, Camlp5 8.04.00; HOL built from source with
`HOLLIGHT_USE_MODULE=1 make`. No Hearth, CRIU images or warm shelves are used.
The native builder is upstream's `tools/build-proof.sh`; every binary starts
with the freshly compiled HOL kernel and loads its ARM dependencies from source.
The observer preserves upstream proof statements and tactics. All three final
correctness/safety claims must match their source quotations with empty
hypotheses, and HOL's `check_axioms()` must accept only its three core axioms.
Each row has a {timeout}-second budget including native compilation and execution.
Timeouts are explicitly NOT REPLAYED COLD and do not block later rows.

Fresh source roots: `{root}`, `{holdir}`.
Build receipts: lane units `ntt-bounds-cold-clone`, `ntt-bounds-cold-hol-clone`,
`ntt-bounds-cold-hol-build` under `/home/bluestar/lanes/status/units/`.
Checkout HOL with `git checkout {hol}` before the fresh build.

Batch command:

```sh
~/lanes/bin/lane-run --wait ntt-bounds-cold-claims ntt-bounds/.venv/bin/python ntt-bounds/cold_replay.py --checkout {root} --hol {holdir} --run-root {receipt_root} --report ntt-bounds/COLD-REPLAY.md --timeout {timeout}
```

Intervals are inclusive. The reducer's cold CONGBOUND interval is centered;
its complete exact-remainder theorem implies the canonical [0,3328] result
in COMMENT.md. Warm values are those already published in the draft.
See the [source comparison](README.md) for the inspected changes between the warm
pin and upstream. Both measured intervals are listed below.

| Claim | Warm interval | Cold interval | Verdict | Receipt |
|---|---|---|---|---|
"""
    body = "".join(f"| {name} | {warm} | {cold} | {verdict} | [{name}]({receipt}) |\n"
                   for name, warm, cold, verdict, receipt in rows)
    path.write_text(header + body + "\nThe reduction calculation tests the existing interval argument with fresh graph\nequations as implication premises; it does not establish an attainable counterexample\nor a modified machine-code proof. x86 was NOT RUN. COMMENT.md changes only if a\nreported number changes. Individual receipts record commands, commits and log paths.\n")


def replay(args):
    root, hol = args.checkout.resolve(), args.hol.resolve()
    receipts = args.run_root.resolve()
    if receipts.exists():
        raise ValueError("run-root already exists; inspect that attempt rather than restarting it")
    s2n, hol_commit = validate_inputs(root, hol)
    receipts.mkdir(parents=True)
    generated = root / "ntt-bounds/generated"
    generated.mkdir(parents=True)
    for file in ("tap.ml", "intt_reduction.ml"):
        shutil.copyfile(bounds.HERE / file, generated.parent / file)
    env = dict(os.environ, TMPDIR=str(receipts), HOLLIGHT_DIR=str(hol))
    # No inherited warm-runtime configuration is needed by the native route.
    for key in list(env):
        if key.startswith(("HOL_WORKBENCH_", "HEARTH_")):
            del env[key]
    warm = bounds.results()
    rows = []
    pending = [(name, f"[{warm[name]['lower']},{warm[name]['upper']}]", "—",
                "NOT STARTED", "—") for name in ORDER]
    pending.append(("late-v21 reduction", "[-32768,32767]; max 32768 > 26624",
                    "—", "NOT STARTED", "—"))
    report(args.report, pending, s2n, hol_commit, args.timeout, root, hol, receipts)
    for name in ORDER:
        source = (root / "arm/proofs" / (name + ".ml")).read_text()
        full = instrument(source, name)
        # Run the inverse row and its graph refutation in one fresh process.
        # The unchanged reduction leaf needs this exact instrumented source.
        (generated / (name + ".ml")).write_text(full)
        entry = generated / (name + "_cold.ml")
        entry.write_text(entry_source(source, name))
        binary = receipts / (name + ".native")
        # build-proof.sh prefixes both paths with arm/, so use relative paths.
        build = ["../tools/build-proof.sh", os.path.relpath(entry, root / "arm"),
                 str(hol / "hol.sh"), os.path.relpath(binary, root / "arm")]
        obj = ("mlkem" if name.startswith("mlkem_") else "mldsa") + "/" + name + ".o"
        assemble = ["make", obj]
        build_log, raw_log = receipts / (name + ".build.log"), receipts / (name + ".log")
        start = time.monotonic()
        code = execute(assemble, root / "arm", receipts / (name + ".assemble.log"), args.timeout, env)
        if code == 0:
            code = execute(build, root / "arm", build_log, args.timeout - (time.monotonic() - start), env)
        if code == 0:
            code = execute([str(binary)], root, raw_log, args.timeout - (time.monotonic() - start), env)
        verdict = "NOT REPLAYED COLD (3 h budget)" if code == 124 else f"FAIL (exit {code})"
        cold = "—"
        reduction = None
        if code == 0:
            try:
                raw = raw_log.read_text()
                _, lo, hi = judge(raw, name)
                cold = f"[{lo},{hi}]"
                verdict = comparison(warm[name], lo, hi)
                if name == "mlkem_intt":
                    rlo, rhi, nodes = judge_reduction(raw)
                    reduction = (rlo, rhi, nodes)
            except ValueError as error:
                verdict = f"FAIL ({error})"
        elapsed = time.monotonic() - start
        receipt = receipts / (name + ".receipt.md")
        receipt.write_text(f"{verdict}: {name}; cold {cold}; elapsed {elapsed:.1f} s; exit {code}\n\n"
                           f"s2n-bignum {s2n}\nHOL Light {hol_commit}\n\n"
                           f"cwd {root / 'arm'}\n{shlex.join(assemble)}\n{shlex.join(build)}\n"
                           f"cwd {root}\n{shlex.join([str(binary)])}\n\n"
                           f"Build log: {build_log}\nProof log: {raw_log}\n"
                           "PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.\n")
        row = (name, f"[{warm[name]['lower']},{warm[name]['upper']}]", cold, verdict, str(receipt))
        rows.append(row)
        pending = [row if old[0] == name else old for old in pending]
        print(f"{verdict}: {name} {cold}; {elapsed:.1f}s; {receipt}", flush=True)
        if name == "mlkem_intt":
            rv = "NOT REPLAYED COLD (inverse replay incomplete)"
            rc = "—"
            if reduction:
                rlo, rhi, nodes = reduction
                maximum = max(abs(rlo), abs(rhi))
                rv = "PASS" if maximum > 26624 else "NUMBER CHANGED (refutation no longer holds)"
                rc = f"[{rlo},{rhi}]; max {maximum} > 26624; {nodes} widened nodes"
                receipt.write_text(receipt.read_text() + f"\nReduction: {rv}; {rc}\n")
            pending[-1] = ("late-v21 reduction", pending[-1][1], rc, rv, str(receipt))
            print(f"{rv}: late-v21 reduction {rc}", flush=True)
        report(args.report, pending, s2n, hol_commit, args.timeout, root, hol, receipts)
    return summarize(pending)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--hol", type=Path, required=True)
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=bounds.HERE / "COLD-REPLAY.md")
    parser.add_argument("--timeout", type=int, default=10800)
    parser.add_argument("--collect-only", action="store_true",
                        help="recheck saved terminal receipts; do not compile or run proofs")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    try:
        return collect(args) if args.collect_only else replay(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL: cold replay: {error}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
