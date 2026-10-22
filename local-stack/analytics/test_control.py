"""Offline regression checks for the RFC qualification gates."""
import json
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


class StagedAvroTests(unittest.TestCase):
    def inspect(self, *, missing=False, extra=False, pii=False, legacy=False):
        artifacts = {}
        for db, tables in control.ALLOW.items():
            for table, columns in tables.items():
                prefix = 'analytics' if legacy else 'analytics_service'
                key = f'clone_{prefix}_{db}_public_{table}_fixture/part.avro'
                artifacts[key] = list(columns)
        if missing:
            artifacts.pop(next(iter(artifacts)))
        descriptions = []

        def query(sql):
            key = next(key for key in artifacts if key in sql)
            if sql.startswith('DESCRIBE TABLE'):
                descriptions.append(key)
                columns = artifacts[key] + ['_peerdb_version']
                if extra:
                    columns.append('customer_email')
                return '\n'.join(f'{column}_{i}\tString' for i, column in enumerate(columns))
            return 'RFC0030_FORBIDDEN_PII' if pii else '{}'

        objects = {'Contents': [{'Key': key} for key in artifacts]}
        with patch.object(control, 'compose', return_value=json.dumps(objects)), \
                patch.object(control, 'ch', side_effect=query):
            control.inspect_staged_avro()
        return descriptions

    def test_current_mirrors_inspect_all_ten_snapshot_schemas(self):
        self.assertEqual(len(self.inspect()), 10)

    def test_missing_snapshot_fails_coverage(self):
        with self.assertRaisesRegex(RuntimeError, 'coverage incomplete'):
            self.inspect(missing=True)

    def test_legacy_prefix_does_not_satisfy_current_coverage(self):
        with self.assertRaisesRegex(RuntimeError, 'coverage incomplete'):
            self.inspect(legacy=True)

    def test_unlisted_column_fails_even_without_pii_marker(self):
        with self.assertRaisesRegex(RuntimeError, 'unexpected Avro column'):
            self.inspect(extra=True)

    def test_pii_marker_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'PII'):
            self.inspect(pii=True)


if __name__ == '__main__':
    unittest.main()
