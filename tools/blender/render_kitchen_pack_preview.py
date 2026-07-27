import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
KITCHEN_DIR = os.path.join(PROJECT_ROOT, "assets", "kitchen")
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "kitchen_pack_preview.png")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def import_asset(filename, location, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(KITCHEN_DIR, filename))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    roots = [obj for obj in imported if obj.parent is None]
    for root in roots:
        root.location = Vector(location)
        root.scale = (scale, scale, scale)
    return imported


def point_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


args = parse_args()
output_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(output_path), exist_ok=True)
clear_scene()

# Back row: cleaned legacy stations and freezer.
import_asset("FTF_Kitchen_Chopping_Station_Blue.glb", (-3.25, 1.25, 0.0))
import_asset("FTF_Kitchen_Oven_Red.glb", (-1.80, 1.25, 0.0))
import_asset("FTF_Kitchen_Double_Door_Freezer_Blue.glb", (2.90, 1.65, 0.0))

# Front row: the two new station types in both team colors.
import_asset("FTF_Kitchen_Induction_Counter_Red.glb", (-3.00, -0.75, 0.0))
import_asset("FTF_Kitchen_Sink_Red.glb", (-1.45, -0.75, 0.0))
import_asset("FTF_Kitchen_Induction_Counter_Blue.glb", (0.15, -0.75, 0.0))
import_asset("FTF_Kitchen_Sink_Blue.glb", (1.70, -0.75, 0.0))

# Existing pots demonstrate the intended placement height.
import_asset("FTF_Kitchen_Pot_Red.glb", (-3.00, -0.765, 1.02))
import_asset("FTF_Kitchen_Pot_Blue.glb", (0.15, -0.765, 1.02))

# Enlarged preview copy of the cleaver on a small display block.
import_asset("FTF_Kitchen_Cleaver.glb", (3.55, -0.65, 0.32), scale=1.55)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(3.55, -0.63, 0.18))
pedestal = bpy.context.object
pedestal.name = "CleaverPreviewPedestal"
pedestal.dimensions = (1.30, 0.70, 0.36)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
pedestal_material = bpy.data.materials.new("MAT_PreviewPedestal")
pedestal_material.diffuse_color = (0.14, 0.18, 0.20, 1.0)
pedestal.data.materials.append(pedestal_material)

bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0.0, 0.0, -0.02))
ground = bpy.context.object
ground_material = bpy.data.materials.new("MAT_PreviewGround")
ground_material.diffuse_color = (0.08, 0.11, 0.13, 1.0)
ground.data.materials.append(ground_material)

bpy.ops.object.light_add(type="AREA", location=(-5.0, -6.0, 7.5))
key = bpy.context.object
key.data.energy = 1250
key.data.size = 5.5
point_at(key, (0.0, 0.0, 0.9))

bpy.ops.object.light_add(type="AREA", location=(5.0, -2.0, 5.0))
fill = bpy.context.object
fill.data.energy = 850
fill.data.size = 4.5
fill.data.color = (0.38, 0.62, 1.0)
point_at(fill, (0.0, 0.0, 0.9))

bpy.ops.object.light_add(type="AREA", location=(0.0, 5.0, 6.0))
rim = bpy.context.object
rim.data.energy = 950
rim.data.size = 4.0
rim.data.color = (1.0, 0.58, 0.28)
point_at(rim, (0.0, 0.0, 1.0))

bpy.ops.object.camera_add(location=(8.5, -13.5, 7.0))
camera = bpy.context.object
camera.data.lens = 58
point_at(camera, (0.0, 0.0, 0.85))
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1400
scene.render.resolution_y = 850
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.world.color = (0.02, 0.03, 0.045)

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
