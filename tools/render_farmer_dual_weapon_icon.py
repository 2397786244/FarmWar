"""Render a waist-up Farmer holding SproutBlaster and M4 on white.

Run with Blender 4.4:
  blender --background --python tools/render_farmer_dual_weapon_icon.py -- [options]
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from render_item_icons import clear_scene, imported_bounds, point_at


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render the Farmer dual-weapon icon.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--output",
        default="assets/icons/app_icon_sources/farmer_dual_weapon_white.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--samples", type=int, default=96)
    return parser.parse_args(argv)


def import_glb(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def hide_collision_meshes(objects):
    for obj in objects:
        name = obj.name.upper()
        if name.startswith("UCX_") or "MESH_UCX_" in name:
            obj.hide_render = True
            obj.hide_set(True)


def find_armature(objects):
    for obj in objects:
        if obj.type == "ARMATURE":
            return obj
    raise RuntimeError("Farmer GLB contains no armature")


def apply_hold_pose(armature):
    preferred = ("RifleHoldTwoHand", "ShootOneHand")
    action = None
    for preferred_name in preferred:
        action = next(
            (candidate for candidate in bpy.data.actions if preferred_name in candidate.name),
            None,
        )
        if action is not None:
            break
    if action is None:
        return
    armature.animation_data_create()
    armature.animation_data.action = action
    start, end = action.frame_range
    bpy.context.scene.frame_set(int(round((start + end) * 0.5)))


def bone_world_position(armature, bone_name):
    bone = armature.pose.bones.get(bone_name)
    if bone is None:
        raise RuntimeError(f"Missing Farmer pose bone: {bone_name}")
    return armature.matrix_world @ bone.head


def add_arm_ik(armature, side, target_position, pole_position):
    hand = armature.pose.bones.get(f"Hand.{side}")
    if hand is None:
        raise RuntimeError(f"Missing Farmer hand bone: Hand.{side}")

    target = bpy.data.objects.new(f"HandTarget.{side}", None)
    target.location = target_position
    bpy.context.scene.collection.objects.link(target)

    pole = bpy.data.objects.new(f"ElbowPole.{side}", None)
    pole.location = pole_position
    bpy.context.scene.collection.objects.link(pole)

    constraint = hand.constraints.new("IK")
    constraint.target = target
    constraint.pole_target = pole
    constraint.chain_count = 3
    constraint.use_rotation = False
    constraint.pole_angle = math.radians(-90.0 if side == "R" else 90.0)
    return target


def make_transform_root(name, objects):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    imported_set = set(objects)
    for obj in objects:
        if obj.parent not in imported_set:
            obj.parent = root
    return root


def place_weapon(project, relative_path, name, position, scale, yaw_degrees=180.0):
    objects = import_glb(project / relative_path)
    hide_collision_meshes(objects)
    root = make_transform_root(name, objects)
    root.location = position
    root.scale = Vector((scale, scale, scale))
    root.rotation_euler = (0.0, 0.0, math.radians(yaw_degrees))
    print(f"[FarmerDualWeaponIcon] {name} root={tuple(round(value, 4) for value in position)}")
    print(f"[FarmerDualWeaponIcon] {name} bounds={imported_bounds(objects)}")
    return root


def setup_white_render(output_path, size, samples, transparent=False):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.filepath = str(output_path)
    scene.render.use_file_extension = True
    scene.render.image_settings.compression = 30
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.0
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = samples


def add_lights(target, character_height):
    lights = (
        ("Key", 500.0, 4.0, target + Vector((-3.2, -4.5, 4.2)) * character_height * 0.45),
        ("Fill", 220.0, 3.0, target + Vector((3.5, -2.0, 2.2)) * character_height * 0.45),
        ("Rim", 320.0, 2.5, target + Vector((1.0, 3.0, 3.6)) * character_height * 0.45),
    )
    for name, energy, size, position in lights:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        light.location = position
        point_at(light, target)
        bpy.context.scene.collection.objects.link(light)


def setup_camera(bounds):
    minimum, maximum = bounds
    height = maximum.z - minimum.z
    target = Vector((0.0, 0.0, minimum.z + height * 0.69))

    data = bpy.data.cameras.new("FarmerIconCamera")
    camera = bpy.data.objects.new("FarmerIconCamera", data)
    bpy.context.scene.collection.objects.link(camera)
    data.type = "ORTHO"
    data.ortho_scale = height * 0.72
    camera.location = target + Vector((3.3, -6.2, 1.45)).normalized() * height * 4.0
    point_at(camera, target)
    bpy.context.scene.camera = camera
    return target, height


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_path = (project / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    clear_scene()
    farmer_objects = import_glb(project / "assets/characters/Farmer_Red.glb")
    hide_collision_meshes(farmer_objects)
    armature = find_armature(farmer_objects)
    apply_hold_pose(armature)
    bpy.context.view_layer.update()

    farmer_bounds = imported_bounds(farmer_objects)
    minimum, maximum = farmer_bounds
    height = maximum.z - minimum.z
    forward = Vector((0.0, -1.0, 0.0))

    right_hand = bone_world_position(armature, "Hand.R")
    left_hand = bone_world_position(armature, "Hand.L")
    right_side = (right_hand - left_hand).normalized()
    chest_z = minimum.z + height * 0.66
    chest = Vector((0.0, 0.0, chest_z))

    right_target_position = chest + right_side * height * 0.24 + forward * height * 0.28
    left_target_position = chest - right_side * height * 0.24 + forward * height * 0.28
    right_pole = chest + right_side * height * 0.42 + forward * height * 0.06 - Vector((0.0, 0.0, height * 0.08))
    left_pole = chest - right_side * height * 0.42 + forward * height * 0.06 - Vector((0.0, 0.0, height * 0.08))

    add_arm_ik(armature, "R", right_target_position, right_pole)
    add_arm_ik(armature, "L", left_target_position, left_pole)
    bpy.context.view_layer.update()

    place_weapon(
        project,
        "assets/tools/SproutBlaster.glb",
        "RightHandSproutBlaster",
        right_target_position + Vector((0.0, -height * 0.06, -height * 0.015)),
        0.52,
    )
    place_weapon(
        project,
        "assets/tools/M4.glb",
        "LeftHandM4",
        left_target_position + Vector((0.0, -height * 0.04, -height * 0.015)),
        0.78,
    )

    scene_bounds = imported_bounds(
        [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"}]
    )
    target, character_height = setup_camera(farmer_bounds)
    add_lights(target, character_height)
    setup_white_render(output_path, args.size, args.samples)
    bpy.ops.render.render(write_still=True)
    print(f"[FarmerDualWeaponIcon] Saved: {output_path}; scene_bounds={scene_bounds}")


if __name__ == "__main__":
    main()
