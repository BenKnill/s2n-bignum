PASS (same number): mlkem_basemul_k2; cold [-9857,9857]; elapsed 713.3 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mlkem/mlkem_basemul_k2.o
../tools/build-proof.sh ../ntt-bounds/generated/mlkem_basemul_k2_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mlkem_basemul_k2.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_basemul_k2.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_basemul_k2.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_basemul_k2.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.
