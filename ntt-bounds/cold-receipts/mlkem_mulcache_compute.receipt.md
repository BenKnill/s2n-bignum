PASS (same number): mlkem_mulcache_compute; cold [-3292,3292]; elapsed 378.7 s; exit 0

s2n-bignum 4d1356a7470663c752660a59375dc3a9ef548428
HOL Light b19af6934759eed622d7aca25092367f81656eee

cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum/arm
make mlkem/mlkem_mulcache_compute.o
../tools/build-proof.sh ../ntt-bounds/generated/mlkem_mulcache_compute_cold.ml /home/bluestar/lanes/ntt-bounds/cold/hol-light/hol.sh ../../receipts/mlkem_mulcache_compute.native
cwd /home/bluestar/lanes/ntt-bounds/cold/s2n-bignum
/home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_mulcache_compute.native

Build log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_mulcache_compute.build.log
Proof log: /home/bluestar/lanes/ntt-bounds/cold/receipts/mlkem_mulcache_compute.log
PASS requires all three source statements, empty hypotheses, check_axioms(), and a unique complete bound marker.
