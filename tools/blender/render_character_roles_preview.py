import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
ASSET_DIR = os.path.join(PROJECT_ROOT, "assets", "characters")
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "character_roles_preview.png")

FILES = [
    "FTF_Character_Farmer_Red.glb",
    "FTF_Character_Farmer_Blue.glb",
    "FTF_Character_Cook_Red.glb",
    "FTF_Character_Cook_Blue.glb",
    "FTF_Character_Guard_Red.glb",
    "FTF_Character_Guard_Blue.glb",
]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def import_at(filename, x):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ASSET_DIR, filename))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    roots = [obj for obj in imported if obj.parent is None]
    for root in roots:
        root.location = (x, 0.0, 0.0)


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = parse_args()
preview_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(preview_path), exist_ok=True)

clear_scene()

positions = (-3.35, -2.05, -0.68, 0.68, 2.05, 3.35)
for filename, x in zip(FILES, positions):
    import_at(filename, x)

bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0.0, 0.0, -0.01))
ground = bpy.context.object
ground.name = "PreviewGround"
ground_material = bpy.data.materials.new("MAT_PreviewGround")
ground_material.diffuse_color = (0.10, 0.14, 0.16, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-4.8, -5.5, 7.2))
key = bpy.context.object
key.data.energy = 1200
key.data.size = 5.5
point_at(key, (0.0, 0.0, 1.1))

bpy.ops.object.light_add(type="AREA", location=(5.0, -2.5, 4.3))
fill = bpy.context.object
fill.data.energy = 850
fill.data.size = 4.0
fill.data.color = (0.40, 0.62, 1.0)
point_at(fill, (0.0, 0.0, 1.1))

bpy.ops.object.light_add(type="AREA", location=(0.0, 4.0, 5.5))
rim = bpy.context.object
rim.data.energy = 1000
rim.data.size = 4.0
rim.data.color = (1.0, 0.60, 0.30)
point_at(rim, (0.0, 0.0, 1.25))

bpy.ops.object.camera_add(location=(0.0, -13.2, 4.1))
camera = bpy.context.object
camera.data.lens = 55
point_at(camera, (0.0, 0.0, 1.1))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = preview_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.03, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", preview_path)
