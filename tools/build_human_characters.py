"""Run with Blender --background --python tools/build_human_characters.py.

Original A/C concept interpretation. Outputs editable .blend and runtime GLB
under ignored assets/characters/humans. Mesh names encode Godot attachment bones.
"""
import math
import hashlib
import json
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/humans'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE=OUT/'source'
SOURCE.mkdir(exist_ok=True)
(SOURCE/'.gdignore').write_text('')


def xyz(p):
    return (p[0], -p[2], p[1])


def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    node = m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = .85
    return m


def finish(obj, name, bone, mat):
    obj.name = bone + '__' + name
    obj.data.materials.append(mat)
    obj['attachment_bone'] = bone
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def oval(name, p, size, bone, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=xyz(p))
    obj = bpy.context.object
    obj.scale = (size[0]/2, size[2]/2, size[1]/2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, bone, mat)


def rounded(name, p, size, bone, mat, bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new('Soft tailored edges', 'BEVEL')
    mod.width = bevel
    mod.segments = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, bone, mat)


def curve(name, points, radius, bone, mat):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions = '3D'
    data.bevel_depth = radius
    data.bevel_resolution = 2
    spline = data.splines.new('POLY')
    spline.points.add(len(points)-1)
    for point, value in zip(spline.points, points):
        point.co = (*xyz(value), 1)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return finish(obj, name, bone, mat)


def hair_cap(mat, female):
    # One continuous scalp shell, open below the forehead; no sphere bunches.
    vertices, faces = [], []
    rings, segments = 10, 32
    for j in range(rings+1):
        for i in range(segments):
            phi = i*math.tau/segments
            # Face is -Z: forehead high in front, neck-length bob at rear.
            front = max(0, min(1, (-math.sin(phi)+.25)/.65))
            end = (2.1 - front*.88 + front*.025*math.cos(phi*5) if female
                   else 1.72-front*(.48+.08*math.cos(phi)))
            theta = .02 + (end-.02)*j/rings
            p = (.355*math.sin(theta)*math.cos(phi),
                 1.315+.36*math.cos(theta),
                 -.03+.305*math.sin(theta)*math.sin(phi))
            vertices.append(xyz(p))
    for j in range(rings):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    mesh=bpy.data.meshes.new('scalp_shell');mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new('scalp',mesh);bpy.context.collection.objects.link(obj)
    finish(obj,'hair_cap','Head',mat)
    if female:
        for side in [-1,1]:
            rounded('bob_side', (side*.305,1.19,.01),(.12,.39,.28),'Head',mat,.055)
    else:
        for i in range(3):
            lock=oval('crown_lock',(-.13+i*.12,1.637,.015),(.22,.1,.19),'Head',mat)
            lock.rotation_euler.y=-.25


def build(gender):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    female=gender=='female'
    for old in list(bpy.data.materials):
        if old.users==0:bpy.data.materials.remove(old)
    skin=material('skin',(.72,.46,.29))
    hair=material('hair',(.055,.042,.038) if female else (.12,.064,.032))
    shirt=material('shirt',(.20,.29,.34) if female else (.23,.28,.14))
    pants=material('pants',(.11,.12,.13) if female else (.46,.39,.27))
    boot=material('boots',(.10,.065,.045))
    eyes=material('eyes',(.025,.02,.018))
    lip=material('mouth',(.32,.10,.065))
    button=material('buttons',(.10,.12,.10))
    oval('neck',(0,.985,.0),(.19,.22,.19),'Spine',skin)
    oval('face',(0,1.285,-.035),(.65,.61,.55),'Head',skin)
    for side in [-1,1]:
        oval('ear',(side*.335,1.265,-.025),(.13,.17,.10),'Head',skin)
        oval('eye',(side*.139,1.31,-.290),(.043,.064,.022),'Head',eyes)
        curve('brow',[(side*.105,1.393,-.31),(side*.14,1.406,-.309),(side*.175,1.392,-.302)],.009,'Head',hair)
    oval('nose',(0,1.26,-.323),(.065,.075,.065),'Head',skin)
    curve('smile',[(-.052,1.195,-.309),(-.025,1.183,-.315),(0,1.180,-.317),(.03,1.188,-.313),(.046,1.202,-.309)],.007,'Head',lip)
    hair_cap(hair,female)
    rounded('jacket',(0,.775,.03),(.52 if female else .56,.46,.37),'Hips',shirt,.085)
    for side in [-1,1]:
        collar=rounded('collar',(side*.095,.968,-.155),(.15,.12,.035),'Spine',shirt,.013)
        collar.rotation_euler.y=side*.35
        rounded('trouser',(side*.145,.39,.025),(.23,.39,.27),'FootL' if side<0 else 'FootR',pants,.055)
        rounded('boot',(side*.145,.115,-.055),(.235,.22,.34),'FootL' if side<0 else 'FootR',boot,.055)
        bone='WingL' if side<0 else 'WingR'
        oval('sleeve',(side*.32,.79,-.015),(.22,.37,.24),bone,shirt)
        oval('hand',(side*.32,.62,-.075),(.17,.20,.18),bone,skin)
    for y in [.88,.77,.66]:
        oval('button',(0,y,-.163),(.027,.027,.014),'Hips',button)
    # All pieces remain editable; runtime attaches their named pivots to its rig.
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(gender+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(gender+'.blend')))


build('male')
build('female')
print('HUMAN_MODELS_EXPORTED',OUT)

index={'generator':'tools/build_human_characters.py','blender':bpy.app.version_string,'files':{}}
for name in ['male.glb','female.glb']:
    path=OUT/name
    index['files'][name]={'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(OUT/'asset_manifest.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
