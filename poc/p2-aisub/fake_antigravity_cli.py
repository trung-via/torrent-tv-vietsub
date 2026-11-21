"""Offline test-only structured-output runner for the Antigravity provider boundary."""
from __future__ import annotations

import json
import subprocess


def target_ids_from_cli_input(data: str) -> tuple[int, ...]:
    message = json.loads(data)
    target = json.loads(message["message"]["content"].split("\n", 1)[1])["target"]
    return tuple(cue["id"] for cue in target)


def cli_result(ids: tuple[int, ...], *, text_prefix: str = "Câu dịch thử",
               status: str = "SUCCESS") -> str:
    return json.dumps({"event": "result", "result": {
        "status": status,
        "structured_output": {"translations": [
            {"id": cue_id, "vi": f"{text_prefix} {cue_id}"} for cue_id in ids
        ]},
    }}, ensure_ascii=False) + "\n"


class FakeAntigravity:
    """Mock CLI execution without account, network or paid model calls."""

    def __init__(self, *, text_prefix: str = "Câu dịch thử"):
        self.calls: list[tuple[int, ...]] = []
        self.text_prefix = text_prefix

    def __call__(self, args, **kwargs):
        ids = target_ids_from_cli_input(kwargs["input"])
        self.calls.append(ids)
        return subprocess.CompletedProcess(
            args, 0, stdout=cli_result(ids, text_prefix=self.text_prefix), stderr="")
