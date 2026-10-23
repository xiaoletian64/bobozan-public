#!/usr/bin/env python3
"""MiNA TTS to one explicit deviceID; credentials stay in environment/local token file."""
import asyncio
import getpass
import json
import logging
import os
from pathlib import Path
import sys


async def run(mode, payload):
    from miservice import MiAccount, MiNAService
    token = Path(payload.get("token_file", "private/mi-token.json")).resolve()
    token.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.umask(0o077)
    # Avoid third-party exception logs containing account identifiers or HTTP data.
    logging.disable(logging.CRITICAL)
    user = os.environ.get("MI_USER", "")
    password = os.environ.get("MI_PASS", "")
    if mode == "login":
        user = user or input("小米账号（仅提交给小米）: ").strip()
        password = password or getpass.getpass("小米密码（不显示）: ")
    elif not token.is_file():
        raise RuntimeError("local MiNA login is required")
    async def otp(prompt):
        if mode != "login":
            raise RuntimeError("login expired; interactive login required")
        return input(prompt).strip()
    account = MiAccount(None, user, password, str(token), otp_callback=otp)
    service = MiNAService(account)
    if mode == "login":
        devices = await asyncio.wait_for(service.device_list(), timeout=180)
        if devices is None:
            raise RuntimeError("device listing failed")
        print(json.dumps([{"device_id": d.get("deviceID"), "name": d.get("name"), "hardware": d.get("hardware")} for d in devices], ensure_ascii=False, indent=2))
    else:
        if not payload.get("device_id"):
            raise ValueError("specific device_id required")
        ok = await asyncio.wait_for(service.text_to_speech(payload["device_id"], payload["text"]), timeout=30)
        if not ok:
            raise RuntimeError("MiNA did not acknowledge TTS")
    if token.is_file():
        os.chmod(token, 0o600)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in {"login", "speak"}:
        raise SystemExit("usage: speaker.py login [token-file] | speak (JSON on stdin)")
    payload = {"token_file": sys.argv[2]} if mode == "login" and len(sys.argv) > 2 else {}
    if mode == "speak":
        payload = json.load(sys.stdin)
    try:
        asyncio.run(run(mode, payload))
    except Exception as exc:
        print(f"speaker operation failed ({type(exc).__name__}); check login locally", file=sys.stderr)
        raise SystemExit(1)
