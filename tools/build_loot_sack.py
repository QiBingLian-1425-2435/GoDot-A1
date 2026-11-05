"""Create a low-poly burlap loot sack in Blender; all art stays external."""
import bpy,math,random,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'assets/props/loot_sack';(out/'source').mkdir(parents=True,exist_ok=True);(out/'source/.gdignore').write_text('')
bpy.ops.wm.read_factory_settings(use_empty=True);random.seed(27)
def material(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1);p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.94;return m
cloth=material('warm_brown_burlap',(.35,.21,.105));rope=material('hemp_rope',(.49,.36,.20));thread=material('stitched_thread',(.63,.47,.27));patch=material('dark_repair_patch',(.23,.135,.065))
image=bpy.data.images.new('burlap_weave',width=256,height=256);pixels=[]
for y in range(256):
 for x in range(256):
  weave=(.025 if x%8<3 else -.012)+(.018 if y%8<3 else -.008)+random.uniform(-.009,.009)
  pixels.extend([.43+weave,.29+weave,.16+weave,1])
image.pixels=pixels;image.filepath_raw=str(out/'burlap_albedo.png');image.file_format='PNG';image.save();image.pack()
n=cloth.node_tree.nodes.new('ShaderNodeTexImage');n.image=image;cloth.node_tree.links.new(n.outputs['Color'],cloth.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
rings=[(0,.19),(.055,.27),(.17,.30),(.31,.265),(.405,.17),(.46,.078),(.49,.076),(.55,.12)]
segments=16;vertices=[]
for j,(z,r) in enumerate(rings):
 for i in range(segments):
  a=i*math.tau/segments;rr=r*(1+.07*math.sin(a*3+j*.65)+(.075*math.cos(a*8) if j>3 else 0))
  vertices.append((math.cos(a)*rr+.02*math.sin(j),math.sin(a)*rr*.84,z+(.012*math.sin(a*5) if j==7 else 0)))
faces=[]
for j in range(len(rings)-1):
 for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
faces.append(tuple(reversed(range(segments))))
mesh=bpy.data.meshes.new('sack_facets');mesh.from_pydata(vertices,[],faces);mesh.update();obj=bpy.data.objects.new('burlap_sack',mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(cloth)
uv=mesh.uv_layers.new(name='UVMap')
for face in mesh.polygons:
 for li in face.loop_indices:
  v=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(math.atan2(v.y,v.x)/math.tau+.5,v.z/.55)
# Rope and two short hanging tails, deliberately thick enough for the game camera.
def cord(name,points,radius,mat):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=radius;c.bevel_resolution=0;c.resolution_u=1
 s=c.splines.new('POLY');s.points.add(len(points)-1)
 for p,co in zip(s.points,points):p.co=(*co,1)
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(mat);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False)
for z in [.462,.481]:cord('neck_tie',[(.082*math.cos(i*math.tau/24)-.015,.071*math.sin(i*math.tau/24),z) for i in range(25)],.012,rope)
cord('tie_loop_left',[(-.02,-.08,.47),(-.09,-.11,.49),(-.105,-.12,.445),(-.05,-.10,.44),(-.02,-.08,.47)],.012,rope)
cord('tie_loop_right',[(-.02,-.08,.47),(.05,-.10,.49),(.075,-.11,.455),(.04,-.10,.44),(-.02,-.08,.47)],.012,rope)
cord('loose_tie',[(-.02,-.09,.46),(-.07,-.15,.39),(-.09,-.195,.33)],.011,rope)
cord('loose_tie',[(-.01,-.09,.46),(.045,-.16,.37),(.07,-.20,.34)],.011,rope)
# Sewn reinforcement on the front, kept just above the fabric surface.
for i in range(8):
 z=.095+i*.031;y=-.24 if z<.26 else -.23+(z-.26)*.48
 cord('front_stitch',[(-.018,y-.006,z-.006),(.018,y-.006,z+.006)],.0038,thread)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/loot_sack.blend'));bpy.ops.export_scene.gltf(filepath=str(out/'loot_sack.glb'),export_format='GLB')
(out/'asset_manifest.json').write_text(json.dumps({'generator':'tools/build_loot_sack.py','files':{n:{'sha256':hashlib.sha256((out/n).read_bytes()).hexdigest()} for n in ['loot_sack.glb','burlap_albedo.png']}},indent=2))
