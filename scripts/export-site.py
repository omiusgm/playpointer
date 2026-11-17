from base64 import b64encode
from html import escape
from pathlib import Path
import json
import re
import subprocess
import sys

source = Path(sys.argv[1])
output = Path(sys.argv[2])
mime_types = {'.webp': 'image/webp', '.svg': 'image/svg+xml', '.wav': 'audio/wav', '.woff2': 'font/woff2'}

def data_url(path):
    return 'data:' + mime_types[path.suffix] + ';base64,' + b64encode(path.read_bytes()).decode('ascii')

assets = {p.relative_to(source).as_posix(): data_url(p) for p in sorted((source / 'assets').iterdir()) if p.is_file() and p.suffix in mime_types}
css = (source / 'styles.css').read_text()
fonts = {p.relative_to(source).as_posix(): data_url(p) for p in sorted((source / 'fonts').glob('*.woff2'))}
for path, url in fonts.items():
    css = css.replace(f'url("{path}")', f'url("{url}")')
css += '\n.offline-licenses { display:none; padding-block:2rem; }\n.offline-licenses:target { display:block; }\n.offline-licenses h2 { font-size:clamp(1.4rem,4vw,2.4rem); }\n.offline-licenses h3 { margin-block-start:1.35rem; }\n.offline-licenses pre { white-space:pre-wrap; overflow-wrap:anywhere; margin-block-start:.6rem; }\n'
page = (source / 'index.html').read_text()
assert page.count('<link rel="stylesheet" href="styles.css">') == 1
page = page.replace('<link rel="stylesheet" href="styles.css">', f'<style>\n{css}</style>')
page = page.replace('  <script defer src="cursors.js"></script>\n  <script defer src="demo.js"></script>\n', '')
page = page.replace('href="assets/funny22.webp" type="image/webp"', 'href="data:," type="image/webp" data-offline-href="assets/funny22.webp"')
seen = set()

def embed_image(match):
    path = match.group(1)
    if path in seen:
        return f'data-offline-src="{path}"'
    seen.add(path)
    return f'src="{assets[path]}" data-offline-asset="{path}"'

page = re.sub(r'\bsrc="(assets/[^"]+)"', embed_image, page)
manifest = (source / 'cursors.js').read_text()
cursors = json.loads(manifest.split('=', 1)[1].strip().removesuffix(';'))
for cursor in cursors:
    for key in ['image', 'pressed', 'alternate']:
        if cursor.get(key):
            assert cursor[key] in assets
    for key in ['rod', 'pressedRod']:
        if cursor.get(key, {}).get('image'):
            assert cursor[key]['image'] in assets
used_assets = set(seen) | {'assets/funny22.webp'}
for cursor in cursors:
    used_assets.update(cursor[key] for key in ['image', 'pressed', 'alternate'] if cursor.get(key))
    used_assets.update(cursor[key]['image'] for key in ['rod', 'pressedRod'] if cursor.get(key, {}).get('image'))
used_assets.update('assets/' + name + '.wav' for name in ['tap_bongo_left', 'tap_bongo_right', 'tap_magic', 'tap_click'])
assets = {path: url for path, url in assets.items() if path in used_assets}
demo = (source / 'demo.js').read_text()
audio = 'new Audio(`assets/${file}.wav`)'
assert demo.count(audio) == 1
demo = demo.replace(audio, 'new Audio(offlineAssets[`assets/${file}.wav`])')
script = '''(() => {
"use strict";
const offlineAssets = ''' + json.dumps({p: u for p, u in assets.items() if p not in seen}, ensure_ascii=False) + ''';
document.querySelectorAll('[data-offline-asset]').forEach(image => { offlineAssets[image.dataset.offlineAsset] = image.getAttribute('src'); });
document.querySelectorAll('[data-offline-src]').forEach(image => { image.src = offlineAssets[image.dataset.offlineSrc]; });
document.querySelectorAll('[data-offline-href]').forEach(link => { link.href = offlineAssets[link.dataset.offlineHref]; });
''' + manifest + '''
for (const cursor of window.PLAYPOINTER_CURSORS) {
  for (const frame of ['image', 'pressed', 'alternate']) {
    if (cursor[frame]) cursor[frame] = offlineAssets[cursor[frame]];
  }
  for (const key of ['rod', 'pressedRod']) {
    if (cursor[key]?.image) cursor[key].image = offlineAssets[cursor[key].image];
  }
}
''' + demo + '\n})();\n'
assert '</script' not in script.lower()
subprocess.run(['node', '--check'], input=script.encode(), check=True)
mit = (source / 'PLAYPOINTER-LICENSE.txt').read_text()
ofl = (source / 'fonts/OFL.txt').read_text()
page = page.replace('<a href="PLAYPOINTER-LICENSE.txt">Лицензия MIT</a>', '<a href="#offline-licenses">Лицензии MIT и OFL</a>')
licenses = '<section class="wrap offline-licenses" id="offline-licenses" aria-labelledby="offline-licenses-title"><h2 id="offline-licenses-title">Лицензии</h2><h3>PlayPointer · MIT</h3><pre>' + escape(mit) + '</pre><h3>Unbounded · SIL Open Font License 1.1</h3><pre>' + escape(ofl) + '</pre></section>'
page = page.replace('</body>', licenses + '\n<script>\n' + script + '</script>\n</body>')
assert not re.search(r'(?<![-\w])(?:src|href)="(?:assets/|fonts/|styles.css|demo.js|cursors.js|PLAYPOINTER-LICENSE)', page)
for url in set(assets.values()) | set(fonts.values()):
    assert page.count(url) == 1, 'Repeated or missing asset'
output.write_text(page)
print(f'{output}: {len(cursors)} cursors, {len(assets)} assets, {output.stat().st_size} bytes, inline JS syntax passed')
