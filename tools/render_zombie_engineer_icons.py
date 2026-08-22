"""Render the Zombie Male walk showcase and FutureEngineer with FutureMPX.

Run with Blender 4.4:
  blender --background --python tools/render_zombie_engineer_icons.py -- [options]
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
    parser = argparse.ArgumentParser(description="Render zombie and engineer showcase icons.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--zombie-output",
        default="assets/icons/app_icon_sources/zombie_male_walk_orthographic.png",
    )
    parser.add_argument(
        "--engineer-output",
        default="assets/icons/app_icon_sources/future_engineer_future_mpx_orthographic.png",
    )
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--samples", type=int, default=96)
    parser.add_argument("--exposure", type=float, default=DEFAULT_EXPOSURE)
    parser.add_argument(
        "--only",
        choices=("all", "zombie", "engineer"),
        default="all",
    )
    return parser.parse_args(argv)


def hide_import_extras(objects):
    """Exclude default Blender test objects bundled inside the GLBs."""
    for obj in objects:
        if obj.type in {"CAMERA", "LIGHT"} or obj.name in {"Cube", "棱角球"}:
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


def set_neutral_face(objects):
    """Match the game's neutral face by disabling the funny tongue mesh."""
    for obj in objects:
        if obj.name == "FunnyTongue":
            obj.hide_render = True
            obj.hide_set(True)


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


def scene_bounds():
    visible = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type in {"MESH", "ARMATURE"} and obj.visible_get()
    ]
    return imported_bounds(visible)


def configure_showcase(output_path, size, samples, exposure):
    setup_white_render(output_path, size, samples, transparent=True)
    bpy.context.scene.view_settings.exposure = exposure
    bpy.context.scene.render.resolution_x = size
    bpy.context.scene.render.resolution_y = size


def player_right_hand_target():
    """Return player.tscn's right-hand IK target in Blender Z-up coordinates."""
    # Godot Head=(0, 1.7080579, -0.45418245),
    # RightHandIKTarget=(0.28, -0.28, -0.42).
    # GLB import uses Blender (X, Z-up, Y-depth): (X,Y,Z)_Godot -> (X,-Z,Y).
    head = Vector((0.0, 0.45418245, 1.7080579))
    return head + Vector((0.28, 0.42, -0.28))


def player_right_elbow_pole():
    # Godot RightElbowPole=(0.65, 1.2, -0.1), converted to Blender.
    return Vector((0.65, 0.1, 1.2))


def render_zombie(project, output_path, size, samples, exposure):
    clear_scene()
    zombie_objects = import_glb(project / "assets/characters/ZombieMale.glb")
    hide_collision_meshes(zombie_objects)
    hide_import_extras(zombie_objects)
    set_neutral_face(zombie_objects)

    root = make_transform_root("ZombieMalePresentationRoot", zombie_objects)
    # Keep the character facing the showcase camera, matching the presentation
    # orientation used by the player/AI appearance scenes.
    root.rotation_euler.z = math.radians(180.0)
    armature = find_armature(zombie_objects)
    apply_action(armature, "Walk")
    bpy.context.view_layer.update()

    bounds = scene_bounds()
    target, scene_size = setup_showcase_camera(bounds, "ZombieMaleWalkCamera")
    add_lights(target, scene_size)
    configure_showcase(output_path, size, samples, exposure)
    bpy.ops.render.render(write_still=True)
    print(
        f"[ZombieMaleWalk] Saved: {output_path}; "
        f"ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def render_engineer(project, output_path, size, samples, exposure):
    clear_scene()
    engineer_objects = import_glb(project / "assets/characters/FutureEngineer.glb")
    hide_collision_meshes(engineer_objects)
    hide_import_extras(engineer_objects)
    set_neutral_face(engineer_objects)

    root = make_transform_root("FutureEngineerPresentationRoot", engineer_objects)
    root.rotation_euler.z = math.radians(180.0)
    armature = find_armature(engineer_objects)
    apply_action(armature, "IdleTool" if any(
        action.name == "IdleTool" for action in bpy.data.actions
    ) else "Idle")
    bpy.context.view_layer.update()

    right_target = player_right_hand_target()
    add_arm_ik(armature, "R", right_target, player_right_elbow_pole())
    bpy.context.view_layer.update()

    weapon_objects = import_glb(
        project / "assets/tools/FTF_Weapon_FutureMPX_BlackGreen.glb"
    )
    hide_collision_meshes(weapon_objects)
    hide_import_extras(weapon_objects)
    weapon_root = make_transform_root("FutureEngineerFutureMPX", weapon_objects)
    weapon_root.location = right_target
    weapon_root.scale = Vector((0.8, 0.8, 0.8))
    # The authored FutureMPX muzzle axis is local +Y in the GLB.  Flip the
    # direct GLB around vertical to match the player's configured grip and
    # point the weapon along the engineer's +Y facing direction.
    weapon_root.rotation_euler = (0.0, 0.0, math.radians(180.0))

    bpy.context.view_layer.update()
    bounds = scene_bounds()
    target, scene_size = setup_showcase_camera(bounds, "FutureEngineerFutureMPXCamera")
    add_lights(target, scene_size)
    configure_showcase(output_path, size, samples, exposure)
    bpy.ops.render.render(write_still=True)
    print(
        f"[FutureEngineerFutureMPX] Saved: {output_path}; "
        f"ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    if args.only in {"all", "zombie"}:
        render_zombie(
            project,
            (project / args.zombie_output).resolve(),
            args.size,
            args.samples,
            args.exposure,
        )
    if args.only in {"all", "engineer"}:
        render_engineer(
            project,
            (project / args.engineer_output).resolve(),
            args.size,
            args.samples,
            args.exposure,
        )


if __name__ == "__main__":
    main()
