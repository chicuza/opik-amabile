"""Opik SDK smoke test — sends one trace and one guardrail check to the deployed stack.

Requires env vars:
    OPIK_URL_OVERRIDE=https://fabricaai.amabileai.com.br/api
    OPIK_API_KEY=<from-UI>
    OPIK_WORKSPACE=default

Run:
    pip install opik
    python sdk-examples/python_smoke.py
"""
from __future__ import annotations

import os
import sys

import opik


def main() -> int:
    for var in ("OPIK_URL_OVERRIDE", "OPIK_API_KEY", "OPIK_WORKSPACE"):
        if not os.getenv(var):
            print(f"missing env var: {var}", file=sys.stderr)
            return 1

    opik.configure(use_local=False)
    client = opik.Opik(project_name="amabile-smoke")
    trace = client.trace(
        name="hello",
        input={"q": "ping"},
        output={"a": "pong"},
        tags=["smoke", "railway"],
    )
    trace.end()
    print(f"trace ok: {trace.id}")

    try:
        from opik.guardrails import Guardrail, PII

        guard = Guardrail(guards=[PII()])
        result = guard.validate("My email is test@example.com and my SSN is 123-45-6789.")
        print(f"guardrail ok: {result}")
    except Exception as exc:  # noqa: BLE001
        print(f"guardrail check failed (non-fatal): {exc}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
