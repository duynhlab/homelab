"""Boundary checks for the RFC's freshness authority; no containers required."""
import unittest
from unittest.mock import patch

import control

from control import freshness_state


class FreshnessTests(unittest.TestCase):
    def test_exact_thresholds_and_oldest_source(self):
        self.assertEqual(freshness_state([0, 30, 120]), 'healthy')
        self.assertEqual(freshness_state([0, 120.1, 30]), 'stale')
        self.assertEqual(freshness_state([300, 0, 30]), 'stale')
        self.assertEqual(freshness_state([0, 0, 300.1]), 'unavailable')

    def test_unknown_missing_and_invalid_authorities_fail_closed(self):
        for values in [[], [0, 0], [0, 0, None], [0, -1, 0],
                       [0, float('nan'), 0], [0, 0, float('inf')]]:
            with self.subTest(values=values):
                self.assertEqual(freshness_state(values), 'unavailable')


class BootstrapTests(unittest.TestCase):
    def test_changed_contract_rejected_before_source_mutation(self):
        def database(db, sql):
            if sql.startswith('SELECT fingerprint'):
                return 'old-contract'
            return ''
        with patch.object(control, 'api', return_value={}), \
                patch.object(control, 'source_mappings', return_value={}), \
                patch.object(control, 'pg', side_effect=database), \
                patch.object(control, 'source_setup') as mutate, \
                patch.object(control, 'fixtures') as fixtures:
            with self.assertRaisesRegex(RuntimeError, 'contract changed'):
                control.bootstrap()
            mutate.assert_not_called()
            fixtures.assert_not_called()


if __name__ == '__main__':
    unittest.main()
