"""Prepare short pitch-preserving rhythm cues from the existing licensed voice.
Requires ffmpeg; reads source WAVs without changing them. No model downloads.
"""
from pathlib import Path
import subprocess, wave, json, hashlib
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio/rhythm'
OUT.mkdir(exist_ok=True)
SPEEDS = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]
manifest = {'source':'release/audio-provenance.json', 'processing':'ffmpeg atempo (pitch preserving), 5ms/15ms fades, gain 0.8', 'files':{}}
for cue in ['ready','charge','guard','wave']:
    for index,speed in enumerate(SPEEDS):
        dest = OUT/f'{cue}-{index}.wav'
        source = ROOT/f'assets/audio/{cue}.wav'
        with wave.open(str(source)) as w: duration = w.getnframes()/w.getframerate()/speed
        filters = f'atempo={speed},afade=t=in:d=0.005,afade=t=out:st={max(0,duration-0.015)}:d=0.015,volume=0.8'
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(source),'-af',filters,'-ar','24000','-ac','1',str(dest)],check=True)
        with wave.open(str(dest)) as w: actual = w.getnframes()/w.getframerate()
        manifest['files'][dest.name] = {'seconds':actual,'speed':speed,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
(ROOT/'release/rhythm-audio-provenance.json').write_text(json.dumps(manifest,indent=2))
print(f'Prepared {len(manifest["files"])} rhythm cues')
