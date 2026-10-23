"""Exercise the actual Swift bridge on macOS; this is not a BLE radio test."""
from pathlib import Path
import json, socket, subprocess
root=Path(__file__).resolve().parents[1]
app=subprocess.Popen([str(root/'builds/native-bridge-test')],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
try:
    cfg=json.loads(app.stdout.readline())
    port=int(cfg['port'])
    assert 0<port<65536 and len(cfg['token'])>=24
    def connect():
        s=socket.create_connection(('127.0.0.1',port),timeout=5)
        s.settimeout(5)
        return s
    with connect() as s:
        s.sendall(b'{"token":"wrong"}\n')
        assert s.recv(1)==b''
    with connect() as s:
        s.sendall(b'x'*8193)
        try: assert s.recv(1)==b''
        except ConnectionResetError: pass
    for _ in range(3):
        with connect() as s:
            s.sendall((json.dumps({'token':cfg['token']})+'\n').encode())
            event=json.loads(s.makefile('rb').readline())
            assert event['event']=='bridge_ready'
            s.sendall(b'{"command":"disconnect"}\n')
    print('PASS: Swift loopback bridge rejects wrong token and oversized auth, accepts valid auth and three reconnects; no radio exercised')
finally:
    app.terminate()
    app.wait(timeout=10)
