"""Convert the installed Ground Zero scenes into external Godot map data.

Reads the installed game without modifying it. Generated game assets stay under
assets/, which is excluded from Git. Install duckov_map_requirements.txt first.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import struct
import time

import numpy as np
import UnityPy
from UnityPy.classes import PPtr
from UnityPy.helpers.MeshHelper import MeshHandler
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

ROOT = Path(__file__).resolve().parents[1]
REFLECT = np.diag([1., 1., -1., 1.])
SCENES = {"surface": 14, "cave": 15}


def vec(value, keys="xyz"):
    return np.array([value[k] if isinstance(value, dict) else getattr(value, k) for k in keys], dtype=np.float64)


def trs(position, rotation, scale):
    x, y, z, w = vec(rotation, "xyzw")
    result = np.eye(4)
    result[:3, :3] = np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)],
    ]) @ np.diag(vec(scale))
    result[:3, 3] = vec(position)
    return result


def transform_record(matrix):
    # Godot Transform3D: basis columns, then origin.
    matrix = REFLECT @ matrix @ REFLECT
    return matrix[:3, :].T.reshape(-1).round(7).tolist()


def clean(value):
    return re.sub(r"[^a-z0-9_]+", "_", str(value).lower()).strip("_")[:90] or "asset"


def uid(reader):
    return f"{clean(reader.assets_file.name)}_{reader.path_id}"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""): digest.update(block)
    return digest.hexdigest()


class Scene:
    def __init__(self, data_dir, index, generator):
        self.index = index
        self.env = UnityPy.load(str(data_dir / f"level{index}"))
        self.objects = list(self.env.objects)
        self.file = self.objects[0].assets_file
        self.transforms = {}
        self.go = {}
        self.go_transform = {}
        self.world = {}
        self.active = {}
        self.scripts = {}
        for obj in self.objects:
            if obj.type.name == "GameObject": self.go[obj.path_id] = obj.parse_as_object()
            elif obj.type.name in ("Transform", "RectTransform"):
                item = obj.parse_as_object()
                self.transforms[obj.path_id] = item
                self.go_transform[item.m_GameObject.m_PathID] = obj.path_id
            elif obj.type.name == "MonoBehaviour":
                head = obj.parse_monobehaviour_head()
                self.scripts[obj.path_id] = (head.m_Script.deref().parse_as_object().m_ClassName, head.m_GameObject.m_PathID)
        self.env.typetree_generator = generator

    def matrix(self, go_id):
        transform_id = self.go_transform[go_id]
        if transform_id not in self.world:
            item = self.transforms[transform_id]
            local = trs(item.m_LocalPosition, item.m_LocalRotation, item.m_LocalScale)
            if item.m_Father:
                parent = self.transforms[item.m_Father.m_PathID].m_GameObject.m_PathID
                local = self.matrix(parent) @ local
            self.world[transform_id] = local
        return self.world[transform_id]

    def enabled(self, go_id):
        if go_id not in self.active:
            item = self.transforms[self.go_transform[go_id]]
            parent_active = True
            if item.m_Father:
                parent_id = self.transforms[item.m_Father.m_PathID].m_GameObject.m_PathID
                parent_active = self.enabled(parent_id)
            self.active[go_id] = bool(self.go[go_id].m_IsActive) and parent_active
        return self.active[go_id]

    def pointer(self, data):
        return PPtr(m_FileID=int(data["m_FileID"]), m_PathID=int(data["m_PathID"]), assetsfile=self.file)

    def matrix_override(self, go_id, overrides, cache):
        transform_id=self.go_transform[go_id]
        if transform_id not in cache:
            item=self.transforms[transform_id];spec=overrides.get(transform_id)
            local=trs(spec["localPosition"],spec["localRotation"]["value"],item.m_LocalScale) if spec else trs(item.m_LocalPosition,item.m_LocalRotation,item.m_LocalScale)
            if item.m_Father:
                parent=self.transforms[item.m_Father.m_PathID].m_GameObject.m_PathID
                local=self.matrix_override(parent,overrides,cache)@local
            cache[transform_id]=local
        return cache[transform_id]


class Exporter:
    def __init__(self, game_dir, output):
        self.game_dir, self.output = game_dir, output
        self.data_dir = game_dir / "Duckov_Data"
        self.generator = TypeTreeGenerator("2022.3.62f2")
        self.generator.load_local_dll_folder(str(self.data_dir / "Managed"))
        for folder in ("meshes", "textures", "terrain"):
            (output / folder).mkdir(parents=True, exist_ok=True)
        self.meshes = {}
        self.materials = {}
        self.textures = {}
        self.used_files = set()
        self.not_converted = Counter()
        self.shaders = {}
        managers=UnityPy.load(str(self.data_dir/"globalgamemanagers"))
        self.layer_names=next(o.read_typetree()["layers"] for o in managers.objects if o.type.name=="TagManager")
        self.collision_matrix=next(o.read_typetree()["m_LayerCollisionMatrix"] for o in managers.objects if o.type.name=="PhysicsManager")

    def texture(self, ptr):
        if not ptr: return ""
        reader = ptr.deref()
        key = uid(reader)
        if key not in self.textures:
            self.used_files.add(reader.assets_file.name)
            tex = reader.parse_as_object()
            path = f"textures/{key}.png"
            tex.image.save(self.output / path)
            self.textures[key] = {"name":tex.m_Name, "path":path, "width":tex.m_Width, "height":tex.m_Height}
        return self.textures[key]["path"]

    def material(self, ptr):
        if not ptr: return ""
        reader = ptr.deref()
        key = uid(reader)
        if key in self.materials: return key
        self.used_files.add(reader.assets_file.name)
        obj = reader.parse_as_object()
        tree = reader.read_typetree()
        saved = tree["m_SavedProperties"]
        colors = dict(saved["m_Colors"])
        floats = dict(saved["m_Floats"])
        tex_envs = dict(obj.m_SavedProperties.m_TexEnvs)
        texture = ""
        uv_scale, uv_offset = [1.,1.], [0.,0.]
        for prop in ("_BaseMap", "_MainTex", "_BaseColorMap", "_Albedo", "_Diffuse"):
            entry = tex_envs.get(prop)
            if entry and entry.m_Texture:
                texture = self.texture(entry.m_Texture)
                uv_scale, uv_offset = vec(entry.m_Scale,"xy").tolist(), vec(entry.m_Offset,"xy").tolist()
                break
        tint = colors.get("_Tint",colors.get("_BaseColor",colors.get("_Color",{"r":1,"g":1,"b":1,"a":1})))
        if "water" in obj.m_Name.lower():
            tint = colors.get("_ColorShallow",colors.get("_Tint",colors.get("_Color",tint))).copy()
            if tint["a"]<=.001: tint["a"] = .7
        alpha_clip = floats.get("_AlphaClip",floats.get("_AlphaClipThreshold",0)) > .5
        alpha_clip |= "leaf" in obj.m_Name.lower() or "grass" in obj.m_Name.lower()
        emission = colors.get("_EmissionColor",{"r":0,"g":0,"b":0,"a":0})
        shader_key = uid(obj.m_Shader.deref()) if obj.m_Shader else ""
        if shader_key and shader_key not in self.shaders:
            # Shader identity is source data too, even when its file contains no mesh.
            self.shaders[shader_key] = obj.m_Shader.deref().parse_as_object().m_ParsedForm.m_Name
            self.used_files.add(obj.m_Shader.deref().assets_file.name)
        shader = self.shaders.get(shader_key,"")
        role = "light_volume" if shader == "ZeroPoint" else "surface"
        if "Particles/" in shader and "Fade" in obj.m_Name: role = "soft_volume"
        self.materials[key] = {
            "name": obj.m_Name, "albedo": [float(tint[k]) for k in "rgba"], "texture": texture,
            "uv_scale":uv_scale, "uv_offset":uv_offset, "roughness":1-floats.get("_Smoothness",.1),
            "alpha_clip":bool(alpha_clip), "alpha_cutoff":floats.get("_Cutoff",.5),
            "transparent":floats.get("_Surface",0)>.5 or "water" in obj.m_Name.lower(),
            "emission":[float(emission[k]) for k in "rgb"],
            "shader":shader, "role":role,
            "cull":int(floats.get("_Cull",2)),
            "water_mask":self.texture(tex_envs["_WaterMask"].m_Texture) if tex_envs.get("_WaterMask") and tex_envs["_WaterMask"].m_Texture else "",
        }
        return key

    def write_mesh(self, key, vertices, normals, uv, triangles, colors=None):
        vertices = np.asarray(vertices,dtype="<f4")[:,:3].copy()
        vertices[:,2] *= -1
        normals = np.asarray(normals,dtype="<f4")[:,:3].copy() if normals is not None and len(normals)==len(vertices) else np.zeros_like(vertices)
        normals[:,2] *= -1
        uv = np.asarray(uv,dtype="<f4")[:,:2].copy() if uv is not None and len(uv)==len(vertices) else np.zeros((len(vertices),2),dtype="<f4")
        uv[:,1] = 1-uv[:,1]
        has_colors = colors is not None and len(colors)==len(vertices)
        triangles = [np.asarray(part,dtype="<u4").reshape(-1,3) for part in triangles]
        # Godot front faces wind clockwise. Preserve the decoded vertex normals.
        for part in triangles:
            if len(part) and np.any(normals):
                face = vertices[part[:min(20,len(part))]]
                cross = np.cross(face[:,1]-face[:,0],face[:,2]-face[:,0])
                if np.sum(cross*normals[part[:len(face),0]])>0: part[:,[1,2]] = part[:,[2,1]]
        path = f"meshes/{key}.meshbin"
        with (self.output / path).open("wb") as stream:
            stream.write(b"DGM1"+struct.pack("<III",len(vertices),len(triangles),int(has_colors)))
            stream.write(vertices.tobytes()); stream.write(normals.tobytes()); stream.write(uv.tobytes())
            if has_colors:
                normalized=np.asarray(colors,dtype="<f4")
                if normalized.max()>1.001:normalized=normalized/255.
                stream.write(normalized.tobytes())
            for part in triangles:
                stream.write(struct.pack("<I",part.size)); stream.write(part.tobytes())
        self.meshes[key] = {"path":path,"vertices":len(vertices),"triangles":sum(len(t) for t in triangles),"surfaces":len(triangles)}
        return key

    def mesh(self, ptr):
        if not ptr: return ""
        reader = ptr.deref()
        key = uid(reader)
        if key not in self.meshes:
            self.used_files.add(reader.assets_file.name)
            mesh = reader.parse_as_object()
            handler = MeshHandler(mesh); handler.process()
            if not handler.m_Vertices: return ""
            self.write_mesh(key,handler.m_Vertices,handler.m_Normals,handler.m_UV0,handler.get_triangles(),handler.m_Colors)
            self.meshes[key]["name"] = mesh.m_Name
        return key

    def prefab(self, ptr, matrix, tint=None, lod_renderers=None, colliders=None):
        """Terrain tree prototypes are ordinary prefab hierarchies, not billboards."""
        reader = ptr.deref()
        go = reader.parse_as_object()
        components = [p.component.deref() for p in go.m_Component]
        lod_group = next((o.parse_as_object() for o in components if o.type.name=="LODGroup"),None)
        if lod_group:
            lod_renderers = {p.renderer.m_PathID:i for i,lod in enumerate(lod_group.m_LODs) for p in lod.renderers}
        transform = next(o.parse_as_object() for o in components if o.type.name=="Transform")
        local = matrix @ trs(transform.m_LocalPosition,transform.m_LocalRotation,transform.m_LocalScale)
        renderer_object = next((o for o in components if o.type.name=="MeshRenderer"),None)
        renderer = renderer_object.parse_as_object() if renderer_object else None
        mesh_filter = next((o.parse_as_object() for o in components if o.type.name=="MeshFilter"),None)
        result = []
        if renderer and mesh_filter and renderer.m_Enabled:
            result.append({"name":go.m_Name,"mesh":self.mesh(mesh_filter.m_Mesh),"materials":[self.material(p) for p in renderer.m_Materials],"transform":transform_record(local),"color":tint or [1,1,1,1],"source":"terrain_tree","shadow_mode":int(renderer.m_CastShadows),"lod":(lod_renderers or {}).get(renderer_object.path_id,0)})
        if colliders is not None:
            for component in components:
                if component.type.name not in ("CapsuleCollider","BoxCollider","SphereCollider","MeshCollider"):continue
                tree=component.read_typetree()
                if not tree.get("m_Enabled",True) or tree.get("m_IsTrigger",False):continue
                record={"name":go.m_Name,"transform":transform_record(local),"type":component.type.name,"trigger":False,"layer":go.m_Layer,"source":"terrain_tree"}
                for key in ("m_Center","m_Size","m_Radius","m_Height","m_Direction","m_Convex"):
                    if key in tree:record[key[2:].lower()]=tree[key]
                if component.type.name=="MeshCollider":record["mesh"]=self.mesh(component.parse_as_object().m_Mesh)
                colliders.append(record)
        for child in transform.m_Children:
            child_transform = child.deref().parse_as_object()
            result.extend(self.prefab(child_transform.m_GameObject,local,tint,lod_renderers,colliders))
        return result

    def skinned_mesh(self, scene, renderer):
        source=renderer.m_Mesh.deref()
        mesh=source.parse_as_object();handler=MeshHandler(mesh);handler.process()
        bind=source.read_typetree()["m_BindPose"]
        matrices=[]
        for bone,pose in zip(renderer.m_Bones,bind):
            bone_transform=bone.deref().parse_as_object()
            matrix=scene.matrix(bone_transform.m_GameObject.m_PathID)
            matrices.append(matrix@np.array([[pose[f"e{r}{c}"] for c in range(4)] for r in range(4)]))
        matrices=np.asarray(matrices)
        bone_ids=np.asarray(handler.m_BoneIndices,dtype=np.int32)
        weights=np.asarray(handler.m_BoneWeights,dtype=np.float64)
        skin=np.sum(matrices[bone_ids]*weights[:,:,None,None],axis=1)
        vertices=np.c_[np.asarray(handler.m_Vertices)[:,:3],np.ones(len(handler.m_Vertices))]
        vertices=np.einsum('nij,nj->ni',skin,vertices)[:,:3]
        normals=np.einsum('nij,nj->ni',np.linalg.inv(skin[:,:3,:3]).transpose(0,2,1),np.asarray(handler.m_Normals)[:,:3])
        normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-8)
        key=f"level{scene.index}_skinned_{renderer.object_reader.path_id}"
        self.write_mesh(key,vertices,normals,handler.m_UV0,handler.get_triangles(),handler.m_Colors)
        self.meshes[key]["name"]=mesh.m_Name
        self.used_files.add(source.assets_file.name)
        return key

    def terrain(self, scene, obj, label):
        renderer = obj.parse_as_object()
        reader = renderer.m_TerrainData.deref()
        self.used_files.add(reader.assets_file.name)
        tree = reader.read_typetree()
        self.terrain_file = reader.assets_file
        heightmap = tree["m_Heightmap"]
        n = int(heightmap["m_Resolution"])
        scale = vec(heightmap["m_Scale"])
        heights = np.asarray(heightmap["m_Heights"],dtype=np.float32).reshape(n,n)/32767.*scale[1]
        holes = np.asarray(heightmap["m_Holes"],dtype=np.uint8).reshape(n-1,n-1) if heightmap["m_Holes"] else np.full((n-1,n-1),255,dtype=np.uint8)
        matrix = scene.matrix(renderer.m_GameObject.m_PathID)
        splat = tree["m_SplatDatabase"]
        def ptr(data):return PPtr(m_FileID=data["m_FileID"],m_PathID=data["m_PathID"],assetsfile=reader.assets_file)
        alpha = self.texture(ptr(splat["m_AlphaTextures"][0]))
        layers = []
        for ref in splat["m_TerrainLayers"]:
            layer_reader = ptr(ref).deref()
            layer = layer_reader.parse_as_object()
            layers.append({"name":layer.m_Name,"texture":self.texture(layer.m_DiffuseTexture),"normal":self.texture(layer.m_NormalMapTexture) if layer.m_NormalMapTexture else "","tile_size":vec(layer.m_TileSize,"xy").tolist(),"tile_offset":vec(layer.m_TileOffset,"xy").tolist()})
        heights.astype("<f4").tofile(self.output/f"terrain/{label}_height.f32")
        holes.tofile(self.output/f"terrain/{label}_holes.u8")
        terrain = {"name":tree["m_Name"],"resolution":n,"scale":scale.tolist(),"transform":transform_record(matrix),"heights":f"terrain/{label}_height.f32","holes":f"terrain/{label}_holes.u8","alpha":alpha,"layers":layers,"chunks":[]}
        grad_z, grad_x = np.gradient(heights,scale[2],scale[0])
        normals = np.stack((-grad_x,np.ones_like(heights),-grad_z),axis=-1)
        normals /= np.linalg.norm(normals,axis=-1,keepdims=True)
        for z in range(0,n-1,32):
            for x in range(0,n-1,32):
                width, depth = min(32,n-1-x),min(32,n-1-z)
                zz,xx = np.mgrid[z:z+depth+1,x:x+width+1]
                vertices = np.stack((xx*scale[0],heights[zz,xx],zz*scale[2]),axis=-1).reshape(-1,3)
                uv = np.stack((xx/(n-1),zz/(n-1)),axis=-1).reshape(-1,2)
                indices = []
                for dz in range(depth):
                    for dx in range(width):
                        if not holes[z+dz,x+dx]: continue
                        a=dz*(width+1)+dx; b=a+1; c=a+width+1; d=c+1
                        indices.extend(((a,c,b),(b,c,d)))
                if not indices: continue
                key=f"terrain_{label}_{x}_{z}"
                self.write_mesh(key,vertices,normals[zz,xx].reshape(-1,3),uv,[indices])
                terrain["chunks"].append(key)
        trees = []; tree_colliders=[]
        detail = tree["m_DetailDatabase"]
        prototypes = detail["m_TreePrototypes"]
        # Cache each prototype once; then multiply its renderer transforms per instance.
        templates=[]; collider_templates=[]
        for prototype in prototypes:
            prototype_colliders=[]
            templates.append(self.prefab(ptr(prototype["prefab"]),np.eye(4),colliders=prototype_colliders))
            collider_templates.append(prototype_colliders)
        for instance in detail["m_TreeInstances"]:
            position=vec(instance["position"])*np.array([(n-1)*scale[0],scale[1],(n-1)*scale[2]])
            angle=instance["rotation"]; rotation={"x":0,"y":float(np.sin(angle/2)),"z":0,"w":float(np.cos(angle/2))}
            scale_tree={"x":instance["widthScale"],"y":instance["heightScale"],"z":instance["widthScale"]}
            tm=matrix @ trs(dict(zip("xyz",position)),rotation,scale_tree)
            rgba=instance["color"]["rgba"]
            color=[((rgba>>(8*k))&255)/255 for k in range(4)]
            for template in templates[instance["index"]]:
                local=np.eye(4); local[:3,:]=np.asarray(template["transform"]).reshape(4,3).T
                unity_local=REFLECT @ local @ REFLECT
                item=template.copy(); item["transform"]=transform_record(tm@unity_local); item["color"]=color
                trees.append(item)
            for template in collider_templates[instance["index"]]:
                local=np.eye(4); local[:3,:]=np.asarray(template["transform"]).reshape(4,3).T
                item=template.copy(); item["transform"]=transform_record(tm@REFLECT@local@REFLECT)
                tree_colliders.append(item)
        terrain["source_tree_instances"]=len(detail["m_TreeInstances"])
        terrain["detail_patch_count"]=len(detail["m_Patches"])
        terrain["nonempty_detail_patches"]=sum(bool(p["coverage"]) for p in detail["m_Patches"])
        terrain["tree_collision_instances"]=len(tree_colliders)
        # Serialized density tiles retain both prototype indices and cell coverage.
        # Unity scatters these at runtime; use a stable seed rather than dropping them.
        samples=int(detail["m_PatchSamples"]); patches=int(detail["m_PatchCount"])
        cell_size=np.array([(n-1)*scale[0],(n-1)*scale[2]])/(samples*patches)
        detail_templates=[self.prefab(ptr(p["prototype"]),np.eye(4)) for p in detail["m_DetailPrototypes"]]
        grass_count=0
        for patch_index,patch in enumerate(detail["m_Patches"]):
            if not patch["coverage"]:continue
            coverage=np.asarray(patch["coverage"],dtype=np.uint8).reshape(len(patch["layerIndices"]),samples,samples)
            for layer_index,prototype_index in enumerate(patch["layerIndices"]):
                prototype=detail["m_DetailPrototypes"][prototype_index]
                rng=np.random.default_rng(int(prototype["noiseSeed"])+patch_index)
                for dz,dx in np.argwhere(coverage[layer_index]>0):
                    for _ in range(int(coverage[layer_index,dz,dx])):
                        xz=(np.array([patch_index%patches*samples+dx,patch_index//patches*samples+dz])+rng.random(2))*cell_size
                        hx,hz=xz[0]/scale[0],xz[1]/scale[2]
                        ix,iz=int(hx),int(hz);fx,fz=hx-ix,hz-iz
                        y=(heights[iz,ix]*(1-fx)+heights[iz,ix+1]*fx)*(1-fz)+(heights[iz+1,ix]*(1-fx)+heights[iz+1,ix+1]*fx)*fz
                        angle=rng.uniform(0,np.pi*2)
                        rotation={"x":0,"y":float(np.sin(angle/2)),"z":0,"w":float(np.cos(angle/2))}
                        width=rng.uniform(prototype["minWidth"],prototype["maxWidth"])
                        height=rng.uniform(prototype["minHeight"],prototype["maxHeight"])
                        gm=matrix@trs({"x":xz[0],"y":float(y),"z":xz[1]},rotation,{"x":width,"y":height,"z":width})
                        for template in detail_templates[prototype_index]:
                            local=np.eye(4);local[:3,:]=np.asarray(template["transform"]).reshape(4,3).T
                            item=template.copy();item["transform"]=transform_record(gm@REFLECT@local@REFLECT)
                            item.pop("lod",None);item["source"]="terrain_detail"
                            trees.append(item)
                        grass_count+=1
        terrain["detail_instances"]=grass_count
        return terrain,trees,tree_colliders

    def scene(self, label, index):
        scene=Scene(self.data_dir,index,self.generator)
        self.used_files.add(f"level{index}")
        filters={}
        renderers=[]; colliders=[]; entities=[]; lights=[]; terrain=None; errors=[]
        runtime_triggers=set()
        doors={};door_parts={};door_blockers={}
        for obj in scene.objects:
            script,go_id=scene.scripts.get(obj.path_id,("",0))
            if script=="OnTriggerEnterEvent":
                runtime_triggers.update(p.component.m_PathID for p in scene.go[go_id].m_Component if p.component.deref().type.name.endswith("Collider"))
            elif script=="CutScene":
                trigger=obj.read_typetree().get("trigger",{})
                if trigger.get("m_FileID",0)==0: runtime_triggers.add(trigger.get("m_PathID",0))
            elif script=="Door" and scene.enabled(go_id):
                spec=obj.read_typetree();door_key=str(obj.path_id)
                doors[door_key]=({p["target"]["m_PathID"]:p for p in spec["openTransforms"]},{})
                for part in spec["doorParts"]:door_parts[part["m_PathID"]]=door_key
                door_blockers[spec["doorCollider"]["m_PathID"]]=door_key
        for obj in scene.objects:
            if obj.type.name=="MeshFilter":
                data=obj.parse_as_object(); filters[data.m_GameObject.m_PathID]=data
        for obj in scene.objects:
            kind=obj.type.name
            if kind not in ("MeshRenderer","BoxCollider","SphereCollider","CapsuleCollider","MeshCollider","Terrain","MonoBehaviour","Light","SkinnedMeshRenderer","ParticleSystem"):continue
            script_kind=""
            try:
                if kind=="MonoBehaviour":
                    script_kind,go_id=scene.scripts[obj.path_id]
                    if script_kind not in ("InteractableLootbox","MultiSceneTeleporter","SimpleTeleporter","InteractableSceneLoader","SceneLocationsProvider","RandomCharacterSpawner","Door","TeleportBeacon","DecalProjector","SimplePointOfInterest","LootBoxLoader","SodaPointLight"):continue
                    data=obj.read_typetree()
                    if not data.get("m_Enabled",True) or not scene.enabled(go_id):continue
                else:
                    data=obj.parse_as_object()
                    go_id=data.m_GameObject.m_PathID
                    if not scene.enabled(go_id) or not getattr(data,"m_Enabled",True):continue
                record={"id":obj.path_id,"name":scene.go[go_id].m_Name,"transform":transform_record(scene.matrix(go_id))}
                if kind in ("MeshRenderer","BoxCollider","SphereCollider","CapsuleCollider","MeshCollider"):
                    transform_id=scene.go_transform[go_id]
                    door_key=""
                    while transform_id:
                        if transform_id in door_parts:
                            door_key=door_parts[transform_id];break
                        transform_id=scene.transforms[transform_id].m_Father.m_PathID
                    if door_key:
                        overrides,cache=doors[door_key]
                        record.update(door_id=door_key,open_transform=transform_record(scene.matrix_override(go_id,overrides,cache)))
                    elif obj.path_id in door_blockers:
                        record.update(door_id=door_blockers[obj.path_id],closed_only=True,open_transform=record["transform"])
                if kind=="SkinnedMeshRenderer":
                    record.update(mesh=self.skinned_mesh(scene,data),materials=[self.material(p) for p in data.m_Materials],transform=transform_record(np.eye(4)),source="baked_source_pose")
                    renderers.append(record)
                elif kind=="MeshRenderer":
                    mesh_filter=filters.get(go_id)
                    if not mesh_filter or not mesh_filter.m_Mesh:continue
                    record.update(mesh=self.mesh(mesh_filter.m_Mesh),materials=[self.material(p) for p in data.m_Materials])
                    roles={self.materials[k].get("role","surface") for k in record["materials"] if k}
                    record["role"] = next(iter(roles)) if len(roles)==1 else "surface"
                    record["shadow_mode"] = int(data.m_CastShadows)
                    renderers.append(record)
                elif kind.endswith("Collider"):
                    tree=obj.read_typetree()
                    layer=int(scene.go[go_id].m_Layer)
                    record.update(type=kind,trigger=bool(data.m_IsTrigger) or obj.path_id in runtime_triggers,layer=layer,blocks_character=bool(self.collision_matrix[9]&(1<<layer)),blocks_projectile=bool(self.collision_matrix[17]&(1<<layer)))
                    for key in ("m_Center","m_Size","m_Radius","m_Height","m_Direction","m_Convex"):
                        if key in tree:record[key[2:].lower()]=tree[key]
                    if kind=="MeshCollider":record["mesh"]=self.mesh(data.m_Mesh)
                    colliders.append(record)
                elif kind=="Terrain":
                    terrain,trees,tree_colliders=self.terrain(scene,obj,label); renderers.extend(trees); colliders.extend(tree_colliders)
                elif kind=="MonoBehaviour":
                    if script_kind=="SodaPointLight":
                        matrix=scene.matrix(go_id)
                        color=data["lightColor"]
                        record.update(type="point",color=[color[k] for k in "rgb"],range=float(np.linalg.norm(matrix[:3,:3],axis=0).max()),attenuation=float(data["fallOff"]),environment_tint=bool(data["enviromentTint"]))
                        lights.append(record)
                    else:
                        record.update(type=script_kind,data={k:v for k,v in data.items() if k not in ("m_GameObject","m_Enabled","m_Script","m_Name")})
                        if script_kind=="DecalProjector" and data.get("m_Material",{}).get("m_PathID",0):
                            record["material"]=self.material(scene.pointer(data["m_Material"]))
                        if script_kind=="SimpleTeleporter" and data.get("target",{}).get("m_PathID",0):
                            target=scene.pointer(data["target"]).deref().parse_as_object()
                            record["target_position"]=transform_record(scene.matrix(target.m_GameObject.m_PathID))[9:]
                        entities.append(record)
                elif kind=="Light":
                    color=data.m_Color
                    record.update(type={0:"spot",1:"directional",2:"point"}.get(data.m_Type,"area"),color=[getattr(color,k)*float(data.m_Intensity) for k in "rgb"],range=float(data.m_Range),spot_angle=float(data.m_SpotAngle))
                    lights.append(record)
                elif kind=="ParticleSystem":
                    self.not_converted[kind]+=1
            except Exception as exc:
                errors.append({"id":obj.path_id,"type":script_kind or kind,"error":str(exc)})
        report={"scene":label,"source_scene_index":index,"renderers":renderers,"colliders":colliders,"terrain":terrain,"entities":entities,"lights":lights,"errors":errors,"source_types":dict(Counter(o.type.name for o in scene.objects))}
        (self.output/f"{label}.json").write_text(json.dumps(report,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        print(f"{label}: {len(renderers)} renderers, {len(colliders)} colliders, {len(entities)} entities, {len(errors)} errors",flush=True)
        if errors: print(json.dumps(errors[:8],ensure_ascii=False),flush=True)
        return {"renderers":len(renderers),"colliders":len(colliders),"entities":len(entities),"errors":len(errors),"source_types":report["source_types"]}

    def run(self):
        started=time.monotonic()
        reports={label:self.scene(label,index) for label,index in SCENES.items()}
        main=Scene(self.data_dir,13,self.generator)
        core=next(obj for obj in main.objects if main.scripts.get(obj.path_id,(None,))[0]=="MultiSceneCore")
        source_core=core.read_typetree()
        (self.output/"locations.json").write_text(json.dumps({"sub_scenes":source_core["subScenes"]},ensure_ascii=False,indent=2),encoding="utf-8")
        (self.output/"library.json").write_text(json.dumps({"meshes":self.meshes,"materials":self.materials,"textures":self.textures},ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        self.used_files.update(("globalgamemanagers","level13"))
        source={}
        for name in sorted(self.used_files):
            path=self.data_dir/name
            if path.is_file(): source[name]={"bytes":path.stat().st_size,"sha256":sha(path)}
            stream=self.data_dir/(name+".resS")
            if stream.is_file():source[stream.name]={"bytes":stream.stat().st_size,"sha256":sha(stream)}
        manifest={"schema":1,"unity":"2022.3.62f2","game_directory":str(self.game_dir),"coordinate_conversion":"Unity (x,y,z) -> Godot (x,y,-z), metres; original world positions retained","tools":{p:importlib.metadata.version(p) for p in ("UnityPy","TypeTreeGeneratorAPI","numpy")},"source_files":source,"scenes":reports,"meshes":len(self.meshes),"materials":len(self.materials),"textures":len(self.textures),"unsupported_dynamic_components":dict(self.not_converted),"seconds":round(time.monotonic()-started,2)}
        (self.output/"extraction_manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        paths={item["path"] for item in self.meshes.values()}|{item["path"] for item in self.textures.values()}
        paths.update(("surface.json","cave.json","locations.json","library.json","extraction_manifest.json"))
        paths.update(f"terrain/{zone}_{name}" for zone in SCENES for name in ("height.f32","holes.u8"))
        files={name:{"bytes":(self.output/name).stat().st_size,"sha256":sha(self.output/name)} for name in sorted(paths)}
        revision=hashlib.sha256(json.dumps({k:v["sha256"] for k,v in files.items() if k!="extraction_manifest.json"},sort_keys=True).encode()).hexdigest()
        (self.output/"asset_manifest.json").write_text(json.dumps({"schema":1,"revision":revision,"files":files},indent=2),encoding="utf-8")
        print(json.dumps({k:v for k,v in manifest.items() if k not in ("source_files","game_directory")},ensure_ascii=False),flush=True)
        return 1 if any(report["errors"] for report in reports.values()) else 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir",type=Path,default=Path(r"E:\SteamLibrary\steamapps\common\Escape from Duckov"))
    parser.add_argument("--output",type=Path,default=ROOT/"assets/worlds/ground_zero")
    args=parser.parse_args()
    return Exporter(args.game_dir.resolve(),args.output.resolve()).run()


if __name__=="__main__":raise SystemExit(main())
