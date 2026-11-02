#!/usr/bin/env python3
"""Generate our tileable leaf/twig masks from reusable outline profiles."""
import json
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def outline(shape):
    if shape == 'palmate':
        return [(0,0),(-.25,.18),(-.52,.18),(-.40,.38),(-.63,.53),(-.35,.56),(-.32,.82),(-.13,.68),(0,1),(.13,.68),(.32,.82),(.35,.56),(.63,.53),(.40,.38),(.52,.18),(.25,.18)]
    points=[]
    for sign in [-1,1]:
        side=[]
        for i in range(49):
            t=i/48
            if shape == 'lobed':
                half=.43*math.sin(math.pi*t)**.42*(.76+.24*math.cos(t*math.tau*4))
            elif shape == 'serrated':
                half=.5*(t/.35 if t<.35 else (1-t)/.65)*(.86+.14*(i%2))
            elif shape == 'heart':
                half=.55*math.sin(math.pi*(t**.65))**.7
            elif shape == 'round':
                half=.5*math.sin(math.pi*t)**.65
            else:
                half=.45*math.sin(math.pi*t)**.85
            side.append((sign*half,t))
        points.extend(side if sign == -1 else reversed(side))
    return points


def main():
    output=ROOT/'art/canopy'; output.mkdir(parents=True,exist_ok=True)
    profiles=json.loads((output/'profiles.json').read_text())
    for name,p in profiles.items():
        size=512; ss=2; rng=random.Random(20261102+p['seed'])
        image=Image.new('RGBA',(size*ss,size*ss),(245,245,245,0)); draw=ImageDraw.Draw(image)
        blade=outline(p['shape'])
        def paint(points,color,line=False):
            for dx in [-size,0,size]:
                for dy in [-size,0,size]:
                    pts=[((x+dx)*ss,(y+dy)*ss) for x,y in points]
                    if line: draw.line(pts,fill=color,width=2*ss)
                    else: draw.polygon(pts,fill=color)
        for _ in range(p['groups']):
            x,y=rng.uniform(0,size),rng.uniform(0,size); a=rng.uniform(0,math.tau)
            axis=(math.cos(a),math.sin(a)); length=p.get('twig',75)
            paint([(x,y),(x+axis[0]*length,y+axis[1]*length)],(170,170,170,255),True)
            count=p.get('count',9)
            for j in range(count):
                t=(j//2+1)/(count//2+1); bx=x+axis[0]*length*.9*t; by=y+axis[1]*length*.9*t
                angle=a-math.pi/2+(-.9 if j%2 else .9); c,s=math.cos(angle),math.sin(angle)
                scale=rng.uniform(.75,1.12); w=p['width']*scale; h=p['length']*scale
                points=[(bx+c*px*w-s*py*h,by+s*px*w+c*py*h) for px,py in blade]
                v=rng.randrange(165,256);paint(points,(v,v,v,255))
        image.resize((size,size),Image.Resampling.LANCZOS).save(output/(name+'.png'))
    print('Baked',len(profiles),'original leaf-mask profiles')

if __name__=='__main__': main()
