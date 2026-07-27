import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
CHARACTER_PATH = os.path.join(
    PROJECT_ROOT,
    "assets",
    "characters",
    "FTF_Character_Farmer_Red.glb",
)
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "character_expressions_preview.png")
EXPRESSIONS = ("Calm", "Fierce", "Funny", "Happy", "Worried")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def apply_expression(objects, expression):
    changed = 0
    for obj in objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        for block in obj.data.shape_keys.key_blocks:
            if block.name == "Basis":
                continue
            block.value = 1.0 if block.name == expression else 0.0
            changed += 1
    if changed == 0:
        raise RuntimeError(f"No blend shapes found for {expression}")


def import_expression(expression, x):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=CHARACTER_PATH)
    imported = [obj for obj in bpy.data.objects if obj not in before]
    roots = [obj for obj in imported if obj.parent is None]
    for root in roots:
        root.location = (x, 0.0, 0.0)
    apply_expression(imported, expression)


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = parse_args()
output_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(output_path), exist_ok=True)
clear_scene()

for expression, x in zip(EXPRESSIONS, (-2.15, -1.08, 0.0, 1.08, 2.15)):
    import_expression(expression, x)

bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.01))
ground = bpy.context.object
ground_material = bpy.data.materials.new("MAT_PreviewGround")
ground_material.diffuse_color = (0.09, 0.12, 0.15, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-3.8, -4.5, 6.2))
key = bpy.context.object
key.data.energy = 1150
key.data.size = 4.5
point_at(key, (0.0, 0.0, 1.5))

bpy.ops.object.light_add(type="AREA", location=(4.5, -2.0, 4.0))
fill = bpy.context.object
fill.data.energy = 750
fill.data.size = 3.5
fill.data.color = (0.38, 0.62, 1.0)
point_at(fill, (0.0, 0.0, 1.5))

bpy.ops.object.camera_add(location=(0.0, -10.2, 2.45))
camera = bpy.context.object
camera.data.lens = 66
point_at(camera, (0.0, 0.0, 1.30))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.03, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
