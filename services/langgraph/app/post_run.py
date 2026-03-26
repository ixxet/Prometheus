from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Protocol

from .config import Settings


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

    def recall(self, query: str, thread_id: str, limit: int) -> list[str]:
        """Return durable memory snippets relevant to the current request."""


class ArchiveSink(Protocol):
    name: str

    def export_run(self, artifact: RunArtifact) -> None:
        """Export a human-readable artifact for a completed run."""


class NoopSemanticMemoryProvider:
    name = "none"

    def record_run(self, artifact: RunArtifact) -> None:
        del artifact

    def recall(self, query: str, thread_id: str, limit: int) -> list[str]:
        del query, thread_id, limit
        return []


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


class Mem0SemanticMemoryProvider:
    name = "mem0"

    def __init__(self, settings: Settings) -> None:
        from mem0 import Memory

        embedder_config: dict[str, str] = {"model": settings.mem0_embedder_model}
        if settings.mem0_embedder_base_url:
            embedder_config["huggingface_base_url"] = settings.mem0_embedder_base_url

        self.user_id = settings.semantic_memory_user_id
        self.agent_id = settings.semantic_memory_agent_id
        self.memory = Memory.from_config(
            {
                "version": "v1.1",
                "vector_store": {
                    "provider": "qdrant",
                    "config": {
                        "collection_name": settings.mem0_qdrant_collection,
                        "host": settings.mem0_qdrant_host,
                        "port": settings.mem0_qdrant_port,
                        "embedding_model_dims": settings.mem0_embedding_dims,
                        "on_disk": True,
                    },
                },
                "llm": {
                    "provider": "vllm",
                    "config": {
                        "model": settings.openai_model,
                        "vllm_base_url": settings.openai_api_base_url,
                        "api_key": settings.openai_api_key,
                        "temperature": 0.0,
                        "max_tokens": 512,
                    },
                },
                "embedder": {
                    "provider": "huggingface",
                    "config": embedder_config,
                },
                "custom_fact_extraction_prompt": (
                    "Extract stable user preferences, project conventions, "
                    "infrastructure facts, and operating rules that should be "
                    "remembered across future runs. Ignore one-off phrasing, "
                    "temporary guesses, and low-value small talk."
                ),
            }
        )

    def record_run(self, artifact: RunArtifact) -> None:
        messages = [{"role": "user", "content": artifact.input_text}]
        if artifact.response_text:
            messages.append({"role": "assistant", "content": artifact.response_text})

        self.memory.add(
            messages,
            user_id=self.user_id,
            agent_id=self.agent_id,
            run_id=artifact.run_id,
            metadata={
                "thread_id": artifact.thread_id,
                "title": artifact.title,
                "approval_required": artifact.require_approval,
                "approval_decision": artifact.approval_decision,
            },
        )

    def recall(self, query: str, thread_id: str, limit: int) -> list[str]:
        del thread_id
        response = self.memory.search(
            query=query,
            user_id=self.user_id,
            agent_id=self.agent_id,
            limit=limit,
        )
        results = []
        if isinstance(response, dict):
            results = response.get("results", [])
        elif isinstance(response, list):
            results = response

        snippets: list[str] = []
        seen: set[str] = set()
        for item in results:
            if not isinstance(item, dict):
                continue
            text = item.get("memory") or item.get("text") or item.get("content")
            if not text or text in seen:
                continue
            seen.add(text)
            snippets.append(str(text))
        return snippets


def build_semantic_memory_provider(settings: Settings) -> SemanticMemoryProvider:
    provider_name = settings.semantic_memory_provider
    if provider_name == "none":
        return NoopSemanticMemoryProvider()
    if provider_name == "mem0":
        return Mem0SemanticMemoryProvider(settings)
    raise ValueError(f"unsupported semantic memory provider: {provider_name}")


def build_archive_sink(sink_name: str, export_dir: str | None) -> ArchiveSink:
    if sink_name == "none":
        return NoopArchiveSink()
    if sink_name == "filesystem":
        if not export_dir:
            raise ValueError("ARCHIVE_EXPORT_DIR is required for filesystem archive sink")
        return FilesystemMarkdownArchiveSink(export_dir)
    raise ValueError(f"unsupported archive sink: {sink_name}")
