import json
import tempfile
import unittest
from pathlib import Path

from controller.report_run import summarize


class ReportingTests(unittest.TestCase):
    def write_episode(self, root, name, reward=0, iid='train-task', error=None):
        record = {'instance_id': iid, 'global_step': 1, 'phase': 'train',
                  'shell_operations': 3,
                  'final': {'reward': reward, 'resolved': reward == 1},
                  'steps': [{'action': 'x', 'observation': 'y', 'reward': 0, 'done': False},
                            {'action': 'x', 'observation': 'y', 'reward': 0, 'done': False},
                            {'action': 'x', 'observation': 'y', 'reward': reward, 'done': True}],
                  'token_alignment': {'response_ids': [1, 2, 3], 'response_mask': [1, 0, 1]}}
        if error:
            record['error'] = error
        path = root / name / 'episode.json'
        path.parent.mkdir()
        path.write_text(json.dumps(record))

    def test_real_group_variation_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_episode(root, 'a', 0)
            self.write_episode(root, 'b', 1)
            report = summarize(root, {'train': ['train-task'], 'eval': ['eval-task']}, 'pilot')
            self.assertEqual(report['informative_groups'], 1)
            self.assertEqual(report['mean_reward'], 0.5)
            self.assertFalse(report['failures'])

    def test_constant_rewards_are_not_learning_signal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_episode(root, 'a')
            self.write_episode(root, 'b')
            report = summarize(root, {'train': ['train-task'], 'eval': ['eval-task']}, 'pilot')
            self.assertEqual(report['informative_groups'], 0)

    def test_partition_and_error_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_episode(root, 'a', iid='eval-task', error={'type': 'RuntimeError'})
            report = summarize(root, {'train': ['train-task'], 'eval': ['eval-task']}, 'pilot')
            self.assertEqual(len(report['failures']), 2)


if __name__ == '__main__':
    unittest.main()
