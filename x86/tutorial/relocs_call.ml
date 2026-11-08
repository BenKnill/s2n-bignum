(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Loading an object whose code calls and jumps to other functions
  ('relocs_call.S').

  Assemblers emit an R_X86_64_PLT32 relocation for each call or jump to a
  global symbol. This file is also a regression test: common/elf.ml must
  accept that relocation.
******************************************************************************)

(* Please copy this file to the root directory of s2n-bignum, then
   follow the instructions. *)

needs "x86/proofs/base.ml";;

(* objdump -dr x86/tutorial/relocs_call.o:

     0:   e8 00 00 00 00          call   5
                  1: R_X86_64_PLT32       relocs_call_f-0x4
     5:   e9 00 00 00 00          jmp    a
                  6: R_X86_64_PLT32       relocs_call_g-0x4
*)

let relocs_call_relocs =
  let _,_,relocs = load_elf_x86 (load_file "x86/tutorial/relocs_call.o") in
  relocs;;

if relocs_call_relocs <>
   [X86_64_pc32,(1,"relocs_call_f",-4); X86_64_pc32,(6,"relocs_call_g",-4)]
then failwith "relocs_call: unexpected relocations";;

(* The code with a symbolic address for each target. The literal below is
   the output of
     print_literal_relocs_from_elf ~map_symbol_name:I
       "x86/tutorial/relocs_call.o";;
*)
let relocs_call_mc,_ = define_assert_relocs_from_elf
  ~map_symbol_name:I "relocs_call_mc" "x86/tutorial/relocs_call.o"
(fun b ADDR -> [b[
  0xe8]; ADDR ("relocs_call_f",(-4)); b[
                           (* CALL (Imm32 (iword (&relocs_call_f - (&pc + &5)))) *)
  0xe9]; ADDR ("relocs_call_g",(-4)); b[
                           (* JMP (Imm32 (iword (&relocs_call_g - (&pc + &10)))) *)
]]);;

(* Decoding gives a CALL and a JMP whose targets are the symbols. *)
let RELOCS_CALL_EXEC = X86_MK_EXEC_RULE relocs_call_mc;;

(* GNU ld 2.46 produces these bytes when it places the code at 0x401000,
   relocs_call_f at 0x402345 and relocs_call_g at 0x400800:
     x86_64-linux-gnu-ld -e 0 -Ttext=0x401000 \
       --defsym relocs_call_f=0x402345 --defsym relocs_call_g=0x400800 \
       x86/tutorial/relocs_call.o
   The relocated code computes the same bytes. *)
let RELOCS_CALL_LINKED = prove
 (`relocs_call_mc 0x401000 0x402345 0x400800 =
   [word 0xe8; word 0x40; word 0x13; word 0x00; word 0x00;
    word 0xe9; word 0xf6; word 0xf7; word 0xff; word 0xff]`,
  REWRITE_TAC[relocs_call_mc] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC INT_RED_CONV)) THEN
  REWRITE_TAC[NUM_OF_INT_OF_NUM] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC INT_RED_CONV ORELSEC
                          WORD_RED_CONV ORELSEC DIMINDEX_CONV)) THEN
  REWRITE_TAC[NUM_OF_INT_OF_NUM] THEN
  CONV_TAC(TOP_DEPTH_CONV(NUM_RED_CONV ORELSEC WORD_RED_CONV)));;
