"""Download selected official Godot 4.4.1 templates using HTTPS range reads."""
import io, urllib.request, zipfile, pathlib
URL='https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz'
class Remote(io.RawIOBase):
 def __init__(self):
  with urllib.request.urlopen(urllib.request.Request(URL,method='HEAD'),timeout=60) as r:
   self.url=r.url; self.size=int(r.headers['Content-Length'])
  self.pos=0
 def seekable(self): return True
 def seek(self,n,whence=0):
  self.pos = n if whence==0 else (self.pos+n if whence==1 else self.size+n)
  return self.pos
 def tell(self): return self.pos
 def read(self,n=-1):
  if n<0:n=self.size-self.pos
  if not n:return b''
  req=urllib.request.Request(self.url,headers={'Range':f'bytes={self.pos}-{self.pos+n-1}'})
  with urllib.request.urlopen(req,timeout=180) as r:
   if r.status!=206: raise RuntimeError('Server did not honor range')
   data=r.read()
  if len(data)!=n:raise RuntimeError('Incorrect range length')
  self.pos+=len(data);return data
with zipfile.ZipFile(Remote()) as z:
 for name in z.namelist():
  if name.endswith(('android_debug.apk','ios.zip')):
   print('Fetching',name, z.getinfo(name).file_size, flush=True)
   data=z.read(name)
   out=pathlib.Path(__file__).resolve().parents[1]/'builds/templates'/pathlib.Path(name).name
   out.parent.mkdir(parents=True, exist_ok=True)
   out.write_bytes(data)
   print('Verified ZIP CRC:',out.name,flush=True)
