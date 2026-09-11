"""Patch only an isolated verl source copy, never the shared original installation."""
import argparse
import ast
import hashlib
import json
import shutil
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', required=True)
    ap.add_argument('--destination', required=True)
    args = ap.parse_args()
    source, destination = Path(args.source).resolve(), Path(args.destination).resolve()
    if source == destination or destination.exists():
        raise RuntimeError('Destination must be a new, isolated source snapshot')
    shutil.copytree(source, destination,
                    ignore=shutil.ignore_patterns('.git', '__pycache__', '*.pyc'))
    path = destination / 'verl/utils/fsdp_utils.py'
    original = path.read_text()
    tree = ast.parse(original)
    node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and
                n.name == 'layered_summon_lora_params')
    lines = original.splitlines(keepends=True)
    replacement = ('def layered_summon_lora_params(fsdp_module) -> OrderedDict:\n'
                   '    from verl_plugin.adapter_export import export_fsdp1_lora\n'
                   '    return export_fsdp1_lora(fsdp_module)\n')
    lines[node.lineno - 1:node.end_lineno] = [replacement]
    text = ''.join(lines)
    start = text.index('            if not lora_params:\n', text.index('def collect_lora_params('))
    end = text.index('        else:\n            with FSDP.summon_full_params', start)
    text = text[:start] + ('            if not lora_params:\n'
                           '                raise RuntimeError("Empty bounded LoRA export; no full-model fallback")\n') + text[end:]
    ast.parse(text)
    path.write_text(text)
    proof = {'file': 'verl/utils/fsdp_utils.py',
             'before_sha256': hashlib.sha256(original.encode()).hexdigest(),
             'after_sha256': hashlib.sha256(text.encode()).hexdigest(),
             'source': str(source), 'destination': str(destination)}
    (destination / 'adapter-export-patch.json').write_text(json.dumps(proof, indent=2))
    print(json.dumps(proof), flush=True)


if __name__ == '__main__':
    main()
