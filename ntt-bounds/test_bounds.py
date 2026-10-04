import unittest
import json
import hashlib
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

    def test_receipt_must_capture_current_observer(self):
        item = dict(package_path="ntt-bounds/tap.ml", sha256=hashlib.sha256(
            (bounds.HERE / "tap.ml").read_bytes()).hexdigest())
        bounds.check_observer_identity(dict(dependency_package_files=[item]))
        for files in ([], [item, item], [dict(item, sha256="old-observer")]):
            with self.subTest(files=files), self.assertRaises(ValueError):
                bounds.check_observer_identity(dict(dependency_package_files=files))

    def test_reduction_result_rejects_incomplete_or_wrong_graph_count(self):
        text = "NTT_REDUCTION_RESULT late-v21 64 -27000 27000 26624\n"
        self.assertEqual(bounds.reduction_values(text), (-27000, 27000))
        for bad in ("", text[:-1], text * 2, text.replace("64 -", "32 -"),
                    text.replace("26624", "26632"), text.replace("-27000 27000", "2 1")):
            with self.subTest(text=bad), self.assertRaises(ValueError):
                bounds.reduction_values(bad)


if __name__ == "__main__":
    unittest.main()
