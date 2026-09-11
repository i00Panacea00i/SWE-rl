import unittest

from sandbox.harness import normalize_django_states


class DjangoLogTests(unittest.TestCase):
    def test_concatenated_subtest_and_next_test(self):
        failed = 'test_inconsistent (module.Case)'
        passed = 'test_invalid (module.Case)'
        log = f'{failed} ... {passed} ... ok\nFAIL: {failed} [fr]\n'
        result = normalize_django_states(log, {failed + ' ... ' + passed: 'PASSED'}, [failed, passed])
        self.assertEqual(result[passed], 'PASSED')
        self.assertEqual(result[failed], 'FAILED')

    def test_failure_overrides_ok(self):
        name = 'test_one (module.Case)'
        result = normalize_django_states(f'{name} ... ok\nERROR: {name} [x]\n', {}, [name])
        self.assertEqual(result[name], 'ERROR')

    def test_missing_test_stays_missing(self):
        name = 'test_one (module.Case)'
        self.assertNotIn(name, normalize_django_states('Ran 8 tests\nOK', {}, [name]))

    def test_ambiguous_short_name_not_used(self):
        names = ['test_one (module.A)', 'test_one (module.B)']
        result = normalize_django_states('', {'test_one': 'PASSED'}, names)
        self.assertTrue(all(n not in result for n in names))


if __name__ == '__main__':
    unittest.main()
