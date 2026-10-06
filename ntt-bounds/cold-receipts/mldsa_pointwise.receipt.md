PASS (same number): mldsa_pointwise; cold [-5514723,5514723]; elapsed 831.0 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mldsa/mldsa_pointwise.o
../tools/build-proof.sh ../ntt-bounds/generated/mldsa_pointwise_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mldsa_pointwise.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.
