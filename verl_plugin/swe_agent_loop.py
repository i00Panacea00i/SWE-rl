"""On-policy SWE loop using AGS and verl's continuous-token helpers."""
from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from pathlib import Path

from verl.experimental.agent_loop.agent_loop import AgentLoopBase, AgentLoopOutput
from verl.utils.rollout_trace import _current_trace_attributes

from sandbox.episode import EpisodeSession, atomic_json, check_patch, evaluate_patch
from sandbox.harness import load_instances



from sandbox.action_protocol import bounded_observation, classify_operation, parse_action


class SWEAgentLoop(AgentLoopBase):
    _semaphore = None

    def __init__(self, *args, max_steps=8, action_tokens=512, observation_tokens=512,
                 sandbox_concurrency=2, system_prompt=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.instances = {i.instance_id: i for i in load_instances()}
        self.max_steps = int(max_steps)
        self.action_tokens = int(action_tokens)
        self.observation_tokens = int(observation_tokens)
        # 训练纪律提示：非空时覆写数据集 system 消息（prompt 策略集中在 agent 配置，数据保持可复用）
        self.system_prompt = (system_prompt or "").strip() or None
        if SWEAgentLoop._semaphore is None:
            SWEAgentLoop._semaphore = asyncio.Semaphore(int(sandbox_concurrency))

    async def run(self, sampling_params, priority=0, **kwargs):
        async with SWEAgentLoop._semaphore:
            return await self._episode(sampling_params, int(priority), **kwargs)

    async def _episode(self, sampling_params, priority, **kwargs):
        info = kwargs["extra_info"]
        iid = info["instance_id"]
        inst = self.instances[iid]
        if info["tool_name"] != inst.tool_name:
            raise ValueError("Untrusted sandbox route")
        episode_id = uuid.uuid4().hex
        attrs = _current_trace_attributes()
        is_eval = bool(self.config.trainer.val_only) or attrs.get("validate", False) or info.get("split") == "eval"
        phase = "eval" if is_eval else "train"
        step = int(kwargs.get("global_steps", attrs.get("step", -1)))
        if step < 0:
            raise RuntimeError("Missing policy training-step metadata")
        run_id = os.environ.get("SWE_RUN_ID", "round0")
        trace_root = Path(os.environ.get("SWE_TRACE_DIR", "/mnt/cfs/swe-rl/traces"))
        directory = trace_root / run_id / phase / f"step-{step}" / iid / episode_id
        directory.mkdir(parents=True, exist_ok=False)
        record = {
            "schema_version": 1, "run_id": run_id, "episode_id": episode_id,
            "instance_id": iid, "tool_name": inst.tool_name,
            "model": str(self.config.actor_rollout_ref.model.path),
            "base_commit": inst.base_commit, "phase": phase, "global_step": step,
            "split": info.get("split"), "started_at": time.time(),
            "agent_kind": "model_generated", "gold_patch_visible": False, "steps": [],
        }
        # rollout 侧预置目标测试：让 Agent 能跑测试拿到执行反馈（奖励仍按 f2p/total 计算）
        session = EpisodeSession(inst, directory / "agent", timeout=1800,
                                 apply_test_patch=True)
        messages = list(kwargs["raw_prompt"])
        if self.system_prompt:
            # 行动纪律提示覆写（数据集 system 消息替换；不改数据集本身，保持可复用与可比性）
            if messages and messages[0].get("role") == "system":
                messages[0] = {**messages[0], "content": self.system_prompt}
            else:
                messages.insert(0, {"role": "system", "content": self.system_prompt})
        runtime_ids = await self.ct_build_initial_tokens(messages)
        mask, logprobs = [], []
        budget = int(self.rollout_config.response_length)
        operations = 0
        metrics = {"generate_sequences": 0.0, "tool_calls": 0.0, "compute_score": 0.0}
        model_extra = {}
        final = None
        closed = False
        try:
            await asyncio.to_thread(session.start)
            record["sandbox_id"] = session.sandbox_id
            record["sandbox_mode"] = session.sandbox_mode
            record["fingerprint"] = session.fingerprint
            for turn in range(self.max_steps):
                remaining = budget - len(mask) - 32
                if remaining < 64:
                    record["stop_reason"] = "token_budget"
                    break
                params = dict(sampling_params)
                params["max_tokens"] = min(self.action_tokens, remaining)
                t0 = time.monotonic()
                generated = await self.server_manager.generate(
                    request_id=episode_id, prompt_ids=runtime_ids,
                    sampling_params=params, priority=priority)
                metrics["generate_sequences"] += time.monotonic() - t0
                if not generated.token_ids:
                    raise RuntimeError("Model returned no action tokens")
                merged, mask, logprobs = await self.ct_merge_assistant_token(
                    runtime_ids, generated.token_ids, mask,
                    logprobs if (logprobs or generated.log_probs) else None,
                    assistant_logprobs=generated.log_probs if generated.log_probs else None)
                runtime_ids = merged.token_ids
                action = self.tokenizer.decode(generated.token_ids, skip_special_tokens=True).strip()
                model_extra.update(generated.extra_fields or {})
                messages.append({"role": "assistant", "content": action})
                command, submit_requested, done = "", False, False
                t0 = time.monotonic()
                try:
                    command, submit_requested = parse_action(action)
                    if command:
                        code, out, err = await asyncio.to_thread(session.run, command, 60)
                        observation = f"exit_code={code}\n{out}{err}"
                        operations += 1
                    else:
                        code, observation = 0, ""
                    if submit_requested:
                        if operations < 3:
                            observation += ("\nBefore submitting, inspect the affected source, edit it, "
                                            "and run the relevant tests in separate turns (at least 3 operations). "
                                            "Do not modify documentation just to add operations.")
                        else:
                            done = True
                            observation += "\nSubmission received."
                except ValueError as exc:
                    code, observation = 2, f"Action format error; no command executed: {exc}"
                metrics["tool_calls"] += time.monotonic() - t0
                if command:
                    kind = classify_operation(command)
                elif submit_requested:
                    kind = "submit"
                else:
                    kind = "format_error"
                record["steps"].append({
                    "step": turn + 1, "kind": kind, "action": action,
                    "executed_command": command,
                    "observation": observation, "reward": 0.0, "done": done,
                    "exit_code": code, "action_token_ids": generated.token_ids,
                })
                atomic_json(directory / "episode.json", record)
                if done:
                    record["stop_reason"] = "submit"
                    break
                if turn + 1 >= self.max_steps:
                    record["stop_reason"] = "step_budget"
                    break
                available = budget - len(mask) - 256 - 64
                if available < 64:
                    record["stop_reason"] = "token_budget"
                    break
                obs = bounded_observation(self.tokenizer, observation,
                                          min(self.observation_tokens, available))
                previous_messages = list(messages)
                messages.append({"role": "user", "content": obs})
                merged, new_mask, new_logprobs = await self.ct_merge_context_msg(
                    previous_messages, messages, runtime_ids, mask,
                    logprobs if logprobs else None)
                if len(new_mask) >= budget:
                    record["stop_reason"] = "token_budget"
                    break
                record["steps"][-1]["observation_in_context"] = obs
                runtime_ids, mask, logprobs = merged.token_ids, new_mask, new_logprobs
            if not mask:
                raise RuntimeError("No generated tokens in episode")
            t0 = time.monotonic()
            try:
                patch = await asyncio.to_thread(session.export_patch)
                check_patch(patch)
                patch_error = None
            except ValueError as exc:
                patch, patch_error = "", str(exc)
            (directory / "candidate.patch").write_text(patch, encoding="utf-8")
            # 完整操作记录：模型相对原始快照实际改动的文件清单（与补丁互证；
            # 该命令本身也会进入 execution.json）。
            try:
                record["changed_files"] = await asyncio.to_thread(session.changed_files)
            except RuntimeError:
                record["changed_files"] = None
            await asyncio.to_thread(session.close)
            closed = True
            if patch_error:
                final = {"instance_id": iid, "reward": 0.0, "resolved": False,
                         "rejection": patch_error, "failure_kind": "candidate_rejected"}
            else:
                try:
                    final = await asyncio.to_thread(evaluate_patch, inst, patch, directory / "judge")
                except Exception as exc:  # 判分失败不允许让整轮训练崩溃
                    # 判分器残余异常（基础设施/对照失败等）降级为 0 分并保留审计
                    # 线索：抛出会丢失该样本（批次被迫上采样），且 Ray 打印
                    # Traceback 会触发流水线 fatal 检测停止整轮训练。
                    final = {"instance_id": iid, "reward": 0.0, "resolved": False,
                             "rejection": f"{type(exc).__name__}: {exc}"[:500],
                             "failure_kind": "judge_error"}
                    print(json.dumps({
                        "event": "swe_judge_error", "episode": str(directory),
                        "instance_id": iid, "phase": phase, "global_step": step,
                        "error": f"{type(exc).__name__}: {exc}"[:300]}), flush=True)
            metrics["compute_score"] = time.monotonic() - t0
            record["final"] = final
            record["shell_operations"] = operations
            record["meets_min_steps"] = operations >= 3
            # 结构化 tracing 汇总：各操作类别（读文件/编辑/执行命令/跑测试）计数
            kind_counts: dict[str, int] = {}
            for s in record["steps"]:
                k = s.get("kind", "unknown")
                kind_counts[k] = kind_counts.get(k, 0) + 1
            record["operation_kinds"] = kind_counts
            record["finished_at"] = time.time()
            record["steps"][-1].update(reward=final["reward"], done=True)
            # Terminal scoring belongs to the driver, not an unrecorded model action.
            record["steps"][-1]["final_test_result"] = final
            response_ids = runtime_ids[-len(mask):]
            prompt_ids = runtime_ids[:-len(mask)]
            if len(response_ids) > budget:
                raise RuntimeError("Continuous-token response exceeds configured budget")
            record["token_alignment"] = {
                "prompt_ids": prompt_ids, "response_ids": response_ids,
                "response_mask": mask, "response_logprobs": logprobs,
            }
            atomic_json(directory / "episode.json", record)
            print(json.dumps({"event": "swe_episode_complete", "episode": str(directory),
                              "instance_id": iid, "phase": phase, "global_step": step,
                              "operations": operations, "reward": final["reward"],
                              "resolved": final["resolved"]}), flush=True)
            model_extra.update({
                "swe_evaluation": final, "trace_path": str(directory / "episode.json"),
                "reward_extra_info": {"acc": float(final["resolved"]),
                                      "swe_reward": float(final["reward"]),
                                      "operations": operations},
            })
            return AgentLoopOutput(
                prompt_ids=prompt_ids, response_ids=response_ids, response_mask=mask,
                response_logprobs=logprobs if logprobs else None,
                reward_score=float(final["reward"]), num_turns=len(messages),
                metrics=metrics, extra_fields=model_extra)
        except Exception as exc:
            record["error"] = {"type": type(exc).__name__, "message": str(exc)[:1500]}
            atomic_json(directory / "episode.json", record)
            raise
        finally:
            if not closed:
                await asyncio.to_thread(session.close)
