import bpy,json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1];src=Path('C:/Users/12512/Downloads/单人医疗床3d模型.glb')
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];before=sum(len(o.data.polygons) for o in meshes)
for o in meshes:
 bpy.context.view_layer.objects.active=o
 dec=o.modifiers.new('runtime_mesh','DECIMATE');dec.ratio=min(1,18000/max(1,before));bpy.ops.object.modifier_apply(modifier=dec.name)
for im in bpy.data.images:
 if max(im.size)>1024:im.scale(1024,1024)
out=root/'assets/worlds/survivor_base/bed_repaired.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB')
print('REPAIRED_BED',src.stat().st_size,before,hashlib.sha256(src.read_bytes()).hexdigest())
