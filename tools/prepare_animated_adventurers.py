"""Build the user-imported animated pair without replacing its skin weights.
Blender --factory-startup -b --python tools/prepare_animated_adventurers.py
"""
import bpy, math, json, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/characters/adventurers'
SOURCE=OUT/'source/imported_animated_pair.blend'
for gender,rig_name in [('male','卡通冒险者3d模型'),('female','探险者3d模型')]:
 bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
 rig=bpy.data.objects[rig_name]
 obj=next(o for o in rig.children if o.type=='MESH')
 rig.animation_data.action=None
 rig.data.pose_position='REST'
 bpy.context.view_layer.update()
 original=obj.data.materials[0];obj.data.materials.clear()
 for name in ['fixed','hair','skin','shirt','pants']:
  m=original.copy();m.name=name;obj.data.materials.append(m)
 for image in bpy.data.images:image.name=gender+'_albedo'
 pixels=None;texture=None
 if gender=='female':
  texture=next(n.image for n in original.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
  pixels=np.empty(len(texture.pixels),dtype=np.float32);texture.pixels.foreach_get(pixels);pixels=pixels.reshape(texture.size[1],texture.size[0],4)
 uv_layer=obj.data.uv_layers.active
 for f in obj.data.polygons:
  c=sum((obj.data.vertices[i].co for i in f.vertices),Vector())/len(f.vertices);x,y,z=c
  part=0
  if z>.86 or (z>.78 and x<.025):part=1
  elif z>.75 or (.34<z<.57 and abs(y)>.135):part=2
  elif .16<z<.49:part=4
  elif .49<z<.78 and x>-.045:part=3
  if gender=='female' and z>.765:
   uv=uv_layer.data[f.loop_indices[0]].uv
   r,g,b,_=pixels[int((uv.y%1)*texture.size[1]),int((uv.x%1)*texture.size[0])]
   hair_color=max(r,g,b)<.46 and g<.34 and b<.30 and r-g<.14
   # Preserve frontal eyes/brows; include lower side locks and the rear ponytail.
   hair_region=x<.07 or z>.84 or abs(y)>.065
   if hair_color and hair_region:part=1
   elif part==1 and z<.89:part=2
  f.material_index=part

 bpy.ops.object.select_all(action='DESELECT')
 obj.select_set(True);bpy.context.view_layer.objects.active=obj
 dec=obj.modifiers.new('runtime_reduction','DECIMATE');dec.ratio=min(1,60000/len(obj.data.polygons))
 bpy.ops.object.modifier_move_up(modifier=dec.name)
 bpy.ops.object.modifier_apply(modifier=dec.name)
 for im in bpy.data.images:
  if im.size[0]>2048:im.scale(2048,2048)
 rig.data.pose_position='POSE'
 # User imported each character separately: unsuffixed run/dance belong to female.
 chosen={'walk':'Armature|walk','run':'Armature|run'+('.001' if gender=='male' else ''),'dance':'Armature|dance_06'+('.001' if gender=='male' else '')}
 for name,action_name in chosen.items():
  action=bpy.data.actions[action_name].copy();action.name=gender+'_'+name
  track=rig.animation_data.nla_tracks.new();track.name=name
  strip=track.strips.new(name,1,action);strip.action_slot=action.slots[0]
  strip.extrapolation='NOTHING'
 root=bpy.data.objects.new('character_orientation',None);bpy.context.collection.objects.link(root)
 root.rotation_euler.z=math.pi/2;root.scale=(1.65,)*3
 rig.parent=root
 bpy.ops.object.select_all(action='DESELECT')
 for ob in [root,rig,obj]:ob.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.context.scene.frame_set(1)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/('animated_'+gender+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/('animated_'+gender+'.glb')),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_force_sampling=True)
 print('EXPORTED',gender,chosen,flush=True)
manifest={'generator':'tools/prepare_animated_adventurers.py','source':SOURCE.name,'files':{n:{'sha256':hashlib.sha256((OUT/n).read_bytes()).hexdigest(),'bytes':(OUT/n).stat().st_size} for n in ['animated_male.glb','animated_female.glb']}}
(OUT/'animated_manifest.json').write_text(json.dumps(manifest,indent=2))
