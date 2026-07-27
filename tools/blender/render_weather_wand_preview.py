import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
MODEL_PATH = os.path.join(
    PROJECT_ROOT,
    "assets",
    "tools",
    "FTF_Tool_Weather_Wand_PurpleCrystal.glb",
)
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "weather_wand_preview.png")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = parse_args()
output_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(output_path), exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=MODEL_PATH)

roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
for root in roots:
    root.rotation_euler = (
        math.radians(-8),
        math.radians(14),
        math.radians(-18),
    )

bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.0, 0.0, -0.02))
ground = bpy.context.object
ground_material = bpy.data.materials.new("MAT_Ground")
ground_material.diffuse_color = (0.07, 0.09, 0.13, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-3.0, -4.0, 5.0))
key = bpy.context.object
key.data.energy = 1050
key.data.size = 3.5
point_at(key, (0.0, 0.0, 0.75))

bpy.ops.object.light_add(type="AREA", location=(3.5, -1.0, 3.0))
fill = bpy.context.object
fill.data.energy = 700
fill.data.size = 2.8
fill.data.color = (0.55, 0.38, 1.0)
point_at(fill, (0.0, 0.0, 0.95))

bpy.ops.object.light_add(type="AREA", location=(0.0, 3.0, 4.0))
rim = bpy.context.object
rim.data.energy = 800
rim.data.size = 2.5
rim.data.color = (0.30, 0.90, 1.0)
point_at(rim, (0.0, 0.0, 1.0))

bpy.ops.object.camera_add(location=(3.2, -5.5, 2.7))
camera = bpy.context.object
camera.data.lens = 72
point_at(camera, (0.0, 0.0, 0.75))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 850
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.025, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
