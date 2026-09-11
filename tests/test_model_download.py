import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

import requests

from deploy.download_model import retry, sha256


class DownloadTests(unittest.TestCase):
    def test_interrupted_stream_is_retried(self):
        operation = Mock(side_effect=[requests.exceptions.ChunkedEncodingError('interrupted'), 'ok'])
        wait = Mock()
        self.assertEqual(retry(operation, 'shard', sleep=wait), 'ok')
        self.assertEqual(operation.call_count, 2)
        wait.assert_called_once_with(5)

    def test_auth_errors_do_not_retry(self):
        response = requests.Response()
        response.status_code = 403
        operation = Mock(side_effect=requests.HTTPError(response=response))
        wait = Mock()
        with self.assertRaises(requests.HTTPError):
            retry(operation, 'shard', sleep=wait)
        self.assertEqual(operation.call_count, 1)
        wait.assert_not_called()

    def test_retry_is_bounded(self):
        operation = Mock(side_effect=requests.Timeout('network timeout'))
        with self.assertRaises(requests.Timeout):
            retry(operation, 'shard', attempts=3, sleep=Mock())
        self.assertEqual(operation.call_count, 3)

    def test_hash_stream(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'file'
            p.write_bytes(b'abc')
            self.assertEqual(sha256(p), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')


if __name__ == '__main__':
    unittest.main()
