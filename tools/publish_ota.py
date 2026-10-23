"""Build a signed OTA release; --deploy publishes APK before atomically replacing latest.json."""
import argparse, base64, hashlib, json, os, pathlib, re, shlex, shutil, subprocess, tempfile, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
CERT = "b25a3706bc994b9493577e83819616b1f73eb34321582da526bc6df58b66d755"
PACKAGE = "com.prototype.bobozan"

def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--apk',required=True,type=pathlib.Path)
    p.add_argument('--notes',required=True)
    p.add_argument('--key',type=pathlib.Path,default=pathlib.Path.home()/'.config/bobozan-ota/manifest-private.pem')
    p.add_argument('--output',type=pathlib.Path,default=ROOT/'release/ota')
    p.add_argument('--deploy',action='store_true')
    p.add_argument('--ssh',default='bobozan-release')
    args=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.@-]+',args.ssh): raise ValueError('Invalid SSH alias')
    sdk=pathlib.Path(os.environ.get('ANDROID_HOME',str(pathlib.Path.home()/'Library/Android/sdk')))
    build=sdk/'build-tools/35.0.0'
    signed=run([str(build/'apksigner'),'verify','--print-certs',str(args.apk)],text=True).stdout
    if CERT not in signed: raise ValueError('APK signing certificate differs from installed builds')
    metadata=run([str(build/'aapt'),'dump','badging',str(args.apk)],text=True).stdout
    match=re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",metadata)
    if not match or match[1] != PACKAGE or not re.fullmatch(r'[0-9A-Za-z.-]+',match[3]): raise ValueError('Invalid package or version')
    sdk_match=re.search(r"sdkVersion:'(\d+)'",metadata)
    if not sdk_match: raise ValueError('Missing min SDK')
    public=run(['openssl','pkey','-in',str(args.key),'-pubout','-outform','DER']).stdout
    if base64.b64encode(public).decode() != (ROOT/'native/android/ota-public-key.txt').read_text().strip(): raise ValueError('Manifest signing key does not match app trust key')
    sha=hashlib.file_digest(args.apk.open('rb'),'sha256').hexdigest()
    filename=f'bobozan-v{match[3]}-{match[2]}.apk'
    release=dict(package=PACKAGE,version_code=int(match[2]),version_name=match[3],min_sdk=int(sdk_match[1]),file=filename,size=args.apk.stat().st_size,sha256=sha,notes=args.notes[:1200])
    payload=json.dumps(release,ensure_ascii=False,separators=(',',':')).encode()
    signature=run(['openssl','dgst','-sha256','-sign',str(args.key)],input=payload).stdout
    envelope=json.dumps(dict(payload=base64.b64encode(payload).decode(),signature=base64.b64encode(signature).decode()),separators=(',',':')).encode()
    args.output.mkdir(parents=True,exist_ok=True)
    shutil.copy2(args.apk,args.output/filename)
    (args.output/'latest.json').write_bytes(envelope)
    if args.deploy:
        # Remote guard serializes releases, rejects rollback and immutable-version replacement.
        staging='/srv/bobozan-ota/staging-'+uuid.uuid4().hex
        run(['ssh','-o','BatchMode=yes',args.ssh,'mkdir -m 700 '+shlex.quote(staging)])
        try:
            run(['scp',str(args.output/filename),str(args.output/'latest.json'),args.ssh+':'+staging+'/'])
            code='''import base64,fcntl,hashlib,json,os,pathlib,shutil
root=pathlib.Path('/srv/bobozan-ota/public')
root.mkdir(parents=True,exist_ok=True)
with open('/srv/bobozan-ota/publish.lock','w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 src=pathlib.Path(STAGING)
 envelope=json.loads((src/'latest.json').read_text())
 new=json.loads(base64.b64decode(envelope['payload']))
 old_file=root/'latest.json'
 if old_file.exists():
  old=json.loads(base64.b64decode(json.loads(old_file.read_text())['payload']))
  assert new['version_code'] >= old['version_code'],'Refusing rollback'
  assert new['version_code'] != old['version_code'] or new['sha256']==old['sha256'],'Version is immutable'
 apk=src/new['file']
 assert apk.stat().st_size==new['size']
 assert hashlib.sha256(apk.read_bytes()).hexdigest()==new['sha256']
 apk.chmod(0o644)
 os.replace(apk,root/new['file'])
 (src/'latest.json').chmod(0o644)
 os.replace(src/'latest.json',old_file)
print('Published',new['version_name'],new['version_code'])
'''
            code='STAGING='+repr(staging)+'\n'+code
            print(run(['ssh','-o','BatchMode=yes',args.ssh,'python3 -'],input=code,text=True).stdout.strip())
        finally:
            run(['ssh','-o','BatchMode=yes',args.ssh,'rm -rf -- '+shlex.quote(staging)])
    print(json.dumps(release,ensure_ascii=False))
if __name__=='__main__': main()
