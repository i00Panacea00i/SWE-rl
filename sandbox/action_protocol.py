"""Parse the shell transport without guessing or rewriting script contents."""
import re


def parse_action(action: str) -> tuple[str, bool]:
    """解析动作（宽松模式）：含 fenced block 时提取第一个块，容忍前后说明性文字。

    训练目标是"动作可执行 + 判分严格"，因此这里只做无损提取：
      1) 含 ``` 块 → 取第一个块的脚本内容（模型先思考再给命令的常见形态）
      2) 无 ``` 块 → 整段视为脚本（裸命令路径）
    块后单独一行 SUBMIT 仍识别为提交信号。
    """
    raw = action.strip()
    if not raw or "\x00" in raw:
        raise ValueError("Empty or invalid action; return one complete bash script")
    outer_submit = False
    if "```" in raw:
        match = re.search(r"```(?:bash|sh)?[ \t]*\n(.*?)\n[ \t]*```", raw, re.S)
        if not match:
            raise ValueError("Incomplete code fence; return a complete bash block without commentary")
        text = match.group(1)
        if "```" in text:
            raise ValueError("Multiple or nested code blocks; return one complete bash block per turn")
        if raw[match.end():].strip() == "SUBMIT":
            outer_submit = True
    else:
        text = raw
    if text.strip() == "SUBMIT":
        return "", True
    lines = text.splitlines()
    # A heredoc delimiter may itself be SUBMIT. Never interpret script data as control.
    has_heredoc = bool(re.search(r"(?<!<)<<(?!=|<)", text))
    if not has_heredoc and lines and lines[-1].strip() == "SUBMIT":
        lines.pop()
        outer_submit = True
    command = "\n".join(lines).strip()
    if not command and not outer_submit:
        raise ValueError("Missing shell command")
    return command, outer_submit


# 操作归类（结构化 tracing）：读文件 / 编辑 / 执行命令 / 跑测试
_EDIT_RE = re.compile(
    r"sed\s+-i\b|\bpatch\s+-p|\bgit\s+apply\b|(?<![0-9&])>>?\s*[^&\s]|\btee\s|"
    r"python[0-9.]*\s+-\s*<<|python[0-9.]*\s+-c\s[^\n]*\bopen\([^\n]*['\"][wa]|"
    r"\btruncate\b", re.M)
_TEST_RE = re.compile(
    r"(^|[\s;&|(])(pytest|python[0-9.]*\s+-m\s+(pytest|unittest)|tox|nosetests|"
    r"runtests\.py|run_tests)([\s/;|&)]|$)", re.M)
_INSPECT_RE = re.compile(
    r"(^|[\s;&|(])(cat|head|tail|grep|rg|ls|find|wc|sed\s+-n|diff|"
    r"git\s+(log|diff|show|status|blame)|python[0-9.]*\s+-c\b)([\s/;|&)]|$)", re.M)


def classify_operation(command: str) -> str:
    """把一条 shell 操作按意图归类：edit / test / inspect / execute。

    优先级 edit > test > inspect（edit+test 的合并命令按 edit 计；某步是否
    跑过测试可由 executed_command 与 episode 级 operation_kinds 汇总互证）。
    inspect 只在首个单管道之前判定——`cmd | tail/grep` 的尾部是输出管道，
    不改变主操作的执行语义。
    """
    text = command.strip()
    if not text:
        return "empty"
    if _EDIT_RE.search(text):
        return "edit"
    if _TEST_RE.search(text):
        return "test"
    before_pipe = re.split(r"(?<!\|)\|(?!\|)", text, maxsplit=1)[0]
    if _INSPECT_RE.search(before_pipe):
        return "inspect"
    return "execute"


def bounded_observation(tokenizer, text: str, limit: int) -> str:
    ids = tokenizer.encode(text, add_special_tokens=False)
    if len(ids) <= limit:
        return text
    marker = "\n[observation truncated; head and tail retained]\n"
    marker_ids = tokenizer.encode(marker, add_special_tokens=False)
    usable = max(0, limit - len(marker_ids))
    head = usable // 4
    tail = usable - head
    return (tokenizer.decode(ids[:head]) + marker +
            (tokenizer.decode(ids[-tail:]) if tail else ""))
