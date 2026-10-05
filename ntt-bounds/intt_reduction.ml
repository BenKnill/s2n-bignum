(* A conditional CONGBOUND calculation for removing the late v21 Barrett
   reductions in arm/mlkem/mlkem_intt.S. This is an interval-method test,
   not an assertion that a modified machine function has been proved.
   Run over the completed instrumented inverse-NTT basis. *)
needs "ntt-bounds/generated/mlkem_intt.ml";;

let ntt_intt_asms =
  match !ntt_bounds_local_inputs with
  | [asms] -> asms
  | _ -> failwith "NTT reduction: expected one local-definition graph";;

let ntt_intt_definitions =
  map (fun th -> let b,v = dest_eq(concl th) in (v,b)) ntt_intt_asms;;

let ntt_intt_is_barmul_var v =
  try let head,_ = strip_comb (assoc v ntt_intt_definitions) in
      fst(dest_const head) = "barmul"
  with Failure _ -> false;;

let ntt_intt_is_barmul_sum bod =
  match bod with
  | Comb(Const("barred",_),Comb(Comb(Const("word_add",_),a),b)) ->
      ntt_intt_is_barmul_var a && ntt_intt_is_barmul_var b
  | _ -> false;;

let ntt_intt_removed =
  let barred_asms = filter
    (fun th -> match lhand(concl th) with
               | Comb(Const("barred",_),_) -> true | _ -> false)
    ntt_intt_asms in
  if length barred_asms <> 192 then
    failwith ("NTT reduction: expected 192 chronological Barrett terms, got " ^
              string_of_int(length barred_asms));
  (* The proof passes LOCAL_CONGBOUND_RULE its definitions oldest first.
     Each of eight blocks reduces Q29 (8 lanes), Q9 (8), then Q21 (8).
     Seven blocks use the loop and the eighth uses the tail. Earlier Q29/Q9
     lanes can have the same barmul-sum shape after the SIMD shuffles, so
     expression shape alone does not identify the intended instruction. *)
  map snd (filter (fun (i,_) -> i mod 24 >= 16)
                  (zip (0--191) barred_asms));;

if length ntt_intt_removed <> 64 then
  failwith ("NTT reduction: expected 64 late Barrett terms, got " ^
            string_of_int(length ntt_intt_removed));;

if not (forall (ntt_intt_is_barmul_sum o lhand o concl) ntt_intt_removed) then
  failwith "NTT reduction: late Barrett operand shape changed";;

let ntt_intt_removed_vars = map (rand o concl) ntt_intt_removed;;

(* The original addition/subtraction rule requires that its interval fit in
   signed 16 bits. Removing a reduction can invalidate that condition. Check
   the condition in the kernel; at a false condition use CONGBOUND_ATOM's
   valid signed-word interval, then continue propagating bounds. *)
let ntt_intt_wrapped_nodes = ref [];;

let rec ntt_intt_rule lfn tm =
  try apply lfn tm with Failure _ ->
  let checked_arithmetic th =
    let side = DIMINDEX_INT_REDUCE_CONV(lhand(concl th)) in
    if aconv (rand(concl side)) `T` then
      CONCL_BOUNDS_RULE(MP th (EQT_ELIM side))
    else if aconv (rand(concl side)) `F` then
      (ntt_intt_wrapped_nodes := (tm,side) :: !ntt_intt_wrapped_nodes;
       CONCL_BOUNDS_RULE(ISPEC tm CONGBOUND_ATOM))
    else failwith "NTT reduction: undecided signed-word arithmetic condition" in
  match tm with
  | Comb(Comb(Const("word_add",_),a),b) ->
      checked_arithmetic (MATCH_MP CONGBOUND_WORD_ADD
        (UNIFY_INTCONG_RULE (ntt_intt_rule lfn a) (ntt_intt_rule lfn b)))
  | Comb(Comb(Const("word_sub",_),a),b) ->
      checked_arithmetic (MATCH_MP CONGBOUND_WORD_SUB
        (UNIFY_INTCONG_RULE (ntt_intt_rule lfn a) (ntt_intt_rule lfn b)))
  | _ ->
      (* Let the original rule handle all other operations, with recursive
         children routed through the checked arithmetic above. *)
      let children = match tm with
        | Comb(Const("word_sx",_),t) -> [t]
        | _ -> filter (fun t -> type_of t = type_of tm)
                      (snd(strip_comb tm)) in
      let subfn = itlist (fun t fn -> (t |-> ntt_intt_rule lfn t) fn)
                        children lfn in
      ntt_bounds_original_rule subfn tm;;

let ntt_intt_without_late_barrett =
  itlist (fun th lfn ->
    let bod,var = dest_eq(concl th) in
    (* Treat the whole changed graph as explicit equations. Do not carry
       any simulation hypotheses from the original machine execution. *)
    let newbod = if mem var ntt_intt_removed_vars then rand bod else bod in
    let eq = ASSUME(mk_eq(newbod,var)) in
    let cb = ntt_intt_rule lfn (lhand(concl eq)) in
    (var |-> SUBS[eq] cb) lfn)
    (rev ntt_intt_asms) undefined;;

let ntt_intt_alternative_bounds =
  map (ntt_intt_rule ntt_intt_without_late_barrett)
      (rev !ntt_bounds_words);;

let NTT_INTT_WITHOUT_LATE_BARRETT_BOUNDS =
  (* Expose the changed graph equations as implication premises, rather than
     leave undischarged hypotheses on the recorded theorem. *)
  DISCH_ALL (end_itlist CONJ (map CONJUNCT2 ntt_intt_alternative_bounds));;

let ntt_intt_alternative_intervals =
  map (fun th -> let lo,hi = dest_conj(rand(concl th)) in
       dest_intconst(lhand lo),dest_intconst(rand hi))
      ntt_intt_alternative_bounds;;

let ntt_intt_alternative_lower =
  end_itlist min_num (map fst ntt_intt_alternative_intervals)
and ntt_intt_alternative_upper =
  end_itlist max_num (map snd ntt_intt_alternative_intervals);;

print_endline ("NTT_REDUCTION_WRAPPED_NODES " ^
               string_of_int(length !ntt_intt_wrapped_nodes));;

print_endline
 ("NTT_REDUCTION_RESULT late-v21 64 " ^
  string_of_num ntt_intt_alternative_lower ^ " " ^
  string_of_num ntt_intt_alternative_upper ^ " 26624");;
