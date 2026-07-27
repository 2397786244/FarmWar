import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
TOOL_DIR = os.path.join(PROJECT_ROOT, "assets", "tools")
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "bug_cannon_aa_preview.png")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def import_asset(filename, location, rotation_z=0.0, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(TOOL_DIR, filename))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    roots = [obj for obj in imported if obj.parent is None]
    for root in roots:
        root.location = location
        root.rotation_euler.z = rotation_z
        root.scale = (scale, scale, scale)
    return imported


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = parse_args()
output_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(output_path), exist_ok=True)
clear_scene()

bug_objects = import_asset(
    "FTF_Tool_Bug_Cannon_GreenPurple.glb",
    (-1.65, -0.25, 1.20),
    rotation_z=math.radians(-18),
    scale=1.25,
)
vehicle_objects = import_asset(
    "FTF_Vehicle_Anti_Air_2m.glb",
    (1.40, 0.10, 0.08),
    rotation_z=math.radians(-18),
)

# Pedestal for the handheld cannon.
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-1.65, -0.15, 0.40))
pedestal = bpy.context.object
pedestal.dimensions = (1.45, 1.10, 0.80)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
pedestal_material = bpy.data.materials.new("MAT_Pedestal")
pedestal_material.diffuse_color = (0.12, 0.16, 0.18, 1.0)
pedestal.data.materials.append(pedestal_material)

# Exactly 2x2m footprint plate beneath the vehicle.
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(1.40, 0.10, 0.035))
footprint = bpy.context.object
footprint.dimensions = (2.0, 2.0, 0.07)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
footprint.rotation_euler.z = math.radians(-18)
footprint_material = bpy.data.materials.new("MAT_Footprint")
footprint_material.diffuse_color = (0.08, 0.24, 0.28, 1.0)
footprint.data.materials.append(footprint_material)

bpy.ops.mesh.primitive_plane_add(size=25.0, location=(0.0, 0.0, -0.02))
ground = bpy.context.object
ground_material = bpy.data.materials.new("MAT_Ground")
ground_material.diffuse_color = (0.07, 0.10, 0.12, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-4.5, -5.5, 7.0))
key = bpy.context.object
key.data.energy = 1250
key.data.size = 5.0
point_at(key, (0.0, 0.0, 0.9))

bpy.ops.object.light_add(type="AREA", location=(5.0, -1.5, 4.5))
fill = bpy.context.object
fill.data.energy = 850
fill.data.size = 4.0
fill.data.color = (0.35, 0.62, 1.0)
point_at(fill, (0.0, 0.0, 0.9))

bpy.ops.object.light_add(type="AREA", location=(0.0, 5.0, 5.5))
rim = bpy.context.object
rim.data.energy = 950
rim.data.size = 3.5
rim.data.color = (1.0, 0.58, 0.26)
point_at(rim, (0.0, 0.0, 1.0))

bpy.ops.object.camera_add(location=(6.8, -10.5, 5.3))
camera = bpy.context.object
camera.data.lens = 60
point_at(camera, (0.0, 0.0, 0.85))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 760
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.03, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
