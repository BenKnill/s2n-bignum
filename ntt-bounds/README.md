# ML-KEM / ML-DSA bound extraction

For the separate cold check on fresh upstream main, clone upstream and HOL Light
into a new directory, check out the HOL commit in upstream's
`.github/workflows/ci.yml`, and run `HOLLIGHT_USE_MODULE=1 make` in that fresh HOL
checkout through `lane-run --wait`. Then, from this repository root:

```sh
~/lanes/bin/lane-run --wait ntt-bounds-cold-claims ntt-bounds/.venv/bin/python ntt-bounds/cold_replay.py --checkout /path/to/fresh/s2n-bignum --hol /path/to/fresh/hol-light --run-root /path/to/new/receipts --report ntt-bounds/COLD-REPLAY.md --timeout 10800
```

The command uses upstream's native proof builder, preserves main's statements
and tactics, and runs every row in a fresh process without Hearth or warm shelves.
It checks all three final source quotations, empty hypotheses, the standard HOL
axioms and the observer's complete result. The inverse-NTT process also performs
the existing reduction calculation. Each row has a three-hour budget including
compilation; a timeout is reported as NOT REPLAYED COLD and later rows continue.
Receipts contain commands, both commits and log paths. COLD-REPLAY.md updates
after each row, preserving the warm table; COMMENT.md changes only if a reported
number changes. An existing receipt directory is refused to prevent accidental
restarts. The command's tests are included in `make -C ntt-bounds test`.
After the batch ends, add `--collect-only` to the same Python command to recheck
the saved terminal receipts and refresh the report without compiling or replaying
any proof. This also checks the current upstream sources and claim probes against
the instrumented files retained with the receipts.

This directory addresses [s2n-bignum #328](https://github.com/awslabs/s2n-bignum/issues/328)
using the rule-observation method in [PR #321](https://github.com/awslabs/s2n-bignum/pull/321).
The analysis revision is `fce78c7c17baee6a60511efe821930d4d049a6c0`, matching the
Hearth `s2n-arm-mlkem` profile. All 14 ARM proofs that call the CONGBOUND family
are covered, including the three base multiplications whose specs only state
congruence and the reducer whose exact remainder result implies canonical bounds.

`PR.patch` is the review copy of this directory's changes against the analysis
revision. It includes the complete ARM table and the reduction refutation.
Refresh the patch after changing this directory. From the repository root:

```sh
git diff --binary fce78c7c17baee6a60511efe821930d4d049a6c0 -- ntt-bounds ':!ntt-bounds/PR.patch' > ntt-bounds/PR.patch
git apply --reverse --check ntt-bounds/PR.patch
```

The second command checks that the exported patch matches the current files.
Apply it to a checkout of the analysis revision with `git apply /path/to/PR.patch`.

From the repository root, prepare a Python environment (standard library only):

```sh
uv venv --python 3.13.2 ntt-bounds/.venv
make -C ntt-bounds test
make -C ntt-bounds table
```

`table` prints saved, source-checked extraction results. It fails on missing or
stale rows. To reproduce the results, configure an existing Hearth runtime with
the matching profile, then run:

```sh
export HOL_WORKBENCH_RUNTIME_CONFIG=/path/to/runtime.toml
make -C ntt-bounds replay HEARTH=/path/to/hearth RUN_ROOT=/path/to/runs
```

This compiles the real ARM objects using the repository Makefile, generates
instrumented copies in `generated/`, and checks each complete proof through
Hearth. `FUNCTIONS='mlkem_tomont mlkem_reduce'` selects a subset for `replay` or
`generate`. Accepted, unchanged rows are reused. Keep the Hearth run directories: each row
records its receipt. On bluestar26, run long commands through
`~/lanes/bin/lane-run --wait`, or use `~/lanes/bin/lane-wait UNIT` for an existing
job; the K-backed native Linux filesystem is appropriate
for runs and proof caches. No GitHub CI is needed.

`tap.ml` shadows the public rule entrypoints after loading the real machinery.
It records the exact lower/upper constants of the theorem that each proof feeds
to its CONGBOUND split, then returns that same theorem. The original statements,
recursive rule implementation, and local-bound propagation are intact. Default
mode also preserves every original tactic; the optional linear mode below
changes only the four NTT congruence finishing branches.
The original complete proof must pass with zero new axioms before a row is saved.
The expected number of output calls is checked; a malformed theorem or changed
source is an error. Unit checks cover source preservation and malformed/incomplete
result rejection. These are interval bounds, not claims of attainable extrema.

The l7 accumulation replay exceeded a 7200-second budget during core simulation.
`SPLIT_SAFETY=1` separates that function at its existing constant-time import:
the correctness and subroutine theorems form a checked basis, and the unchanged
safety theorem and result marker form a leaf. Concatenating the two source pieces
recovers the complete instrumented proof, with every statement and tactic intact.
For example:

```sh
make -C ntt-bounds replay SPLIT_SAFETY=1 TIMEOUT=14400 FUNCTIONS=mldsa_pointwise_acc_l7 HEARTH=/path/to/hearth RUN_ROOT=/path/to/runs
```

`TIMEOUT` bounds each phase independently. The collector requires both correctness
bindings and the safety binding to pass with zero new axioms, checks the exact
basis bytes, and keeps the original full-proof fingerprint. Hearth's shared
runtime manages basis caching and idle retirement. Other functions retain their
existing layout; accepted rows are reused.
`generate SPLIT_SAFETY=1 FUNCTIONS=mldsa_pointwise_acc_l7`
also prepares the two files for a direct Hearth invocation. The complete l7
replay passed: two correctness bindings in 10019.5 seconds, then the safety
binding in 440.0 seconds, each with zero new axioms, matched source conclusions
and empty hypotheses. The collector accepted 256 output observations with
interval [-5220386,5220386], and the basis was retired. Local source-preservation
and rejection tests also pass.

For `mlkem_reduce`, CONGBOUND supplies the centered intermediate; the proof then
conditionally adds q to obtain its exact `x rem q` result. The table reports
the resulting canonical range and labels the observed intermediate explicitly.
For other rows, CONGBOUND acts on the final output word.
The input column lists coefficient bounds; memory separation, alignment, table
constants and functional cache relationships remain as in the linked source specs.

Upstream main inspected on 2026-10-04 is `4d1356a7470663c752660a59375dc3a9ef548428`.
The four ARM NTT files change only the final congruence tactic (to
`INT_LINEAR_CONG_TAC`) and its import. The other ten target proofs are unchanged.
[The tactic change](https://github.com/awslabs/s2n-bignum/commit/f6c3644561e1cb1a594fef5d0dec35e4d7551081)
avoids converting each expanded coefficient expression through real arithmetic;
the range branches and theorem statements remain unchanged. This extraction
uses the original pinned congruence tactic by default.
The shared machinery factors recursion into `ASM_CONGBOUND_STEP` and adds a
memoized variant, and factors the SIMD simplification helper without changing its
ARM body; the numeric reduction lemmas are unchanged. Later ARM polynomial
proofs do not call CONGBOUND. These changes preserve the bound expressions and
numeric rules used by the 14 target proofs, so the same intervals are expected
at that upstream revision. This expectation is an inference from source comparison;
the warm table is measured at the pin. [COLD-REPLAY.md](COLD-REPLAY.md) separately
reports the fresh upstream replay, both intervals and the exact completed coverage.
x86 is explicitly not run until a suitable profile is available.

`upstream_int_linear.ml` is an unmodified copy of `common/int_linear.ml` at
`f6c3644561e1cb1a594fef5d0dec35e4d7551081`. Enable this alternative finishing
tactic with `make -C ntt-bounds replay LINEAR=1 HEARTH=/path/to/hearth
RUN_ROOT=/path/to/runs`. `generate LINEAR=1 FUNCTIONS=mlkem_intt` prepares just the
inverse-NTT variant for direct Hearth commands. This applies upstream's exact
congruence-finisher replacement
to the four NTT proofs, keeping the pinned statements and range branches.
The collector verifies the helper hash for this mode, including the inverse-NTT
basis dependency. Accepted rows from either mode are reused without regenerating
their proofs; the table reports how many NTT rows use each tactic. The original
and linear variants have distinct fingerprints.
`make -C ntt-bounds check-linear HEARTH=/path/to/hearth RUN_ROOT=/path/to/runs`
checks its compatibility on two simple congruences, for q=3329 and q=8380417,
using the light profile (2/2 bindings, zero new axioms in the local check).
These auxiliary checks do not establish NTT correctness
or any output bound; a complete function replay remains required.

The inverse-NTT contracts differ: ARM requires `abs(z) <= 26624` (`8q-8`),
whereas x86 requires `abs(z) <= 26631` (equivalently `<26632`, or `<8q`). Both permit arbitrary signed
16-bit inputs. The table preserves those distinct contracts; an ARM result
does not establish the x86 bound or removal question.

The reduction investigation starts with the x86 difference raised in #321.
The [pq-crystals AVX2 inverse NTT](https://github.com/pq-crystals/kyber/blob/main/avx2/invntt.S)
reduces after levels 2 and 4. This revision of s2n-bignum also reduces after
levels 3 and 5: `ymm10` at assembly lines 254–257 / 542–545, and `ymm7` at
330–333 / 618–621. This source comparison identifies extra reductions; it is
not an x86 proof or a claim that the ARM implementation uses the same algorithm.

The ARM candidate is the late `v21` reduction at lines 193/203/211 in the
loop, with the tail at 239/242/245. It reduces a sum of two `barmul` results.
`intt_reduction.ml` will evaluate the changed expression graph over the completed
inverse-NTT basis, requiring exactly 64 matching coefficient occurrences. It
selects the final eight terms of each chronological group of 24 standalone
reductions: Q29, Q9, then Q21. Earlier shuffled lanes can share the same operand
shape, so a shape-only selector would include extra reductions. The two scratch
registers in the loop (Q19/Q16) and the tail scratch register Q20 are overwritten
before their next unrelated uses. There are seven loop blocks and one tail block;
the candidate removes six static instructions and 24 dynamic instruction executions.
The leaf also checks the selected terms' operand shape. It introduces no axiom:
changed local equations are discharged into explicit implication premises.
Its result must be interpreted as a bound-propagation test, not an unchanged-spec
machine proof or an attainable counterexample.
Addition and subtraction use the original CONGBOUND lemmas while their signed-word
side conditions hold. If the kernel reduces such a condition to false, the leaf
uses CONGBOUND_ATOM's signed-word interval at that node and continues. It reports
the number of these broadened nodes. This preserves valid interval theorems through
possible wraparound; it does not preserve the original polynomial congruence there.
The local Hearth calculation passed in 45.9 seconds with zero new axioms. Four
side conditions became false; the resulting output interval is [-32768,32767],
with maximum absolute bound 32768 (9.843196q), exceeding the unchanged 26624
(7.997597q) specification. This rejects the current interval argument for the
removal, without asserting an attainable counterexample or a machine-code proof.
`make -C ntt-bounds analyze-reduction HEARTH=/path/to/hearth RUN_ROOT=/path/to/runs`
runs that leaf over the inverse-NTT basis. `make -C ntt-bounds reduction` reads its
accepted receipt and prints the refutation row; a bound that fits the spec fails
this refutation gate and requires the assembly proof and M5 timing route instead.

For durable lane execution, the inverse-NTT basis can be prepared directly with
`lane-run --wait UNIT /path/to/hearth prove ntt-bounds/generated/mlkem_intt_result.ml
--basis ntt-bounds/generated/mlkem_intt.ml
--profile s2n-arm-mlkem --timeout 7200 --run-root /path/to/runs/mlkem_intt`.
After it passes, `bounds.py collect mlkem_intt --hearth /path/to/hearth
--run-root /path/to/runs` imports its accepted result. Use the same basis
for `intt_reduction.ml`; the shared runtime handles cache reuse and idle retirement.
Do not replay an unchanged completed proof
just to regenerate a status report.
