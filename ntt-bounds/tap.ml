(* Observe the theorem supplied to the CONGBOUND split, without changing it.
   LOCAL_CONGBOUND_RULE retains its original lexical bindings, so only calls
   made directly by the function proof are counted (not intermediate nodes). *)
let ntt_bounds_observed = ref [];;
let ntt_bounds_words = ref [];;
let ntt_bounds_local_inputs = ref [];;
let ntt_bounds_original_rule = ASM_CONGBOUND_RULE;;

let LOCAL_CONGBOUND_RULE lfn asms =
  ntt_bounds_local_inputs := asms :: !ntt_bounds_local_inputs;
  LOCAL_CONGBOUND_RULE lfn asms;;

let ntt_bounds_tap th =
  let lo,hi = dest_conj(rand(concl th)) in
  if not (is_binop `(<=):int->int->bool` lo &&
          is_binop `(<=):int->int->bool` hi &&
          aconv (rand lo) (lhand hi))
  then failwith "NTT bounds: unexpected CONGBOUND theorem shape";
  let l = dest_intconst(lhand lo) and u = dest_intconst(rand hi) in
  if l >/ u then failwith "NTT bounds: inverted interval";
  ntt_bounds_observed := (l,u):: !ntt_bounds_observed;
  th;;

let ASM_CONGBOUND_RULE lfn tm =
  ntt_bounds_words := tm :: !ntt_bounds_words;
  ntt_bounds_tap (ASM_CONGBOUND_RULE lfn tm);;
let GEN_CONGBOUND_RULE ths tm = ntt_bounds_tap (GEN_CONGBOUND_RULE ths tm);;
let CONGBOUND_RULE tm = ntt_bounds_tap (CONGBOUND_RULE tm);;

let ntt_bounds_finish name expected =
  let intervals = !ntt_bounds_observed in
  if length intervals <> expected then
    failwith ("NTT bounds: expected " ^ string_of_int expected ^
              " calls, observed " ^ string_of_int (length intervals));
  let lower = end_itlist min_num (map fst intervals)
  and upper = end_itlist max_num (map snd intervals) in
  print_endline ("NTT_BOUND_RESULT " ^ name ^ " " ^ string_of_int expected ^
                 " " ^ string_of_num lower ^ " " ^ string_of_num upper);;
