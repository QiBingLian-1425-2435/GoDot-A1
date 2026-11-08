"""Blender: keep supplied zombie skin, optimize it and author five bone clips."""
import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion
root=Path(__file__).resolve().parents[1];out=root/'assets/characters/zombie';out.mkdir(parents=True,exist_ok=True)
(out/'source').mkdir(exist_ok=True);(out/'source/.gdignore').write_text('')
src=Path.home()/'Downloads/僵尸3d模型.glb'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
points=[o.evaluated_get(deps).matrix_world@v.co for o in meshes for v in o.evaluated_get(deps).data.vertices]
lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
print('VERTEX_BOUNDS',list(lo),list(hi),flush=True)
before=sum(len(o.data.polygons) for o in meshes)
for obj in meshes:
 bpy.context.view_layer.objects.active=obj
 dec=obj.modifiers.new('runtime_reduction','DECIMATE');dec.ratio=min(1,18000/max(1,before));bpy.ops.object.modifier_move_up(modifier=dec.name);bpy.ops.object.modifier_apply(modifier=dec.name)
for image in bpy.data.images:
 if max(image.size)>1024:image.scale(1024,1024)
anchor=bpy.data.objects.new('zombie_orientation',None);bpy.context.collection.objects.link(anchor)
for obj in list(bpy.context.scene.objects):
 if obj!=anchor and obj.parent is None:obj.parent=anchor
factor=1.7;anchor.scale=(factor,)*3;anchor.rotation_euler.z=math.pi/2
center=rig.data.bones["Root"].head_local.copy();center.z=0
anchor.location=-(anchor.rotation_euler.to_matrix()@center)*factor
rig.animation_data_create();bpy.context.scene.render.fps=30

def rotate(name,angle,axis=Vector((0,1,0))):
 if name not in rig.pose.bones:return
 bone=rig.pose.bones[name];bone.rotation_mode='QUATERNION';local=bone.bone.matrix_local.to_quaternion().inverted()@axis;bone.rotation_quaternion=Quaternion(local,angle)

for name,length in [('idle',2.0),('walk',1.2),('attack',1.3),('hit',.25),('death',.9)]:
 action=bpy.data.actions.new('zombie_'+name);rig.animation_data.action=action
 frames=round(length*30)
 for frame in range(frames+1):
  t=frame/30;p=t/length;phase=p*math.tau
  for b in rig.pose.bones:b.rotation_mode='QUATERNION';b.rotation_quaternion=Quaternion();b.location=(0,0,0)
  rotate('Waist',.07+.015*math.sin(phase));rotate('Head',-.06)
  for i,side in enumerate(['L','R']):
   s=math.sin(phase+i*math.pi)
   rotate(side+'_Upperarm',-.12);rotate(side+'_Forearm',-.08)
   if name=='walk':
    rotate(side+'_Thigh',-.32*s);rotate(side+'_Calf',.45*max(0,s));rotate(side+'_Foot',-.1*s)
    rotate(side+'_Upperarm',-.35+.18*s);rotate(side+'_Forearm',-.18)
   elif name=='attack':
    if t<.28:a=-.12-2.0*math.sin(t/.28*math.pi/2)
    elif t<.50:a=-2.12+(t-.28)/.22*1.55
    else:a=-.57+(t-.5)/.8*.45
    rotate(side+'_Upperarm',a);rotate(side+'_Forearm',-.3);rotate('Waist',.07+.18*math.sin(p*math.pi))
   elif name=='hit':
    rotate('Waist',-.3*math.sin(p*math.pi));rotate('Head',-.2*math.sin(p*math.pi));rotate(side+'_Upperarm',.15*math.sin(p*math.pi))
   elif name=='death':
    a=min(1,p/.85);a=a*a*(3-2*a);rotate('Root',1.48*a);rotate(side+'_Upperarm',-.6*a);rotate(side+'_Calf',.3*a)
  for b in rig.pose.bones:
   b.keyframe_insert(data_path='rotation_quaternion',frame=frame+1,group=b.name)
 track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,action);strip.action_slot=action.slots[0];strip.extrapolation='NOTHING'
 rig.animation_data.action=None
 for b in rig.pose.bones:b.rotation_quaternion=Quaternion()
bpy.context.scene.frame_set(1)
# NLA tracks export independently; avoid all five clips mixing in the saved rest preview.
for track in rig.animation_data.nla_tracks:track.mute=True
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/zombie.blend'))
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.export_scene.gltf(filepath=str(out/'zombie.glb'),export_format='GLB',export_animation_mode='NLA_TRACKS',export_nla_strips=True,export_force_sampling=True)
manifest={'generator':'tools/prepare_zombie_model.py','source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'source_faces':before,'scale':factor,'source_bounds_min':list(lo),'source_bounds_max':list(hi),'clips':['idle','walk','attack','hit','death'],'files':{'zombie.glb':hashlib.sha256((out/'zombie.glb').read_bytes()).hexdigest()},'bytes':(out/'zombie.glb').stat().st_size}
(out/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8');print('ZOMBIE_ASSET',manifest,flush=True)
