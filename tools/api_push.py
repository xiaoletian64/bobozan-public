#!/usr/bin/env python3
"""106 上跑：用 Git Data API 把沙箱来的修改推上 GitHub（绕过 git smart-http 被掐）。
用法: python3 api_push.py <manifest文件>  # manifest 每行: <本地路径>\t<仓库内路径>
"""
import sys, json, base64, subprocess

REPO = "xiaoletian64/bobozan"

def gh(endpoint, input=None, method=None):
    cmd = ["gh", "api", "repos/" + REPO + endpoint]
    if method: cmd += ["-X", method]
    if input is not None:
        cmd += ["--input", "-"]
        r = subprocess.run(cmd, input=json.dumps(input).encode(),
                           capture_output=True)
    else:
        r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode()[:300])
    return json.loads(r.stdout) if r.stdout.strip() else {}

manifest = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]

ref = gh("/git/ref/heads/main")
head = ref["object"]["sha"]
commit = gh("/git/commits/" + head)
base_tree = commit["tree"]["sha"]
print("head:", head[:10], "tree:", base_tree[:10])

tree_items = []
for local, inrepo in manifest:
    data = open(local, "rb").read()
    b = gh("/git/blobs", {"content": base64.b64encode(data).decode(), "encoding": "base64"})
    tree_items.append({"path": inrepo, "mode": "100644", "type": "blob", "sha": b["sha"]})
    print("blob:", inrepo, len(data), "bytes")

tree = gh("/git/trees", {"base_tree": base_tree, "tree": tree_items})
print("new tree:", tree["sha"][:10])

new = gh("/git/commits", {"message": "iOS App Store readiness: production preset+icons, CI workflow, BLE plist keys, hide OTA on iOS",
    "tree": tree["sha"], "parents": [head]})
print("new commit:", new["sha"][:10])

gh("/git/refs/heads/main", {"sha": new["sha"], "force": False}, method="PATCH")
print("PUSHED main ->", new["sha"][:10])
