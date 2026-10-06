import unittest
import json
import hashlib
import contextlib
import io
from pathlib import Path
from tempfile import TemporaryDirectory
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

    def test_linear_variant_preserves_every_other_proof_step(self):
        for name in bounds.SPECS:
            original = bounds.instrument(name)
            linear = bounds.instrument(name, True)
            if name in bounds.NTT_NAMES:
                self.assertEqual(linear.count(bounds.LINEAR_FINISH), 1)
                restored = linear.replace(bounds.LINEAR_IMPORT, "")
                restored = restored.replace(bounds.LINEAR_FINISH, bounds.ORIGINAL_FINISH)
                self.assertEqual(restored, original)
                self.assertNotEqual(bounds.fingerprint(name), bounds.fingerprint(name, True))
            else:
                self.assertEqual(linear, original)

    def test_linear_mode_reuses_accepted_original_without_regenerating(self):
        name = "mlkem_ntt"
        args = SimpleNamespace(names=[name], linear=True)
        saved = {name: dict(fingerprint=bounds.fingerprint(name))}
        with patch.object(bounds, "results", return_value=saved), \
             patch.object(bounds, "generate") as generate, \
             patch.object(bounds, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            bounds.replay(args)
        generate.assert_called_once_with([], True, False)
        run.assert_not_called()

    def test_generate_cli_selects_only_named_proofs(self):
        with patch("sys.argv", ["bounds.py", "generate", "--linear", "mlkem_intt"]), \
             patch.object(bounds, "generate") as generate:
            self.assertEqual(bounds.main(), 0)
        generate.assert_called_once_with(["mlkem_intt"], True, False)
        with patch("sys.argv", ["bounds.py", "generate", "unknown"]), \
             patch.object(bounds, "generate") as generate, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(bounds.main(), 1)
        generate.assert_not_called()

    def test_replay_uses_shared_basis_cache_without_retiring_shared_bases(self):
        for name in ("mlkem_intt", "mldsa_pointwise_acc_l7"):
            with self.subTest(name=name):
                args = SimpleNamespace(names=[name], linear=False, split_safety=True,
                                       hearth="hearth", run_root=Path("runs"), timeout=14400)
                with patch.object(bounds, "results", return_value={}), \
                     patch.object(bounds, "generate"), \
                     patch.object(bounds, "run") as run, \
                     patch.object(bounds, "collect", return_value=dict(lower="-1", upper="1")), \
                     patch.object(bounds, "save_results"), \
                     contextlib.redirect_stdout(io.StringIO()):
                    bounds.replay(args)
                commands = [call.args[0] for call in run.call_args_list]
                self.assertEqual(len(commands), 2)
                self.assertEqual(commands[0][:3], ["make", "-C", "arm"])
                proof = commands[1]
                self.assertEqual(proof[:2], ["hearth", "prove"])
                basis_file = (name + "_basis.ml" if name in bounds.SPLIT_NAMES
                              else name + ".ml")
                self.assertEqual(proof[proof.index("--basis") + 1],
                                 str(bounds.HERE / "generated" / basis_file))
                self.assertNotIn("--basis-cache-root", proof)
                self.assertNotIn("--cache-root", proof)

    def test_table_refuses_missing_results(self):
        with patch.object(bounds, "check_sources"), patch.object(bounds, "results", return_value={}):
            with self.assertRaisesRegex(ValueError, "incomplete"):
                bounds.table()

    def test_safety_split_preserves_all_statements_and_tactics(self):
        name = "mldsa_pointwise_acc_l7"
        prefix, suffix = bounds.split_sources(name)
        self.assertEqual(prefix + suffix, bounds.instrument(name))
        self.assertIn("let MLDSA_POINTWISE_ACC_L7_CORRECT = prove", prefix)
        self.assertIn("let MLDSA_POINTWISE_ACC_L7_SUBROUTINE_CORRECT = prove", prefix)
        self.assertNotIn("let MLDSA_POINTWISE_ACC_L7_SUBROUTINE_SAFE", prefix)
        self.assertIn("let MLDSA_POINTWISE_ACC_L7_SUBROUTINE_SAFE = time prove", suffix)
        self.assertEqual(bounds.entry_source(name, split_safety=True),
                         f'needs "ntt-bounds/generated/{name}_basis.ml";;\n' + suffix)
        with self.assertRaises(ValueError):
            bounds.split_sources("mlkem_tomont")

    def test_split_basis_identity_rejects_stale_missing_and_duplicate_files(self):
        name = "mldsa_pointwise_acc_l7"
        prefix, _ = bounds.split_sources(name)
        item = dict(package_path=f"ntt-bounds/generated/{name}_basis.ml",
                    sha256=hashlib.sha256(prefix.encode()).hexdigest())
        bounds.check_split_basis_identity(dict(dependency_package_files=[item]), name)
        for files in ([], [item, item], [dict(item, sha256="stale")]):
            with self.subTest(files=files), self.assertRaises(ValueError):
                bounds.check_split_basis_identity(dict(dependency_package_files=files), name)

    def test_split_collection_requires_both_checked_phases(self):
        name = "mldsa_pointwise_acc_l7"
        prefix, _ = bounds.split_sources(name)
        prefix_sha = hashlib.sha256(prefix.encode()).hexdigest()
        observer = dict(package_path="ntt-bounds/tap.ml", sha256=hashlib.sha256(
            (bounds.HERE / "tap.ml").read_bytes()).hexdigest())
        basis = dict(package_path=f"ntt-bounds/generated/{name}_basis.ml", sha256=prefix_sha)
        with TemporaryDirectory() as directory:
            receipt = Path(directory) / "transcript.log.json"
            receipt.write_text(json.dumps(dict(dependency_package_files=[observer, basis],
                project_basis=dict(preparation_receipt="basis-receipt.json"))))
            receipt.with_name("transcript.log.raw").write_text(
                f"NTT_BOUND_RESULT {name} 256 -5000000 5000000\n")
            leaf = dict(verdict="passed", new_axioms=0, receipt=str(receipt),
                source_sha256=hashlib.sha256(bounds.entry_source(name, split_safety=True).encode()).hexdigest(),
                bindings_proved=1, bindings_total=1)
            prepared = dict(verdict="passed", new_axioms=0, source_sha256=prefix_sha,
                bindings_proved=2, bindings_total=2, bindings=[
                    dict(name=name.upper() + "_CORRECT"),
                    dict(name=name.upper() + "_SUBROUTINE_CORRECT")])
            for changed in ({}, dict(verdict="incomplete"), dict(new_axioms=1),
                            dict(source_sha256="stale"), dict(bindings_proved=1)):
                with patch.object(bounds, "run", side_effect=[
                        SimpleNamespace(stdout=json.dumps(leaf)),
                        SimpleNamespace(stdout=json.dumps(dict(prepared, **changed)))]):
                    if changed:
                        with self.subTest(changed=changed), self.assertRaises(ValueError):
                            bounds.collect("hearth", Path(directory), name)
                    else:
                        row = bounds.collect("hearth", Path(directory), name)
                        self.assertEqual(row["upper"], "5000000")
                        self.assertEqual(row["fingerprint"], bounds.fingerprint(name))

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

    def test_intt_collection_checks_loaded_graph(self):
        observer = dict(package_path="ntt-bounds/tap.ml", sha256=hashlib.sha256(
            (bounds.HERE / "tap.ml").read_bytes()).hexdigest())
        graph = dict(package_path="ntt-bounds/generated/mlkem_intt.ml",
                     sha256=hashlib.sha256(bounds.instrument("mlkem_intt").encode()).hexdigest())
        with TemporaryDirectory() as directory:
            receipt = Path(directory) / "transcript.log.json"
            receipt.with_name("transcript.log.raw").write_text(
                "NTT_BOUND_RESULT mlkem_intt 256 -123 123\n")
            info = dict(verdict="passed", new_axioms=0, receipt=str(receipt),
                        source_sha256=hashlib.sha256(bounds.entry_source("mlkem_intt").encode()).hexdigest())
            with patch.object(bounds, "run", return_value=SimpleNamespace(stdout=json.dumps(info))):
                receipt.write_text(json.dumps(dict(dependency_package_files=[observer, graph])))
                self.assertEqual(bounds.collect("hearth", Path(directory), "mlkem_intt")["upper"], "123")
                for graphs in ([], [graph, graph], [dict(graph, sha256="old-graph")]):
                    receipt.write_text(json.dumps(dict(dependency_package_files=[observer, *graphs])))
                    with self.subTest(graphs=graphs), self.assertRaisesRegex(ValueError, "inverse-NTT graph"):
                        bounds.collect("hearth", Path(directory), "mlkem_intt")

    def test_reduction_result_rejects_incomplete_or_wrong_graph_count(self):
        text = "NTT_REDUCTION_RESULT late-v21 64 -27000 27000 26624\n"
        self.assertEqual(bounds.reduction_values(text), (-27000, 27000))
        for bad in ("", text[:-1], text * 2, text.replace("64 -", "32 -"),
                    text.replace("26624", "26632"), text.replace("-27000 27000", "2 1")):
            with self.subTest(text=bad), self.assertRaises(ValueError):
                bounds.reduction_values(bad)

    def test_linear_collection_checks_helper_for_direct_and_basis_proofs(self):
        observer = dict(package_path="ntt-bounds/tap.ml", sha256=hashlib.sha256(
            (bounds.HERE / "tap.ml").read_bytes()).hexdigest())
        helper = dict(package_path="ntt-bounds/upstream_int_linear.ml", sha256=hashlib.sha256(
            (bounds.HERE / "upstream_int_linear.ml").read_bytes()).hexdigest())
        with TemporaryDirectory() as directory:
            receipt = Path(directory) / "transcript.log.json"
            for name in ("mlkem_ntt", "mlkem_intt"):
                receipt.with_name("transcript.log.raw").write_text(
                    f"NTT_BOUND_RESULT {name} 256 -123 123\n")
                graph = ([dict(package_path="ntt-bounds/generated/mlkem_intt.ml",
                               sha256=hashlib.sha256(bounds.instrument(name, True).encode()).hexdigest())]
                         if name == "mlkem_intt" else [])
                info = dict(verdict="passed", new_axioms=0, receipt=str(receipt),
                            source_sha256=hashlib.sha256(bounds.entry_source(name, True).encode()).hexdigest())
                with patch.object(bounds, "run", return_value=SimpleNamespace(stdout=json.dumps(info))):
                    receipt.write_text(json.dumps(dict(dependency_package_files=[observer, helper, *graph])))
                    result = bounds.collect("hearth", Path(directory), name)
                    self.assertEqual(result["fingerprint"], bounds.fingerprint(name, True))
                    for helpers in ([], [helper, helper], [dict(helper, sha256="old-helper")]):
                        receipt.write_text(json.dumps(dict(dependency_package_files=[observer, *helpers, *graph])))
                        with self.subTest(name=name, helpers=helpers), self.assertRaisesRegex(ValueError, "linear congruence tactic"):
                            bounds.collect("hearth", Path(directory), name)


if __name__ == "__main__":
    unittest.main()
