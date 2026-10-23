"""Optional mitmproxy adapter: inspect existing app responses, never replay requests.

Does not install certificates, set system proxies, export cookies, or save full traffic.
"""
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from reminder import LEBOGOU, QIANGUO, Reminder


def schema(value, depth=0):
    if depth > 4:
        return type(value).__name__
    if isinstance(value, dict):
        return {str(k): schema(v, depth + 1) for k, v in list(value.items())[:80]}
    if isinstance(value, list):
        return [schema(value[0], depth + 1)] if value else []
    return type(value).__name__


class Observer:
    def load(self, loader):
        path = Path(os.environ.get("ANSWER_REMINDER_CONFIG", Path(__file__).with_name("config.example.json"))).resolve()
        self.config = json.loads(path.read_text())
        os.chdir(path.parent)
        self.reminder = Reminder(self.config)
        self.seen = set()

    def response(self, flow):
        if flow.request.host not in QIANGUO | LEBOGOU:
            return
        if not flow.response or flow.response.status_code != 200:
            return
        if len(flow.response.raw_content or b"") > 2_000_000:
            return
        try:
            body = json.loads(flow.response.get_text())
        except (ValueError, UnicodeError):
            return
        request = {}
        try:
            raw = json.loads(flow.request.get_text() or "{}")
            if isinstance(raw, dict):
                request = {k: raw[k] for k in ("liveId", "topicId") if k in raw}
        except (ValueError, UnicodeError):
            form = parse_qs(flow.request.get_text() or "")
            request = {k: form[k][0] for k in ("liveId", "topicId") if k in form}
        record = {"url": flow.request.pretty_url, "body": body, "request": request}
        self.reminder.process(record)
        if flow.request.host in LEBOGOU:
            # Unmapped first-app API discovery stores structure/types, never field values.
            path = re.sub(r"/[0-9]{4,}(?=/|$)", "/:id", urlsplit(flow.request.pretty_url).path)
            if any(x in path.lower() for x in ("login", "auth", "token", "verif", "account")):
                return
            sample = {"host": flow.request.host, "path": path, "schema": schema(body)}
            key = json.dumps(sample, ensure_ascii=False, sort_keys=True)
            if key not in self.seen:
                self.seen.add(key)
                destination = Path("private/lebogou-schemas.jsonl")
                destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                fd = os.open(destination, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
                with os.fdopen(fd, "a") as stream:
                    stream.write(key + "\n")

    def websocket_message(self, flow):
        if flow.request.host not in QIANGUO | LEBOGOU or not flow.websocket:
            return
        message = flow.websocket.messages[-1]
        if message.from_client or len(message.content) > 2_000_000:
            return
        try:
            body = json.loads(message.content)
        except (ValueError, UnicodeError):
            return
        # Only decoded TIM message objects; binary/protobuf transport isn't decoded here.
        records = body.get("data", []) if isinstance(body, dict) and body.get("name") == "onMessageReceived" else [body]
        if not isinstance(records, list):
            return
        for item in records:
            self.reminder.process({"kind": "im", "url": flow.request.pretty_url, "body": item})


addons = [Observer()]
