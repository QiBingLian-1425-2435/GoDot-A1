"""Run with Blender --background --python tools/prepare_survivor_base.py -- --source DIR.
Keep originals untouched; optimize textured user assets for the standalone base.
"""
import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source=Path(args[args.index('--source')+1]) if '--source' in args else Path('E:/new/模型')
out=root/'assets/worlds/survivor_base';out.mkdir(parents=True,exist_ok=True)
names={'中央六角取暖炉3d模型':'heater','公告板3d模型':'notice_board','军绿双门储物柜3d模型':'locker','医护角色3d模型':'doctor','医疗标识旗布3d模型':'medical_banner','单人医疗床3d模型':'bed','厨房工作台3d模型':'kitchen_counter','双扇钢制大门3d模型':'gate','双眼燃气灶3d模型':'stove','商人':'merchant','地面储水罐3d模型':'water_tank','床头木柜3d模型':'bedside','抽屉档案柜3d模型':'filing_cabinet','方形石板地砖3d模型':'floor_tile','旗帜3d模型':'banner','暖光灯笼3d模型':'lantern','木托盘3d模型':'pallet','木柱遮阳棚3d模型':'canopy','木箱 3d 模型':'crate','木质 办公桌 3d模型':'counter','木质凳子3d模型':'stool','木质办公桌3d模型':'desk','木质背椅3d模型':'chair','混凝土直墙模块3d模型':'wall','砖砌炉子3d模型':'forge','立式警示灯3d模型':'warning_light','管理员':'administrator','绿色医疗隔离帘3d模型':'curtain','药柜3d模型':'medicine_cabinet','金属货架3d模型':'shelf','铁匠':'blacksmith','高架储水塔3d模型':'water_tower','黄色便携柴油发电机3d模型':'generator'}
report=[]
for src in sorted(source.glob('*.glb')):
 if src.stem not in names:continue
 name=names[src.stem];dest=out/(name+'.glb')
 if dest.exists():
  print('CACHED',name,flush=True);continue
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(src))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 pts=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
 lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
 before=sum(len(o.data.polygons) for o in meshes)
 for o in meshes:
  bpy.context.view_layer.objects.active=o
  mod=o.modifiers.new('game_mesh','DECIMATE');mod.ratio=min(1,18000/max(1,before))
  bpy.ops.object.modifier_apply(modifier=mod.name)
 for im in bpy.data.images:
  if im.size[0]>1024 or im.size[1]>1024:im.scale(1024,1024)
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',export_image_format='JPEG',export_jpeg_quality=88)
 record={'name':name,'source':src.name,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'bounds_min':list(lo),'bounds_max':list(hi),'faces_before':before,'faces_after':sum(len(o.data.polygons) for o in meshes),'bytes':dest.stat().st_size}
 report.append(record);print('PREPARED',json.dumps(record),flush=True)
 (out/(name+'.json')).write_text(json.dumps(record,indent=2),encoding='utf-8')
(out/'asset_manifest.json').write_text(json.dumps([json.loads(p.read_text()) for p in out.glob('*.json') if p.name!='asset_manifest.json'],ensure_ascii=False,indent=2),encoding='utf-8')
