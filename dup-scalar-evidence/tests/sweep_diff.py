# usage: sweep_diff.py stock.tsv patched.tsv [allpattern-patched.tsv]
# Compares decoder sweeps and checks patched results against the
# transcribed scalar DUP (element) rule.
import sys
def load(p): return dict(l.rstrip('\n').split('\t', 1) for l in open(p))
def rule(w):
    x = int(w, 16); imm5 = (x >> 16) & 31
    if x & 0xffe0fc00 != 0x5e000400 or imm5 in (0, 16): return None
    size = (imm5 & -imm5).bit_length() - 1
    return 'SOME (arm_DUP_ELEM_SCALAR Q%d Q%d %d %d)' % (x & 31, (x >> 5) & 31, imm5 >> (size + 1), 8 << size)
st, pa = load(sys.argv[1]), load(sys.argv[2])
assert st.keys() == pa.keys()
diff = [w for w in st if st[w] != pa[w]]
unexpected = [w for w in diff if not (rule(w) and st[w].startswith('FAIL') and pa[w] == rule(w))]
legal = [w for w in st if rule(w)]
print('differential: %d words, %d differ, %d unexpected differences, %d legal scalar DUP words, %d of them changed as expected'
      % (len(st), len(diff), len(unexpected), len(legal), sum(1 for w in legal if w in diff and w not in unexpected)))
for w in unexpected[:20]: print('UNEXPECTED', w, st[w][:100], '|', pa[w][:100])
if len(sys.argv) > 3:
    ap = load(sys.argv[3]); ok = ref = bad = 0
    for w, v in ap.items():
        r = rule(w)
        if r is None: ref += v.startswith('FAIL'); bad += not v.startswith('FAIL')
        else: ok += v == r; bad += v != r
    print('all-pattern: %d words, %d legal decode exactly per rule, %d reserved refused, %d bad' % (len(ap), ok, ref, bad))
