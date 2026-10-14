(* Checks for scalar DUP (element) against the patched tree:
   - exact decoder results for every element size (B/H/S/D), including
     Rd = Rn alias cases and the highest/lowest lane index;
   - a one-step ensures theorem per case stating that the low esize bits of
     Vd get the selected lane of the *old* Vn, the remaining 128-esize bits
     of Vd are zero, and (when Rd <> Rn) Vn is unchanged;
   - decoder refusal of the reserved imm5 values and of neighbouring
     unallocated encodings in the same "Advanced SIMD scalar copy" class. *)
loadt "arm/proofs/base.ml";;

let chk_fail = ref 0 and chk_pass = ref 0;;
let chk name ok =
  (if ok then incr chk_pass else incr chk_fail);
  Printf.printf "%s %s\n%!" (if ok then "PASS" else "FAIL") name;;

let chk_decode w = rhs (concl (DECODE_CONV (mk_comb(`decode`,
  mk_comb(`word:num->int32`, mk_numeral(Num.num_of_int w))))));;

let dup_word esize idx rd rn =
  let size = match esize with 8 -> 0 | 16 -> 1 | 32 -> 2 | 64 -> 3
             | _ -> failwith "esize" in
  let imm5 = (idx lsl (size + 1)) lor (1 lsl size) in
  0x5e000400 lor (imm5 lsl 16) lor (rn lsl 5) lor rd;;

let chk_mc w =
  let b k = Printf.sprintf "word 0x%02x" ((w lsr (8 * k)) land 255) in
  let tm = parse_term (Printf.sprintf "[%s; %s; %s; %s]:((8)word)list"
                         (b 0) (b 1) (b 2) (b 3)) in
  new_definition (mk_eq (mk_var(Printf.sprintf "chk_mc_%08x" w, type_of tm), tm));;

let chk_goal name esize idx rd rn =
  let pre = if rd = rn then "" else Printf.sprintf " /\\ read Q%d s = d" rd
  and post = if rd = rn then "" else Printf.sprintf " /\\ read Q%d s = a" rn in
  parse_term (Printf.sprintf
   "!pc a d. ensures arm
      (\\s. aligned_bytes_loaded s (word pc) %s /\\ read PC s = word pc /\\
           read Q%d s = a%s)
      (\\s. read PC s = word (pc + 4) /\\
           word_subword (read Q%d s) (0,%d):(%d)word =
             word_subword a (%d,%d) /\\
           word_subword (read Q%d s) (%d,%d):(%d)word = word 0%s)
      (MAYCHANGE [PC] ,, MAYCHANGE [Q%d])"
   name rn pre rd esize esize (esize * idx) esize
   rd esize (128 - esize) (128 - esize) post rd);;

let cases =
  [ 8, 15, 1, 2;   8, 0, 31, 31;   8, 7, 12, 0;
    16, 5, 3, 3;   16, 7, 9, 10;   16, 0, 0, 31;
    32, 2, 4, 5;   32, 3, 6, 6;    32, 0, 17, 18;
    64, 0, 7, 7;   64, 1, 0, 0;    64, 1, 0, 5;   64, 1, 2, 4;  64, 1, 30, 1 ];;

let () = List.iter (fun (esize,idx,rd,rn) ->
  let w = dup_word esize idx rd rn in
  let tag = Printf.sprintf "0x%08x esize=%d idx=%d Rd=%d Rn=%d%s"
              w esize idx rd rn (if rd = rn then " (alias)" else "") in
  let expected = parse_term (Printf.sprintf
    "SOME (arm_DUP_ELEM_SCALAR Q%d Q%d %d %d)" rd rn idx esize) in
  chk ("decode " ^ tag) (try aconv (chk_decode w) expected with Failure _ -> false);
  let mc = chk_mc w in
  let name = fst (dest_const (lhs (concl mc))) in
  let ok =
    try let exec = ARM_MK_EXEC_RULE mc in
        let g = chk_goal name esize idx rd rn in
        let pre = REPEAT STRIP_TAC THEN ENSURES_INIT_TAC "s0" THEN
                  ARM_STEPS_TAC exec (1--1) THEN ENSURES_FINAL_STATE_TAC THEN
                  ASM_REWRITE_TAC[] in
        (try let _ = prove (g, pre THEN REPEAT CONJ_TAC THEN CONV_TAC WORD_BLAST) in true
         with Failure msg ->
           Printf.printf "DIAG %s: %s\n%!" tag msg;
           (try let (_,gls,_) = pre ([],g) in
                List.iter (fun (asl,w) -> Printf.printf "DIAG goal: %s\n%!"
                  (string_of_term w)) gls
            with Failure m2 -> Printf.printf "DIAG pre-tactic fails: %s\n%!" m2);
           false)
    with Failure m -> (Printf.printf "DIAG exec %s\n%!" m; false) in
  chk ("step lane-copy+upper-zero " ^ tag) ok) cases;;

let refusals =
  [ 0x5e000400, "imm5=00000 (reserved)";
    0x5e100400, "imm5=10000 (reserved)";
    0x5e1007ff, "imm5=10000 (reserved), Rd=Rn=31";
    0x7e080400, "op=1 (unallocated)";
    0x7e180400, "op=1, imm5 as d[1] (unallocated)";
    0x5e080c00, "imm4=0001 (unallocated)";
    0x5e187c00, "imm4=1111 (unallocated)" ];;

let () = List.iter (fun (w,why) ->
  chk (Printf.sprintf "refuse 0x%08x %s" w why)
      (try let t = chk_decode w in
           Printf.printf "DIAG decode 0x%08x = %s : %s\n%!" w (string_of_term t)
             (string_of_type (type_of t));
           false
       with Failure _ -> true))
  (* PURE_DECODE_CONV only succeeds when decode evaluates to SOME _, so a
     failure here is the decoder refusing the word; this is the same test
     the cosimulator uses for "fails correctly". *)
  refusals;;

let () = Printf.printf "CHECKS pass=%d fail=%d\n%!" !chk_pass !chk_fail;;
