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

(* v21 sums the two freshly Barrett-multiplied butterfly differences. The
   other standalone reductions sum eight scaled inputs. Distinguish these
   structurally, then require all 64 coefficient occurrences. *)
let ntt_intt_is_late_barred bod =
  match bod with
  | Comb(Const("barred",_),Comb(Comb(Const("word_add",_),a),b)) ->
      ntt_intt_is_barmul_var a && ntt_intt_is_barmul_var b
  | _ -> false;;

let ntt_intt_removed =
  filter (ntt_intt_is_late_barred o lhand o concl) ntt_intt_asms;;

if length ntt_intt_removed <> 64 then
  failwith ("NTT reduction: expected 64 late Barrett terms, got " ^
            string_of_int(length ntt_intt_removed));;

let ntt_intt_without_late_barrett =
  itlist (fun th lfn ->
    let bod,var = dest_eq(concl th) in
    (* Treat the whole changed graph as explicit equations. Do not carry
       any simulation hypotheses from the original machine execution. *)
    let newbod = if ntt_intt_is_late_barred bod then rand bod else bod in
    let eq = ASSUME(mk_eq(newbod,var)) in
    let cb = ntt_bounds_original_rule lfn (lhand(concl eq)) in
    (var |-> SUBS[eq] cb) lfn)
    (rev ntt_intt_asms) undefined;;

let ntt_intt_alternative_bounds =
  map (ntt_bounds_original_rule ntt_intt_without_late_barrett)
      (rev !ntt_bounds_words);;

let NTT_INTT_WITHOUT_LATE_BARRETT_BOUNDS =
  end_itlist CONJ (map CONJUNCT2 ntt_intt_alternative_bounds);;

let ntt_intt_alternative_intervals =
  map (fun th -> let lo,hi = dest_conj(rand(concl th)) in
       dest_intconst(lhand lo),dest_intconst(rand hi))
      ntt_intt_alternative_bounds;;

let ntt_intt_alternative_lower =
  end_itlist min_num (map fst ntt_intt_alternative_intervals)
and ntt_intt_alternative_upper =
  end_itlist max_num (map snd ntt_intt_alternative_intervals);;

print_endline
 ("NTT_REDUCTION_RESULT late-v21 64 " ^
  string_of_num ntt_intt_alternative_lower ^ " " ^
  string_of_num ntt_intt_alternative_upper ^ " 26624");;
