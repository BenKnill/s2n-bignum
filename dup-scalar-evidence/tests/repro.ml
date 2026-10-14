(* Minimal reproducer for scalar DUP (element), alias MOV <V><d>, <Vn>.<T>[i].
   The three words are the scalar DUP instructions of Node v22.14.0's
   armv8_crc32_pmull_little (AArch64).  The statements use only stock terms,
   so the same file builds against the stock and the patched tree.  For each
   word it prints the decoder result and whether the one-step ensures
   theorem (low lane copied, upper 64 bits cleared, source preserved) is
   provable. *)
loadt "arm/proofs/base.ml";;

let repro_oneline s = String.map (fun c -> if c = '\n' then ' ' else c) s;;

let repro_cases =
 [ (* word, mnemonic, Rd, Rn *)
   0x5e180400, "mov d0, v0.d[1]  (Rd = Rn)", 0, 0;
   0x5e1804a0, "mov d0, v5.d[1]", 0, 5;
   0x5e180482, "mov d2, v4.d[1]", 2, 4 ];;

let repro_mc w =
  let b k = Printf.sprintf "word 0x%02x" ((w lsr (8 * k)) land 255) in
  let tm = parse_term (Printf.sprintf "[%s; %s; %s; %s]:((8)word)list"
                         (b 0) (b 1) (b 2) (b 3)) in
  let name = Printf.sprintf "repro_mc_%08x" w in
  new_definition (mk_eq (mk_var(name, type_of tm), tm));;

let repro_goal name rd rn =
  let pre_src = if rd = rn then ""
                else Printf.sprintf " /\\ read Q%d s = d" rd in
  let post_src = if rd = rn then ""
                 else Printf.sprintf " /\\ read Q%d s = a" rn in
  parse_term (Printf.sprintf
   "!pc a d. ensures arm
      (\\s. aligned_bytes_loaded s (word pc) %s /\\ read PC s = word pc /\\
           read Q%d s = a%s)
      (\\s. read PC s = word (pc + 4) /\\
           word_subword (read Q%d s) (0,64):int64 = word_subword a (64,64) /\\
           word_subword (read Q%d s) (64,64):int64 = word 0%s)
      (MAYCHANGE [PC] ,, MAYCHANGE [Q%d])" name rn pre_src rd rd post_src rd);;

let () =
  List.iter (fun (w,mn,rd,rn) ->
    let tm = mk_comb(`decode`,
                     mk_comb(`word:num->int32`, mk_numeral(Num.num_of_int w))) in
    let dec = try repro_oneline (string_of_term (rhs (concl (DECODE_CONV tm))))
              with Failure s -> "FAIL " ^ s in
    let mc = repro_mc w in
    let name = fst (dest_const (lhs (concl mc))) in
    let step =
      match (try Some (ARM_MK_EXEC_RULE mc) with Failure _ -> None) with
      | None -> "NO (ARM_MK_EXEC_RULE fails: word does not decode)"
      | Some exec ->
        if can prove (repro_goal name rd rn,
             REPEAT STRIP_TAC THEN ENSURES_INIT_TAC "s0" THEN
             ARM_STEPS_TAC exec (1--1) THEN ENSURES_FINAL_STATE_TAC THEN
             ASM_REWRITE_TAC[] THEN REPEAT CONJ_TAC THEN CONV_TAC WORD_BLAST)
        then "YES" else "NO (proof failed)" in
    Printf.printf "REPRO 0x%08x  %-28s decode = %s\n" w mn dec;
    Printf.printf "REPRO 0x%08x  step theorem proved: %s\n%!" w step)
  repro_cases;;
