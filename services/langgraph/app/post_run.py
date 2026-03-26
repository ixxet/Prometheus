from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Protocol


@dataclass(frozen=True)
class RunArtifact:
    thread_id: str
    run_id: str
    title: str | None
    input_text: str
    response_text: str | None
    require_approval: bool
    approval_decision: bool | None
    created_at: datetime
    updated_at: datetime


class SemanticMemoryProvider(Protocol):
    name: str

    def record_run(self, artifact: RunArtifact) -> None:
        """Persist semantic memory derived from a completed run."""


class ArchiveSink(Protocol):
    name: str

    def export_run(self, artifact: RunArtifact) -> None:
        """Export a human-readable artifact for a completed run."""


class NoopSemanticMemoryProvider:
    name = "none"

    def record_run(self, artifact: RunArtifact) -> None:
        del artifact


class NoopArchiveSink:
    name = "none"

    def export_run(self, artifact: RunArtifact) -> None:
        del artifact


class FilesystemMarkdownArchiveSink:
    name = "filesystem_markdown"

    def __init__(self, export_dir: str) -> None:
        self.export_dir = Path(export_dir)

    def export_run(self, artifact: RunArtifact) -> None:
        self.export_dir.mkdir(parents=True, exist_ok=True)
        output_path = self.export_dir / self._filename_for(artifact)
        output_path.write_text(self._render_markdown(artifact))

    @staticmethod
    def _filename_for(artifact: RunArtifact) -> str:
        stamp = artifact.created_at.strftime("%Y%m%dT%H%M%SZ")
        title = artifact.title or artifact.thread_id
        slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-") or artifact.thread_id
        return f"{stamp}-{slug}.md"

    @staticmethod
    def _render_markdown(artifact: RunArtifact) -> str:
        approval = "required" if artifact.require_approval else "not required"
        approval_decision = "not applicable"
        if artifact.approval_decision is True:
            approval_decision = "approved"
        elif artifact.approval_decision is False:
            approval_decision = "declined"

        return (
            f"# {artifact.title or artifact.thread_id}\n\n"
            f"- thread_id: `{artifact.thread_id}`\n"
            f"- run_id: `{artifact.run_id}`\n"
            f"- created_at: `{artifact.created_at.isoformat()}`\n"
            f"- updated_at: `{artifact.updated_at.isoformat()}`\n"
            f"- approval: `{approval}`\n"
            f"- approval_decision: `{approval_decision}`\n\n"
            f"## Input\n\n{artifact.input_text}\n\n"
            f"## Response\n\n{artifact.response_text or '_no response text_'}\n"
        )


def build_semantic_memory_provider(provider_name: str) -> SemanticMemoryProvider:
    if provider_name == "none":
        return NoopSemanticMemoryProvider()
    raise ValueError(f"unsupported semantic memory provider: {provider_name}")


def build_archive_sink(sink_name: str, export_dir: str | None) -> ArchiveSink:
    if sink_name == "none":
        return NoopArchiveSink()
    if sink_name == "filesystem":
        if not export_dir:
            raise ValueError("ARCHIVE_EXPORT_DIR is required for filesystem archive sink")
        return FilesystemMarkdownArchiveSink(export_dir)
    raise ValueError(f"unsupported archive sink: {sink_name}")
