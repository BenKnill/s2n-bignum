(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Decoding and stepping LDRB/STRB with a register offset in every option:
  UXTW and SXTW (a 32-bit index register Wm), and LSL and SXTX (a 64-bit Xm),
  with the S bit either clear or set. For byte accesses the shift amount is
  always 0, so the address is Xn + ExtendReg(Rm, option, 0, 64):

    UXTW: Xn + ZeroExtend(Xm<31:0>)      SXTW: Xn + SignExtend(Xm<31:0>)
    LSL, SXTX: Xn + Xm

  The first six instructions are copied from clang's aarch64 build of a
  streaming PNG unfilter.
******************************************************************************)

needs "arm/proofs/base.ml";;

let ldrb_strb_extreg_mc =
  define_assert_from_elf "ldrb_strb_extreg_mc" "arm/tutorial/ldrb_strb_extreg.o" [
  0x387b4920;       (* arm_LDRB W0 X9 (Register_Offset (Extendedreg X27 UXTW)) *)
  0x387b4ae1;       (* arm_LDRB W1 X23 (Register_Offset (Extendedreg X27 UXTW)) *)
  0x387b4902;       (* arm_LDRB W2 X8 (Register_Offset (Extendedreg X27 UXTW)) *)
  0x383b4adc;       (* arm_STRB W28 X22 (Register_Offset (Extendedreg X27 UXTW)) *)
  0x386e4830;       (* arm_LDRB W16 X1 (Register_Offset (Extendedreg X14 UXTW)) *)
  0x382e484c;       (* arm_STRB W12 X2 (Register_Offset (Extendedreg X14 UXTW)) *)
  0x3865c883;       (* arm_LDRB W3 X4 (Register_Offset (Extendedreg X5 SXTW)) *)
  0x3825c883;       (* arm_STRB W3 X4 (Register_Offset (Extendedreg X5 SXTW)) *)
  0x3865e883;       (* arm_LDRB W3 X4 (Register_Offset X5) *)
  0x3825e883;       (* arm_STRB W3 X4 (Register_Offset X5) *)
  0x38656883;       (* arm_LDRB W3 X4 (Register_Offset X5) *)
  0x38657883;       (* arm_LDRB W3 X4 (Register_Offset X5) *)
  0x38655883;       (* arm_LDRB W3 X4 (Register_Offset (Extendedreg X5 UXTW)) *)
  0x3825d883;       (* arm_STRB W3 X4 (Register_Offset (Extendedreg X5 SXTW)) *)
  0x38654be3;       (* arm_LDRB W3 SP (Register_Offset (Extendedreg X5 UXTW)) *)
  0x383fc89f        (* arm_STRB WZR X4 (Register_Offset (Extendedreg XZR SXTW)) *)
];;

let EXEC = ARM_MK_EXEC_RULE ldrb_strb_extreg_mc;;

(* ------------------------------------------------------------------------- *)
(* Decoding. Every word decodes to the expected instruction, and the         *)
(* encodings whose option<1> is 0 (UNDEFINED in the Arm ARM) still do not.   *)
(* ------------------------------------------------------------------------- *)

let LDRB_STRB_EXTREG_EXPECTED = [
  `arm_LDRB W0 X9 (Register_Offset (Extendedreg X27 UXTW))`;
  `arm_LDRB W1 X23 (Register_Offset (Extendedreg X27 UXTW))`;
  `arm_LDRB W2 X8 (Register_Offset (Extendedreg X27 UXTW))`;
  `arm_STRB W28 X22 (Register_Offset (Extendedreg X27 UXTW))`;
  `arm_LDRB W16 X1 (Register_Offset (Extendedreg X14 UXTW))`;
  `arm_STRB W12 X2 (Register_Offset (Extendedreg X14 UXTW))`;
  `arm_LDRB W3 X4 (Register_Offset (Extendedreg X5 SXTW))`;
  `arm_STRB W3 X4 (Register_Offset (Extendedreg X5 SXTW))`;
  `arm_LDRB W3 X4 (Register_Offset X5)`;
  `arm_STRB W3 X4 (Register_Offset X5)`;
  `arm_LDRB W3 X4 (Register_Offset X5)`;
  `arm_LDRB W3 X4 (Register_Offset X5)`;
  `arm_LDRB W3 X4 (Register_Offset (Extendedreg X5 UXTW))`;
  `arm_STRB W3 X4 (Register_Offset (Extendedreg X5 SXTW))`;
  `arm_LDRB W3 SP (Register_Offset (Extendedreg X5 UXTW))`;
  `arm_STRB WZR X4 (Register_Offset (Extendedreg XZR SXTW))`];;

let () =
  let decoded = map (rand o rand o snd o strip_forall o concl o option_get)
                    (filter option_is_some (Array.to_list (snd EXEC))) in
  if decoded <> LDRB_STRB_EXTREG_EXPECTED then
    failwith "ldrb_strb_extreg: unexpected decoding";;

let () =
  let decodes w =
    can DECODE_CONV (mk_comb(`decode`,mk_comb(`word:num->int32`,mk_small_numeral w))) in
  (* LDRB w3, [x4, ?5] with option 000, 001, 100, 101 (S = 0) and 000 (S = 1),
     and STRB with option 000 and 101. *)
  let reserved = [0x38650883; 0x38652883; 0x38658883; 0x3865a883;
                  0x38651883; 0x38250883; 0x3825b883] in
  if exists decodes reserved then
    failwith "ldrb_strb_extreg: a reserved option decoded";;

(* ------------------------------------------------------------------------- *)
(* Stepping. One theorem per instruction, from a symbolic state.             *)
(* The UXTW offset is word(val(word_zx xm:int32)) and the SXTW one is        *)
(* iword(ival(word_zx xm:int32)), the zero- and sign-extension of the low    *)
(* 32 bits of Xm; the 64-bit forms take Xm = word i and add word i.          *)
(* ------------------------------------------------------------------------- *)

let LDRB_STRB_STEP_TAC =
  REWRITE_TAC[fst EXEC] THEN REPEAT STRIP_TAC THEN ENSURES_INIT_TAC "s0" THEN
  ARM_STEPS_TAC EXEC [1] THEN ENSURES_FINAL_STATE_TAC THEN ASM_REWRITE_TAC[] THEN
  CONV_TAC WORD_BLAST;;

let ldrb_strb_step_goal (i,ld,rt,rn,rm,ext) =
  let off = match ext with
      "UXTW" -> "word (val (word_zx xm:int32))"
    | "SXTW" -> "iword (ival (word_zx xm:int32))"
    | _ -> "word i" in
  let pc0 = if i = 0 then "word pc" else Printf.sprintf "word (pc + %d)" (4 * i)
  and pc1 = Printf.sprintf "word (pc + %d)" (4 * i + 4) in
  let xm,xmval = if ext = "X" then "i","word i" else "xm","xm" in
  let sp = if rn = "SP" then "aligned 16 xn ==> " else "" in
  parse_term
   (if ld then Printf.sprintf
     "!pc xn %s b. %s
      ensures arm
       (\\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\\
            read PC s = %s /\\ read %s s = xn /\\ read %s s = %s /\\
            read (memory :> bytes8 (word_add xn (%s))) s = b)
       (\\s. read PC s = %s /\\ read %s s = word_zx b)
       (MAYCHANGE [PC; %s] ,, MAYCHANGE [events])"
     xm sp pc0 rn rm xmval off pc1 rt rt
    else Printf.sprintf
     "!pc xn %s xt.
      nonoverlapping (word_add xn (%s),1) (word pc,LENGTH ldrb_strb_extreg_mc)
      ==> ensures arm
       (\\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\\
            read PC s = %s /\\ read %s s = xn /\\ read %s s = %s /\\
            read %s s = xt)
       (\\s. read PC s = %s /\\
            read (memory :> bytes8 (word_add xn (%s))) s = word_zx xt)
       (MAYCHANGE [PC] ,, MAYCHANGE [memory :> bytes8 (word_add xn (%s))] ,,
        MAYCHANGE [events])"
     xm off pc0 rn rm xmval rt pc1 off off);;

(* (instruction index, is a load, Rt as an X register, Rn, Rm, offset kind) *)
let LDRB_STRB_STEPS = map
  (fun e -> prove(ldrb_strb_step_goal e, LDRB_STRB_STEP_TAC))
 [0,true,"X0","X9","X27","UXTW";   1,true,"X1","X23","X27","UXTW";
  2,true,"X2","X8","X27","UXTW";   3,false,"X28","X22","X27","UXTW";
  4,true,"X16","X1","X14","UXTW";  5,false,"X12","X2","X14","UXTW";
  6,true,"X3","X4","X5","SXTW";    7,false,"X3","X4","X5","SXTW";
  8,true,"X3","X4","X5","X";       9,false,"X3","X4","X5","X";
  10,true,"X3","X4","X5","X";      11,true,"X3","X4","X5","X";
  12,true,"X3","X4","X5","UXTW";   13,false,"X3","X4","X5","SXTW";
  14,true,"X3","SP","X5","UXTW"];;

(* STRB WZR, [X4, WZR, SXTW] stores 0 at X4. *)
let STRB_WZR_STEP = prove
 (`!pc x4.
    nonoverlapping (x4,1) (word pc,LENGTH ldrb_strb_extreg_mc)
    ==> ensures arm
     (\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\
          read PC s = word (pc + 60) /\ read X4 s = x4)
     (\s. read PC s = word (pc + 64) /\ read (memory :> bytes8 x4) s = word 0)
     (MAYCHANGE [PC] ,, MAYCHANGE [memory :> bytes8 x4] ,, MAYCHANGE [events])`,
  LDRB_STRB_STEP_TAC);;

(* ------------------------------------------------------------------------- *)
(* Concrete values: UXTW ignores the upper half of X27, and SXTW reads       *)
(* 0xfffffffe in the low half of X5 as -2.                                   *)
(* ------------------------------------------------------------------------- *)

let LDRB_UXTW_CONCRETE = prove
 (`!pc x9 b.
    ensures arm
     (\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\
          read PC s = word pc /\ read X9 s = x9 /\
          read X27 s = word 0xffffffff00000005 /\
          read (memory :> bytes8 (word_add x9 (word 5))) s = b)
     (\s. read PC s = word (pc + 4) /\ read X0 s = word_zx b)
     (MAYCHANGE [PC; X0] ,, MAYCHANGE [events])`,
  LDRB_STRB_STEP_TAC);;

let LDRB_SXTW_CONCRETE = prove
 (`!pc x4 b.
    ensures arm
     (\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\
          read PC s = word (pc + 24) /\ read X4 s = x4 /\
          read X5 s = word 0x12345678fffffffe /\
          read (memory :> bytes8 (word_sub x4 (word 2))) s = b)
     (\s. read PC s = word (pc + 28) /\ read X3 s = word_zx b)
     (MAYCHANGE [PC; X3] ,, MAYCHANGE [events])`,
  LDRB_STRB_STEP_TAC);;

(* ------------------------------------------------------------------------- *)
(* The sign boundary of the 32-bit index, with garbage in the upper half:    *)
(* low half 0x7fffffff, 0x80000000 and 0xffffffff, for SXTW (+2^31-1, -2^31, *)
(* -1) and UXTW (always non-negative), loads and stores.                     *)
(* ------------------------------------------------------------------------- *)

let ldrb_strb_boundary_goal (i,ld,rt,rn,rm,xmval,addr) =
  let pc0 = if i = 0 then "word pc" else Printf.sprintf "word (pc + %d)" (4 * i)
  and pc1 = Printf.sprintf "word (pc + %d)" (4 * i + 4) in
  parse_term
   (if ld then Printf.sprintf
     "!pc xn b.
      ensures arm
       (\\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\\
            read PC s = %s /\\ read %s s = xn /\\ read %s s = word %s /\\
            read (memory :> bytes8 (%s)) s = b)
       (\\s. read PC s = %s /\\ read %s s = word_zx b)
       (MAYCHANGE [PC; %s] ,, MAYCHANGE [events])"
     pc0 rn rm xmval addr pc1 rt rt
    else Printf.sprintf
     "!pc xn xt.
      nonoverlapping (%s,1) (word pc,LENGTH ldrb_strb_extreg_mc)
      ==> ensures arm
       (\\s. aligned_bytes_loaded s (word pc) ldrb_strb_extreg_mc /\\
            read PC s = %s /\\ read %s s = xn /\\ read %s s = word %s /\\
            read %s s = xt)
       (\\s. read PC s = %s /\\ read (memory :> bytes8 (%s)) s = word_zx xt)
       (MAYCHANGE [PC] ,, MAYCHANGE [memory :> bytes8 (%s)] ,,
        MAYCHANGE [events])"
     addr pc0 rn rm xmval rt pc1 addr addr);;

(* (instruction index, is a load, Rt, Rn, Rm, value of Rm, address) *)
let LDRB_STRB_BOUNDARY_STEPS = map
  (fun e -> prove(ldrb_strb_boundary_goal e, LDRB_STRB_STEP_TAC))
 [6,true,"X3","X4","X5","0xa5a5a5a57fffffff","word_add xn (word 0x7fffffff)";
  6,true,"X3","X4","X5","0x0000000180000000","word_sub xn (word 0x80000000)";
  6,true,"X3","X4","X5","0x00000000ffffffff","word_sub xn (word 1)";
  7,false,"X3","X4","X5","0xa5a5a5a57fffffff","word_add xn (word 0x7fffffff)";
  7,false,"X3","X4","X5","0x0000000180000000","word_sub xn (word 0x80000000)";
  7,false,"X3","X4","X5","0x00000000ffffffff","word_sub xn (word 1)";
  0,true,"X0","X9","X27","0xa5a5a5a57fffffff","word_add xn (word 0x7fffffff)";
  0,true,"X0","X9","X27","0x0000000180000000","word_add xn (word 0x80000000)";
  0,true,"X0","X9","X27","0xffffffffffffffff","word_add xn (word 0xffffffff)";
  3,false,"X28","X22","X27","0x0000000180000000","word_add xn (word 0x80000000)";
  3,false,"X28","X22","X27","0xffffffffffffffff","word_add xn (word 0xffffffff)"];;
