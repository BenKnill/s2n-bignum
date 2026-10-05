Draft: five ARM results and the reduction calculation are pending.

At `fce78c7`, I instrumented CONGBOUND's output and require each complete ARM proof
to pass with zero new axioms. These are interval bounds, not attainable extrema.
`make -C ntt-bounds table` checks coverage and prints the full table.

Here q=3329 for ML-KEM and q=8380417 for ML-DSA. Entries are absolute upper
bounds unless shown as intervals. S=[−32768,32767]=[−9.8432q,9.8429q] denotes
the signed-16-bit type. Decimal ratios are rounded. Original memory and cache
relationships still apply.

| Function | Input | Spec | Derived |
|---|---|---|---|
| mlkem_basemul_k2 | x:4096(1.2304q);y,y′:S | S | 9857(2.9609q) |
| mlkem_basemul_k3 | x:4096(1.2304q);y,y′:S | S | 13953(4.1913q) |
| mlkem_basemul_k4 | x:4096(1.2304q);y,y′:S | S | 18049(5.4217q) |
| mlkem_intt | S | 26624(7.9976q) | 26624(7.9976q) |
| mlkem_mulcache_compute | S | 3328(0.9997q) | 3292(0.9889q) |
| mlkem_ntt | 8191(2.4605q) | 23594(7.0874q) | 23594(7.0874q) |
| mlkem_reduce | S | [0,3328](0.9997q) | [0,3328](0.9997q) |
| mlkem_tomont | S | 3328(0.9997q) | 2653(0.7969q) |
| mldsa_intt | q−1 | q−1 | PENDING |
| mldsa_ntt | q−1 | 9q−1 | PENDING |
| mldsa_pointwise | x,y:9q−1 | q−1 | 5514723(0.6580q) |
| mldsa_pointwise_acc_l4 | x:q−1;y:9q−1 | q−1 | PENDING |
| mldsa_pointwise_acc_l5 | x:q−1;y:9q−1 | q−1 | PENDING |
| mldsa_pointwise_acc_l7 | x:q−1;y:9q−1 | q−1 | PENDING |

The reducer's observed centered intermediate is [−1664,1664]; its exact-remainder
postcondition gives the canonical result above.

Reduction result: PENDING for removing the ARM inverse-NTT's late v21 Barrett
reductions (64 scalar occurrences).

x86 was not run; #321 reports 14939. Its inverse-NTT contract is <8q, versus
ARM's ≤8q−8. At upstream `4d1356a7`, unchanged contracts and numeric rules suggest
the same intervals; this is source comparison, not an upstream replay.
