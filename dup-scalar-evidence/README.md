# Test evidence for "Arm: Add DUP (element), scalar form"

This directory lives on a separate evidence branch and is **not** part of the proposed patch. It retains the test drivers and logs behind the validation summary in the PR.

- Upstream base: `4d1356a7470663c752660a59375dc3a9ef548428`; HOL Light CI pin `b19af6934759eed622d7aca25092367f81656eee`.
- `tests/`: decode sweep, differential decode, disassembler cross-check, HOL checks (`dup_scalar_checks.ml`), simulator class driver, reproducer.
- `logs/`: outputs of those runs, including the native Apple M5 (arm64 Linux VM) and QEMU cosimulation mixtures.

Not run: the full `make sematest` and full `make proofs`.
