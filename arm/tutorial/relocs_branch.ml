(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Loading an object whose code calls a function and branches to others
  ('relocs_branch.S').

  Assemblers emit R_AARCH64_CALL26 for BL and R_AARCH64_JUMP26 for B to a
  global symbol. This file is also a regression test: common/elf.ml and
  arm/proofs/decode.ml must accept and apply R_AARCH64_JUMP26.
******************************************************************************)

(* Please copy this file to the root directory of s2n-bignum, then
   follow the instructions. *)

needs "arm/proofs/base.ml";;

(* objdump -dr arm/tutorial/relocs_branch.o:

     0:   94000000        bl      0 <relocs_branch_f>
                  0: R_AARCH64_CALL26     relocs_branch_f
     4:   14000000        b       0 <relocs_branch_g>
                  4: R_AARCH64_JUMP26     relocs_branch_g
     8:   14000000        b       0 <relocs_branch_g>
                  8: R_AARCH64_JUMP26     relocs_branch_g-0x4
     c:   14000000        b       0 <relocs_branch_f>
                  c: R_AARCH64_JUMP26     relocs_branch_f+0x8
*)

let relocs_branch_relocs =
  let _,_,relocs = load_elf_arm (load_file "arm/tutorial/relocs_branch.o") in
  relocs;;

if relocs_branch_relocs <>
   [Arm_call26,(0,"relocs_branch_f",0); Arm_jump26,(4,"relocs_branch_g",0);
    Arm_jump26,(8,"relocs_branch_g",-4); Arm_jump26,(12,"relocs_branch_f",8)]
then failwith "relocs_branch: unexpected relocations";;

(* The code with a symbolic address for each target. The literal below is
   the output of
     print_literal_relocs_from_elf ~map_symbol_name:I
       "arm/tutorial/relocs_branch.o";;
   A B instruction with an R_AARCH64_JUMP26 relocation is printed as
   B_JUMP26, a global checker, rather than as a parameter of the function,
   so that existing five-parameter literals still apply. *)
let relocs_branch_mc,_ = define_assert_relocs_from_elf
  ~map_symbol_name:I "relocs_branch_mc" "arm/tutorial/relocs_branch.o"
(fun w BL ADR ADRP ADD_rri64 -> [
  BL (mk_var("relocs_branch_f",`:num`),0,0);
  B_JUMP26 (mk_var("relocs_branch_g",`:num`),0,4);
  B_JUMP26 (mk_var("relocs_branch_g",`:num`),-4,8);
  B_JUMP26 (mk_var("relocs_branch_f",`:num`),8,12)
]);;

(* Decoding gives a BL and three Bs whose targets are the symbols plus
   their addends. *)
let RELOCS_BRANCH_EXEC = ARM_MK_EXEC_RULE relocs_branch_mc;;

(* GNU ld 2.46 produces these words when it places the code at 0x400000,
   relocs_branch_f at 0x400100 and relocs_branch_g at 0x3ff000:
     ld -e 0 -Ttext=0x400000 \
       --defsym relocs_branch_f=0x400100 --defsym relocs_branch_g=0x3ff000 \
       arm/tutorial/relocs_branch.o
   giving 0x94000040 (bl), 0x17fffbff (b back to relocs_branch_g),
   0x17fffbfd (b relocs_branch_g-4) and 0x1400003f (b relocs_branch_f+8).
   The relocated code computes the same bytes. The parameters of
   relocs_branch_mc are pc, relocs_branch_g and relocs_branch_f, in the
   order define_assert_relocs_from_elf chose. *)
let RELOCS_BRANCH_LINKED = prove
 (`relocs_branch_mc 0x400000 0x3ff000 0x400100 =
   [word 0x40; word 0x00; word 0x00; word 0x94;
    word 0xff; word 0xfb; word 0xff; word 0x17;
    word 0xfd; word 0xfb; word 0xff; word 0x17;
    word 0x3f; word 0x00; word 0x00; word 0x14]`,
  REWRITE_TAC[relocs_branch_mc; encode_BL; encode_B] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC INT_RED_CONV)) THEN
  REWRITE_TAC[NUM_OF_INT_OF_NUM] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC INT_RED_CONV ORELSEC
                          WORD_RED_CONV ORELSEC DIMINDEX_CONV)) THEN
  REWRITE_TAC[NUM_OF_INT_OF_NUM] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC WORD_RED_CONV)));;
