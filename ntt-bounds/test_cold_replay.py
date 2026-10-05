import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import contextlib
import io

import bounds
import cold_replay


class ColdReplayChecks(unittest.TestCase):
    def test_preserves_proofs_and_checks_three_claims(self):
        for name in cold_replay.ORDER:
            source = (bounds.ROOT / 'arm/proofs' / (name + '.ml')).read_text()
            generated = cold_replay.instrument(source, name)
            restored = generated.replace('\nneeds "ntt-bounds/tap.ml";;', '')
            restored = restored[:restored.rindex('\nntt_bounds_finish')]
            self.assertEqual(restored, source)
            probe = cold_replay.probes(source, name)
            self.assertEqual(probe.count('if hyp '), 3)
            self.assertEqual(probe.count('not (aconv (concl '), 3)
            self.assertEqual(probe.count('NTT_COLD_BINDING '), 3)
            self.assertIn('check_axioms ();;', probe)

    def test_requires_completed_claims_and_unique_bound(self):
        name = 'mlkem_tomont'
        raw = f'NTT_BOUND_RESULT {name} 256 -2653 2653\n'
        markers = [f'NTT_COLD_BINDING {name.upper()}{suffix}\n' for suffix in
                   ('_CORRECT', '_SUBROUTINE_CORRECT', '_SUBROUTINE_SAFE')]
        good = raw + ''.join(markers) + f'NTT_COLD_PASS {name} 3 0\n'
        self.assertEqual(cold_replay.judge(good, name), (256, -2653, 2653))
        for bad in (raw, good.replace(markers[1], ''), good + markers[0],
                    good + raw, good.replace('3 0', '3 1'),
                    good + 'Fatal error: exception Failure("proof failed")\n'):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                cold_replay.judge(bad, name)

    def test_reduction_requires_complete_unique_calculation(self):
        good = ('NTT_REDUCTION_WRAPPED_NODES 4\n'
                'NTT_REDUCTION_RESULT late-v21 64 -32768 32767 26624\n'
                'NTT_COLD_REDUCTION_PASS 0\n')
        self.assertEqual(cold_replay.judge_reduction(good), (-32768, 32767, 4))
        for bad in (good.replace('NTT_COLD_REDUCTION_PASS 0\n', ''),
                    good + 'NTT_REDUCTION_WRAPPED_NODES 4\n',
                    good.replace('64', '63'), good.replace('-32768', '32768')):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                cold_replay.judge_reduction(bad)

    def test_inverse_accepts_combined_reduction_marker(self):
        name = 'mlkem_intt'
        raw = f'NTT_BOUND_RESULT {name} 256 -26624 26624\n'
        raw += ''.join(f'NTT_COLD_BINDING {name.upper()}{suffix}\n' for suffix in
                       ('_CORRECT', '_SUBROUTINE_CORRECT', '_SUBROUTINE_SAFE'))
        raw += f'NTT_COLD_REDUCTION_PASS 0\nNTT_COLD_PASS {name} 3 0\n'
        self.assertEqual(cold_replay.judge(raw, name), (256, -26624, 26624))
        with self.assertRaises(ValueError):
            cold_replay.judge(raw.replace('mlkem_intt', 'mlkem_tomont'), 'mlkem_tomont')

    def test_reducer_compares_centered_observation_to_centered_warm_value(self):
        warm = dict(lower='-1664', upper='1664')
        self.assertEqual(cold_replay.comparison(warm, -1664, 1664), 'PASS (same number)')
        self.assertEqual(cold_replay.comparison(warm, -1665, 1665), 'PASS (NUMBER CHANGED)')

    def test_collect_repairs_summary_without_replaying_and_refuses_missing_exit(self):
        name = 'mlkem_tomont'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generated = root / 'ntt-bounds/generated'
            generated.mkdir(parents=True)
            proofs = root / 'arm/proofs'
            proofs.mkdir(parents=True)
            for file in ('tap.ml', 'intt_reduction.ml'):
                (generated.parent / file).write_bytes((bounds.HERE / file).read_bytes())
            source = (bounds.ROOT / 'arm/proofs' / (name + '.ml')).read_text()
            (proofs / (name + '.ml')).write_text(source)
            (generated / (name + '.ml')).write_text(cold_replay.instrument(source, name))
            (generated / (name + '_cold.ml')).write_text(cold_replay.entry_source(source, name))
            receipts = root / 'receipts'
            receipts.mkdir()
            receipt = receipts / (name + '.receipt.md')
            receipt.write_text('FAIL (old summary): mlkem_tomont; cold —; elapsed 1.0 s; exit 0\n\n'
                               's2n-bignum s2n\nHOL Light hol\n')
            raw = f'NTT_BOUND_RESULT {name} 256 -2653 2653\n'
            raw += ''.join(f'NTT_COLD_BINDING {name.upper()}{suffix}\n' for suffix in
                           ('_CORRECT', '_SUBROUTINE_CORRECT', '_SUBROUTINE_SAFE'))
            raw += f'NTT_COLD_PASS {name} 3 0\n'
            (receipts / (name + '.log')).write_text(raw)
            args = type('Args', (), dict(checkout=root, hol=root, run_root=receipts,
                                         report=root / 'report.md', timeout=10800))()
            with patch.object(cold_replay, 'validate_inputs', return_value=('s2n', 'hol')), \
                 patch.object(cold_replay, 'ORDER', [name]), \
                 patch.object(cold_replay, 'execute') as execute, \
                 patch.object(cold_replay, 'report'), contextlib.redirect_stdout(io.StringIO()):
                cold_replay.collect(args)
                execute.assert_not_called()
                self.assertTrue(receipt.read_text().startswith('PASS (same number)'))
                receipt.write_text(receipt.read_text().replace('; exit 0', ''))
                with self.assertRaisesRegex(ValueError, 'missing terminal exit'):
                    cold_replay.collect(args)

    def test_refuses_existing_attempt_instead_of_restarting(self):
        with tempfile.TemporaryDirectory() as directory:
            args = type('Args', (), dict(checkout=Path(directory), hol=Path(directory),
                                         run_root=Path(directory)))()
            with self.assertRaisesRegex(ValueError, 'inspect that attempt'):
                cold_replay.replay(args)

    def test_timeout_kills_and_reaps_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            code = cold_replay.execute([sys.executable, '-c', 'import time; time.sleep(60)'],
                                       directory, Path(directory) / 'log', 0.02, os.environ)
            self.assertEqual(code, 124)


if __name__ == '__main__':
    unittest.main()
