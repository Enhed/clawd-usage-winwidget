"""Composite frames from record-gif.ps1 onto a solid background and encode a GIF.

usage: python tools/compose-gif.py <frames dir> <out.gif>
Needs Pillow and ffmpeg on PATH. The GIF plays at the mascot's 90 ms step.
"""
import glob, json, os, subprocess, sys, tempfile
from PIL import Image

BG = (13, 17, 23, 255)   # GitHub dark
PAD, DOWN = 24, 1.5      # padding in source pixels; frames are rendered at 2x

src, out = sys.argv[1], sys.argv[2]
meta = json.load(open(os.path.join(src, 'meta.json'), encoding='utf-8-sig'))
frames = [Image.open(f).convert('RGBA') for f in sorted(glob.glob(os.path.join(src, 'f*.png')))]
if meta.get('cropH'):
    frames = [f.crop((0, 0, f.width, meta['cropH'])) for f in frames]
# The window can grow while it loads - pad every frame to the largest one.
W = max(f.width for f in frames)
H = max(f.height for f in frames)
with tempfile.TemporaryDirectory() as tmp:
    for i, f in enumerate(frames):
        canvas = Image.new('RGBA', (W + 2 * PAD, H + 2 * PAD), BG)
        canvas.alpha_composite(f, (PAD, PAD))
        canvas = canvas.resize((round(canvas.width / DOWN), round(canvas.height / DOWN)), Image.LANCZOS)
        canvas.convert('RGB').save(os.path.join(tmp, f'{i:04d}.png'))
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(1 / 0.09),
                    '-i', os.path.join(tmp, '%04d.png'), '-filter_complex',
                    'split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];'
                    '[b][p]paletteuse=dither=none:diff_mode=rectangle',
                    '-loop', '0', out], check=True)
print(out, len(frames), 'frames', os.path.getsize(out) // 1024, 'KB')
