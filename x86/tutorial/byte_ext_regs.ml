(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Stepping instructions that use the 8-bit and 16-bit views of the
  extended registers r8-r15 ('byte_ext_regs.S').

  This also serves as a regression test: OPERAND_CLAUSES must carry
  OPERAND8 clauses for r8b..r15b and OPERAND16 clauses for r8w..r15w,
  and REGISTER_ALIASES must list them, otherwise symbolic simulation of
  `cmp r15b, 5`, `movzx edx, r9w` or `mov r8b, dl` gets stuck.
******************************************************************************)

(* Please copy this file to the root directory of s2n-bignum, then
   follow the instructions. *)

needs "x86/proofs/base.ml";;

(* The program:

     0:   41 80 ff 05             cmp    $0x5,%r15b
     4:   44 00 f8                add    %r15b,%al
     7:   41 0f b6 c7             movzbl %r15b,%eax
     b:   41 0f b7 d1             movzwl %r9w,%edx
     f:   41 88 d0                mov    %dl,%r8b
    12:   c3                      ret
*)

let byte_ext_regs_mc = define_assert_from_elf "byte_ext_regs_mc"
  "x86/tutorial/byte_ext_regs.o"
[
  0x41; 0x80; 0xff; 0x05;  (* CMP (% r15b) (Imm8 (word 5)) *)
  0x44; 0x00; 0xf8;        (* ADD (% al) (% r15b) *)
  0x41; 0x0f; 0xb6; 0xc7;  (* MOVZX (% eax) (% r15b) *)
  0x41; 0x0f; 0xb7; 0xd1;  (* MOVZX (% edx) (% r9w) *)
  0x41; 0x88; 0xd0;        (* MOV (% r8b) (% dl) *)
  0xc3                     (* RET *)
];;

let BYTE_EXT_REGS_EXEC = X86_MK_CORE_EXEC_RULE byte_ext_regs_mc;;

(* The low byte and the low 16 bits as the simulation leaves them,
   word (val x MOD 256) and word (val x MOD 65536), at each result width. *)
let BYTE_EXT_REGS_LOW = map WORD_BLAST
 [`word (val (a:int64) MOD 256):byte = word_zx a`;
  `word (val (a:int64) MOD 256):int16 = word_zx (word_zx a:byte)`;
  `word (val (a:int64) MOD 256):int32 = word_zx (word_zx a:byte)`;
  `word (val (a:int64) MOD 256):int64 = word_zx (word_zx a:byte)`;
  `word (val (b:int64) MOD 65536):int16 = word_zx b`;
  `word (val (b:int64) MOD 65536):int32 = word_zx (word_zx b:int16)`;
  `word (val (b:int64) MOD 65536):int64 = word_zx (word_zx b:int16)`];;

(* Everything but the RET. The low byte of r15 and the low 16 bits of r9
   come out zero-extended in rax and rdx; r8 and the flags change. *)
let BYTE_EXT_REGS_CORRECT = prove
 (`!a b pc.
     ensures x86
      (\s. bytes_loaded s (word pc) (BUTLAST byte_ext_regs_mc) /\
           read RIP s = word pc /\
           read R15 s = a /\
           read R9 s = b)
      (\s. read RIP s = word (pc + 0x12) /\
           read RAX s = word_zx (word_zx a:byte) /\
           read RDX s = word_zx (word_zx b:int16))
      (MAYCHANGE [RIP; RAX; RDX; R8] ,, MAYCHANGE SOME_FLAGS ,,
       MAYCHANGE [events])`,
  REWRITE_TAC[SOME_FLAGS] THEN REPEAT STRIP_TAC THEN
  X86_SIM_TAC BYTE_EXT_REGS_EXEC (1--5) THEN
  REWRITE_TAC BYTE_EXT_REGS_LOW THEN CONV_TAC WORD_BLAST);;
