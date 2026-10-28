"""Blender --background --python tools/refine_human_hair.py.

Refine only hair in the existing editable A/C sources. Body meshes are preserved.
Closed tapered ribbon volumes follow a scalp, with deliberately authored locks.
"""
import bpy
import math
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/humans'
RENDERS = ROOT / 'artifacts/hair_refinement'
RENDERS.mkdir(parents=True, exist_ok=True)


def xyz(p):
    return Vector((p[0], -p[2], p[1]))


def scalp(theta, phi, lift=0):
    return Vector(((.352+lift)*math.sin(theta)*math.cos(phi)+.045*max(0,math.cos(theta))**3,
                   1.315+(.36+lift)*math.cos(theta),
                   -.03+(.304+lift)*math.sin(theta)*math.sin(phi)))


def lock(name, centers, widths, thickness, mat):
    verts, faces = [], []
    sides = 20
    for i, center in enumerate(centers):
        tangent = (centers[min(i+1,len(centers)-1)]-centers[max(i-1,0)]).normalized()
        radial = Vector((center.x, (center.y-1.315)*.65, center.z+.03)).normalized()
        across = tangent.cross(radial).normalized()
        normal = across.cross(tangent).normalized()
        if normal.dot(radial)<0:normal=-normal
        for j in range(sides):
            a=j*math.tau/sides
            p=center+across*(math.cos(a)*widths[i])+normal*(math.sin(a)*thickness*min(1,widths[i]/.025))
            verts.append(xyz(p))
    for i in range(len(centers)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(centers)-1)*sides+j for j in range(sides)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('Head__hair_'+name,mesh);bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat);obj['attachment_bone']='Head'
    for p in mesh.polygons:p.use_smooth=True
    # Correct closed volume normals before GLB backface culling.
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)
    return obj


def swept(name, phi, end, width, mat, female=False, start=.10, sweep=.45, lift=.012):
    points=[];widths=[]
    for i in range(49):
        t=i/48
        theta=start+(end-start)*t
        angle=phi+sweep*(1-t)**1.4
        p=scalp(theta,angle,lift)
        # Bury roots below the continuous scalp instead of stacking a visible
        # circular plug at the crown. The lock emerges smoothly from the part.
        if female and t<.18:
            p.y-=.010*(1-t/.18)**2
        if female and end>1.7:
            # Full bob sides stay almost vertical below the temple, then tuck in.
            if theta>1.35:
                u=(theta-1.35)/(end-1.35)
                radius=math.sin(1.35)+.12*math.sin(u*math.pi)-.09*u**5
                p.x=(.352+lift)*math.cos(angle)*radius
                p.z=-.03+(.304+lift)*math.sin(angle)*radius
                p.y=1.394-.32*u
        if female:
            profile=min(1,math.sqrt(max(.000004,t/.10)))
            if t>.80:profile*=math.sqrt(max(.000004,1-((t-.80)/.20)**2))
        else:
            profile=max(.002,math.sin(math.pi*t)**.55)
        # Broad roots merge into crown, asymmetric pointed terminal end.
        widths.append(width*profile*(1-.08*t if female else 1-.15*t))
        points.append(p)
    return lock(name,points,widths,.021 if female else .027,mat)


def shell(mat, female):
    vertices=[];faces=[];segments=96;rings=32
    for j in range(rings+1):
        for i in range(segments):
            phi=i*math.tau/segments
            front=max(0,min(1,(-math.sin(phi)-.30)/.45))
            end=(2.02 if female else 1.65)-front*(.98 if female else .60)
            theta=.001+(end-.001)*j/rings
            crown_fill=.045*math.exp(-(theta/.45)**2) if female else 0
            p=scalp(theta,phi,-.006+crown_fill)
            vertices.append(xyz(p))
    for j in range(rings):
        for i in range(segments):
            a=j*segments+i;b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    mesh=bpy.data.meshes.new('continuous_scalp');mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new('Head__hair_underlayer',mesh);bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for p in mesh.polygons:p.use_smooth=True
    mod=obj.modifiers.new('Scalp thickness','SOLIDIFY');mod.thickness=.012


def render(gender, hair_only, back=False):
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=24
    scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
    scene.world.color=(.28,.28,.28)
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    scene.view_settings.exposure=-.7
    for o in scene.objects:
        if o.type=='MESH':o.hide_render=hair_only and '__hair_' not in o.name
    target=xyz((0,1.37,-.02))
    bpy.ops.object.camera_add(location=xyz((1.1,2.25,2.8 if back else -2.8)))
    camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=1.04;scene.camera=camera
    lights=[]
    for loc,power,size in [((-2,3,-3),160,3),((2,2,-1),70,2),((0,3,2),180,2)]:
        bpy.ops.object.light_add(type='AREA',location=xyz(loc));o=bpy.context.object
        o.data.energy=power;o.data.shape='DISK';o.data.size=size
        o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler();lights.append(o)
    scene.render.filepath=str(RENDERS/(gender+('_hair' if hair_only else '_head')+('_back' if back else '')+'.png'))
    bpy.ops.render.render(write_still=True)
    for o in [camera,*lights]:bpy.data.objects.remove(o,do_unlink=True)
    for o in scene.objects:o.hide_render=False


def build(gender):
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'source'/(gender+'.blend')))
    for obj in list(bpy.context.scene.objects):
        if any(token in obj.name for token in ['hair','fringe','bob_side','crown_lock']):
            bpy.data.objects.remove(obj,do_unlink=True)
    female=gender=='female'
    mat=next(o.data.materials[0] for o in bpy.context.scene.objects if '__brow' in o.name)
    color=(.055,.042,.038) if female else (.12,.064,.032)
    mat.diffuse_color=(*color,1)
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1)
    bpy.ops.object.select_all(action='DESELECT')
    shell(mat,female)
    # Rear/side locks, clockwise around the head. Front remains open for the face.
    for i in range(15 if female else 13):
        n=15 if female else 13
        phi=-.45+i*(math.pi+ .90)/(n-1)
        swept('outer_%02d'%i,phi,2.13 if female else 1.76+.08*math.sin(i*1.7),
              .073 if female else .079,mat,female,sweep=-.14 if female else -.52)
    # Forehead locks: varying lengths and side sweep are the defining A/C features.
    if female:
        for i,(phi,end,width) in enumerate([(-2.53,2.13,.070),(-2.24,1.35,.073),(-1.91,1.20,.066),(-1.57,1.20,.062),(-1.24,1.24,.061),(-.91,1.31,.060),(-.63,2.13,.068)]):
            swept('fringe_%02d'%i,phi,end,width,mat,True,sweep=-.22,lift=.027)
    else:
        for i,(phi,end,width) in enumerate([(-2.73,1.76,.075),(-2.42,1.61,.087),(-2.09,1.46,.095),(-1.76,1.34,.092),(-1.42,1.26,.084),(-1.09,1.30,.076),(-.72,1.52,.066)]):
            swept('fringe_%02d'%i,phi,end,width,mat,sweep=-.82,lift=.032)
        for i in range(5):
            swept('crown_%02d'%i,.2+i*.65,1.04,.071,mat,start=.04,sweep=-.95,lift=.045)
        # Staggered side layers break the helmet silhouette into reference tufts.
        for i,(phi,end) in enumerate([(-2.95,1.33),(-2.68,1.18),(-2.40,.96),(-.45,1.26),(.0,1.48),(1.0,1.40),(2.2,1.48)]):
            swept('layer_%02d'%i,phi,end,.069,mat,start=.28,sweep=-.65,lift=.056)
        for i in range(3):
            points=[];widths=[]
            a=Vector((.21-i*.035,1.635+i*.008,.10-i*.065))
            b=Vector((-.04,1.79+i*.006,.11-i*.060))
            c=Vector((-.29+i*.035,1.65+i*.013,.06-i*.060))
            for j in range(49):
                t=j/48;points.append((1-t)**2*a+2*t*(1-t)*b+t*t*c)
                widths.append(.045*max(.002,math.sin(math.pi*t)**.55))
            lock('crest_%02d'%i,points,widths,.025,mat)
    if female:
        # Fuse intersecting roots into one continuous sculpted surface. This
        # removes the artificial crown seam while retaining the large grooves.
        bpy.ops.object.select_all(action='DESELECT')
        hair_objects=[o for o in bpy.context.scene.objects if '__hair_' in o.name]
        for o in hair_objects:
            bpy.context.view_layer.objects.active=o
            for modifier in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
            o.select_set(True)
        bpy.context.view_layer.objects.active=hair_objects[0]
        bpy.ops.object.join();sculpt=bpy.context.object;sculpt.name='Head__hair_sculpt'
        mod=sculpt.modifiers.new('Continuous sculpt union','REMESH');mod.mode='VOXEL';mod.voxel_size=.003
        mod.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=sculpt.modifiers.new('Soft root transitions','SMOOTH');mod.factor=.5;mod.iterations=4
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=sculpt.modifiers.new('Runtime surface budget','DECIMATE');mod.ratio=.40
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for p in sculpt.data.polygons:p.use_smooth=True
    # Save editable source and export only runtime meshes, never studio objects.
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects:
        if o.type=='MESH':o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(gender+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/(gender+'.blend')))
    render(gender,True);render(gender,False);render(gender,True,True)


for gender in ['male','female']:build(gender)
manifest={'generator':'tools/refine_human_hair.py','blender':bpy.app.version_string,'files':{}}
for name in ['male.glb','female.glb']:
    p=OUT/name;manifest['files'][name]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
