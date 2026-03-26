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
            "mistralai/Mistral-7B-Instruct-v0.3",
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
    )
