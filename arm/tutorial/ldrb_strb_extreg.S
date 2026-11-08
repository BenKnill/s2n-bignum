// LDRB/STRB with a register offset in every encodable option. The first six
// words are copied from clang's aarch64 build of a streaming PNG unfilter
// (unf_step in unf-full-aarch64.elf at +0x98, +0xa0, +0xf8, +0x108 and in
// unf-restricted-aarch64.elf at +0x40, +0x50).
ldrb w0, [x9, w27, uxtw]
ldrb w1, [x23, w27, uxtw]
ldrb w2, [x8, w27, uxtw]
strb w28, [x22, w27, uxtw]
ldrb w16, [x1, w14, uxtw]
strb w12, [x2, w14, uxtw]
// The other options and the S bit, which for bytes leaves the shift at 0.
ldrb w3, [x4, w5, sxtw]
strb w3, [x4, w5, sxtw]
ldrb w3, [x4, x5, sxtx]
strb w3, [x4, x5, sxtx]
ldrb w3, [x4, x5]
ldrb w3, [x4, x5, lsl #0]
ldrb w3, [x4, w5, uxtw #0]
strb w3, [x4, w5, sxtw #0]
ldrb w3, [sp, w5, uxtw]
strb wzr, [x4, wzr, sxtw]
