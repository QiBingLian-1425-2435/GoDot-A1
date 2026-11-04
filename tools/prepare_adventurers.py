"""Blender background builder for supplied textured male/female player models."""
import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/characters/adventurers';(OUT/'source').mkdir(parents=True,exist_ok=True);(OUT/'source/.gdignore').write_text('')
for gender,filename in [('male','卡通冒险者3d模型.glb'),('female','探险者3d模型.glb')]:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(Path.home()/'Downloads'/filename))
 obj=next(o for o in bpy.context.scene.objects if o.type=='MESH');obj.name='adventurer_body'
 # Preserve UVs and photographic color details; split tint regions into surfaces.
 original=obj.data.materials[0];obj.data.materials.clear()
 for name in ['fixed','hair','skin','shirt','pants']:
  m=original.copy();m.name=name;obj.data.materials.append(m)
 for image in bpy.data.images:image.name=gender+'_albedo'
 for f in obj.data.polygons:
  c=sum((obj.data.vertices[i].co for i in f.vertices),Vector())/len(f.vertices);x,y,z=c
  part=0
  if z>.86 or (z>.78 and x<.025):part=1
  elif z>.75 or (.34<z<.57 and abs(y)>.135):part=2
  elif .16<z<.49:part=4
  elif .49<z<.78 and x>-.045:part=3
  f.material_index=part
 # Reduce dense generated topology while retaining seams and texture coordinates.
 bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 dec=obj.modifiers.new('runtime_reduction','DECIMATE');dec.ratio=.12;bpy.ops.object.modifier_apply(modifier=dec.name)
 for v in obj.data.vertices:v.co=Vector((-v.co.y*1.65,v.co.x*1.65,v.co.z*1.65))
 bpy.ops.object.armature_add();rig=bpy.context.object;rig.name='player_rig';bpy.ops.object.mode_set(mode='EDIT');bones=rig.data.edit_bones;bones.remove(bones[0])
 positions={'Root':(0,0,0),'Hips':(0,-.06,.72),'Spine':(0,-.04,.92),'Head':(0,.10,1.30),'FootL':(-.19,0,.20),'FootR':(.19,0,.20),'WingL':(-.37,.11,.95),'WingR':(.37,.11,.95)}
 parents={'Hips':'Root','Spine':'Hips','Head':'Spine','FootL':'Root','FootR':'Root','WingL':'Spine','WingR':'Spine'}
 for side,x in [("L",-.19),("R",.19)]:
  positions["Thigh"+side]=(x,0,.76);positions["Shin"+side]=(x,0,.45)
  parents["Thigh"+side]="Root";parents["Shin"+side]="Root"
 for name,point in positions.items():
  b=bones.new(name);b.head=point;b.tail=Vector(point)+Vector((0,0,.15))
  if name in parents:b.parent=bones[parents[name]]
 bpy.ops.object.mode_set(mode='OBJECT');groups={n:obj.vertex_groups.new(name=n) for n in positions}
 vertex_parts={}
 for face in obj.data.polygons:
  for index in face.vertices:vertex_parts[index]=face.material_index
 skin_candidates={v.index for v in obj.data.vertices if vertex_parts.get(v.index)==2 and v.co.z<1.15}
 adjacency={i:[] for i in skin_candidates}
 for edge in obj.data.edges:
  a,b=edge.vertices
  if a in adjacency and b in adjacency:adjacency[a].append(b);adjacency[b].append(a)
 skin_arms=set();remaining_skin=set(skin_candidates)
 while remaining_skin:
  pending=[remaining_skin.pop()];component=[]
  while pending:
   index=pending.pop();component.append(index)
   for neighbor in adjacency[index]:
    if neighbor in remaining_skin:remaining_skin.remove(neighbor);pending.append(neighbor)
  mean_side=sum(abs(obj.data.vertices[i].co.x) for i in component)/len(component)
  if mean_side>.255:skin_arms.update(component)
 for v in obj.data.vertices:
  x,y,z=v.co;weights={};side='L' if x<0 else 'R'
  arm=max(0,min(1,(abs(x)-.165)/.075))*max(0,min(1,(1.35-z)/.12)) if z>.56 else 0
  part=vertex_parts.get(v.index,0)
  if part in [0,4]:arm=0
  if part==2 and z<1.15:arm=1 if v.index in skin_arms else 0
  leg=max(0,min(1,(.86-z)/.16)) if z<.86 else 0
  head=max(0,min(1,(z-1.19)/.10))
  weights['Wing'+side]=arm;remaining=1-arm
  lower=max(0,min(1,(.51-z)/.12));foot=max(0,min(1,(.27-z)/.08))
  weights['Thigh'+side]=remaining*leg*(1-lower)
  weights['Shin'+side]=remaining*leg*lower*(1-foot)
  weights['Foot'+side]=remaining*leg*lower*foot;remaining*=1-leg
  weights['Head']=remaining*head;weights['Hips']=remaining*(1-head)
  for name,w in weights.items():
   if w>0:groups[name].add([v.index],w,'REPLACE')
 mod=obj.modifiers.new('player_skin','ARMATURE');mod.object=rig;obj.parent=rig
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/(gender+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(gender+'.glb')),export_format='GLB')
(OUT/'asset_manifest.json').write_text(json.dumps({'generator':'tools/prepare_adventurers.py','files':{n:{'sha256':hashlib.sha256((OUT/n).read_bytes()).hexdigest()} for n in ['male.glb','female.glb']}},indent=2))
