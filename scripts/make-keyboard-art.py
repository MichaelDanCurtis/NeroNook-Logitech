#!/usr/bin/env python3
"""Original vector illustration. No vendor asset is copied or embedded."""
from pathlib import Path
from html import escape
root=Path(__file__).resolve().parents[1]/'Resources/Views/devices'
s=['''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 756 242">
<defs><linearGradient id="case" x2=".2" y2="1"><stop stop-color="#879199"/><stop offset=".12" stop-color="#525c65"/><stop offset=".9" stop-color="#39424b"/><stop offset="1" stop-color="#202933"/></linearGradient><linearGradient id="key" x2=".15" y2="1"><stop stop-color="#353e46"/><stop offset=".8" stop-color="#202931"/><stop offset="1" stop-color="#111920"/></linearGradient><radialGradient id="dish"><stop stop-color="#172129"/><stop offset=".65" stop-color="#1d2730"/><stop offset="1" stop-color="#39434b"/></radialGradient></defs>
<rect x="6" y="17" width="744" height="221" rx="15" fill="#0a1016"/><rect x="6" y="10" width="744" height="221" rx="15" fill="url(#case)" stroke="#a2abb1" stroke-opacity=".4"/><path d="M18 17H738" stroke="#d0d5d8" opacity=".12"/>
''']
def key(x,y,w,label,h=29,small=False,accent=False):
 s.append(f'<rect x="{x}" y="{y+1}" width="{w}" height="{h}" rx="5" fill="#091018"/><rect x="{x}" y="{y}" width="{w}" height="{h-1}" rx="5" fill="url(#key)" stroke="#72808b" stroke-opacity=".35" stroke-width=".7"/>')
 if not small:
  s.append(f'<ellipse cx="{x+w/2}" cy="{y+(h-1)/2}" rx="{min(w/2-2,12)}" ry="{min((h-1)/2-2,12)}" fill="url(#dish)" opacity=".9"/>')
 s.append(f'<text x="{x+w/2}" y="{y+(h-1)/2+3.5}" font-family="-apple-system,Helvetica,Arial,sans-serif" font-size="{8 if small else 10}" fill="{"#a8dcce" if accent else "#d6dde2"}" text-anchor="middle">{escape(label)}</text>')
# Mac ANSI main cluster, six rows with proportional modifiers.
function=['esc','☀ F1','☀ F2','▣ F3','⌕ F4','◉ F5','☾ F6','◀ F7','▶ F8','▶ F9','◁ F10','− F11','+ F12']
for i,label in enumerate(function):key(20+i*35.3,30,31.3,label,22,True)
rows=[
 [('`',1),('1',1),('2',1),('3',1),('4',1),('5',1),('6',1),('7',1),('8',1),('9',1),('0',1),('−',1),('=',1),('delete',1.6)],
 [('tab',1.45),('Q',1),('W',1),('E',1),('R',1),('T',1),('Y',1),('U',1),('I',1),('O',1),('P',1),('[',1),(']',1),('\\',1.15)],
 [('caps lock',1.7),('A',1),('S',1),('D',1),('F',1),('G',1),('H',1),('J',1),('K',1),('L',1),(';',1),("'",1),('return',1.9)],
 [('shift',2.2),('Z',1),('X',1),('C',1),('V',1),('B',1),('N',1),('M',1),(',',1),('.',1),('/',1),('shift',2.4)],
 [('fn',1),('control',1.15),('option',1.15),('⌘',1.35),('',6.3),('⌘',1.35),('option',1.15),('control',1.15)]
]
for r,keys in enumerate(rows):
 unit=459/sum(w for _,w in keys);x=20;y=61+r*32
 for label,w in keys:
  key(round(x,2),y,round(unit*w-3,2),label,29, len(label)>3)
  if label in ['F','J']:s.append(f'<path d="M{x+unit*w/2-3} {y+23}h6" stroke="#71818e" stroke-width=".8"/>')
  x+=unit*w
# Separate navigation cluster and three physical host keys.
for i,label in enumerate(['1','2','3']):key(494+i*32,30,28,label,22,True,True)
for r,row in enumerate([['fn','home','pg up'],['del','end','pg dn']]):
 for c,label in enumerate(row):key(494+c*32,61+r*32,28,label,29,True)
key(526,157,28,'↑')
for c,label in enumerate(['←','↓','→']):key(494+c*32,189,28,label)
# Number pad, with full-height plus and enter, wide zero.
for c,label in enumerate(['◉','✂','▣','⌑']):key(601+c*32,30,28,label,22,True)
for c,label in enumerate(['clear','=','/','*']):key(601+c*32,61,28,label,29,True)
for c,label in enumerate(['7','8','9','−']):key(601+c*32,93,28,label)
for c,label in enumerate(['4','5','6']):key(601+c*32,125,28,label)
key(697,125,28,'+',61)
for c,label in enumerate(['1','2','3']):key(601+c*32,157,28,label)
key(601,189,60,'0');key(665,189,28,'.');key(697,189,28,'enter',29,True)
s.append('<circle cx="728" cy="20" r="1.5" fill="#a0dec0"/><path d="M23 226H730" stroke="#b5bec6" opacity=".12"/></svg>')
(root/'keyboard.svg').write_text('\n'.join(s))
(root/'generic-mouse.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 280 300"><rect x="67" y="24" width="146" height="250" rx="70" fill="#35434d" stroke="#6b7e8b"/><path d="M140 28v92" stroke="#15222d" stroke-width="3"/><rect x="130" y="59" width="20" height="45" rx="9" fill="#b0c8c6"/></svg>')
(root/'generic-keyboard.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 756 242"><rect x="8" y="20" width="740" height="200" rx="15" fill="#34444f" stroke="#6b7e8b"/>'+''.join(f'<rect x="{27+c*47}" y="{40+r*38}" width="39" height="30" rx="5" fill="#16232d"/>' for r in range(4) for c in range(15))+'<rect x="215" y="190" width="270" height="18" rx="5" fill="#16232d"/></svg>')
