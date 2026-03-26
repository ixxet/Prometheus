from __future__ import annotations

from typing import Annotated, TypedDict

from langchain_core.messages import AIMessage, AnyMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages
from langgraph.types import interrupt

from .config import Settings


class AgentState(TypedDict, total=False):
    messages: Annotated[list[AnyMessage], add_messages]
    approval_required: bool
    approval_decision: bool | None
    memory_context: list[str]


class LangGraphRuntime:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.model = ChatOpenAI(
            model=settings.openai_model,
            api_key=settings.openai_api_key,
            base_url=settings.openai_api_base_url,
            temperature=0,
        )

    def build_graph(self, checkpointer):
        builder = StateGraph(AgentState)
        builder.add_node("approval_gate", self.approval_gate)
        builder.add_node("call_model", self.call_model)
        builder.add_node("decline", self.decline)
        builder.add_edge(START, "approval_gate")
        builder.add_conditional_edges(
            "approval_gate",
            self.route_after_gate,
            {
                "call_model": "call_model",
                "decline": "decline",
            },
        )
        builder.add_edge("call_model", END)
        builder.add_edge("decline", END)
        return builder.compile(checkpointer=checkpointer)

    def approval_gate(self, state: AgentState):
        if state.get("approval_required") and state.get("approval_decision") is None:
            latest_user_message = next(
                (
                    message.content
                    for message in reversed(state.get("messages", []))
                    if isinstance(message, HumanMessage)
                ),
                None,
            )
            decision = interrupt(
                {
                    "kind": "approval_required",
                    "latest_user_message": latest_user_message,
                    "message_count": len(state.get("messages", [])),
                }
            )
            return {"approval_decision": bool(decision.get("approved"))}
        return {}

    @staticmethod
    def route_after_gate(state: AgentState) -> str:
        if state.get("approval_required") and state.get("approval_decision") is False:
            return "decline"
        return "call_model"

    def call_model(self, state: AgentState):
        prompt_messages: list[AnyMessage] = [SystemMessage(content=self.settings.system_prompt)]
        if state.get("memory_context"):
            recalled_memories = "\n".join(f"- {item}" for item in state["memory_context"])
            prompt_messages.append(
                SystemMessage(
                    content=(
                        "Relevant durable memory from prior runs. Use it when it helps, "
                        "but prefer the current conversation if there is a conflict.\n"
                        f"{recalled_memories}"
                    )
                )
            )
        prompt_messages.extend(state.get("messages", []))
        response = self.model.invoke(prompt_messages)
        return {"messages": [response]}

    @staticmethod
    def decline(state: AgentState):
        return {
            "messages": [
                AIMessage(
                    content=(
                        "Request was not approved. The run was resumed, but the model "
                        "was intentionally not invoked."
                    )
                )
            ]
        }
