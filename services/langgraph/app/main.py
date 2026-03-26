from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage
from langgraph.checkpoint.postgres import PostgresSaver
from langgraph.types import Command
from sqlalchemy import select, text

from .config import Settings, load_settings
from .db import Database, RunRecord, ThreadRecord
from .graph_runtime import LangGraphRuntime
from .schemas import ResumeRequest, RunCreateRequest, RunResponse, ThreadCreateRequest, ThreadResponse


def message_to_dict(message: BaseMessage) -> dict[str, Any]:
    return {
        "type": message.type,
        "id": getattr(message, "id", None),
        "content": message.content,
    }


def interrupt_to_dict(interrupt_obj) -> dict[str, Any]:
    return {
        "id": getattr(interrupt_obj, "id", None),
        "value": getattr(interrupt_obj, "value", None),
    }


def snapshot_to_dict(snapshot) -> dict[str, Any] | None:
    if snapshot is None:
        return None

    values = snapshot.values or {}
    messages = [message_to_dict(message) for message in values.get("messages", [])]
    configurable = snapshot.config.get("configurable", {}) if snapshot.config else {}
    return {
        "checkpoint_id": configurable.get("checkpoint_id"),
        "created_at": snapshot.created_at,
        "next": list(snapshot.next),
        "messages": messages,
        "approval_required": values.get("approval_required"),
        "approval_decision": values.get("approval_decision"),
        "interrupts": [interrupt_to_dict(item) for item in snapshot.interrupts],
    }


def latest_ai_text(messages: list[BaseMessage]) -> str | None:
    for message in reversed(messages):
        if isinstance(message, AIMessage):
            return str(message.content)
    return None


def run_to_response(record: RunRecord, latest_state: dict[str, Any] | None = None) -> RunResponse:
    return RunResponse(
        run_id=record.run_id,
        thread_id=record.thread_id,
        status=record.status,
        require_approval=record.require_approval,
        response_text=record.response_text,
        interrupts=record.interrupt_payload or [],
        latest_state=latest_state,
        created_at=record.created_at,
        updated_at=record.updated_at,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = load_settings()
    database = Database(settings.sqlalchemy_database_uri)
    database.setup()

    checkpointer_cm = PostgresSaver.from_conn_string(settings.database_uri)
    checkpointer = checkpointer_cm.__enter__()
    checkpointer.setup()

    runtime = LangGraphRuntime(settings)
    graph = runtime.build_graph(checkpointer)

    app.state.settings = settings
    app.state.database = database
    app.state.graph = graph
    app.state.checkpointer_cm = checkpointer_cm

    try:
        yield
    finally:
        checkpointer_cm.__exit__(None, None, None)
        database.dispose()


app = FastAPI(
    title="Prometheus LangGraph Runtime",
    version="0.3.0-dev",
    lifespan=lifespan,
)


def graph_config(thread_id: str) -> dict[str, Any]:
    return {"configurable": {"thread_id": thread_id}}


def get_thread_or_404(database: Database, thread_id: str) -> ThreadRecord:
    with database.session() as session:
        thread = session.get(ThreadRecord, thread_id)
        if thread is None:
            raise HTTPException(status_code=404, detail="thread not found")
        session.expunge(thread)
        return thread


def load_runs(database: Database, thread_id: str) -> list[RunRecord]:
    with database.session() as session:
        records = list(
            session.scalars(
                select(RunRecord)
                .where(RunRecord.thread_id == thread_id)
                .order_by(RunRecord.created_at.asc())
            )
        )
        for record in records:
            session.expunge(record)
        return records


@app.get("/healthz")
def healthz(request: Request):
    database: Database = request.app.state.database
    with database.session() as session:
        session.execute(text("select 1"))

    settings: Settings = request.app.state.settings
    return {
        "ok": True,
        "database": "ok",
        "model_backend": settings.openai_api_base_url,
        "model": settings.openai_model,
    }


@app.post("/threads", response_model=ThreadResponse)
def create_thread(payload: ThreadCreateRequest, request: Request):
    database: Database = request.app.state.database
    thread_id = str(uuid4())

    with database.session() as session:
        thread = ThreadRecord(
            thread_id=thread_id,
            title=payload.title,
            status="idle",
        )
        session.add(thread)
        session.flush()
        session.refresh(thread)
        session.expunge(thread)

    return ThreadResponse(
        thread_id=thread.thread_id,
        title=thread.title,
        status=thread.status,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        checkpoint_count=0,
        latest_state=None,
        runs=[],
    )


@app.get("/threads/{thread_id}", response_model=ThreadResponse)
def get_thread(thread_id: str, request: Request):
    database: Database = request.app.state.database
    graph = request.app.state.graph

    thread = get_thread_or_404(database, thread_id)
    state = graph.get_state(graph_config(thread_id))
    history_count = sum(1 for _ in graph.get_state_history(graph_config(thread_id)))
    runs = load_runs(database, thread_id)

    return ThreadResponse(
        thread_id=thread.thread_id,
        title=thread.title,
        status=thread.status,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        checkpoint_count=history_count,
        latest_state=snapshot_to_dict(state),
        runs=[run_to_response(run) for run in runs],
    )


@app.post("/threads/{thread_id}/runs", response_model=RunResponse)
def create_run(thread_id: str, payload: RunCreateRequest, request: Request):
    database: Database = request.app.state.database
    graph = request.app.state.graph
    _ = get_thread_or_404(database, thread_id)
    run_id = str(uuid4())

    with database.session() as session:
        thread = session.get(ThreadRecord, thread_id)
        if thread is None:
            raise HTTPException(status_code=404, detail="thread not found")
        if thread.status in {"running", "waiting_for_approval"}:
            raise HTTPException(
                status_code=409,
                detail="thread already has an active run",
            )

        record = RunRecord(
            run_id=run_id,
            thread_id=thread_id,
            status="running",
            input_text=payload.message,
            require_approval=payload.require_approval,
        )
        thread.status = "running"
        session.add(record)
        session.flush()
        session.refresh(record)
        session.expunge(record)

    try:
        result = graph.invoke(
            {
                "messages": [HumanMessage(content=payload.message)],
                "approval_required": payload.require_approval,
                "approval_decision": None,
            },
            config=graph_config(thread_id),
        )
    except Exception as exc:
        with database.session() as session:
            thread = session.get(ThreadRecord, thread_id)
            record = session.get(RunRecord, run_id)
            if thread:
                thread.status = "failed"
            if record:
                record.status = "failed"
                record.error_text = str(exc)
        raise HTTPException(status_code=500, detail=f"run failed: {exc}") from exc

    state = graph.get_state(graph_config(thread_id))
    latest_state = snapshot_to_dict(state)
    messages = result.get("messages", [])
    interrupts = [interrupt_to_dict(item) for item in result.get("__interrupt__", [])]

    with database.session() as session:
        thread = session.get(ThreadRecord, thread_id)
        record = session.get(RunRecord, run_id)
        if thread is None or record is None:
            raise HTTPException(status_code=500, detail="run bookkeeping failed")

        if interrupts:
            thread.status = "waiting_for_approval"
            record.status = "waiting_for_approval"
            record.interrupt_payload = interrupts
            record.response_text = None
        else:
            thread.status = "idle"
            record.status = "completed"
            record.interrupt_payload = None
            record.response_text = latest_ai_text(messages)

        session.flush()
        session.refresh(record)
        session.expunge(record)

    return run_to_response(record, latest_state=latest_state)


@app.post("/threads/{thread_id}/resume", response_model=RunResponse)
def resume_run(thread_id: str, payload: ResumeRequest, request: Request):
    database: Database = request.app.state.database
    graph = request.app.state.graph
    _ = get_thread_or_404(database, thread_id)

    with database.session() as session:
        record = session.scalar(
            select(RunRecord)
            .where(
                RunRecord.thread_id == thread_id,
                RunRecord.status == "waiting_for_approval",
            )
            .order_by(RunRecord.updated_at.desc())
        )
        if record is None:
            raise HTTPException(status_code=409, detail="no interrupted run to resume")
        run_id = record.run_id
        record.status = "running"
        thread = session.get(ThreadRecord, thread_id)
        if thread:
            thread.status = "running"

    try:
        result = graph.invoke(
            Command(resume={"approved": payload.approved}),
            config=graph_config(thread_id),
        )
    except Exception as exc:
        with database.session() as session:
            thread = session.get(ThreadRecord, thread_id)
            record = session.get(RunRecord, run_id)
            if thread:
                thread.status = "failed"
            if record:
                record.status = "failed"
                record.error_text = str(exc)
        raise HTTPException(status_code=500, detail=f"resume failed: {exc}") from exc

    state = graph.get_state(graph_config(thread_id))
    latest_state = snapshot_to_dict(state)
    messages = result.get("messages", [])
    interrupts = [interrupt_to_dict(item) for item in result.get("__interrupt__", [])]

    with database.session() as session:
        thread = session.get(ThreadRecord, thread_id)
        record = session.get(RunRecord, run_id)
        if thread is None or record is None:
            raise HTTPException(status_code=500, detail="resume bookkeeping failed")

        if interrupts:
            thread.status = "waiting_for_approval"
            record.status = "waiting_for_approval"
            record.interrupt_payload = interrupts
            record.response_text = None
        else:
            thread.status = "idle"
            record.status = "completed"
            record.interrupt_payload = None
            record.response_text = latest_ai_text(messages)

        session.flush()
        session.refresh(record)
        session.expunge(record)

    return run_to_response(record, latest_state=latest_state)


@app.exception_handler(HTTPException)
async def http_exception_handler(_, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
