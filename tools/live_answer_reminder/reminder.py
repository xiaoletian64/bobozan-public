#!/usr/bin/env python3
"""Passive answer notifications. Never submits answers or claims rewards."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
from urllib.parse import urlsplit, parse_qs, quote, urlencode
from urllib.request import Request, urlopen


QIANGUO = {"api.qianguolive.cn", "app.qianguolive.cn", "apipush.qianguolive.cn", "ims.qianguolive.cn"}
LEBOGOU = {"liveapi.njyqkj0ksyz.com", "live-play.njyqkj0ksyz.com", "live.njyqkj0ksyz.com", "live-gw.njyqkj0ksyz.com", "zhibo-api.njyqkj0ksyz.com", "h5.njyqkj0ksyz.cn", "wx.7948.cn", "ypgw.njyqkj0ksyz.com"}


def field(value, path):
    for key in path.split("."):
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def truth(value):
    return value is True or type(value) is int and value == 1


def success(value):
    return type(value) is int and value == 0 or type(value) is str and value == "0"


def event(provider, room, signal, fingerprint="answer"):
    if not room:
        return None
    return {"provider": provider, "room": str(room), "signal": signal, "fingerprint": str(fingerprint)}


def question_fingerprint(questions):
    # Do not store question text, correct answers or account information.
    return hashlib.sha256(json.dumps(questions, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:20]


def classify(record, config):
    """Only recognize observed signals; unknown first-app responses need verified rules."""
    url = urlsplit(record.get("url", ""))
    host = url.hostname or ""
    body = record.get("body")
    if host not in QIANGUO | LEBOGOU:
        return None
    if not isinstance(body, dict):
        return None
    request = record.get("request", {})
    if not isinstance(request, dict):
        request = {}
    query = parse_qs(url.query)
    room = request.get("liveId") or query.get("liveId", [None])[0]
    if host in QIANGUO:
        if record.get("kind") == "im":
            payload = body.get("payload", {})
            if not isinstance(payload, dict) or payload.get("text") != "hcj_im_token_ANSWER":
                return None
            # TIM may expose group as `to`, while decoded adapters may use groupID.
            group = body.get("to", "") or body.get("groupID", "")
            match = re.fullmatch(r"im_shop_group([A-Za-z0-9_-]+)", str(group))
            if not match:
                return None
            return event("qianguo", match[1], "im_answer")
        if not success(body.get("code")):
            return None
        data = body.get("data")
        if not isinstance(data, dict):
            return None
        match = re.fullmatch(r"/qg/app/live/getLiveAnswerList/([A-Za-z0-9_-]+)", url.path)
        if host == "api.qianguolive.cn" and match:
            questions = data.get("newLiveQuestionVO")
            if truth(data.get("isCanAnswer")) and isinstance(questions, list) and questions:
                return event("qianguo", match[1], "answer_available", question_fingerprint(questions))
        if host == "api.qianguolive.cn" and url.path == "/qg/app/live/jumpPage":
            if data.get("liveJumpPageEnum") in ("ANSWER_PAGE", "ANSWER_POPUP"):
                return event("qianguo", room, "answer_page")
        return None
    if record.get("kind") == "im" and body.get("Types") == "正常消息":
        message = body.get("Msg", {})
        if not isinstance(message, dict):
            return None
        room = message.get("TopicId")
        if message.get("msgtype") == 511:
            content = message.get("content", {})
            if isinstance(content, str):
                try:
                    content = json.loads(content)
                except ValueError:
                    return None
            reward = content.get("answerReward", {}) if isinstance(content, dict) else {}
            if isinstance(reward, dict) and type(reward.get("state")) is int and reward["state"] == 1 and reward.get("id") not in (None, -1, 0):
                return event("lebogou", room, "activity_started", reward["id"])
        # 790 routes to im_msg_question_show; 791 is its end event. This is
        # separate from reward activity 511, so do not confuse the two systems.
        if message.get("msgtype") == 790:
            return event("lebogou", room, "question_shown")
        return None
    if host in {"live-gw.njyqkj0ksyz.com", "ypgw.njyqkj0ksyz.com"} and url.path == "/generic/v1/h5/answer/get_question_list":
        data = body.get("dataObj")
        if not success(body.get("code")) or not truth(body.get("isok")) or not isinstance(data, dict):
            return None
        reward = data.get("answerReward")
        if not isinstance(reward, dict) or type(reward.get("state")) is not int or reward["state"] != 1 or reward.get("id") in (None, -1, 0):
            return None
        if truth(data.get("answered")):
            return None
        room = request.get("topicId") or query.get("topicId", [None])[0]
        # Activity state is confirmed. Personal watch/sign-in/time eligibility is
        # browser-local, so this is an activity reminder, not a claim of eligibility.
        return event("lebogou", room, "activity_started", reward["id"])
    for rule in config.get("lebogou_rules", []):
        # No speculative endpoint/boolean names are shipped for this app.
        if host != rule["host"] or url.path != rule["path"]:
            continue
        actual = field(body, rule["status_field"])
        expected = rule["status_value"]
        if type(actual) is not type(expected) or actual != expected:
            continue
        room = field(body, rule["room_field"]) if rule.get("room_field") else request.get(rule.get("request_room_field", "liveId"))
        fingerprint = field(body, rule["round_field"]) if rule.get("round_field") else "answer"
        return event("lebogou", room, "verified_rule", fingerprint)
    return None


class Speaker:
    def __init__(self, config):
        self.config = config

    def speak(self, text):
        kind = self.config.get("type", "console")
        if kind == "console":
            print(json.dumps({"dry_run": True, "message": text}, ensure_ascii=False), flush=True)
            return
        if kind == "miservice":
            # Require a specific speaker; MiService otherwise broadcasts to all devices.
            did = self.config.get("device_id")
            if not did:
                raise ValueError("speaker.device_id is required")
            command = self.config.get("python_executable", sys.executable)
            helper = str(Path(__file__).with_name("speaker.py"))
            payload = {"device_id": str(did), "text": text,
                       "token_file": str(Path(self.config.get("token_file", "private/mi-token.json")).resolve())}
            result = subprocess.run([command, helper, "speak"], input=json.dumps(payload).encode(), capture_output=True, timeout=40)
            if result.returncode:
                raise RuntimeError("MiService failed; check login locally (credentials are not logged)")
            return
        raise ValueError("unsupported speaker type")


class Reminder:
    def __init__(self, config, speaker=None, now=time.time):
        self.config, self.now = config, now
        path = config.get("state_file", "private/reminders.sqlite3")
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(path)
        if path != ":memory:":
            os.chmod(path, 0o600)
        self.db.execute("CREATE TABLE IF NOT EXISTS sent (provider TEXT, room TEXT, fingerprint TEXT, at REAL, PRIMARY KEY(provider,room,fingerprint))")
        self.speaker = speaker or Speaker(config.get("speaker", {}))

    def process(self, record):
        detected = classify(record, self.config)
        if not detected:
            return False
        provider, room, fingerprint = (detected[k] for k in ("provider", "room", "fingerprint"))
        now = self.now()
        row = self.db.execute("SELECT at FROM sent WHERE provider=? AND room=? AND fingerprint=?", (provider, room, fingerprint)).fetchone()
        if row and now - row[0] < self.config.get("repeat_after_seconds", 21600):
            return False
        latest = self.db.execute("SELECT MAX(at) FROM sent WHERE provider=? AND room=?", (provider, room)).fetchone()[0]
        if latest is not None and now - latest < self.config.get("cooldown_seconds", 120):
            return False
        name = "千果" if provider == "qianguo" else "乐播购"
        text = f"妈妈，{name}可以答题了，请看一下手机。"
        if detected["signal"] == "activity_started":
            text = "妈妈，乐播购有答题活动了，请看一下手机上的答题条件。"
        if detected["signal"] == "question_shown":
            text = "妈妈，乐播购推送了答题互动，请看一下手机。"
        self.speaker.speak(text)
        # Record only after successful delivery; failed delivery remains retryable.
        self.db.execute("INSERT OR REPLACE INTO sent VALUES (?,?,?,?)", (provider, room, fingerprint, now))
        self.db.commit()
        return True


def poll_once(config, reminder, provider="qianguo"):
    settings = config[provider]
    room = str(settings.get("live_id" if provider == "qianguo" else "topic_id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]+", room):
        raise ValueError("room ID is missing or invalid")
    headers = json.loads(Path(settings["headers_file"]).read_text())
    request = {}
    if provider == "qianguo":
        if not headers.get("memberToken"):
            raise ValueError("memberToken is missing from the private headers file")
        url = "https://api.qianguolive.cn/qg/app/live/getLiveAnswerList/" + quote(room, safe="")
        http_request = Request(url, headers=headers)
    else:
        if not headers.get("buid"):
            raise ValueError("buid is missing from the private headers file")
        url = "https://live-gw.njyqkj0ksyz.com/generic/v1/h5/answer/get_question_list"
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers.setdefault("X-Requested-With", "XMLHttpRequest")
        request = {"topicId": room}
        http_request = Request(url, data=urlencode(request).encode(), headers=headers)
    with urlopen(http_request, timeout=15) as response:
        body = json.loads(response.read(2_000_001))
    if not isinstance(body, dict) or not success(body.get("code")):
        raise RuntimeError("answer status unavailable; check login and room locally")
    if provider == "lebogou" and not truth(body.get("isok")):
        raise RuntimeError("activity status unavailable; check login locally")
    return reminder.process({"url": url, "body": body, "request": request})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["replay", "poll", "check"])
    parser.add_argument("--config", default="config.example.json")
    parser.add_argument("--input", help="JSONL normalized response records")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--provider", choices=["qianguo", "lebogou", "both"], default="both")
    args = parser.parse_args()
    config_path = Path(args.config).resolve()
    config = json.loads(config_path.read_text())
    os.chdir(config_path.parent)
    if args.mode == "check":
        settings = config.get("qianguo", {})
        first = config.get("lebogou", {})
        print(json.dumps({"qianguo_room_configured": bool(settings.get("live_id")), "qianguo_login_file_present": Path(settings.get("headers_file", "private/qianguo-headers.json")).is_file(), "lebogou_room_configured": bool(first.get("topic_id")), "lebogou_login_file_present": Path(first.get("headers_file", "private/lebogou-headers.json")).is_file(), "speaker_type": config.get("speaker", {}).get("type", "console"), "live_verified": False}, ensure_ascii=False))
        return
    reminder = Reminder(config)
    if args.mode == "replay":
        if not args.input:
            parser.error("replay requires --input")
        with open(args.input) as stream:
            for line in stream:
                if line.strip():
                    reminder.process(json.loads(line))
        return
    providers = ["qianguo", "lebogou"] if args.provider == "both" else [args.provider]
    failures = dict.fromkeys(providers, 0)
    due = dict.fromkeys(providers, 0)
    while True:
        for provider in providers:
            if not args.once and time.monotonic() < due[provider]:
                continue
            try:
                from session_store import renew
                renew(provider, config.get(provider, {}))
                poll_once(config, reminder, provider)
                failures[provider] = 0
            except Exception as exc:
                failures[provider] += 1
                # Avoid HTTP bodies, headers, credentials or private URLs in logs.
                print(f"{provider}: status check failed ({type(exc).__name__}); consecutive failures={failures[provider]}", flush=True)
            interval = max(10, float(config.get(provider, {}).get("interval_seconds", 15)))
            due[provider] = time.monotonic() + min(interval * 2 ** min(failures[provider], 4), 300)
        if args.once:
            if any(failures.values()):
                raise SystemExit(1)
            return
        time.sleep(max(0, min(due.values()) - time.monotonic()))


if __name__ == "__main__":
    main()
