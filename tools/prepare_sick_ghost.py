"""Blender --background --python tools/prepare_sick_ghost.py -- input.glb"""
import bpy,sys,math,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'assets/characters/sick_ghost';(out/'source').mkdir(parents=True,exist_ok=True)
(out/'source/.gdignore').write_text('')
source=Path(sys.argv[sys.argv.index('--')+1])
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source))
for i,image in enumerate(bpy.data.images):image.name='sick_ghost_texture_'+str(i)
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');mesh.name='sick_ghost_body'
# Flatten the isolated lip on the raised fist, retaining UVs and surrounding fingers.
count=0
for v in mesh.data.vertices:
 x,y,z=v.co
 if .132<x<.183 and .185<y and .744<z<.774:
  v.co.z=.744+(z-.744)*.08;count+=1
print('REPAIRED_VERTICES',count)
# Normalize to 1.8 metres and face Godot -Z (Blender -Y).
for v in mesh.data.vertices:v.co=Vector((-v.co.x*1.84,-v.co.y*1.84,v.co.z*1.84))
bpy.ops.object.armature_add();rig=bpy.context.object;rig.name='sick_ghost_rig'
bpy.ops.object.mode_set(mode='EDIT');bones=rig.data.edit_bones;bones.remove(bones[0])
b=bones.new('root');b.head=(0,0,0);b.tail=(0,0,.85)
for side,x in [('left',-.17),('right',.17)]:
 b=bones.new(side+'_thigh');b.head=(x,.06,.76);b.tail=(x,.03,.40);b.parent=bones['root']
 b=bones.new(side+'_shin');b.head=(x,.03,.40);b.tail=(x,-.04,.12);b.parent=bones[side+'_thigh'];b.use_connect=True
bpy.ops.object.mode_set(mode='OBJECT')
groups={n:mesh.vertex_groups.new(name=n) for n in ['root','left_thigh','left_shin','right_thigh','right_shin']}
for v in mesh.data.vertices:
 x,y,z=v.co;side='left' if x<0 else 'right'
 leg=max(0,min(1,(.85-z)/.22));shin=max(0,min(1,(.47-z)/.14))
 if leg<1:groups['root'].add([v.index],1-leg,'REPLACE')
 if leg*(1-shin)>0:groups[side+'_thigh'].add([v.index],leg*(1-shin),'REPLACE')
 if leg*shin>0:groups[side+'_shin'].add([v.index],leg*shin,'REPLACE')
mod=mesh.modifiers.new('leg_skin','ARMATURE');mod.object=rig;mesh.parent=rig
bpy.context.scene.render.fps=30
for frame in range(1,32,5):
 phase=(frame-1)/30*math.tau
 for i,side in enumerate(['left','right']):
  p=phase+i*math.pi
  for name,angle in [(side+'_thigh',math.sin(p)*.30),(side+'_shin',max(0,-math.sin(p))*.42)]:
   b=rig.pose.bones[name];b.rotation_mode='XYZ';b.rotation_euler.x=angle;b.keyframe_insert(data_path='rotation_euler',frame=frame,group=name)
rig.animation_data.action.name='walk';bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/sick_ghost.blend'))
bpy.ops.export_scene.gltf(filepath=str(out/'sick_ghost.glb'),export_format='GLB',export_animations=True)
(out/'asset_manifest.json').write_text(json.dumps({'generator':'tools/prepare_sick_ghost.py','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'files':{'sick_ghost.glb':hashlib.sha256((out/'sick_ghost.glb').read_bytes()).hexdigest()}},indent=2))
