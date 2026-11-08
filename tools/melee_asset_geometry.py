"""Blender helper: put a source weapon's handle at the origin, tip along +Z."""
import numpy as np
from mathutils import Matrix, Vector

LENGTHS={'fire_axe':.90,'crowbar':.80,'baseball_bat':.82,'baton':.58,'machete':.62,'katana':.98}

def normalize(meshes, kind):
    points=np.array([tuple(obj.matrix_world@v.co) for obj in meshes for v in obj.data.vertices])
    center=points.mean(axis=0)
    values, axes=np.linalg.eigh(np.cov(points.T))
    axis=axes[:,-1]
    # All supplied references have the working end in native Godot +Z (Blender -Y).
    if axis[1]>0:axis=-axis
    projection=(points-center)@axis
    low,high=projection.min(),projection.max()
    length=high-low
    near=points[(projection>low+.04*length)&(projection<low+.20*length)].mean(axis=0)
    grip=near+axis*(low+.09*length-(near-center)@axis)
    rotation=Vector(axis).rotation_difference(Vector((0,0,1))).to_matrix().to_4x4()
    factor=LENGTHS[kind]/length
    matrix=rotation@Matrix.Scale(factor,4)@Matrix.Translation(-Vector(grip))
    for obj in meshes:obj.matrix_world=matrix@obj.matrix_world
    return {'grip_source':grip.tolist(),'axis_source':axis.tolist(),'length':LENGTHS[kind]}
