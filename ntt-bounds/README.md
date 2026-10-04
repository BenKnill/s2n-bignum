# ML-KEM / ML-DSA bound extraction

This directory addresses [s2n-bignum #328](https://github.com/awslabs/s2n-bignum/issues/328)
using the rule-observation method in [PR #321](https://github.com/awslabs/s2n-bignum/pull/321).
The analysis revision is `fce78c7c17baee6a60511efe821930d4d049a6c0`, matching the
Hearth `s2n-arm-mlkem` profile. All 14 ARM proofs that call the CONGBOUND family
are covered, including the three base multiplications whose specs only state
congruence and the reducer whose exact remainder result implies canonical bounds.

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
Hearth. `FUNCTIONS='mlkem_tomont mlkem_reduce'` selects a subset. Already
accepted, unchanged rows are reused. Keep the Hearth run directories: each row
records its receipt. On bluestar26, run long commands through
`~/lanes/bin/lane-run`; the K-backed native Linux filesystem is appropriate
for runs and proof caches. No GitHub CI is needed.

`tap.ml` shadows the public rule entrypoints after loading the real machinery.
It records the exact lower/upper constants of the theorem that each proof feeds
to its CONGBOUND split, then returns that same theorem. The original statements,
tactics, recursive rule implementation, and local-bound propagation are intact.
The original complete proof must pass with zero new axioms before a row is saved.
The expected number of output calls is checked; a malformed theorem or changed
source is an error. Unit checks cover source preservation and malformed/incomplete
result rejection. These are interval bounds, not claims of attainable extrema.

For `mlkem_reduce`, CONGBOUND supplies the centered intermediate; the proof then
conditionally adds q to obtain its exact `x rem q` result. The table reports
the resulting canonical range and labels the observed intermediate explicitly.
For other rows, CONGBOUND acts on the final output word.
The input column lists coefficient bounds; memory separation, alignment, table
constants and functional cache relationships remain as in the linked source specs.

Upstream main inspected on 2026-10-04 is `4d1356a7470663c752660a59375dc3a9ef548428`.
The four ARM NTT files change only the final congruence tactic (to
`INT_LINEAR_CONG_TAC`) and its import. The other ten target proofs are unchanged.
The shared machinery factors recursion into `ASM_CONGBOUND_STEP` and adds a
memoized variant, and factors the SIMD simplification helper without changing its
ARM body; the numeric reduction lemmas are unchanged. Later ARM polynomial
proofs do not call CONGBOUND. The table is measured at the pin; applicability to
upstream will be assessed against these source changes, not claimed as an upstream
replay. x86 is explicitly not run until a suitable profile is available.

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
does not introduce an axiom: changed local equations are explicit hypotheses.
Its result must be interpreted as a bound-propagation test, not an unchanged-spec
machine proof or an attainable counterexample. At present this leaf is unvalidated.
`make -C ntt-bounds analyze-reduction HEARTH=/path/to/hearth RUN_ROOT=/path/to/runs`
runs that leaf over the inverse-NTT basis. `make -C ntt-bounds reduction` reads its
accepted receipt and prints the refutation row; a bound that fits the spec fails
this refutation gate and requires the assembly proof and M5 timing route instead.

For durable lane execution, the inverse-NTT basis can be prepared directly with
`lane-run UNIT /path/to/hearth prove ntt-bounds/generated/mlkem_intt_result.ml
--basis ntt-bounds/generated/mlkem_intt.ml --basis-cache-root /path/to/runs
--profile s2n-arm-mlkem --timeout 7200 --run-root /path/to/runs/mlkem_intt`.
After it passes, `bounds.py collect mlkem_intt --hearth /path/to/hearth
--run-root /path/to/runs` imports its accepted result. Use the same basis/cache
for `intt_reduction.ml`, then retire this lane's basis with `hearth basis retire
--all --cache-root /path/to/runs`. Do not replay an unchanged completed proof
just to regenerate a status report.
