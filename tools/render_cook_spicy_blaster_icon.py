"""Render the Cook character holding the SpicyBlaster.

Run with Blender 4.4:
  blender --background --python tools/render_cook_spicy_blaster_icon.py -- [options]
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
    bone_world_position,
    find_armature,
    hide_collision_meshes,
    import_glb,
    imported_bounds,
    make_transform_root,
    place_weapon,
    setup_white_render,
)
from render_item_icons import clear_scene, point_at  # noqa: E402


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render Cook holding the SpicyBlaster.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--output",
        default="assets/icons/app_icon_sources/cook_spicy_blaster_orthographic.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--samples", type=int, default=96)
    parser.add_argument("--exposure", type=float, default=-1.3)
    return parser.parse_args(argv)


def setup_full_scene_camera(bounds):
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    scene_size = max(dimensions.length * 0.9, dimensions.z * 1.16, 1.0)
    distance = max(dimensions.length * 6.0, 6.0)
    direction = Vector((3.3, 6.2, 1.45)).normalized()

    camera_data = bpy.data.cameras.new("CookSpicyBlasterCamera")
    camera = bpy.data.objects.new("CookSpicyBlasterCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scene_size
    camera.location = center + direction * distance
    point_at(camera, center)
    bpy.context.scene.camera = camera
    return center, scene_size


def hide_import_extras(objects):
    """Exclude the test primitives and default lights bundled in the GLBs."""
    for obj in objects:
        if obj.type in {"CAMERA", "LIGHT"} or obj.name in {"Cube", "棱角球"}:
            obj.hide_render = True
            obj.hide_set(True)


def apply_idle_pose(armature):
    idle = next(
        (action for action in bpy.data.actions if action.name == "Idle"),
        None,
    )
    if idle is None:
        raise RuntimeError("Cook GLB does not contain the Idle action")
    armature.animation_data_create()
    armature.animation_data.action = idle
    start, end = idle.frame_range
    bpy.context.scene.frame_set(int(round((start + end) * 0.5)))


def set_neutral_face(objects):
    """Match the game's neutral state for the standalone render.

    The exported GLB currently stores all five facial morph weights as 1.0.
    Blender honors those defaults when importing the file, which stacks every
    expression and produces an obviously distorted face.  Godot resets these
    values on the MeshInstance3D, so do the same explicitly here.
    """
    for obj in objects:
        if obj.type == "MESH" and obj.data.shape_keys is not None:
            key_blocks = obj.data.shape_keys.key_blocks
            for block in key_blocks:
                if block.name == "Basis":
                    block.value = 0.0
                elif block.name == "Calm":
                    block.value = 1.0
                else:
                    block.value = 0.0
        if obj.name == "FunnyTongue":
            obj.hide_render = True
            obj.hide_set(True)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_path = (project / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    clear_scene()
    cook_objects = import_glb(project / "assets/characters/Cook_Red.glb")
    hide_collision_meshes(cook_objects)
    hide_import_extras(cook_objects)
    set_neutral_face(cook_objects)
    cook_root = make_transform_root("CookPresentationRoot", cook_objects)
    # player.gd rotates the imported appearance by 180 degrees around the
    # Godot Y axis.  The Blender import is Z-up, so the equivalent is a Z turn.
    cook_root.rotation_euler.z = math.radians(180.0)
    armature = find_armature(cook_objects)
    apply_idle_pose(armature)
    bpy.context.view_layer.update()

    # player.tscn uses Head=(0, 1.7080579, -0.45418245) and
    # RightHandIKTarget=(0.28, -0.28, -0.42) in Godot coordinates.
    # Convert Godot (X,Y,Z) to Blender (X,-Z,Y) for the Z-up GLB import.
    player_head_position = Vector((0.0, 0.45418245, 1.7080579))
    right_target_position = player_head_position + Vector((0.28, 0.42, -0.28))
    right_elbow_pole = Vector((0.65, 0.1, 1.2))
    add_arm_ik(armature, "R", right_target_position, right_elbow_pole)
    bpy.context.view_layer.update()

    weapon_objects = import_glb(project / "assets/tools/SpicyBlaster.glb")
    hide_collision_meshes(weapon_objects)
    hide_import_extras(weapon_objects)
    weapon_root = make_transform_root("CookSpicyBlaster", weapon_objects)
    weapon_root.location = right_target_position
    weapon_root.scale = Vector((0.3, 0.3, 0.3))
    # SpicyBlaster's authored muzzle axis is local -Y.  Flip it around the
    # vertical axis so the nozzle follows Cook's Blender-space +Y facing
    # direction instead of pointing backward.
    weapon_root.rotation_euler = (0.0, 0.0, math.radians(180.0))

    bpy.context.view_layer.update()
    scene_objects = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type in {"MESH", "ARMATURE"} and obj.visible_get()
    ]
    scene_bounds = imported_bounds(scene_objects)
    target, scene_size = setup_full_scene_camera(scene_bounds)
    add_lights(target, scene_size)
    setup_white_render(output_path, args.size, args.samples, transparent=True)
    bpy.context.scene.view_settings.exposure = args.exposure
    bpy.ops.render.render(write_still=True)
    print(
        f"[CookSpicyBlaster] Saved: {output_path}; "
        f"ortho_scale={scene_size:.3f}; exposure={args.exposure}"
    )


if __name__ == "__main__":
    main()
