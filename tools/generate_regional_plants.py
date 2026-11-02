#!/usr/bin/env python3
"""Rebuild the 20 regional species resources from explicit scenario traits.
Taxonomic links identify names/life forms; numeric coefficients are not field fits.
"""
from pathlib import Path
from urllib.parse import quote
import re

ROOT = Path(__file__).resolve().parents[1]
# id, Russian, Latin, form, morphology, height, C, shade threshold, flood, ecto guild, note
SPECIES = [
('rowan','Рябина обыкновенная','Sorbus aucuparia','tree','broad',9,25,.15,.25,'arbuscular','Небольшое листопадное дерево с перистыми листьями и красными плодами.'),
('oak','Дуб черешчатый','Quercus robur','tree','broad',17,95,.18,.3,'ecto','Долговечное листопадное дерево с широкой кроной; эктомикоризный хозяин.'),
('lime','Липа мелколистная','Tilia cordata','tree','broad',16,65,.06,.2,'ecto','Теневыносливое листопадное дерево широколиственных и смешанных лесов.'),
('maple','Клён остролистный','Acer platanoides','tree','broad',15,55,.09,.18,'arbuscular','Листопадное дерево с широкой кроной и яркой осенней листвой.'),
('black_alder','Ольха чёрная','Alnus glutinosa','tree','broad',15,48,.14,.7,'ecto','Влаголюбивое дерево сырых лесов и берегов; фиксация азота пока не моделируется.'),
('pine','Сосна обыкновенная','Pinus sylvestris','tree','pine',18,60,.28,.15,'ecto','Светолюбивое хвойное дерево с высоко поднятой кроной; эктомикоризный хозяин.'),
('bird_cherry','Черёмуха обыкновенная','Prunus padus','tree','broad',7,18,.09,.45,'arbuscular','Невысокое дерево или крупный кустарник влажных лесов, с белыми кистями цветков.'),
('hazel','Лещина обыкновенная','Corylus avellana','shrub','shrub',3.5,4,.07,.18,'ecto','Многоствольный кустарник подлеска; эктомикоризный хозяин.'),
('guelder_rose','Калина обыкновенная','Viburnum opulus','shrub','shrub',2.6,2.5,.1,.5,'arbuscular','Листопадный кустарник влажных опушек с красными плодами.'),
('alder_buckthorn','Крушина ломкая','Frangula alnus','shrub','shrub',2.8,2.3,.09,.5,'arbuscular','Кустарник сырых лесов и опушек; плоды не считаются кормом по умолчанию.'),
('fly_honeysuckle','Жимолость лесная','Lonicera xylosteum','shrub','shrub',1.8,1.4,.07,.22,'arbuscular','Теневыносливый кустарник смешанного леса; красные плоды не включены в корм зайца.'),
('juniper','Можжевельник обыкновенный','Juniperus communis','shrub','conifer',2.5,2.8,.18,.12,'arbuscular','Вечнозелёный хвойный кустарник опушек и светлых лесов.'),
('lingonberry','Брусника','Vaccinium vitis-idaea','dwarf_shrub','low',.22,.07,.08,.15,'ericoid','Вечнозелёный кустарничек хвойных лесов; эрикоидная микориза пока только признак.'),
('heather','Вереск обыкновенный','Calluna vulgaris','dwarf_shrub','low',.45,.1,.25,.12,'ericoid','Вечнозелёный кустарничек светлых кислых почв; эрикоидная микориза пока только признак.'),
('male_fern','Щитовник мужской','Dryopteris filix-mas','herb','fern',.9,.12,.04,.25,'arbuscular','Многолетний папоротник тенистого леса; размножается спорами, не семенами.'),
('ostrich_fern','Страусник обыкновенный','Matteuccia struthiopteris','herb','fern',1.3,.16,.05,.5,'arbuscular','Крупный папоротник сырых лесов и пойм; споры представлены общим банком диаспор.'),
('bracken','Орляк обыкновенный','Pteridium aquilinum','herb','fern',1.05,.14,.13,.18,'arbuscular','Папоротник светлых лесов и вырубок; споры представлены общим банком диаспор.'),
('wood_anemone','Ветреница дубравная','Anemone nemorosa','herb','flower',.18,.035,.05,.16,'arbuscular','Весеннее корневищное растение леса; ранняя фенология, без пищевой доступности по умолчанию.'),
('lily_of_valley','Ландыш майский','Convallaria majalis','herb','broadleaf',.28,.045,.05,.18,'arbuscular','Корневищный лесной многолетник с широкими листьями и белыми поникающими цветками.'),
('meadowsweet','Таволга вязолистная','Filipendula ulmaria','herb','flower',1.1,.18,.12,.65,'arbuscular','Высокий многолетник сырых полян и берегов с кремовыми соцветиями.'),
]

def mesh(kind, name, **fields):
    values='\n'.join(f'{k} = {v}' for k,v in fields.items())
    return f'[sub_resource type="{kind}" id="{name}"]\n{values}\n'

def module(name, mesh_name, **fields):
    return mesh('Resource',name,script='ExtResource("2")',mesh=f'SubResource("{mesh_name}")',**fields)

def render(row):
    ident,ru,latin,form,shape,h,c,shade,flood,guild,note=row
    parts=[]; modules=[]
    if shape in ('broad','shrub','pine','conifer'):
        trunk_height=h*(.65 if form=='tree' else .6)
        parts.append(mesh('CylinderMesh','StemMesh',top_radius=.025 if form!='tree' else .07,bottom_radius=.07 if form!='tree' else .22,height=trunk_height,radial_segments=6))
        parts.append(module('Stems','StemMesh',count=1 if form=='tree' else 5,offset=f'Vector3(0, {trunk_height/2}, 0)',radial_offset=.0 if form=='tree' else .16,turn=2.4,color='Color(.36, .29, .19, 1)'))
        modules.append('Stems')
        if shape in ('pine','conifer'):
            parts.append(mesh('CylinderMesh','LeafMesh',top_radius=0.0,bottom_radius=1.0,height=1.0,radial_segments=9))
        else:
            parts.append(mesh('SphereMesh','LeafMesh',radius=1.0,height=2.0,radial_segments=8,rings=3))
        radius=h*(.18 if form=='tree' else .24)
        parts.append(module('Crown','LeafMesh',foliage='true',count=5 if shape!='conifer' else 6,offset=f'Vector3(0, {h*.56}, 0)',step=f'Vector3(0, {h*.06}, 0)',radial_offset=radius*.42,turn=2.4,scale_start=f'Vector3({radius}, {h*.2}, {radius*.85})',color='Color(.20, .32, .19, 1)' if shape in ('pine','conifer') else 'Color(.29, .44, .16, 1)'))
        modules.append('Crown')
        if ident in ('rowan','guelder_rose'):
            parts.append(mesh('SphereMesh','FruitMesh',radius=.09 if form=='tree' else .05,height=.18 if form=='tree' else .10,radial_segments=6,rings=3))
            # Terminal corymbs at staggered branch tips, not individual fruit
            # spread around the trunk in one horizontal necklace.
            spread=.28 if form=='tree' else .15
            depth=.13 if form=='tree' else .07
            # Four heads of seven retain the original 28-fruit geometry budget.
            parts.append(module('Fruit','FruitMesh',foliage='true',count=4,offset=f'Vector3(0, {h*.60}, 0)',step=f'Vector3(0, {h*.055}, 0)',radial_offset=radius*1.38,radial_step=-radius*.055,turn=2.4,cluster_members=7,cluster_spread=f'Vector3({spread}, {depth}, {spread})',color='Color(.76, .13, .035, 1)'))
            modules.append('Fruit')
    elif shape=='fern':
        parts.append(mesh('CylinderMesh','RachisMesh',top_radius=.002,bottom_radius=.007,height=h*.8,radial_segments=4))
        parts.append(module('Fronds','RachisMesh',whorls=8,whorl_turn=.785398,offset=f'Vector3(0, {h*.34}, {h*.15})',rotation_degrees='Vector3(28,0,0)',color='Color(.26,.36,.13,1)'))
        parts.append(mesh('SphereMesh','LeafMesh',radius=1.0,height=2.0,radial_segments=5,rings=2))
        parts.append(module('Pinnae','LeafMesh',foliage='true',whorls=8,whorl_turn=.785398,count=9,offset=f'Vector3(0, {h*.12}, {h*.04})',step=f'Vector3(0,{h*.075},{h*.04})',scale_start=f'Vector3({h*.20},{h*.009},{h*.04})',scale_step=f'Vector3({-h*.018},0,0)',rotation_degrees='Vector3(15,0,0)',color='Color(.19,.42,.14,1)'))
        modules=['Fronds','Pinnae']
    else:
        parts.append(mesh('CylinderMesh','StemMesh',top_radius=.002,bottom_radius=.008,height=h*.8,radial_segments=4))
        parts.append(module('Stems','StemMesh',count=4,offset=f'Vector3(0,{h*.4},0)',radial_offset=h*.07,turn=2.4,color='Color(.31,.39,.14,1)'))
        parts.append(mesh('SphereMesh','LeafMesh',radius=1.0,height=2.0,radial_segments=7,rings=3))
        parts.append(module('Leaves','LeafMesh',foliage='true',count=6,offset=f'Vector3(0,{h*.48},0)',radial_offset=h*.24,turn=2.4,scale_start=f'Vector3({h*.3},{h*.035},{h*(.52 if shape=="broadleaf" else .22)})',color='Color(.24,.44,.15,1)'))
        modules=['Stems','Leaves']
        if shape in ('flower','broadleaf'):
            parts.append(mesh('SphereMesh','FlowerMesh',radius=h*.045,height=h*.08,radial_segments=6,rings=2))
            parts.append(module('Flowers','FlowerMesh',foliage='true',count=5,offset=f'Vector3(0,{h*.84},0)',radial_offset=h*.12,turn=2.4,color='Color(.91,.88,.70,1)'))
            modules.append('Flowers')
    evergreen=ident in ('pine','juniper','lingonberry','heather')
    params=dict(species_id=f'&"{ident}"',display_name=f'"{ru}"',latin_name=f'"{latin}"',description=f'"{note}"',source_url=f'"https://powo.science.kew.org/results?q={quote(latin)}"',growth_form=f'&"{form}"',life_cycle='&"perennial"',initial_age_years='Vector2(5,55)' if form=='tree' else 'Vector2(1,8)',biomass_kg_c=c,cn_ratio=45 if form=='tree' else 28,cp_ratio=500 if form=='tree' else 330,dead_decay_per_year=.12 if form=='tree' else .8,edible_fraction=.03 if ident in ('rowan','hazel','meadowsweet','lingonberry') else 0.0,mature_age_years=15 if form=='tree' else 2,seed_cost_kg_c=.001 if form=='tree' else .00003,reproduction_per_year=.4,dispersal_m=15.0 if form=='tree' else 3.0,germination_fraction=.18,recruitment_light=shade,weight=.055 if form=='tree' else .07,wind_strength=.02 if form=='tree' else .012,deciduous='false' if evergreen else 'true',leaf_on_day=85.0 if ident=='wood_anemone' else 110.0,leaf_off_day=155.0 if ident=='wood_anemone' else 255.0,leaf_transition_days=20.0,autumn_color='Color(.87,.36,.10,1)' if ident in ('rowan','maple') else 'Color(.75,.57,.20,1)',reference_height_m=h,max_height_m=h*1.8,crown_radius_m=h*(.2 if form=='tree' else .3),height_growth_m_year=h*.035,transpiration_m_s=2.3e-8 if form=='tree' else 5e-9,minimum_light=shade,flood_depth_m=flood,stress_days=18.0,recovery_days=8.0,lifespan_years=250.0 if form=='tree' else 40.0,leaf_mass_fraction=.04 if form=='tree' else .25,mycorrhiza_type=f'&"{guild}"')
    if shape=='fern': params['propagule_kind']='&"spore"'
    header=f'[gd_resource type="Resource" script_class="ForestPlantDefinition" load_steps={len(parts)+3} format=3]\n[ext_resource type="Script" path="res://scripts/plant_definition.gd" id="1"]\n[ext_resource type="Script" path="res://scripts/plant_module.gd" id="2"]\n'
    fields='\n'.join(f'{k} = {v}' for k,v in params.items())
    refs=', '.join(f'SubResource("{x}")' for x in modules)
    return re.sub(r'(?<=[(,])\s*(-?)\.(\d)', r'\g<1>0.\2', header+'\n'.join(parts)+'[resource]\nscript = ExtResource("1")\n'+fields+'\nmodules = Array[ExtResource("2")](['+refs+'])\n')

def main():
    for row in SPECIES:
        (ROOT/'data/plants'/f'{row[0]}.tres').write_text(render(row))
    p=ROOT/'data/forest.tres';s=p.read_text()
    for row in SPECIES:
        s=re.sub(r'^\[ext_resource[^\n]*path="res://data/plants/'+row[0]+r'\.tres"[^\n]*\n', '', s, flags=re.M)
    pos=s.index('[resource]');existing=s[:pos];refs=[]
    for i,row in enumerate(SPECIES,11):
        existing+=f'[ext_resource type="Resource" path="res://data/plants/{row[0]}.tres" id="{i}"]\n';refs.append(f'ExtResource("{i}")')
    tail=s[pos:]
    refs=[f'ExtResource("{i}")' for i in range(2,11)]+refs
    tail=re.sub(r'^plants = .+$','plants = Array[Resource](['+', '.join(refs)+'])',tail,flags=re.M)
    s=existing+tail
    steps=1+len(re.findall(r"^\[ext_resource",s,flags=re.M))
    s=re.sub(r'load_steps=\d+',f'load_steps={steps}',s,count=1)
    p.write_text(s)

if __name__=='__main__': main()
