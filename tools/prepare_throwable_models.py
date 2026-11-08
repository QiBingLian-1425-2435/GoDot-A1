"""Blender: optimize supplied throwable art, retaining UVs and baked materials."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'assets/props/throwables';out.mkdir(parents=True,exist_ok=True)
(out/'source').mkdir(exist_ok=True);(out/'source/.gdignore').write_text('')
report=[]
for kind,filename,height in [('frag_grenade','破片手雷3d模型.glb',.22),('smoke_grenade','烟雾弹3d模型.glb',.25),('molotov','玻璃瓶3d模型.glb',.32)]:
 src=Path.home()/'Downloads'/filename
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];before=sum(len(o.data.polygons) for o in meshes)
 points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
 lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
 center=(lo+hi)/2;factor=height/max(hi-lo)
 for o in meshes:
  matrix=o.matrix_world.copy()
  for v in o.data.vertices:v.co=(matrix@v.co-center)*factor
  o.matrix_world.identity();bpy.context.view_layer.objects.active=o
  mod=o.modifiers.new('game_mesh','DECIMATE');mod.ratio=min(1,8000/max(1,before));bpy.ops.object.modifier_apply(modifier=mod.name)
 for im in bpy.data.images:
  if max(im.size)>1024:im.scale(1024,1024)
 target=out/(kind+'.glb');bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB')
 bpy.ops.wm.save_as_mainfile(filepath=str(out/'source'/(kind+'.blend')))
 report.append(dict(kind=kind,source=str(src),source_faces=before,bounds_min=list(lo),bounds_max=list(hi),scale=factor,bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
 (out/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
 print('THROWABLE_ASSET',report[-1],flush=True)
