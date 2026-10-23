#!/usr/bin/env python3
"""APK-native signer and normal account login client. Does not bypass login."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import zipfile

PACKAGE = "com.lebogou.jssqdeyousheng"
VERSION = "260703"
CHANNEL = "lebogou"  # Verified from this APK's signing-block channel entry.
ROOT = Path(__file__).resolve().parent


def run(args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError("native signing command failed; inspect the local emulator setup")
    return result.stdout


def prepare(apk, serial, sdk):
    destination = ROOT / "private/native"
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    classes, dex = destination / "classes", destination / "dex"
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        library = archive.read("lib/arm64-v8a/libpush.so")
    so = destination / "libpush.so"
    so.write_bytes(library)
    adb = sdk / "platform-tools/adb"
    versions = sorted((sdk / "build-tools").iterdir(), key=lambda p: tuple(int(x) for x in p.name.split(".") if x.isdigit()))
    build_tools = versions[-1]
    badge = run([build_tools / "aapt", "dump", "badging", apk])
    if f"name='{PACKAGE}'" not in badge or f"versionCode='{VERSION}'" not in badge:
        raise ValueError("this signer was verified for lebogou 260703 only")
    run(["javac", "-source", "8", "-target", "8", "-d", classes, ROOT / "native_signer/SignProbe.java", ROOT / "native_signer/com/vzan/live/publisher/SignUtils.java"])
    run([build_tools / "d8", "--min-api", "26", "--output", dex, classes / "SignProbe.class", classes / "com/vzan/live/publisher/SignUtils.class"])
    run([adb, "-s", serial, "push", dex / "classes.dex", "/data/local/tmp/answer-sign.dex"])
    run([adb, "-s", serial, "push", so, "/data/local/tmp/answer-libpush.so"])


def signed_params(serial, sdk, values):
    timestamp = str(int(time.time() * 1000))
    uid = str(values.get("uid", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]*", uid):
        raise ValueError("unsupported uid format")
    # Only fixed command tokens and validated identifier fields go through adb shell.
    uid_arg = uid or "''"
    command = f"CLASSPATH=/data/local/tmp/answer-sign.dex app_process /system/bin SignProbe {timestamp} {uid_arg} {VERSION}"
    output = run([sdk / "platform-tools/adb", "-s", serial, "shell", command])
    match = re.search(r"^SIGN_RESULT ([0-9a-fA-F]+)$", output, re.M)
    if not match:
        raise RuntimeError("native signer returned no signature")
    return dict(values, uid=uid, deviceType="1", versionCode=VERSION, timestamp=timestamp, sign=match[1], platform="android_vzanlive", appid=PACKAGE)


def request(serial, sdk, endpoint, values):
    permitted = {"GetDomain", "SendNormalUserLoginVerifiyCode", "NormalUserLoginByPhoneV2"}
    if endpoint not in permitted:
        raise ValueError("unsupported endpoint")
    data = urlencode(signed_params(serial, sdk, values)).encode()
    headers = {"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "okhttp/4.12.0", "Authorization": "Bearer ", "appname": "lebogou", "appchannel": CHANNEL, "packagename": PACKAGE, "uniqueType": "Android", "wxappid": "wxa010fa37c86b1da5"}
    with urlopen(Request("https://liveapi.njyqkj0ksyz.com/VNLive/" + endpoint, data=data, headers=headers), timeout=20) as response:
        return json.loads(response.read(2_000_000))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "domain", "send-code", "login"])
    parser.add_argument("--apk")
    parser.add_argument("--serial", default="emulator-5580")
    parser.add_argument("--sdk", default=str(Path.home() / "Library/Android/sdk"))
    args = parser.parse_args()
    sdk = Path(args.sdk)
    os.umask(0o077)
    if args.mode == "prepare":
        if not args.apk:
            parser.error("prepare requires --apk")
        prepare(Path(args.apk), args.serial, sdk)
        print("native signer prepared")
        return
    if args.mode == "domain":
        result = request(args.serial, sdk, "GetDomain", {})
        # Public bootstrap only. Account login responses are never printed.
        print(json.dumps({"isok": result.get("isok"), "domain": result.get("dataObj") if result.get("isok") is True else None}, ensure_ascii=False))
        return
    phone = input("乐播购登录手机号（仅提交给乐播购）: ").strip()
    if not re.fullmatch(r"1[0-9]{10}", phone):
        raise ValueError("invalid phone format")
    values = {"phone": phone}
    endpoint = "SendNormalUserLoginVerifiyCode"
    if args.mode == "login":
        values["code"] = getpass.getpass("短信验证码（不显示）: ").strip()
        endpoint = "NormalUserLoginByPhoneV2"
    result = request(args.serial, sdk, endpoint, values)
    if result.get("isok") is not True:
        print("login operation was not accepted; no credentials saved:", result.get("Msg") or result.get("msg") or result.get("message") or "unknown reason")
        raise SystemExit(1)
    if args.mode == "login":
        destination = ROOT / "private/lebogou-login.json"
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        destination.write_text(json.dumps(result, ensure_ascii=False))
        os.chmod(destination, 0o600)
        data = result.get("dataObj")
        if not isinstance(data, dict):
            print("login response stored; account data must be checked before use")
        elif data.get("allowMultiAccount") or data.get("needWechatAuth"):
            print("login response stored; account selection or WeChat binding is still required")
        else:
            print("login response stored; authenticated API access still needs verification")
    else:
        print("SMS request accepted")


if __name__ == "__main__":
    main()
