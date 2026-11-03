import bpy, math, random
from mathutils import Vector
from pathlib import Path
random.seed(8)
out=Path(__file__).resolve().parents[1]/'assets/characters/sick_ghost';out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(n,c):
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True;m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*c,1);return m
skin=mat('sallow_skin',(.55,.43,.28));cloth=mat('faded_sage',(.30,.36,.22));hair=mat('dark_hair',(.075,.055,.04));dark=mat('sunken_eyes',(.055,.045,.025));band=mat('wrist_band',(.7,.7,.57))
def ball(n,p,s,m):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=p);o=bpy.context.object;o.name=n;o.scale=s;o.data.materials.append(m);return o
def rod(n,a,b,r,m):
 d=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cone_add(vertices=7,radius1=r,radius2=r*.85,depth=d.length,location=(Vector(a)+Vector(b))/2);o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
# Blender forward -Y, up Z
ball('hunched_gown',(0,.09,1.05),(.30,.23,.43),cloth)
ball('shoulders',(0,-.05,1.36),(.34,.23,.22),cloth)
for side in [-1,1]:
 x=side*.16
 rod('shin',(x,.04,.12),(x,.12,.62),.065,skin)
 ball('slipper',(x,-.075,.075),(.115,.21,.075),cloth)
 rod('thigh',(x,.12,.55),(x,.08,.91),.095,skin)
 for j in range(3):
  xx=x+(j-1)*.09
  bpy.ops.mesh.primitive_cone_add(vertices=3,radius1=0,radius2=.12,depth=.29,location=(xx,-.025,.67+random.random()*.07));bpy.context.object.data.materials.append(cloth)
ball('neck',(0,-.20,1.43),(.10,.12,.15),skin)
ball('head',(0,-.29,1.59),(.19,.17,.23),skin)
ball('hair_cap',(0,-.25,1.76),(.21,.18,.12),hair)
for i in range(11):
 a=i*math.tau/11
 ball('hair_lock',(math.cos(a)*.16,-.26+math.sin(a)*.13,1.73),(.085,.08,.13+random.random()*.05),hair)
for x in [-.08,.08]:
 ball('eye_socket',(x,-.435,1.62),(.062,.022,.033),dark)
rod('nose',(0,-.43,1.62),(0,-.49,1.54),.035,skin)
ball('mouth',(0,-.435,1.49),(.065,.018,.025),dark)
rod('sleeve_left',(-.29,-.03,1.34),(-.34,-.07,1.13),.115,cloth)
rod('arm_left',(-.34,-.07,1.13),(-.35,-.21,.83),.055,skin)
rod('wrist_band',(-.35,-.20,.88),(-.35,-.21,.83),.062,band)
ball('hand_left',(-.35,-.23,.76),(.065,.045,.10),skin)
for i in range(4):rod('finger',(-.40+i*.028,-.24,.76),(-.40+i*.028,-.27,.65),.013,skin)
rod('sleeve_right',(.29,-.05,1.34),(.35,-.16,1.14),.105,cloth)
rod('cough_forearm',(.35,-.16,1.14),(.16,-.48,1.49),.06,skin)
ball('cough_hand',(.10,-.49,1.49),(.09,.055,.075),skin)
for i in range(4):ball('knuckle',(.035+i*.035,-.52,1.53),(.023,.026,.03),skin)
for i in range(8):ball('cloth_patch',(random.uniform(-.23,.23),-.135,random.uniform(.84,1.31)),(.035,.012,.055),dark)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/sick_ghost.blend'))
bpy.ops.export_scene.gltf(filepath=str(out/'sick_ghost.glb'),export_format='GLB')
