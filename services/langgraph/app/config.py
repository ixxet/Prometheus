from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import quote


@dataclass(frozen=True)
class Settings:
    port: int
    database_uri: str
    openai_api_base_url: str
    openai_model: str
    openai_api_key: str
    system_prompt: str
    semantic_memory_provider: str
    semantic_memory_user_id: str
    semantic_memory_agent_id: str
    semantic_memory_top_k: int
    mem0_qdrant_host: str
    mem0_qdrant_port: int
    mem0_qdrant_collection: str
    mem0_embedding_dims: int
    mem0_embedder_model: str
    mem0_embedder_base_url: str | None
    archive_sink: str
    archive_export_dir: str | None

    @property
    def sqlalchemy_database_uri(self) -> str:
        if self.database_uri.startswith("postgresql://"):
            return self.database_uri.replace("postgresql://", "postgresql+psycopg://", 1)
        return self.database_uri


def load_settings() -> Settings:
    database_uri = os.environ.get("DATABASE_URI")
    if not database_uri:
        database_user = os.environ["DATABASE_USER"]
        database_password = quote(os.environ["DATABASE_PASSWORD"], safe="")
        database_host = os.environ.get("DATABASE_HOST", "postgres.agents.svc.cluster.local")
        database_port = os.environ.get("DATABASE_PORT", "5432")
        database_name = os.environ["DATABASE_NAME"]
        database_uri = (
            f"postgresql://{database_user}:{database_password}@"
            f"{database_host}:{database_port}/{database_name}"
        )
    return Settings(
        port=int(os.environ.get("PORT", "8000")),
        database_uri=database_uri,
        openai_api_base_url=os.environ.get(
            "OPENAI_API_BASE_URL",
            "http://vllm.ai.svc.cluster.local:8000/v1",
        ),
        openai_model=os.environ.get(
            "OPENAI_MODEL",
            "google/gemma-4-26B-A4B-it",
        ),
        openai_api_key=os.environ.get("OPENAI_API_KEY", "local-not-required"),
        system_prompt=os.environ.get(
            "LANGGRAPH_SYSTEM_PROMPT",
            (
                "You are the Prometheus local agent runtime. Be concise, factual, and "
                "safe. Use the conversation history, answer directly, and do not claim "
                "to have performed external actions you did not actually perform."
            ),
        ),
        semantic_memory_provider=os.environ.get("SEMANTIC_MEMORY_PROVIDER", "none"),
        semantic_memory_user_id=os.environ.get("SEMANTIC_MEMORY_USER_ID", "prometheus"),
        semantic_memory_agent_id=os.environ.get("SEMANTIC_MEMORY_AGENT_ID", "langgraph"),
        semantic_memory_top_k=int(os.environ.get("SEMANTIC_MEMORY_TOP_K", "3")),
        mem0_qdrant_host=os.environ.get(
            "MEM0_QDRANT_HOST",
            "qdrant.semantic-memory.svc.cluster.local",
        ),
        mem0_qdrant_port=int(os.environ.get("MEM0_QDRANT_PORT", "6333")),
        mem0_qdrant_collection=os.environ.get("MEM0_QDRANT_COLLECTION", "prometheus-memory"),
        mem0_embedding_dims=int(os.environ.get("MEM0_EMBEDDING_DIMS", "384")),
        mem0_embedder_model=os.environ.get("MEM0_EMBEDDER_MODEL", "tei"),
        mem0_embedder_base_url=os.environ.get(
            "MEM0_EMBEDDER_BASE_URL",
            "http://tei-embeddings.semantic-memory.svc.cluster.local/v1",
        ),
        archive_sink=os.environ.get("ARCHIVE_SINK", "none"),
        archive_export_dir=os.environ.get("ARCHIVE_EXPORT_DIR"),
    )
