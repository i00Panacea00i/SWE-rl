"""Two-GPU numerical regression for bounded FSDP1 LoRA export; no model download."""
import functools
import json
import os
from unittest.mock import patch

import torch
import torch.distributed as dist
from peft import LoraConfig, get_peft_model
from peft.utils.save_and_load import get_peft_model_state_dict
from torch import nn
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
from torch.distributed.fsdp.wrap import lambda_auto_wrap_policy

from verl_plugin.adapter_export import export_fsdp1_lora


class TinyModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.first = nn.Linear(64, 64, bias=False)
        self.second = nn.Linear(64, 64, bias=False)

    def forward(self, x):
        return self.second(torch.tanh(self.first(x)))


def main():
    dist.init_process_group('nccl')
    rank = int(os.environ['LOCAL_RANK'])
    torch.cuda.set_device(rank)
    device = torch.device('cuda', rank)
    for use_orig in (False, True):
        torch.manual_seed(37)
        model = get_peft_model(TinyModel(), LoraConfig(r=4, lora_alpha=8,
                                                      target_modules=['first', 'second'], bias='none'))
        policy = functools.partial(lambda_auto_wrap_policy,
                                   lambda_fn=lambda m: isinstance(m, nn.Linear) and m.weight.requires_grad)
        model = FSDP(model.to(device), auto_wrap_policy=policy, use_orig_params=use_orig,
                     device_id=device, sync_module_states=True)
        opt = torch.optim.SGD(model.parameters(), lr=0.1)
        previous = None
        for step in range(2):
            opt.zero_grad()
            loss = model(torch.randn(4, 64, device=device)).square().mean()
            loss.backward()
            opt.step()
            # Full gather is confined to this tiny numerical reference, never production.
            with FSDP.summon_full_params(model, writeback=False):
                reference = {name: value.detach().cpu().clone()
                             for name, value in get_peft_model_state_dict(model.module).items()}
            original_summon = FSDP.summon_full_params
            calls = []

            def bounded(unit, **kwargs):
                assert kwargs.get('recurse') is False
                assert kwargs.get('offload_to_cpu') is False
                assert kwargs.get('rank0_only') is False
                calls.append(unit)
                return original_summon(unit, **kwargs)

            with patch.object(FSDP, 'summon_full_params', side_effect=bounded):
                result = export_fsdp1_lora(model)
            assert calls and set(result) == set(reference)
            for name in reference:
                torch.testing.assert_close(result[name], reference[name], rtol=0, atol=0)
            assert any(torch.count_nonzero(v).item() for n, v in result.items() if 'lora_B' in n)
            if previous is not None:
                assert any(not torch.equal(result[n], previous[n]) for n in result)
            previous = {k: v.clone() for k, v in result.items()}
            repeated = export_fsdp1_lora(model)
            for name in result:
                torch.testing.assert_close(repeated[name], result[name], rtol=0, atol=0)
            print(json.dumps({'adapter_export_test': 'passed', 'rank': rank, 'use_orig_params': use_orig,
                              'step': step, 'tensors': len(result), 'summon_calls': len(calls)}), flush=True)
        dist.barrier()
        del model, opt
        torch.cuda.empty_cache()
    dist.destroy_process_group()


if __name__ == '__main__':
    main()
