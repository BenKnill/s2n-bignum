# Cross-check the scalar DUP (element) decode rule against a disassembler.
# usage: disas_check.py gen <out.bin> | check <objdump-output.txt> <label>
import sys, struct, re
def words():
    for op in (0, 1):
        for imm4 in range(16):
            for imm5 in range(32):
                regs = [(rd, rn) for rd in range(32) for rn in range(32)] if (op, imm4) == (0, 0) else [(3, 7), (31, 31)]
                for rd, rn in regs:
                    yield 0x5e000400 | (op << 29) | (imm5 << 16) | (imm4 << 11) | (rn << 5) | rd
def model(w):
    # the patched decoder rule, transcribed
    if w & 0xffe0fc00 != 0x5e000400: return None
    imm5 = (w >> 16) & 31
    if imm5 == 0 or imm5 == 16: return None
    size = (imm5 & -imm5).bit_length() - 1
    esize = 8 << size; idx = imm5 >> (size + 1)
    return ("bhsd"[size], w & 31, (w >> 5) & 31, "bhsd"[size], idx)
if sys.argv[1] == "gen":
    ws = list(words()); open(sys.argv[2], "wb").write(b"".join(struct.pack("<I", w) for w in ws)); print(len(ws), "words"); sys.exit()
txt = open(sys.argv[2]).read()
pat = re.compile(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8}|(?:[0-9a-f]{2} ){4})\s+(.*)$", re.M)
n = ok = bad = undef_ok = 0
for m in pat.finditer(txt):
    raw = m.group(1).replace(" ", "")
    w = int(raw, 16) if len(m.group(1)) == 8 else struct.unpack("<I", bytes.fromhex(raw))[0]
    ins = m.group(2).split("//")[0].split(";")[0].strip()
    n += 1; exp = model(w)
    d = re.match(r"(?:mov|dup)\s+([bhsd])(\d+),\s*v(\d+)(?:\.([bhsd]))?\[(\d+)\]$", ins)  # Apple syntax omits .T
    if exp is None:
        if d: bad += 1; print("MISMATCH model-refuses but disassembler", hex(w), ins)
        else: undef_ok += 1
    else:
        got = (d.group(1), int(d.group(2)), int(d.group(3)), d.group(4) or d.group(1), int(d.group(5))) if d else None
        if got == exp: ok += 1
        else: bad += 1; print("MISMATCH", hex(w), ins, exp)
print(f"{sys.argv[3]}: {n} words, {ok} legal forms agree, {undef_ok} refused by both, {bad} mismatches")
