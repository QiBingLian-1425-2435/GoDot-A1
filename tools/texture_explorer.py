"""Blender --background --python tools/texture_explorer.py -- input.glb"""
import bpy,sys,random,math,bmesh,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'assets/characters/explorer';(out/'source').mkdir(parents=True,exist_ok=True);(out/'source/.gdignore').write_text('')
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=sys.argv[sys.argv.index('--')+1])
colors=[(.24,.27,.13),(.40,.32,.20),(.16,.10,.065),(.66,.44,.27),(.075,.045,.027),(.75,.43,.08),(.38,.37,.29),(.09,.065,.04)]
random.seed(4);size=256;image=bpy.data.images.new('explorer_albedo',width=size,height=size);pixels=[]
for y in range(size):
 for x in range(size):
  c=colors[x//32];noise=random.uniform(-.013,.013);pixels.extend([max(0,min(1,v+noise)) for v in c]+[1])
image.pixels=pixels;image.filepath_raw=str(out/'explorer_albedo.png');image.file_format='PNG';image.save();image.pack()
mat=bpy.data.materials.new('explorer_textured');mat.use_nodes=True;n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=image;mat.node_tree.links.new(n.outputs['Color'],mat.node_tree.nodes['Principled BSDF'].inputs['Base Color']);mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.85
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in objects:
 part=int(o.name.rsplit('_',1)[1]);o.data.materials.clear();o.data.materials.append(mat)
 
 while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
 uv=o.data.uv_layers.new(name='UVMap')
 for poly in o.data.polygons:
  center=sum((o.data.vertices[i].co for i in poly.vertices),Vector())/len(poly.vertices);x,y,z=center
  color={0:1,1:3,2:0,3:2,4:2,5:2,6:0,7:0,8:2,9:3,10:3,11:5,12:2,13:1,14:2}[part]
  if part==1:
   if z>.85 or (x<.015 and z>.79):color=4
   if x>.125 and .805<z<.835 and .024<abs(y)<.074:color=7
  if part in [6,7] and z<.56:color=1
  for j,li in enumerate(poly.loop_indices):uv.data[li].uv=((color+.5)/8+o.data.vertices[o.data.loops[li].vertex_index].co.y*.01,.5+o.data.vertices[o.data.loops[li].vertex_index].co.z*.1)
  poly.material_index=0
 # Split trousers at the centre so both legs follow existing feet pivots.
 chunks=[o]
 if part==0:
  other=o.copy();other.data=o.data.copy();bpy.context.collection.objects.link(other);chunks=[o,other]
  for k,obj in enumerate(chunks):
   bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.delete(bm,geom=[f for f in bm.faces if (f.calc_center_median().y<0)==(k==0)],context='FACES');bm.to_mesh(obj.data);bm.free()
 for k,obj in enumerate(chunks):
  cy=sum(v.co.y for v in obj.data.vertices)/max(1,len(obj.data.vertices))
  bone='Head' if part==1 else ('FootL' if cy>0 else 'FootR') if part in [0,3,4] else ('WingL' if cy>0 else 'WingR') if part in [6,7,9,10] else 'Hips'
  obj.name=bone+'__explorer_'+str(part)+'_'+str(k)
  for v in obj.data.vertices:v.co=Vector((-v.co.y*1.65,v.co.x*1.65,v.co.z*1.65))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/explorer.blend'));bpy.ops.export_scene.gltf(filepath=str(out/'male.glb'),export_format='GLB')
(out/'asset_manifest.json').write_text(json.dumps({'generator':'tools/texture_explorer.py','files':{n:{'sha256':hashlib.sha256((out/n).read_bytes()).hexdigest()} for n in ['male.glb','explorer_albedo.png']}},indent=2))
