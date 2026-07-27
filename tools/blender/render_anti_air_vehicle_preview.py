import argparse
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
    "FTF_Vehicle_Anti_Air_2m.glb",
)
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "anti_air_vehicle_preview.png")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def point_at(obj, target):
    obj.rotation_euler = (
        Vector(target) - obj.location
    ).to_track_quat("-Z", "Y").to_euler()


def add_area(name, location, energy, color, size):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.color = color
    light.data.shape = "DISK"
    light.data.size = size
    point_at(light, (0.0, 0.0, 0.72))


args = parse_args()
output_path = os.path.abspath(args.output)
os.makedirs(os.path.dirname(output_path), exist_ok=True)

clear_scene()
bpy.ops.import_scene.gltf(filepath=MODEL_PATH)

bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0.0, 0.0, -0.015))
ground = bpy.context.object
ground.name = "PreviewGround"
ground_mat = bpy.data.materials.new("PreviewGroundMaterial")
ground_mat.diffuse_color = (0.035, 0.05, 0.06, 1.0)
ground_mat.use_nodes = True
ground_bsdf = ground_mat.node_tree.nodes.get("Principled BSDF")
ground_bsdf.inputs["Base Color"].default_value = (0.035, 0.05, 0.06, 1.0)
ground_bsdf.inputs["Roughness"].default_value = 0.9
ground.data.materials.append(ground_mat)

bpy.ops.object.camera_add(location=(4.5, -6.8, 3.6))
camera = bpy.context.object
camera.name = "PreviewCamera"
camera.data.lens = 62
point_at(camera, (0.0, 0.0, 0.70))
bpy.context.scene.camera = camera

add_area("KeyLight", (4.0, -4.2, 6.0), 760, (1.0, 0.78, 0.58), 4.0)
add_area("FillLight", (-4.0, -2.0, 3.5), 480, (0.38, 0.66, 1.0), 3.5)
add_area("RimLight", (-2.0, 4.0, 4.5), 620, (0.42, 0.92, 1.0), 3.0)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1200
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = output_path
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = -0.7

world = bpy.data.worlds.new("PreviewWorld") if scene.world is None else scene.world
scene.world = world
world.use_nodes = True
background = world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.012, 0.018, 0.026, 1.0)
background.inputs["Strength"].default_value = 0.30

bpy.ops.render.render(write_still=True)
print("PREVIEW", output_path)
