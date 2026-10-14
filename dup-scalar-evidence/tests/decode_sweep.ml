(* Differential decoder sweep: decode every word listed in $SWEEP_IN (one hex
   word per line) and write "word<TAB>result" lines to $SWEEP_OUT.  Built
   unchanged against the stock and the patched tree, then the outputs are
   diffed. *)
loadt "arm/proofs/base.ml";;

let sweep_oneline s = String.map (fun c -> if c = '\n' then ' ' else c) s;;

let sweep_decode w =
  let tm = mk_comb(`decode`,
                   mk_comb(`word:num->int32`, mk_numeral(Num.num_of_int w))) in
  try sweep_oneline (string_of_term (rhs (concl (DECODE_CONV tm))))
  with Failure s -> "FAIL " ^ s;;

let () =
  let fin = open_in (Sys.getenv "SWEEP_IN")
  and fout = open_out (Sys.getenv "SWEEP_OUT") in
  let t0 = Unix.gettimeofday () and n = ref 0 in
  (try while true do
     let l = String.trim (input_line fin) in
     if l <> "" then begin
       let w = int_of_string l in
       Printf.fprintf fout "0x%08x\t%s\n" w (sweep_decode w);
       incr n
     end
   done with End_of_file -> ());
  close_in fin; close_out fout;
  Printf.printf "SWEEP done: %d words in %.1f s\n%!" !n (Unix.gettimeofday () -. t0);;
