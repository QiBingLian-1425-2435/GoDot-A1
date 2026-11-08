"""Blender entry: preserve source UV/materials while preparing external game assets."""
import bpy, json, hashlib, sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from melee_asset_geometry import normalize

root = Path(__file__).resolve().parents[1]
out = root / 'assets/weapons/melee'
out.mkdir(parents=True, exist_ok=True)
(out / 'source').mkdir(exist_ok=True)
(out / 'source/.gdignore').write_text('')
report = []
for kind, filename in [
    ('fire_axe', '消防斧3d模型.glb'), ('crowbar', '钩状工具3d模型.glb'),
    ('baseball_bat', '棒球棍3d模型.glb'), ('baton', '伸缩警棍3d模型.glb'),
    ('machete', '开山刀3d模型.glb'), ('katana', '日本刀3d模型.glb'),
]:
    src = Path.home() / 'Downloads' / filename
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    before = sum(len(o.data.polygons) for o in meshes)
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new('game_mesh', 'DECIMATE')
        modifier.ratio = min(1, 10000 / max(1, before))
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for image in bpy.data.images:
        if max(image.size) > 1024:
            image.scale(1024, 1024)
    points = [o.matrix_world @ Vector(v) for o in meshes for v in o.bound_box]
    grip_info=normalize(meshes,kind)
    target = out / (kind + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB')
    bpy.ops.wm.save_as_mainfile(filepath=str(out / 'source' / (kind + '.blend')))
    report.append(dict(kind=kind, source=str(src), source_faces=before,
        bounds_min=[min(p[i] for p in points) for i in range(3)],
        bounds_max=[max(p[i] for p in points) for i in range(3)],
        source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),
        sha256=hashlib.sha256(target.read_bytes()).hexdigest(), bytes=target.stat().st_size, **grip_info))
    (out / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print('MELEE_MODEL', report[-1], flush=True)
