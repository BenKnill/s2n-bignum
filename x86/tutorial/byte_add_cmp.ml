(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Verifying a subroutine that uses 8-bit ADD and CMP ('byte_add_cmp.S').

  This also serves as a regression test: X86_OPERATION_CLAUSES must carry
  8-bit instances of x86_ADD and x86_CMP, otherwise symbolic simulation of
  `add byte ptr [..], sil`, `add al, byte ptr [..]` or
  `cmp byte ptr [..], sil` gets stuck.
******************************************************************************)

(* Please copy this file to the root directory of s2n-bignum, then
   follow the instructions. *)

needs "x86/proofs/base.ml";;

(* The program, with a C signature of
     uint64_t byte_add_cmp(uint8_t *x, uint64_t d):

     0:   31 c0                   xor    %eax,%eax
     2:   40 00 37                add    %sil,(%rdi)
     5:   02 07                   add    (%rdi),%al
     7:   40 38 37                cmp    %sil,(%rdi)
     a:   c3                      ret

   It adds the low byte of d to the byte at x, returns the new byte
   zero-extended to 64 bits, and leaves the flags of comparing the new
   byte with the low byte of d.
*)

let byte_add_cmp_mc = define_assert_from_elf "byte_add_cmp_mc"
  "x86/tutorial/byte_add_cmp.o"
[
  0x31; 0xc0;              (* XOR (% eax) (% eax) *)
  0x40; 0x00; 0x37;        (* ADD (Memop Byte (%% (rdi,0))) (% sil) *)
  0x02; 0x07;              (* ADD (% al) (Memop Byte (%% (rdi,0))) *)
  0x40; 0x38; 0x37;        (* CMP (Memop Byte (%% (rdi,0))) (% sil) *)
  0xc3                     (* RET *)
];;

(* X86_MK_CORE_EXEC_RULE decodes all but the final RET. *)
let BYTE_ADD_CMP_EXEC = X86_MK_CORE_EXEC_RULE byte_add_cmp_mc;;

(* Two word facts used to tidy up the final states below. *)
let BYTE_ADD_CMP_LOWBYTE = WORD_BLAST
  `word (val (d:int64) MOD 256):byte = word_zx d`;;

let BYTE_ADD_CMP_JOIN0 = WORD_BLAST
  `!a:byte. word_join (word 0:(56)word) a:int64 = word_zx a`;;

(* The core (everything but the RET), proved with X86_ACCSIM_TAC. It steps
   all four instructions and accumulates the results of steps 2-4, which are
   the two 8-bit ADDs and the 8-bit CMP. *)
let BYTE_ADD_CMP_CORRECT = prove
 (`!x d b pc.
     nonoverlapping (word pc,0xb) (x,1)
     ==> ensures x86
          (\s. bytes_loaded s (word pc) (BUTLAST byte_add_cmp_mc) /\
               read RIP s = word pc /\
               C_ARGUMENTS [x; d] s /\
               read (memory :> bytes8 x) s = b)
          (\s. read RIP s = word (pc + 0xa) /\
               read (memory :> bytes8 x) s = word_add b (word_zx d) /\
               C_RETURN s = word_zx (word_add b (word_zx d):byte) /\
               (read CF s <=>
                  val(word_add b (word_zx d):byte) < val(word_zx d:byte)) /\
               (read ZF s <=> word_add b (word_zx d):byte = word_zx d))
          (MAYCHANGE [RIP; RAX] ,, MAYCHANGE SOME_FLAGS ,,
           MAYCHANGE [events] ,, MAYCHANGE [memory :> bytes8 x])`,
  REWRITE_TAC[C_ARGUMENTS; C_RETURN; SOME_FLAGS; NONOVERLAPPING_CLAUSES] THEN
  REPEAT STRIP_TAC THEN
  X86_ACCSIM_TAC BYTE_ADD_CMP_EXEC [2;3;4] (1--4) THEN
  REWRITE_TAC[BYTE_ADD_CMP_LOWBYTE; WORD_ADD_0] THEN
  REWRITE_TAC[CARRY_WORD_SUB; VAL_EQ; BYTE_ADD_CMP_JOIN0]);;

(* The whole subroutine, promoted from the core by the standard wrapper. *)
let BYTE_ADD_CMP_SUBROUTINE_CORRECT = prove
 (`!x d b pc stackpointer returnaddress.
     nonoverlapping (word pc,LENGTH byte_add_cmp_mc) (x,1) /\
     nonoverlapping (stackpointer,8) (x,1)
     ==> ensures x86
          (\s. bytes_loaded s (word pc) byte_add_cmp_mc /\
               read RIP s = word pc /\
               read RSP s = stackpointer /\
               read (memory :> bytes64 stackpointer) s = returnaddress /\
               C_ARGUMENTS [x; d] s /\
               read (memory :> bytes8 x) s = b)
          (\s. read RIP s = returnaddress /\
               read RSP s = word_add stackpointer (word 8) /\
               read (memory :> bytes8 x) s = word_add b (word_zx d) /\
               C_RETURN s = word_zx (word_add b (word_zx d):byte) /\
               (read CF s <=>
                  val(word_add b (word_zx d):byte) < val(word_zx d:byte)) /\
               (read ZF s <=> word_add b (word_zx d):byte = word_zx d))
          (MAYCHANGE [RSP] ,, MAYCHANGE_REGS_AND_FLAGS_PERMITTED_BY_ABI ,,
           MAYCHANGE [memory :> bytes8 x])`,
  X86_PROMOTE_RETURN_NOSTACK_TAC byte_add_cmp_mc BYTE_ADD_CMP_CORRECT);;

(* The same subroutine simulated directly from entry to RET with
   X86_SIM_TAC, without a separate core theorem. *)
let BYTE_ADD_CMP_FULL_EXEC = X86_MK_EXEC_RULE byte_add_cmp_mc;;

let BYTE_ADD_CMP_SUBROUTINE_SIM = prove
 (`!x d b pc stackpointer returnaddress.
     nonoverlapping (word pc,LENGTH byte_add_cmp_mc) (x,1) /\
     nonoverlapping (stackpointer,8) (x,1)
     ==> ensures x86
          (\s. bytes_loaded s (word pc) byte_add_cmp_mc /\
               read RIP s = word pc /\
               read RSP s = stackpointer /\
               read (memory :> bytes64 stackpointer) s = returnaddress /\
               C_ARGUMENTS [x; d] s /\
               read (memory :> bytes8 x) s = b)
          (\s. read RIP s = returnaddress /\
               read RSP s = word_add stackpointer (word 8) /\
               read (memory :> bytes8 x) s = word_add b (word_zx d) /\
               C_RETURN s = word_zx (word_add b (word_zx d):byte) /\
               (read CF s <=>
                  val(word_add b (word_zx d):byte) < val(word_zx d:byte)) /\
               (read ZF s <=> word_add b (word_zx d):byte = word_zx d))
          (MAYCHANGE [RIP; RSP; RAX] ,, MAYCHANGE SOME_FLAGS ,,
           MAYCHANGE [events] ,, MAYCHANGE [memory :> bytes8 x])`,
  REWRITE_TAC[C_ARGUMENTS; C_RETURN; SOME_FLAGS; NONOVERLAPPING_CLAUSES;
              fst BYTE_ADD_CMP_FULL_EXEC] THEN
  REPEAT STRIP_TAC THEN
  X86_SIM_TAC BYTE_ADD_CMP_FULL_EXEC (1--5) THEN
  REWRITE_TAC[BYTE_ADD_CMP_LOWBYTE; WORD_ADD_0] THEN
  REWRITE_TAC[CARRY_WORD_SUB; VAL_EQ; BYTE_ADD_CMP_JOIN0]);;
