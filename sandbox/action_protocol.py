"""Parse the shell transport without guessing or rewriting script contents."""
import re


def parse_action(action: str) -> tuple[str, bool]:
    text = action.strip()
    if not text or "\x00" in text:
        raise ValueError("Empty or invalid action; return one complete bash script")
    outer_submit = False
    if text.startswith("```"):
        match = re.fullmatch(r"```(?:bash|sh)?\n(.*?)\n```(?:\s*\n(SUBMIT))?", text, re.S)
        if not match:
            raise ValueError("Incomplete code fence; return a complete bash block without commentary")
        text = match.group(1)
        if "```" in text:
            raise ValueError("Multiple or nested code blocks; return one complete bash block per turn")
        outer_submit = bool(match.group(2))
    elif "```" in text:
        raise ValueError("Mixed prose/code fences; return only the complete bash command")
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
