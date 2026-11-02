"""Blender 4.5 CPU-only authoring: editable actions -> sampled motion curves.
Run with Blender --background --factory-startup --python this_file.
These are shared pose clips, not a claim of anatomical motion capture.
"""
import bpy, json, math
from pathlib import Path
root = Path(__file__).resolve().parents[1]
bpy.context.preferences.filepaths.save_version=0
# Factory-startup isolated process only. Never attach to the user's live scene.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
rig = bpy.data.objects.new('ForestMotionChannels', None)
bpy.context.collection.objects.link(rig)
channels=['stride','head','ears','breath','bob','tail','wings','flight','wrist']
clips={
 'idle':(3.6,lambda p: [0,.035*math.sin(p),.075*max(0,math.sin(p*2))**8,.012*math.sin(p),0,.035*math.sin(p),0]),
 'walk':(.8,lambda p: [.32*math.sin(p),.025*math.sin(p*2),.025*math.sin(p),.004*math.sin(p*2),.012*abs(math.sin(p)),.13*math.sin(p),.5*math.sin(p)]),
 'hop':(.7,lambda p: [.38*math.sin(p),-.06*math.sin(p),-.10*math.sin(p),.006*math.sin(p),.07*max(0,math.sin(p)),.07*math.sin(p),0]),
 'feed':(1.4,lambda p: [0,.20+.08*math.sin(p*2),.04*math.sin(p),.01*math.sin(p),0,.025*math.sin(p),0]),
 'sleep':(4.8,lambda p: [0,.09,.03,.016*math.sin(p),0,0,0]),
 'alert':(2.2,lambda p: [0,-.10+.13*math.sin(p),.16*math.sin(p*2),.008*math.sin(p),0,.05*math.sin(p),0]),
 'fly':(.24,lambda p: [.025*math.sin(p),-.05,0,.004*math.sin(p),.018*math.sin(p-.5),.035*math.sin(p),.90*math.cos(p)+.12*math.sin(2*p),1.0,.20-.30*math.sin(p)])}
clips['swim']=(1.05,lambda p: [.22*math.sin(p),-.08,-.04,.004*math.sin(p),.007*math.sin(p),.06*math.sin(p),0])
result={'source':'Blender 4.5.3 actions, local authored scenario clips','fps':30,'channels':channels,'clips':{}}
for name,(duration,fn) in clips.items():
 rig.animation_data_clear()
 for channel in channels: rig[channel]=0.0
 count=33
 for i in range(count):
  phase=2*math.pi*i/(count-1)
  values=fn(phase)
  values += [0.0] * (len(channels)-len(values))
  frame=1+duration*30*i/(count-1)
  for ch,value in zip(channels,values):
   rig[ch]=value
   rig.keyframe_insert(data_path=f'["{ch}"]',frame=frame,group=name)
 action=rig.animation_data.action
 action.name='forest_'+name
 action.use_fake_user=True
 result['clips'][name]={'duration':duration,'samples':[(lambda v: v+[0.0]*(len(channels)-len(v)))(fn(2*math.pi*i/(count-1))) for i in range(count)]}
bpy.context.scene.frame_end=145
bpy.ops.wm.save_as_mainfile(filepath=str(root/'art/source/forest-animal-motion.blend'))
(root/'data/animation/animal_motion.json').write_text(json.dumps(result,indent=2))
print('FOREST_MOTION_ACTIONS',list(result['clips']))
