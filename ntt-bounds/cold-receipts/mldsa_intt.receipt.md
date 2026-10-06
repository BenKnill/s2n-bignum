PASS (same number): mldsa_intt; cold [-6390410,6390410]; elapsed 5888.2 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mldsa/mldsa_intt.o
../tools/build-proof.sh ../ntt-bounds/generated/mldsa_intt_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mldsa_intt.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_intt.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_intt.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mldsa_intt.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.
