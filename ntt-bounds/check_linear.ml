(* Compatibility checks for the unchanged upstream congruence tactic.
   These are auxiliary checks, not NTT function proofs or bound results. *)
needs "ntt-bounds/upstream_int_linear.ml";;

let NTT_BOUNDS_LINEAR_MLKEM = prove
 (`!x y z:int.
     (&17 * x - &3328 * y + &6659 * z == &17 * x + y + z) (mod &3329)`,
  REPEAT GEN_TAC THEN INT_LINEAR_CONG_TAC);;

let NTT_BOUNDS_LINEAR_MLDSA = prove
 (`!x y z:int.
     (x + &8380418 * y - &16760833 * z == x + y + z) (mod &8380417)`,
  REPEAT GEN_TAC THEN INT_LINEAR_CONG_TAC);;
