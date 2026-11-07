"""Level the imported bed using its principal frame axes; keep its original UVs."""
import bpy,numpy as np,shutil,json
from pathlib import Path
from mathutils import Vector,Matrix
root=Path(__file__).resolve().parents[1]/'assets/worlds/survivor_base'
backup=root/'source/bed_before_level.glb'
if not backup.exists():shutil.copy2(root/'bed.glb',backup)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(backup))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
a=np.array([list(o.matrix_world@v.co) for o in objects for v in o.data.vertices])
values,axes=np.linalg.eigh(np.cov(a.T))
x=axes[:,1];y=axes[:,2]
if x[0]<0:x=-x
if y[1]<0:y=-y
z=np.cross(x,y)
rotation=np.stack([x,y,z]);center=a.mean(axis=0)
b=(a-center)@rotation.T
floor=float(np.percentile(b[:,2],.6))
for o in objects:
 inv=o.matrix_world.inverted()
 for v in o.data.vertices:
  point=rotation@(np.array(o.matrix_world@v.co)-center)
  point[2]=max(0.0,float(point[2])-floor)
  v.co=inv@Vector(point.tolist())
bpy.ops.export_scene.gltf(filepath=str(root/'bed.glb'),export_format='GLB',export_image_format='JPEG',export_jpeg_quality=92)
(root/'source/bed_level_report.json').write_text(json.dumps({'basis':rotation.tolist(),'floor':floor,'method':'principal frame alignment and bottom contact leveling'},indent=2))
print('BED_LEVELLED',rotation.tolist())
