import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'assets/weapons/firearms';out.mkdir(parents=True,exist_ok=True)
(out/'source').mkdir(exist_ok=True);(out/'source/.gdignore').write_text('')
report=[]
for kind,filename in [('rifle','步枪3d模型.glb'),('pistol','手枪3d模型.glb'),('sniper','狙击步枪3d模型.glb')]:
 src=Path.home()/'Downloads'/filename
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];points=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
 lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
 before=sum(len(o.data.polygons) for o in meshes)
 for o in meshes:
  bpy.context.view_layer.objects.active=o;dec=o.modifiers.new('game_mesh','DECIMATE');dec.ratio=min(1,12000/max(1,before));bpy.ops.object.modifier_apply(modifier=dec.name)
 for im in bpy.data.images:
  if max(im.size)>1024:im.scale(1024,1024)
 # Separate the detachable magazine without changing the surface or its UVs.
 if kind=='rifle':
  for o in meshes:
   bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
   bpy.context.tool_settings.mesh_select_mode=(False,False,True)
   bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
   for face in o.data.polygons:
    p=o.matrix_world@(sum((o.data.vertices[i].co for i in face.vertices),Vector())/len(face.vertices))
    face.select=p.z<.17 and -.02<p.y<.13
   bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
   for part in bpy.context.selected_objects:
    if part!=o:part.name='Magazine'
 bpy.ops.export_scene.gltf(filepath=str(out/(kind+'.glb')),export_format='GLB')
 bpy.ops.wm.save_as_mainfile(filepath=str(out/'source'/(kind+'.blend')))
 report.append({'kind':kind,'bounds_min':list(lo),'bounds_max':list(hi),'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'source_faces':before})
 (out/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print('WEAPON',report[-1],flush=True)
