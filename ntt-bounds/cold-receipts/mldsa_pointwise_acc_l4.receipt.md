PASS (same number): mldsa_pointwise_acc_l4; cold [-4778882,4778882]; elapsed 2103.7 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mldsa/mldsa_pointwise_acc_l4.o
../tools/build-proof.sh ../ntt-bounds/generated/mldsa_pointwise_acc_l4_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mldsa_pointwise_acc_l4.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise_acc_l4.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise_acc_l4.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_pointwise_acc_l4.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.
