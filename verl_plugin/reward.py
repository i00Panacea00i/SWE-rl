"""Consume only trusted judge output supplied by SWEAgentLoop."""
import math


def compute_score(data_source, solution_str, ground_truth, extra_info=None, **kwargs):
    result = (extra_info or {}).get("swe_evaluation")
    if not isinstance(result, dict) or result.get("instance_id") != ground_truth:
        raise ValueError("Trusted SWE evaluation is missing; no text-based reward fallback")
    reward = float(result["reward"])
    if not math.isfinite(reward) or not 0 <= reward <= 1:
        raise ValueError("Invalid execution reward")
    return {"score": reward, "acc": float(result["resolved"])}
