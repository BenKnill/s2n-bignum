#!/bin/sh
# cross objdump shim so check_insns can read AArch64 objects on x86_64
exec aarch64-linux-gnu-objdump "$@"
