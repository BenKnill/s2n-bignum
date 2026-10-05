import os
from pathlib import Path
import sys
import tempfile
import unittest

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
