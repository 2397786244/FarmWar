"""Render a transparent Zombie Female walk icon and Farmer with SproutBlaster.

Run with Blender 4.4:
  blender --background --python tools/render_zombie_female_farmer_icons.py -- [options]
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

from render_farmer_dual_weapon_icon import (  # noqa: E402
    add_arm_ik,
    add_lights,
    find_armature,
    hide_collision_meshes,
    import_glb,
    imported_bounds,
    make_transform_root,
    setup_white_render,
)
from render_item_icons import clear_scene, point_at  # noqa: E402


DEFAULT_SIZE = 1024
DEFAULT_EXPOSURE = -1.3


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(
        description="Render transparent Zombie Female and Farmer showcase icons."
    )
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--zombie-female-output",
        default="assets/icons/app_icon_sources/zombie_female_walk_orthographic.png",
    )
    parser.add_argument(
        "--farmer-output",
        default="assets/icons/app_icon_sources/farmer_sprout_blaster_orthographic.png",
    )
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--samples", type=int, default=96)
    parser.add_argument("--exposure", type=float, default=DEFAULT_EXPOSURE)
    parser.add_argument(
        "--only",
        choices=("all", "zombie", "farmer"),
        default="all",
    )
    return parser.parse_args(argv)


def hide_import_extras(objects):
    for obj in objects:
        if obj.type in {"CAMERA", "LIGHT"} or obj.name in {"Cube", "棱角球"}:
            obj.hide_render = True
            obj.hide_set(True)


def set_neutral_face(objects):
    """Keep imported facial morph defaults from stacking expressions."""
    for obj in objects:
        if obj.type == "MESH" and obj.data.shape_keys is not None:
            for block in obj.data.shape_keys.key_blocks:
                block.value = 1.0 if block.name == "Calm" else 0.0
        if obj.name == "FunnyTongue":
            obj.hide_render = True
            obj.hide_set(True)


def apply_action(armature, action_name):
    action = next(
        (candidate for candidate in bpy.data.actions if candidate.name == action_name),
        None,
    )
    if action is None:
        raise RuntimeError(f"Model does not contain the {action_name} action")
    armature.animation_data_create()
    armature.animation_data.action = action
    start, end = action.frame_range
    bpy.context.scene.frame_set(int(round((start + end) * 0.5)))


def setup_showcase_camera(bounds, name):
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    scene_size = max(dimensions.length * 0.9, dimensions.z * 1.16, 1.0)
    distance = max(dimensions.length * 6.0, 6.0)
    direction = Vector((3.3, 6.2, 1.45)).normalized()

    camera_data = bpy.data.cameras.new(name)
    camera = bpy.data.objects.new(name, camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scene_size
    camera.location = center + direction * distance
    point_at(camera, center)
    bpy.context.scene.camera = camera
    return center, scene_size


def configure_render(output_path, size, samples, exposure):
    setup_white_render(output_path, size, samples, transparent=True)
    bpy.context.scene.view_settings.exposure = exposure


def player_right_hand_target():
    # player.gd Head=(0, 1.7080579, -0.45418245) and
    # RightHandIKTarget=(0.28, -0.28, -0.42), converted from Godot to Blender.
    head = Vector((0.0, 0.45418245, 1.7080579))
    return head + Vector((0.28, 0.42, -0.28))


def player_right_elbow_pole():
    return Vector((0.65, 0.1, 1.2))


def render_zombie_female(project, output_path, size, samples, exposure):
    clear_scene()
    objects = import_glb(project / "assets/characters/ZombieFemale.glb")
    hide_collision_meshes(objects)
    hide_import_extras(objects)
    set_neutral_face(objects)

    root = make_transform_root("ZombieFemalePresentationRoot", objects)
    root.rotation_euler.z = math.radians(180.0)
    armature = find_armature(objects)
    apply_action(armature, "Walk")
    bpy.context.view_layer.update()

    bounds = imported_bounds(
        [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"} and obj.visible_get()]
    )
    target, scene_size = setup_showcase_camera(bounds, "ZombieFemaleWalkCamera")
    add_lights(target, scene_size)
    configure_render(output_path, size, samples, exposure)
    bpy.ops.render.render(write_still=True)
    print(
        f"[ZombieFemaleWalk] Saved: {output_path}; "
        f"ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def render_farmer(project, output_path, size, samples, exposure):
    clear_scene()
    farmer_objects = import_glb(project / "assets/characters/Farmer_Red.glb")
    hide_collision_meshes(farmer_objects)
    hide_import_extras(farmer_objects)
    set_neutral_face(farmer_objects)

    root = make_transform_root("FarmerSproutBlasterPresentationRoot", farmer_objects)
    root.rotation_euler.z = math.radians(180.0)
    armature = find_armature(farmer_objects)
    apply_action(armature, "IdleTool")
    bpy.context.view_layer.update()

    right_target = player_right_hand_target()
    add_arm_ik(armature, "R", right_target, player_right_elbow_pole())
    bpy.context.view_layer.update()

    weapon_objects = import_glb(project / "assets/tools/SproutBlaster.glb")
    hide_collision_meshes(weapon_objects)
    hide_import_extras(weapon_objects)
    weapon_root = make_transform_root("FarmerSproutBlaster", weapon_objects)
    weapon_root.location = right_target + Vector((0.0, -0.08, -0.02))
    weapon_root.scale = Vector((0.52, 0.52, 0.52))
    weapon_root.rotation_euler = (0.0, 0.0, math.radians(180.0))
    bpy.context.view_layer.update()

    bounds = imported_bounds(
        [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"} and obj.visible_get()]
    )
    target, scene_size = setup_showcase_camera(bounds, "FarmerSproutBlasterCamera")
    add_lights(target, scene_size)
    configure_render(output_path, size, samples, exposure)
    bpy.ops.render.render(write_still=True)
    print(
        f"[FarmerSproutBlaster] Saved: {output_path}; "
        f"ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    if args.only in {"all", "zombie"}:
        render_zombie_female(
            project,
            (project / args.zombie_female_output).resolve(),
            args.size,
            args.samples,
            args.exposure,
        )
    if args.only in {"all", "farmer"}:
        render_farmer(
            project,
            (project / args.farmer_output).resolve(),
            args.size,
            args.samples,
            args.exposure,
        )


if __name__ == "__main__":
    main()
