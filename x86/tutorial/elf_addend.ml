(*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0 OR ISC OR MIT-0
 *)

(******************************************************************************
  Reading 64-bit integer fields of an ELF object ('elf_addend.S').

  This is also a regression test for common/elf.ml:
  - get_int_le must check the top byte of the field it reads (bs[a+7]),
    and reject values that do not fit in a non-negative OCaml int;
  - an ELF64 relocation addend is signed, and must be read exactly or
    rejected, never wrapped modulo 2^63.
******************************************************************************)

(* Please copy this file to the root directory of s2n-bignum, then
   follow the instructions. *)

needs "x86/proofs/base.ml";;

(* The object has one relocation, for
     0:   48 8d 05 00 00 00 00    lea    0x0(%rip),%rax
                  3: R_X86_64_PC32  elf_addend_data-0x4
     7:   c3                      ret
*)

let elf_addend_file = load_file "x86/tutorial/elf_addend.o";;

let elf_addend_failures = ref ([]:string list);;

let elf_addend_check name ok =
  if ok then Printf.printf "PASS %s\n%!" name
  else (Printf.printf "FAIL %s\n%!" name;
        elf_addend_failures := name :: !elf_addend_failures);;

(* The relocation as the x86 backend sees it. *)
let elf_addend_relocs bs =
  let _,_,relocs = load_elf_x86 bs in relocs;;

elf_addend_check "the object's addend is read as -4"
  (elf_addend_relocs elf_addend_file =
   [X86_64_pc32,(3,"elf_addend_data",-4)]);;

(* The file offset of the addend: the only occurrence of -4 as eight
   little-endian bytes. *)
let elf_addend_offset =
  let pat = Bytes.of_string "\xfc\xff\xff\xff\xff\xff\xff\xff" in
  let n = Bytes.length elf_addend_file in
  let hits = filter (fun i -> Bytes.sub elf_addend_file i 8 = pat)
    (0--(n - 8)) in
  match hits with
  | [i] -> i
  | _ -> failwith "elf_addend: expected exactly one addend of -4";;

(* A copy of the object whose addend is the eight bytes given. *)
let elf_addend_with (le_bytes:int list) =
  let bs = Bytes.copy elf_addend_file in
  List.iteri (fun i c -> Bytes.set bs (elf_addend_offset + i) (Char.chr c))
    le_bytes;
  bs;;

let elf_addend_read le_bytes =
  match (try Some (elf_addend_relocs (elf_addend_with le_bytes))
         with Failure _ -> None) with
  | Some [_,(_,_,a)] -> Some a
  | Some _ -> failwith "elf_addend: expected one relocation"
  | None -> None;;

(* The extremes of the OCaml int range are read exactly. *)
elf_addend_check "addend 2^62 - 1 is read exactly"
  (elf_addend_read [0xff;0xff;0xff;0xff;0xff;0xff;0xff;0x3f] =
   Some max_int);;

elf_addend_check "addend -2^62 is read exactly"
  (elf_addend_read [0x00;0x00;0x00;0x00;0x00;0x00;0x00;0xc0] =
   Some min_int);;

(* 2^63 - 4 used to be read as -4, and 2^62 as -2^62. Both are rejected. *)
elf_addend_check "addend 2^63 - 4 is rejected"
  (elf_addend_read [0xfc;0xff;0xff;0xff;0xff;0xff;0xff;0x7f] = None);;

elf_addend_check "addend 2^62 is rejected"
  (elf_addend_read [0x00;0x00;0x00;0x00;0x00;0x00;0x00;0x40] = None);;

elf_addend_check "addend -2^62 - 1 is rejected"
  (elf_addend_read [0xff;0xff;0xff;0xff;0xff;0xff;0xff;0xbf] = None);;

(* get_int_le checks the field's own top byte. Here byte 7 of the buffer
   is zero but the field at offset 8 is 2^63. *)
let elf_addend_buffer =
  let bs = Bytes.make 16 '\x00' in Bytes.set bs 15 '\x80'; bs;;

elf_addend_check "get_int_le rejects 2^63 in a field at offset 8"
  (can (get_int_le elf_addend_buffer 8) 8 = false);;

elf_addend_check "get_int_le reads 2^62 - 1 exactly"
  (get_int_le (Bytes.of_string "\xff\xff\xff\xff\xff\xff\xff\x3f") 0 8 =
   max_int);;

(* 2^62 has the top bit clear but does not fit in a non-negative OCaml int. *)
elf_addend_check "get_int_le rejects 2^62"
  (can (get_int_le (Bytes.of_string "\x00\x00\x00\x00\x00\x00\x00\x40") 0) 8
   = false);;

if !elf_addend_failures <> [] then
  failwith ("elf_addend: " ^ string_of_int (length !elf_addend_failures) ^
            " check(s) failed");;
