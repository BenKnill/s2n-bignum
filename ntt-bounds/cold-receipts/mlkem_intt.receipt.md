PASS (same number): mlkem_intt; cold [-26624,26624]; elapsed 1723.0 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mlkem/mlkem_intt.o
../tools/build-proof.sh ../ntt-bounds/generated/mlkem_intt_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mlkem_intt.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_intt.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_intt.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_intt.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.








Reduction: PASS; [-32768,32767]; max 32768; spec 26624; 4 widened nodes
