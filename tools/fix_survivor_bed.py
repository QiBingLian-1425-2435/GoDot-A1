"""Blender: level the actual mattress plane, excluding pillow and end rails."""
import bpy,numpy as np,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]/'assets/worlds/survivor_base'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source=Path(args[0]) if args else Path('C:/Users/12512/Downloads/单人医疗床3d模型.glb')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
a=np.array([list(o.matrix_world@v.co) for o in objects for v in o.data.vertices])
# Fit exposed quilt surface; pillow at +Y and end rails are deliberately excluded.
samples=[]
for x in np.linspace(-.12,.12,7):
 for y in np.linspace(-.30,.02,9):
  patch=a[(abs(a[:,0]-x)<.018)&(abs(a[:,1]-y)<.018)]
  if len(patch)>10:samples.append([x,y,float(np.percentile(patch[:,2],85))])
samples=np.array(samples)
slope=np.linalg.lstsq(np.c_[samples[:,:2],np.ones(len(samples))],samples[:,2],rcond=None)[0]
normal=Vector((-float(slope[0]),-float(slope[1]),1)).normalized()
rotation=normal.rotation_difference(Vector((0,0,1))).to_matrix()
r=np.array(rotation);b=a@r.T
floor=float(np.percentile(b[:,2],.3))
for o in objects:
 inv=o.matrix_world.inverted()
 for v in o.data.vertices:
  q=rotation@(o.matrix_world@v.co);q.z=max(0,q.z-floor);v.co=inv@q
 bpy.context.view_layer.objects.active=o
 mod=o.modifiers.new('game_mesh','DECIMATE');mod.ratio=min(1,18000/len(o.data.polygons))
 bpy.ops.object.modifier_apply(modifier=mod.name)
for im in bpy.data.images:
 if im.size[0]>1024:im.scale(1024,1024)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'source/medical_bed_level.blend'))
bpy.ops.export_scene.gltf(filepath=str(root/'bed.glb'),export_format='GLB',export_image_format='JPEG',export_jpeg_quality=92)
corrected=samples@r.T
residual=np.linalg.lstsq(np.c_[corrected[:,:2],np.ones(len(corrected))],corrected[:,2],rcond=None)[0]
report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'surface_slope_before':slope.tolist(),'surface_slope_after':residual.tolist(),'method':'exposed mattress plane fit; pillow and rails excluded'}
(root/'source/bed_level_report.json').write_text(json.dumps(report,indent=2))
print('BED_LEVEL_REPORT',report)
