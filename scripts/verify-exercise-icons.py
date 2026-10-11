#!/usr/bin/env python3
"""Check SVG geometry, transparency, source fidelity and portable archive."""
from pathlib import Path
import hashlib
import json
import zipfile
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops, ImageOps, ImageFilter
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT/'design/exercise-icons'
OUTPUT = ROOT/'build/ExerciseIcons'
OUTPUT.mkdir(parents=True,exist_ok=True)
catalog = json.loads((DESIGN/'catalog.json').read_text())
assert len(catalog['icons']) == 43
report, hashes = [], set()
for item in catalog['icons']:
    source = DESIGN/item['file']
    svg = ET.parse(source).getroot()
    tags = [node.tag.split('}')[-1] for node in svg.iter()]
    assert svg.get('viewBox') == '0 0 64 64' and 'path' in tags
    assert not any(tag in tags for tag in ['image','script','foreignObject','mask'])
    assert 'data:' not in source.read_text() and 'base64' not in source.read_text()
    geometry = [(node.tag, sorted(node.attrib.items())) for node in svg.iter()
                if node.tag.endswith(('path','g'))]
    digest = hashlib.sha256(json.dumps(geometry).encode()).hexdigest()
    assert digest not in hashes, item['id']
    hashes.add(digest)
    rendered = OUTPUT/f'{item["id"]}.png'
    cairosvg.svg2png(url=str(source),write_to=str(rendered),output_width=512,output_height=512)
    image = Image.open(rendered).convert('RGBA')
    alpha = image.getchannel('A')
    assert alpha.getextrema() == (0,255), item['id']
    bbox = alpha.getbbox()
    assert bbox[0] >= 30 and bbox[1] >= 30 and bbox[2] <= 482 and bbox[3] <= 482, (item['id'],bbox)
    ink = alpha.point(lambda value:255 if value>=128 else 0)
    original = ImageOps.invert(Image.open(DESIGN/'validation'/f'{item["id"]}-source.png').convert('L'))
    original = original.point(lambda value:255 if value>=128 else 0)
    intersection = ImageChops.multiply(ink,original)
    union = ImageChops.lighter(ink,original)
    iou = sum(intersection.get_flattened_data())/sum(union.get_flattened_data())
    # Curve tracing smooths staircase pixels; permit one pixel at 512 px while
    # requiring the actual ink shape to stay close to the approved raster.
    source_near = original.filter(ImageFilter.MaxFilter(3))
    vector_near = ink.filter(ImageFilter.MaxFilter(3))
    missed = sum(ImageChops.subtract(original,vector_near).get_flattened_data())
    added = sum(ImageChops.subtract(ink,source_near).get_flattened_data())
    edge_error = (missed+added)/sum(union.get_flattened_data())
    assert iou > 0.90 and edge_error < 0.02, (item['id'],iou,edge_error)
    report.append({'id':item['id'],'iou':round(iou,4),'edgeError':round(edge_error,4),'bounds':bbox,'bytes':source.stat().st_size})
for name in ['overview','overview-barbell','overview-dumbbell','overview-machine','overview-bodyweight','overview-sample','strength-detail']:
    cairosvg.svg2png(url=str(DESIGN/f'{name}.svg'),write_to=str(OUTPUT/f'{name}.png'))
with zipfile.ZipFile(DESIGN/'gymcount-exercise-icons.zip') as archive:
    assert len([name for name in archive.namelist() if name.startswith('svg/')]) == 43
    assert archive.testzip() is None
    for item in catalog['icons']:
        assert archive.read(item['file']) == (DESIGN/item['file']).read_bytes()
(OUTPUT/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(report)} SVGs verified: transparent backgrounds, unique geometry, no bitmap payload; minimum source IoU {min(r["iou"] for r in report):.4f}')
