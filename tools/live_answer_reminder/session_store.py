"""Restricted local session storage and the two observed session renewal flows."""
import json
import os
from pathlib import Path
import tempfile
import time
from urllib.request import Request, urlopen


class ReauthenticationRequired(RuntimeError):
    pass


def save_private(path, value):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".session-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(value, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_private(path):
    path = Path(path)
    if path.stat().st_mode & 0o077:
        raise PermissionError("session file must be readable only by its owner")
    return json.loads(path.read_text())


def renew(provider, settings, force=False):
    """Only use an existing authenticated identity; never invent refresh tokens."""
    session_file = settings.get("session_file")
    if not session_file:
        return False
    session = load_private(session_file)
    now = time.time()
    if not force and now - session.get("last_renewed_at", 0) < 3600:
        return False
    headers = load_private(settings["headers_file"])
    request_headers = {"Content-Type": "application/json;charset=UTF-8"}
    if provider == "lebogou":
        identity = session.get("encryptUserId")
        if not identity:
            raise ReauthenticationRequired("authenticated encrypted user ID is missing")
        url = "https://liveauth.njyqkj0ksyz.com/api/v1/login/get_wx_token"
        params = {"encryptUserId": identity}
    elif provider == "qianguo":
        if not headers.get("memberToken") or not settings.get("merchant_id") or not settings.get("live_id") or not session.get("openIdType"):
            raise ReauthenticationRequired("authenticated live session context is missing")
        url = "https://api.qianguolive.cn/qg/app/live/silenceLogin"
        params = {"memberToken": headers["memberToken"], "merchantId": settings["merchant_id"], "liveId": settings["live_id"], "openIdType": session["openIdType"]}
        request_headers.update(headers)
        request_headers["Content-Type"] = "application/json;charset=UTF-8"
    else:
        raise ValueError("unsupported provider")
    with urlopen(Request(url, data=json.dumps(params).encode(), headers=request_headers), timeout=20) as response:
        result = json.loads(response.read(2_000_000))
    if provider == "lebogou":
        data = result.get("dataObj")
        ok = result.get("isok") is True or type(result.get("code")) is int and result["code"] == 0
        if not ok or not isinstance(data, dict) or not data.get("token"):
            raise ReauthenticationRequired("normal token renewal was rejected")
        headers["Authorization"] = "Bearer " + data["token"]
        session["server_token_expires"] = data.get("tokenExpires")
    else:
        data = result.get("data")
        if type(result.get("code")) is not int or result["code"] != 0 or not isinstance(data, dict) or not data.get("memberToken"):
            raise ReauthenticationRequired("normal silent login was rejected")
        headers["memberToken"] = data["memberToken"]
    # A crash between these writes leaves a usable new header and merely causes
    # another renewal later, instead of dropping the working token.
    save_private(settings["headers_file"], headers)
    session["last_renewed_at"] = now
    save_private(session_file, session)
    return True
