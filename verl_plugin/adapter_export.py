"""Bounded FSDP1 plain-LoRA export. No root-recursive gather or full-model fallback."""
from collections import OrderedDict
import json


def clean_name(name):
    return '.'.join(part for part in name.split('.') if part and part != '_fsdp_wrapped_module')


def export_fsdp1_lora(root, max_unit_bytes=256 * 1024 * 1024):
    import torch
    from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
    from peft.utils.save_and_load import get_peft_model_state_dict

    if not isinstance(root, FSDP):
        raise TypeError('Bounded adapter export currently requires FSDP1')
    peft_model = root.module
    configs = getattr(peft_model, 'peft_config', {})
    if set(configs) != {'default'}:
        raise ValueError('Exactly one default adapter is required')
    config = configs['default']
    if (config.bias != 'none' or getattr(config, 'modules_to_save', None) or
            getattr(config, 'use_dora', False) or str(config.peft_type).split('.')[-1] != 'LORA'):
        raise ValueError('Only plain LoRA bias=none without modules_to_save/DoRA is supported')
    units, expected = [], {}
    for prefix, unit in root.named_modules():
        if not isinstance(unit, FSDP):
            continue
        handle = unit._handle
        if handle is None:
            continue
        flat = handle.flat_param
        fqns = getattr(flat, '_fqns', None)
        shapes = getattr(flat, '_shapes', None)
        if fqns is None or shapes is None or len(fqns) != len(shapes):
            raise RuntimeError('Unsupported PyTorch FSDP flat-parameter metadata')
        owned = []
        full_numel = 0
        for local_name, shape in zip(fqns, shapes):
            full_numel += shape.numel()
            name = clean_name(prefix + '.' + local_name)
            if '.lora_A.default.' not in name and '.lora_B.default.' not in name:
                continue
            if name in expected:
                raise RuntimeError(f'Duplicate adapter ownership: {name}')
            expected[name] = tuple(shape)
            owned.append((local_name, name, tuple(shape)))
        if not owned:
            continue
        size = full_numel * flat.element_size()
        if size > max_unit_bytes:
            raise RuntimeError(f'Adapter FSDP unit exceeds gather cap: {prefix}: {size} bytes')
        units.append((unit, owned, size))
    if not expected:
        raise RuntimeError('No adapter metadata found; full-model fallback is forbidden')
    for name in expected:
        peer = name.replace('.lora_A.', '.lora_B.') if '.lora_A.' in name else name.replace('.lora_B.', '.lora_A.')
        if peer not in expected:
            raise RuntimeError(f'Unpaired LoRA parameter: {name}')
    raw = OrderedDict()
    for unit, owned, _ in units:
        with FSDP.summon_full_params(unit, recurse=False, writeback=False,
                                    rank0_only=False, offload_to_cpu=False):
            for local_name, full_name, shape in owned:
                parameter = unit.module.get_parameter(local_name)
                if tuple(parameter.shape) != shape:
                    raise RuntimeError(f'Unsharded adapter shape mismatch: {full_name}')
                raw[full_name] = parameter.detach().to(device='cpu', copy=True)
    if set(raw) != set(expected):
        raise RuntimeError('Incomplete adapter export')
    result = get_peft_model_state_dict(peft_model, state_dict=raw,
                                       adapter_name='default', save_embedding_layers=False)
    normalized = {name.replace('.default.', '.'): shape for name, shape in expected.items()}
    if set(result) != set(normalized):
        raise RuntimeError('PEFT adapter keys differ from complete FSDP inventory')
    for name, tensor in result.items():
        if tuple(tensor.shape) != normalized[name] or tensor.device.type != 'cpu':
            raise RuntimeError(f'Invalid exported adapter: {name}')
    print('BOUNDED_LORA_EXPORT ' + json.dumps({
        'rank': torch.distributed.get_rank(), 'units': len(units), 'tensors': len(result),
        'max_unit_bytes': max(size for _, _, size in units),
        'adapter_bytes': sum(t.numel() * t.element_size() for t in result.values()),
    }), flush=True)
    return OrderedDict(result)
