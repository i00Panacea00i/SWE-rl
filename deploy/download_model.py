"""Bounded Hugging Face resume with pinned revision and streaming hash verification."""
import argparse
import hashlib
import json
import time
from pathlib import Path


def event(name, **fields):
    print(json.dumps({'event': name, 'time': time.time(), **fields}), flush=True)


def retry(operation, label, attempts=5, sleep=time.sleep):
    import requests
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except requests.RequestException as exc:
            response = getattr(exc, 'response', None)
            status = getattr(response, 'status_code', None)
            transient = status is None or status in (408, 429, 500, 502, 503, 504)
            if not transient or attempt == attempts:
                event('download_failed', file=label, exception=type(exc).__name__, status=status)
                raise
            delay = min(5 * 2 ** (attempt - 1), 60)
            event('transport_retry', file=label, attempt=attempt, exception=type(exc).__name__,
                  status=status, wait_seconds=delay)
            sleep(delay)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    from huggingface_hub import HfApi, hf_hub_download

    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--output', required=True)
    args = ap.parse_args()
    root = Path(args.output)
    root.mkdir(parents=True, exist_ok=True)
    pin = root / '.download-revision.json'
    existing_pin = json.loads(pin.read_text()) if pin.exists() else {}
    if existing_pin and existing_pin.get('repo') != args.repo:
        raise RuntimeError('Model directory belongs to a different repository')
    api = HfApi()
    info = retry(lambda: api.model_info(args.repo, revision=existing_pin.get('revision', 'main'),
                                        files_metadata=True), 'repository_metadata')
    revision = info.sha
    pin.write_text(json.dumps({'repo': args.repo, 'revision': revision}, indent=2))
    entries = {entry.rfilename: entry for entry in info.siblings}
    event('revision_pinned', repo=args.repo, revision=revision)
    verified = {}

    def download(name):
        entry = entries[name]
        event('file_start', file=name, expected_bytes=entry.size)
        path = Path(retry(lambda: hf_hub_download(args.repo, name, revision=revision,
                                                local_dir=str(root)), name))
        if entry.size is None or path.stat().st_size != entry.size:
            raise RuntimeError(f'Size verification failed: {name}')
        lfs = entry.lfs
        actual = sha256(path)
        expected = getattr(lfs, 'sha256', None) if lfs is not None else None
        if isinstance(lfs, dict):
            expected = lfs.get('sha256')
        if expected:
            if actual != expected:
                raise RuntimeError(f'SHA256 verification failed: {name}; keeping file for diagnosis')
        elif entry.blob_id:
            digest = hashlib.sha1(f'blob {entry.size}\0'.encode())
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            if digest.hexdigest() != entry.blob_id:
                raise RuntimeError(f'Git blob verification failed: {name}')
        else:
            raise RuntimeError(f'No authoritative checksum for {name}')
        verified[name] = {'bytes': entry.size, 'sha256': actual}
        event('file_verified', file=name, bytes=entry.size)
        return path

    index_path = download('model.safetensors.index.json')
    index = json.loads(index_path.read_text())
    shards = sorted(set(index['weight_map'].values()))
    for name in shards:
        if Path(name).name != name or not name.endswith('.safetensors'):
            raise RuntimeError(f'Unexpected shard path: {name}')
        download(name)
    small = ['config.json', 'generation_config.json', 'tokenizer_config.json',
             'tokenizer.json', 'vocab.json', 'merges.txt', 'special_tokens_map.json',
             'added_tokens.json', 'chat_template.jinja']
    for name in small:
        if name in entries:
            download(name)
    for required in ('config.json', 'tokenizer_config.json', 'tokenizer.json'):
        if required not in verified:
            raise RuntimeError(f'Missing required model asset: {required}')
    result = {'download_complete': True, 'repo': args.repo, 'revision': revision,
              'shards': len(shards), 'files': verified}
    target = root / '.download-verified.json'
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(result, indent=2))
    temporary.replace(target)
    event('download_verified', shards=len(shards), bytes=sum(f['bytes'] for f in verified.values()))


if __name__ == '__main__':
    main()
