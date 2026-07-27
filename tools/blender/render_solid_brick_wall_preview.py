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
    "buildings",
    "FTF_Building_Solid_Brick_Wall_2x3m.glb",
)
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "solid_brick_wall_preview.png")


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
    root.location = (-0.75, 0.0, 0.0)
    root.rotation_euler.z = math.radians(-12)

# A second tilted copy exposes the back, side and bottom brick skins.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=MODEL_PATH)
second_import = [obj for obj in bpy.data.objects if obj not in before]
second_roots = [obj for obj in second_import if obj.parent is None]
for root in second_roots:
    root.location = (1.55, 0.40, 1.30)
    root.scale = (0.62, 0.62, 0.62)
    root.rotation_euler = (
        math.radians(68),
        math.radians(-8),
        math.radians(155),
    )

bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, 0.0, -0.02))
ground = bpy.context.object
ground_material = bpy.data.materials.new("MAT_Ground")
ground_material.diffuse_color = (0.08, 0.11, 0.13, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-4.5, -5.0, 7.5))
key = bpy.context.object
key.data.energy = 1250
key.data.size = 5.0
point_at(key, (0.0, 0.0, 1.5))

bpy.ops.object.light_add(type="AREA", location=(4.0, -1.0, 5.0))
fill = bpy.context.object
fill.data.energy = 700
fill.data.size = 3.5
fill.data.color = (0.45, 0.65, 1.0)
point_at(fill, (0.0, 0.0, 1.5))

bpy.ops.object.light_add(type="AREA", location=(0.0, 4.0, 6.0))
rim = bpy.context.object
rim.data.energy = 850
rim.data.size = 3.0
rim.data.color = (1.0, 0.55, 0.28)
point_at(rim, (0.0, 0.0, 1.5))

bpy.ops.object.camera_add(location=(6.8, -10.0, 4.7))
camera = bpy.context.object
camera.data.lens = 65
point_at(camera, (0.20, 0.0, 1.45))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.03, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
