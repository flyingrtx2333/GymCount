#!/usr/bin/env python3
"""Build native template assets, searchable gallery, SVG sprite and ZIP."""
from pathlib import Path
import json
import math
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'design/exercise-icons'
catalog = json.loads((SOURCE/'catalog.json').read_text())
categories = {'barbell':'杠铃','dumbbell':'哑铃','machine':'器械与绳索','bodyweight':'自重与壶铃','sample':'采集类别'}
icons, symbols, seen = [], [], set()
for item in catalog['icons']:
    assert item['id'] not in seen
    seen.add(item['id'])
    source = SOURCE/item['file']
    svg = ET.fromstring(source.read_text())
    assert svg.get('viewBox') == '0 0 64 64'
    assert any(node.tag.endswith('path') for node in svg.iter())
    assert not any(node.tag.endswith(('script','image','foreignObject','mask')) for node in svg.iter())
    for target in ['GymCount Watch App','GymCount iOS']:
        asset = ROOT/target/'Assets.xcassets'/(item['asset']+'.imageset')
        asset.mkdir(parents=True,exist_ok=True)
        (asset/'icon.svg').write_text(source.read_text().replace('currentColor','#000000'))
        (asset/'Contents.json').write_text(json.dumps(dict(images=[dict(filename='icon.svg',idiom='universal')],info=dict(author='xcode',version=1),properties={'preserves-vector-representation':True,'template-rendering-intent':'template'}),indent=2)+'\n')
    inline = source.read_text().replace('role="img"','aria-hidden="true"').replace(f'aria-labelledby="{item["id"]}-title"','').replace(f'id="{item["id"]}-title"','')
    icons.append(dict(item,inline=inline))
    inner = ''.join(ET.tostring(child,encoding='unicode') for child in svg if not child.tag.endswith('title'))
    symbols.append(f'<symbol id="exercise-{item["id"]}" viewBox="0 0 64 64">{inner}</symbol>')
for target in ['GymCount Watch App','GymCount iOS']:
    contents = ROOT/target/'Assets.xcassets/Contents.json'
    if not contents.exists(): contents.write_text('{"info":{"author":"xcode","version":1}}\n')
(SOURCE/'sprite.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"><defs>'+''.join(symbols)+'</defs></svg>')
cards = ''.join(f'<button class="card" data-id="{i["id"]}" data-category="{i["category"]}" data-name="{i["name"]}" aria-pressed="false"><span class="glyph">{i["inline"]}</span><strong>{i["name"]}</strong><small>{categories[i["category"]]}</small></button>' for i in icons)
filters = '<button class="filter active" data-filter="all" aria-pressed="true">全部 · 43</button>'
filters += ''.join(f'<button class="filter" data-filter="{key}" aria-pressed="false">{name} · {sum(i["category"]==key for i in icons)}</button>' for key,name in categories.items())
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GymCount · 动作图标库</title><style>
:root{color-scheme:light;--bg:#f5f7f4;--surface:#fff;--ink:#152c24;--muted:#63766e;--line:#dce5dd;--accent:#237d55}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}body.dark{color-scheme:dark;--bg:#101713;--surface:#18231d;--ink:#eef6f0;--muted:#a0b1a5;--line:#34483c;--accent:#8ae2ad}main{max-width:1280px;margin:auto;padding:40px 28px}header{display:flex;justify-content:space-between;align-items:start;gap:20px}.eyebrow{font-size:11px;letter-spacing:2px;color:var(--muted);margin:0 0 12px}h1{font-size:30px;margin:0 0 10px}p{font-size:14px;line-height:1.7;color:var(--muted);margin:0}button,input,a{font:inherit}button{cursor:pointer;color:inherit;border:1px solid var(--line);background:var(--surface);border-radius:10px}button:focus-visible,input:focus-visible,a:focus-visible{outline:3px solid var(--accent);outline-offset:3px}.actions{display:flex;gap:8px;flex-wrap:wrap}#theme,.download{padding:11px 14px;font-size:13px}.download{background:var(--ink);color:var(--surface);border-radius:10px;text-decoration:none;white-space:nowrap}.tools{display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin:28px 0 20px}.filters{display:flex;flex-wrap:wrap;gap:6px;flex:1}.filter{padding:9px 11px;font-size:12px}.filter.active{border-color:var(--accent);color:var(--accent)}#search{width:220px;padding:11px 12px;background:var(--surface);color:var(--ink);border:1px solid var(--line);border-radius:10px}.layout{display:grid;grid-template-columns:minmax(0,1fr) 240px;gap:24px}.catalog{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;align-content:start}.card{display:flex;align-items:center;flex-direction:column;padding:18px 6px 14px;gap:11px;min-width:0}.card[aria-pressed=true]{border-color:var(--accent);box-shadow:inset 0 0 0 1px var(--accent)}.card[hidden]{display:none}.glyph{width:100px;height:100px;display:block}.glyph svg{width:100%;height:100%;display:block}strong{font-size:13px;text-align:center}small{font-size:10px;color:var(--muted)}aside{position:sticky;top:24px;align-self:start;border:1px solid var(--line);border-radius:16px;padding:20px;background:var(--surface)}#selected-large{width:180px;height:180px;margin:0 auto 16px}#selected-large svg{width:100%;height:100%}h2{font-size:17px;margin:0 0 6px}#selected-id{font-size:10px;color:var(--muted);overflow-wrap:anywhere;margin:0 0 20px}.sizes{display:flex;align-items:end;justify-content:space-between;gap:12px;border-top:1px solid var(--line);padding-top:18px}.size{display:flex;align-items:center;flex-direction:column;gap:9px;font-size:10px;color:var(--muted)}.size svg{display:block;color:var(--ink)}#download-one{display:block;text-align:center;border:1px solid var(--line);border-radius:8px;padding:10px;margin-top:20px;color:var(--accent);text-decoration:none;font-size:12px}.count{font-size:12px;color:var(--muted);margin-top:18px}#empty{grid-column:1/-1;padding:40px;text-align:center}footer{margin-top:30px;border-top:1px solid var(--line);padding-top:20px;font-size:12px;color:var(--muted);line-height:1.8}@media(max-width:950px){.catalog{grid-template-columns:repeat(3,minmax(0,1fr))}.layout{grid-template-columns:minmax(0,1fr) 220px}.glyph{width:88px;height:88px}}@media(max-width:680px){main{padding:24px 16px}header{flex-direction:column}h1{font-size:25px}.layout{display:flex;flex-direction:column}aside{position:static;order:-1;display:grid;grid-template-columns:110px minmax(0,1fr);column-gap:16px;padding:16px}#selected-large{grid-row:1/5;width:110px;height:110px;margin:0}.sizes{padding-top:10px;gap:8px}#selected-id{margin-bottom:10px}#download-one{grid-column:1/-1;margin-top:14px}.catalog{grid-template-columns:repeat(2,minmax(0,1fr))}.glyph{width:104px;height:104px}.tools{align-items:stretch}#search{width:100%}.filters{flex-basis:100%}.filter{font-size:11px;padding:8px 9px}}
</style><main><header><div><p class="eyebrow">GYMCOUNT / EXERCISE LIBRARY</p><h1>动作图标库</h1><p>40 个常见训练动作 · 3 个采集类别<br>自然人体轮廓，统一圆润线条。</p></div><div class="actions"><button id="theme">切换深色</button><a class="download" href="gymcount-exercise-icons.zip" download>下载整套 SVG</a></div></header><section class="tools" aria-label="筛选动作"><div class="filters">FILTERS</div><input id="search" type="search" placeholder="搜索动作，例如：划船" aria-label="搜索动作"></section><div class="layout"><section class="catalog" aria-label="动作图标">CARDS<p id="empty" hidden>没有匹配的动作</p></section><aside aria-label="选中动作预览"><div id="selected-large"></div><h2 id="selected-name"></h2><p id="selected-id"></p><div class="sizes" id="sizes"></div><a id="download-one" download>下载此动作 SVG</a></aside></div><p class="count" id="count" aria-live="polite"></p><footer>透明背景 · 支持深浅主题 · 独立 SVG 文件<br>建议列表使用 32–48 px，动作详情使用 96 px 以上；复杂器械图优先使用较大尺寸。</footer></main><script>
const cards=[...document.querySelectorAll('.card')];let category='all';function select(card){cards.forEach(c=>c.setAttribute('aria-pressed',String(c===card)));document.querySelector('#selected-large').innerHTML=card.querySelector('.glyph').innerHTML;document.querySelector('#selected-name').textContent=card.dataset.name;document.querySelector('#selected-id').textContent=card.dataset.id;document.querySelector('#download-one').href='svg/'+card.dataset.id+'.svg';document.querySelector('#sizes').innerHTML=[26,32,48].map(size=>'<span class="size">'+card.querySelector('.glyph').innerHTML.replace('<svg ','<svg width="'+size+'" height="'+size+'" ')+'<span>'+size+' px</span></span>').join('')}cards.forEach(card=>card.addEventListener('click',()=>select(card)));function filter(){let query=document.querySelector('#search').value.trim().toLowerCase();let visible=cards.filter(card=>{let match=(category==='all'||card.dataset.category===category)&&(card.dataset.name.includes(query)||card.dataset.id.includes(query));card.hidden=!match;return match});document.querySelector('#count').textContent='显示 '+visible.length+' / '+cards.length+' 个动作';document.querySelector('#empty').hidden=visible.length!==0;if(visible.length&&!visible.some(c=>c.getAttribute('aria-pressed')==='true'))select(visible[0])}document.querySelectorAll('.filter').forEach(button=>button.addEventListener('click',()=>{category=button.dataset.filter;document.querySelectorAll('.filter').forEach(b=>{b.classList.toggle('active',b===button);b.setAttribute('aria-pressed',String(b===button))});filter()}));document.querySelector('#search').addEventListener('input',filter);document.querySelector('#theme').addEventListener('click',e=>{document.body.classList.toggle('dark');e.target.textContent=document.body.classList.contains('dark')?'切换浅色':'切换深色'});select(cards[0]);filter();
</script></html>'''
(SOURCE/'index.html').write_text(page.replace('FILTERS',filters).replace('CARDS',cards))

def overview(items,destination,cols=4,cell=220):
    width,height = cols*cell, math.ceil(len(items)/cols)*cell+80
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><rect width="{width}" height="{height}" fill="#f5f7f4"/><text x="28" y="42" fill="#152c24" font-family="PingFang SC,sans-serif" font-size="23">GymCount · 动作图标</text>']
    for n,item in enumerate(items):
        x,y = (n%cols)*cell, (n//cols)*cell+70
        svg = ET.fromstring(item['inline'])
        svg.set('x',str(x+30)); svg.set('y',str(y+8))
        svg.set('width',str(cell-60)); svg.set('height',str(cell-60)); svg.set('color','#152c24')
        parts.append(ET.tostring(svg,encoding='unicode'))
        parts.append(f'<text x="{x+cell/2}" y="{y+cell-32}" text-anchor="middle" fill="#152c24" font-size="14" font-family="PingFang SC,sans-serif">{item["name"]}</text>')
    parts.append('</svg>')
    destination.write_text(''.join(parts))

overview(icons,SOURCE/'overview.svg',cols=6,cell=200)
overview(icons[:4],SOURCE/'strength-detail.svg',cols=2,cell=400)
for key in categories:
    overview([item for item in icons if item['category']==key],SOURCE/f'overview-{key}.svg',cols=3,cell=260)
with zipfile.ZipFile(SOURCE/'gymcount-exercise-icons.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for file in sorted((SOURCE/'svg').glob('*.svg')):
        archive.write(file,file.relative_to(SOURCE))
    for name in ['catalog.json','sprite.svg','README.md','overview.svg']:
        archive.write(SOURCE/name,name)
    # The extracted package already contains every SVG. Avoid a broken link to
    # a recursively nested copy of the same ZIP in its portable offline gallery.
    portable = page.replace('FILTERS',filters).replace('CARDS',cards)
    portable = portable.replace('href="gymcount-exercise-icons.zip"','href="catalog.json"').replace('下载整套 SVG','下载动作清单')
    archive.writestr('index.html',portable)
print(f'Built {len(icons)} Watch/iPhone vector assets, gallery, sprite and ZIP')
