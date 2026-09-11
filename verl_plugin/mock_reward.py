"""冒烟②用 mock 奖励：验证 LoRA×MoE 训练路径，不看效果。"""


def mock_reward(data_source, solution_str, ground_truth, extra_info=None, **kwargs):
    # 简单确定性信号：含 SUBMIT 得 1，含 bash 得 0.5，否则 0.1
    if "SUBMIT" in solution_str:
        return 1.0
    if "test" in solution_str or "ls" in solution_str:
        return 0.5
    return 0.1
