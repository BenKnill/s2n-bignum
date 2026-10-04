import unittest
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import bounds


class ExtractionChecks(unittest.TestCase):
    def test_reject_partial_duplicate_wrong_count_or_inverted_result(self):
        good = "NTT_BOUND_RESULT mlkem_tomont 256 -1665 1665\n"
        self.assertEqual(bounds.read_result(good, "mlkem_tomont"), ("256", "-1665", "1665"))
        for bad in ("", good[:-4], good * 2, good + "NTT_BOUND_RESULT truncated\n", good.replace("256", "128"),
                    good.replace("-1665 1665", "3 2"), good.replace("tomont", "ntt")):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                bounds.read_result(bad, "mlkem_tomont")

    def test_instrument_preserves_original_proof(self):
        for name in bounds.SPECS:
            original = (bounds.ROOT / "arm/proofs" / (name + ".ml")).read_text()
            generated = bounds.instrument(name)
            restored = generated.replace('\nneeds "ntt-bounds/tap.ml";;', '')
            restored = restored[:restored.rindex('\nntt_bounds_finish')]
            self.assertEqual(original, restored)

    def test_table_refuses_missing_results(self):
        with patch.object(bounds, "check_sources"), patch.object(bounds, "results", return_value={}):
            with self.assertRaisesRegex(ValueError, "incomplete"):
                bounds.table()

    def test_collect_rejects_incomplete_axioms_and_stale_source(self):
        for verdict, axioms, source in (("incomplete", 0, ""), ("passed", 1, ""),
                                         ("passed", 0, "wrong-source-hash")):
            info = dict(verdict=verdict, new_axioms=axioms, source_sha256=source)
            with patch.object(bounds, "run", return_value=SimpleNamespace(stdout=json.dumps(info))):
                with self.subTest(info=info), self.assertRaises(ValueError):
                    bounds.collect("hearth", Path("unused"), "mlkem_tomont")


if __name__ == "__main__":
    unittest.main()
