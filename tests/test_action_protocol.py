import ast
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from sandbox.action_protocol import bounded_observation, parse_action
from sandbox.episode import EpisodeSession
from sandbox.harness import load_instances


class ActionProtocolTests(unittest.TestCase):
    def test_fences_and_submit(self):
        for action in ('```bash\necho ok\n```\nSUBMIT',
                       '```sh\necho ok\nSUBMIT\n```', 'echo ok\nSUBMIT'):
            self.assertEqual(parse_action(action), ('echo ok', True))
        self.assertEqual(parse_action('SUBMIT'), ('', True))

    def test_heredoc_is_unchanged(self):
        script = "cat <<'SUBMIT'\nThis is important text.\nSUBMIT"
        self.assertEqual(parse_action(script), (script, False))
        self.assertEqual(parse_action('```bash\n' + script + '\n```\nSUBMIT'), (script, True))

    def test_incomplete_fences_are_not_executed(self):
        for action in ('```bash\necho ok', 'explanation\n```bash\necho ok\n```',
                       '```bash\necho one\n```\n```bash\necho two\n```\nSUBMIT', ''):
            with self.assertRaises(ValueError):
                parse_action(action)

    def test_no_prose_heuristic_rewrites(self):
        action = 'echo ok\nThis is important text.'
        self.assertEqual(parse_action(action), (action, False))

    def test_observation_keeps_tail(self):
        tokenizer = SimpleNamespace(encode=lambda s, **kw: list(s), decode=lambda ids: ''.join(ids))
        result = bounded_observation(tokenizer, 'HEAD' + '.' * 900 + 'FAILED test_x', 150)
        self.assertLessEqual(len(result), 150)
        self.assertTrue(result.startswith('HEAD'))
        self.assertTrue(result.endswith('FAILED test_x'))
        self.assertIn('truncated', result)

    def test_streaming_and_syntax_guard(self):
        def run_local(cmd, **kwargs):
            cmd = cmd.replace('cd /testbed || exit 125;', 'true;')
            cmd = cmd.replace('/opt/miniconda3/envs/testbed/bin/python', sys.executable)
            proc = subprocess.run(['bash', '-c', cmd], capture_output=True, text=True, timeout=10)
            return SimpleNamespace(exit_code=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
        with tempfile.TemporaryDirectory() as tmp:
            session = EpisodeSession(load_instances(['django__django-10939'])[0], Path(tmp))
            session.sb = SimpleNamespace(commands=SimpleNamespace(run=run_local))
            marker = Path(tmp) / 'finished'
            command = f"{sys.executable} -c \"print('x'*200000)\"; printf done > {marker}; echo TAIL"
            code, out, _ = session.run(command)
            self.assertEqual(code, 0)
            self.assertTrue(marker.exists())
            self.assertIn('truncated', out)
            self.assertTrue(out.endswith('TAIL\n'))
            marker.unlink()
            code, out, _ = session.run(f"touch {marker}; cat <<EOF\nunfinished")
            self.assertEqual(code, 2)
            self.assertFalse(marker.exists())
            self.assertIn('not executed', out)

    def test_python36_drain_syntax(self):
        ast.parse(Path('sandbox/episode.py').read_text())


if __name__ == '__main__':
    unittest.main()
