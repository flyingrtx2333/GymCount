#!/usr/bin/env python3
"""Trace approved/generated line art into transparent, editable SVG paths.

Requires Pillow and the potrace CLI. Generation is separate and never repeated
by this script. Label-free crop bounds and source provenance remain reproducible.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'design/exercise-icons'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
catalog = []
base = [
    ('squat', '深蹲', 'barbell', (0, 0, 418, 369)),
    ('bench_press', '卧推', 'barbell', (418, 0, 836, 369)),
    ('deadlift', '硬拉', 'barbell', (836, 0, 1254, 369)),
    ('bicep_curl', '弯举', 'dumbbell', (0, 422, 418, 799)),
    ('rest', '静止', 'sample', (418, 422, 836, 799)),
    ('walking', '走动', 'sample', (836, 422, 1254, 799)),
    ('other', '其他非训练', 'sample', (0, 854, 418, 1190)),
]
jobs = [(key, name, category, 'imagegen-exercises-line-v1.png', bounds)
        for key, name, category, bounds in base]

def blank_boundary(image, expected, horizontal=True):
    """Find the center of a white gutter instead of cutting generated line art."""
    runs, start = [], None
    for position in range(expected-48, expected+49):
        line = image.crop((0, position, image.width, position+1) if horizontal
                          else (position, 0, position+1, image.height))
        blank = min(line.get_flattened_data()) >= 155
        if blank and start is None:
            start = position
        if not blank and start is not None:
            runs.append((start, position))
            start = None
    if start is not None:
        runs.append((start, expected+49))
    assert runs, 'No white separation between generated cells'
    first, last = max(runs, key=lambda run: run[1]-run[0])
    return (first+last)//2

for batch in json.loads((DESIGN/'concepts/expansion-manifest.json').read_text()):
    sheet = Image.open(DESIGN/'concepts'/f"line-{batch['key']}-v1.png").convert('L')
    xs = [0, blank_boundary(sheet, 418, False), blank_boundary(sheet, 836, False), 1254]
    ys = [0, blank_boundary(sheet, 418), blank_boundary(sheet, 836), 1254]
    for i, (key, name) in enumerate(zip(batch['ids'], batch['names'])):
        col, row = i % 3, i // 3
        jobs.append((key, name, batch['key'], f"line-{batch['key']}-v1.png",
                     (xs[col], ys[row], xs[col+1], ys[row+1])))

report = []
with tempfile.TemporaryDirectory(prefix='gymcount-vector-') as temp:
    temp = Path(temp)
    for key, name, category, source, bounds in jobs:
        original = Image.open(DESIGN/'concepts'/source).convert('RGB')
        assert original.size == (1254, 1254), f'Unexpected sheet dimensions: {source}'
        gray = ImageOps.grayscale(original.crop(bounds))
        binary = gray.point(lambda value: 0 if value < 155 else 255)
        bbox = ImageOps.invert(binary).getbbox()
        assert bbox is not None, key
        # Cell crops must not cut the outline or include adjacent-cell strokes.
        assert bbox[0] > 1 and bbox[1] > 1, (key, bbox)
        assert bbox[2] < binary.width-1 and bbox[3] < binary.height-1, (key, bbox)
        ink = binary.crop(bbox)
        scale = 448 / max(ink.size)
        size = tuple(round(value*scale) for value in ink.size)
        ink = ink.resize(size, Image.Resampling.LANCZOS).point(lambda v: 0 if v < 155 else 255)
        canvas = Image.new('L', (512, 512), 255)
        canvas.paste(ink, ((512-size[0])//2, (512-size[1])//2))
        bitmap = temp/f'{key}.pbm'
        canvas.convert('1').save(bitmap)
        traced = temp/f'{key}.svg'
        subprocess.run(['potrace', str(bitmap), '--svg', '--output', str(traced),
                        '--turdsize', '3', '--alphamax', '0.8', '--opttolerance', '0.05'], check=True)
        traced_root = ET.parse(traced).getroot()
        svg = ET.Element(f'{{{NS}}}svg', {'viewBox':'0 0 64 64', 'fill':'currentColor',
                        'stroke':'none', 'role':'img', 'aria-labelledby':f'{key}-title'})
        ET.SubElement(svg, f'{{{NS}}}title', {'id':f'{key}-title'}).text = name
        wrapper = ET.SubElement(svg, f'{{{NS}}}g', {'transform':'scale(0.125)'})
        for child in traced_root:
            if child.tag.endswith('metadata'):
                continue
            for node in child.iter():
                if node.get('fill') in ('#000000', '#000', 'black'):
                    node.set('fill', 'currentColor')
            wrapper.append(child)
        text = ET.tostring(svg, encoding='unicode')+'\n'
        (DESIGN/'svg'/f'{key}.svg').write_text(text)
        catalog.append({'id':key, 'name':name, 'group':'sample' if category=='sample' else 'strength',
                        'category':category, 'file':f'svg/{key}.svg', 'asset':f'Exercise-{key}',
                        'source':f'concepts/{source}', 'crop':list(bounds)})
        normalized = DESIGN/'validation'/f'{key}-source.png'
        normalized.parent.mkdir(exist_ok=True)
        canvas.save(normalized)
        report.append({'id':key, 'bytes':len(text.encode()), 'paths':sum(n.tag.endswith('path') for n in svg.iter())})

assert len(catalog) == 43 and len({item['id'] for item in catalog}) == 43
(DESIGN/'catalog.json').write_text(json.dumps({'version':6, 'style':'athletic-contour',
    'viewBox':[0,0,64,64], 'icons':catalog}, ensure_ascii=False, indent=2)+'\n')
(DESIGN/'validation/trace-report.json').write_text(json.dumps(report, indent=2)+'\n')
print(f'Traced {len(catalog)} transparent SVGs; {sum(item["bytes"] for item in report)} bytes total')
