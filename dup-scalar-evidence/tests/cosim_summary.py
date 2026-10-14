# Summarize an s2n-bignum simulator log: counts per decoded form.
import sys, re, collections
for p in sys.argv[1:]:
    t = open(p, errors="replace").read()
    oks = re.findall(r"^OK:(.*)$", t, re.M)
    c = collections.Counter()
    for o in oks:
        if "fails correctly" in o:
            w = int(re.search(r"\[(\d+)\]", o).group(1)) if re.search(r"\[(\d+)\]", o) else None
            c["refused by model and trapped on hardware" + (" (scalar DUP pattern)" if w is not None and (w & 0xffe0fc00) == 0x5e000400 else "")] += 1
            continue
        m = re.search(r"arm_DUP_ELEM_SCALAR Q(\d+) Q(\d+) (\d+) (\d+)", o)
        if m:
            rd, rn, idx, es = map(int, m.groups())
            c["DUP_ELEM_SCALAR esize=%d" % es] += 1
            if rd == rn: c["DUP_ELEM_SCALAR Rd=Rn alias"] += 1
            if (es, idx) == (64, 1) and (rd, rn) in [(0, 0), (0, 5), (2, 4)]: c["DUP_ELEM_SCALAR exact Node word"] += 1
        else:
            c["other: " + re.sub(r"Q\d+|X\d+|W\d+|\d+", "_", o.strip())[:40]] += 1
    fin = re.search(r"^Finished.*$", t, re.M)
    err = re.search(r"^(Error.*|.*[Ee]xception.*)$", t, re.M)
    print("==", p, "| OK lines:", len(oks), "|", fin.group(0) if fin else "NOT FINISHED", "|", err.group(0)[:120] if err else "no error")
    for k, v in sorted(c.items()): print("  %6d  %s" % (v, k))
