from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class ThreadCreateRequest(BaseModel):
    title: str | None = None


class RunCreateRequest(BaseModel):
    message: str = Field(min_length=1)
    require_approval: bool = False


class ResumeRequest(BaseModel):
    approved: bool


class RunResponse(BaseModel):
    run_id: str
    thread_id: str
    status: str
    require_approval: bool
    response_text: str | None
    interrupts: list[dict] = Field(default_factory=list)
    latest_state: dict | None = None
    created_at: datetime
    updated_at: datetime


class ThreadResponse(BaseModel):
    thread_id: str
    title: str | None
    status: str
    created_at: datetime
    updated_at: datetime
    checkpoint_count: int
    latest_state: dict | None
    runs: list[RunResponse]
