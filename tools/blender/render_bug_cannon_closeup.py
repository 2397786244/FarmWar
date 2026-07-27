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
    "FTF_Tool_Bug_Cannon_GreenPurple.glb",
)
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "bug_cannon_closeup.png")


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
    root.location = (0.0, 0.0, 0.55)
    root.rotation_euler = (
        math.radians(-8),
        math.radians(-10),
        math.radians(-22),
    )

bpy.ops.object.light_add(type="AREA", location=(-3.8, -4.5, 5.8))
key = bpy.context.object
key.data.energy = 1050
key.data.size = 4.0
point_at(key, (0.0, 0.0, 0.25))

bpy.ops.object.light_add(type="AREA", location=(4.0, -1.0, 3.5))
fill = bpy.context.object
fill.data.energy = 700
fill.data.size = 3.0
fill.data.color = (0.38, 0.62, 1.0)
point_at(fill, (0.0, 0.0, 0.2))

bpy.ops.object.light_add(type="AREA", location=(0.0, 3.5, 4.0))
rim = bpy.context.object
rim.data.energy = 850
rim.data.size = 2.8
rim.data.color = (0.72, 1.0, 0.42)
point_at(rim, (0.0, 0.0, 0.35))

bpy.ops.object.camera_add(location=(3.7, -5.8, 2.8))
camera = bpy.context.object
camera.data.lens = 66
point_at(camera, (0.0, -0.08, 0.15))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.025, 0.035, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
