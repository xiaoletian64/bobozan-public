"""Generate fixed game cues locally using Kokoro's Apache-2.0 Chinese model.
Run using builds/audio-venv. Only resulting WAV assets ship in the game.
"""
from pathlib import Path
import hashlib, json
import numpy as np
import soundfile as sf
from kokoro import KModel, KPipeline

ROOT = Path(__file__).resolve().parents[1]
REPO = 'hexgrad/Kokoro-82M-v1.1-zh'
VOICE = 'zm_010'
CUES = {'ready':'波！', 'charge':'攒！', 'wave':'波！', 'guard':'防！', 'super':'强化波！', 'strong_guard':'强化防！'}
model = KModel(repo_id=REPO).to('cpu').eval()
pipeline = KPipeline(lang_code='z', repo_id=REPO, model=model, en_callable=lambda text: '')
out = ROOT / 'builds/voice-candidate'
out.mkdir(exist_ok=True)
manifest = {'model':REPO,'voice':VOICE,'license':'Apache-2.0','sample_rate':24000,'cues':{}}
for name, text in CUES.items():
    chunks = [r.audio.numpy() for r in pipeline(text, voice=VOICE, speed=1.15)]
    data = np.concatenate(chunks)
    audible = np.flatnonzero(np.abs(data) > 0.007)
    if len(audible) == 0: raise RuntimeError('Silent cue: '+name)
    data = data[max(0,audible[0]-240):min(len(data),audible[-1]+720)]
    data = data / max(float(np.max(np.abs(data))),0.001) * 0.8
    path = out / (name+'.wav')
    sf.write(path,data,24000,subtype='PCM_16')
    manifest['cues'][name] = {'text':text,'seconds':len(data)/24000,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    print(name,manifest['cues'][name],flush=True)
(out/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
