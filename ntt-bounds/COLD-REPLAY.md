# Cold replay of the #328 claims

Upstream s2n-bignum: `4d1356a7470663c752660a59375dc3a9ef548428` (fresh main checkout).
HOL Light: `b19af6934759eed622d7aca25092367f81656eee` (the upstream workflow's HOLLIGHT_COMMIT).
System toolchain: OCaml 5.4.0, Camlp5 8.04.00; HOL built from source with
`HOLLIGHT_USE_MODULE=1 make`. No Hearth, CRIU images or warm shelves are used.
The native builder is upstream's `tools/build-proof.sh`; every binary starts
with the freshly compiled HOL kernel and loads its ARM dependencies from source.
The observer preserves upstream proof statements and tactics. All three final
correctness/safety claims must match their source quotations with empty
hypotheses, and HOL's `check_axioms()` must accept only its three core axioms.
Each row has a 10800-second budget including native compilation and execution.
Timeouts are explicitly NOT REPLAYED COLD and do not block later rows.

Fresh source roots: `/home/bluestar/lanes/ntt-bounds/cold/s2n-bignum`, `/home/bluestar/lanes/ntt-bounds/cold/hol-light`.
Build receipts: lane units `ntt-bounds-cold-clone`, `ntt-bounds-cold-hol-clone`,
`ntt-bounds-cold-hol-build` under `/home/bluestar/lanes/status/units/`.
Checkout HOL with `git checkout b19af6934759eed622d7aca25092367f81656eee` before the fresh build.

Batch command:

```sh
~/lanes/bin/lane-run --wait ntt-bounds-cold-claims ntt-bounds/.venv/bin/python ntt-bounds/cold_replay.py --checkout /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum --hol /home/bluestar/lanes/ntt-bounds/cold/hol-light --run-root /home/bluestar/lanes/ntt-bounds/cold/receipts --report ntt-bounds/COLD-REPLAY.md --timeout 10800
```

Intervals are inclusive. The reducer's cold CONGBOUND interval is centered;
its complete exact-remainder theorem implies the canonical [0,3328] result
in COMMENT.md. Warm values are those already published in the draft.

| Claim | Warm interval | Cold interval | Verdict | Receipt |
|---|---|---|---|---|
| mlkem_tomont | [-2653,2653] | [-2653,2653] | PASS (same number) | [mlkem_tomont](/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_tomont.receipt.md) |
| mlkem_reduce | [-1664,1664] | [-1664,1664] | PASS (same number) | [mlkem_reduce](/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_reduce.receipt.md) |
| mlkem_mulcache_compute | [-3292,3292] | [-3292,3292] | PASS (same number) | [mlkem_mulcache_compute](/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_mulcache_compute.receipt.md) |
| mldsa_pointwise | [-5514723,5514723] | — | NOT STARTED | [mldsa_pointwise](—) |
| mlkem_basemul_k2 | [-9857,9857] | — | NOT STARTED | [mlkem_basemul_k2](—) |
| mlkem_basemul_k3 | [-13953,13953] | — | NOT STARTED | [mlkem_basemul_k3](—) |
| mlkem_basemul_k4 | [-18049,18049] | — | NOT STARTED | [mlkem_basemul_k4](—) |
| mlkem_intt | [-26624,26624] | — | NOT STARTED | [mlkem_intt](—) |
| mlkem_ntt | [-23594,23594] | — | NOT STARTED | [mlkem_ntt](—) |
| mldsa_pointwise_acc_l4 | [-4778882,4778882] | — | NOT STARTED | [mldsa_pointwise_acc_l4](—) |
| mldsa_pointwise_acc_l5 | [-4926050,4926050] | — | NOT STARTED | [mldsa_pointwise_acc_l5](—) |
| mldsa_ntt | [-42163872,42163872] | — | NOT STARTED | [mldsa_ntt](—) |
| mldsa_pointwise_acc_l7 | [-5220386,5220386] | — | NOT STARTED | [mldsa_pointwise_acc_l7](—) |
| mldsa_intt | [-6390410,6390410] | — | NOT STARTED | [mldsa_intt](—) |
| late-v21 reduction | [-32768,32767]; max 32768 > 26624 | — | NOT STARTED | [late-v21 reduction](—) |

The reduction calculation tests the existing interval argument with fresh graph
equations as implication premises; it does not establish an attainable counterexample
or a modified machine-code proof. x86 was NOT RUN. COMMENT.md changes only if a
reported number changes. Individual receipts record commands, commits and log paths.
