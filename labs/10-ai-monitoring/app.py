"""Toy LLM service: AI product-description generator for SimplCommerce.
The New Relic Python agent (started by `newrelic-admin run-program`, see the Dockerfile) auto-instruments the
OpenAI client: every chat completion becomes LlmChatCompletionSummary + LlmChatCompletionMessage events
(model, tokens, latency, prompt and response when NEW_RELIC_AI_MONITORING_RECORD_CONTENT_ENABLED=true)
and a span inside the FastAPI transaction. No New Relic code in this file.
"""
import os
from fastapi import FastAPI
from openai import OpenAI

app = FastAPI()
# OPENAI_API_KEY from env. OPENAI_BASE_URL empty -> api.openai.com; set it for Azure OpenAI / Ollama / any OpenAI-compatible server.
client = OpenAI(base_url=os.environ.get("OPENAI_BASE_URL") or None)
MODEL = os.environ.get("MODEL", "gpt-4o-mini")


@app.get("/describe")
def describe(product: str = "laptop"):
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": f"Write a 2-sentence e-commerce description for: {product}"}],
        max_tokens=80,
    )
    return {"product": product, "description": resp.choices[0].message.content}


@app.get("/ask")
def ask(q: str = "Explain root cause analysis in two sentences."):
    """Free-form prompt for the workshop - every call becomes an LLM event with prompt, answer and tokens."""
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": q}],
        max_tokens=int(os.environ.get("MAX_TOKENS", "200")),
    )
    u = resp.usage
    return {"question": q, "answer": resp.choices[0].message.content,
            "model": resp.model, "tokens": {"input": u.prompt_tokens, "output": u.completion_tokens} if u else None}


@app.get("/health")
def health():
    return {"ok": True}
