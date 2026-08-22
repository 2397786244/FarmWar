"""Render character and nature showcase icons for the Harvest Operation project.

The character renders reuse the same right-hand IK target, imported GLB
orientation, lighting and transparent PNG setup as the Cook/Farmer showcase
scripts.  The crop and animal renders use the same camera direction and a
tighter adaptive framing so each subject fills the square as much as its
silhouette allows.

Run with Blender:
  blender --background --factory-startup --python \
      tools/render_bandit_mage_nature_icons.py -- [options]
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
)
from render_item_icons import clear_scene, point_at  # noqa: E402


DEFAULT_OUTPUT_DIR = "assets/icons/app_icon_sources"
DEFAULT_EXPOSURE = -1.4
DEFAULT_SIZE = 1024
DEFAULT_SAMPLES = 96

PLAYER_HEAD_POSITION = Vector((0.0, 0.45418245, 1.7080579))
RIGHT_HAND_TARGET = PLAYER_HEAD_POSITION + Vector((0.28, 0.42, -0.28))
RIGHT_ELBOW_POLE = Vector((0.65, 0.1, 1.2))


RENDER_JOBS = {
    "bandit": {
        "kind": "character",
        "label": "BanditSuppressedPistol",
        "model": "assets/characters/Bandit.glb",
        "weapon": "assets/tools/SuppressedPistol.glb",
        "output": "bandit_suppressed_pistol_orthographic.png",
        "action": "IdleTool",
        "weapon_scale": 0.3,
        "weapon_yaw": 180.0,
        "weapon_offset": Vector((0.0, -0.015, -0.015)),
    },
    "mage": {
        "kind": "character",
        "label": "MageWand",
        "model": "assets/characters/Mage_Red.glb",
        "weapon": "assets/tools/Wand.glb",
        "output": "mage_wand_orthographic.png",
        "action": "IdleTool",
        "weapon_scale": 0.5,
        "weapon_yaw": 0.0,
        "weapon_offset": Vector((0.0, 0.0, 0.0)),
    },
    "pumpkin": {
        "kind": "nature",
        "label": "PumpkinPlant",
        "model": "assets/plants/Pumpkin.glb",
        "output": "pumpkin_plant_orthographic.png",
        "action": None,
    },
    "cotton": {
        "kind": "nature",
        "label": "CottonPlant",
        "model": "assets/plants/Cotton.glb",
        "output": "cotton_plant_orthographic.png",
        "action": None,
    },
    "redmaple": {
        "kind": "nature",
        "label": "RedMaple",
        "model": "assets/nature/RedMaple.glb",
        "output": "red_maple_orthographic.png",
        "action": None,
    },
    "chicken": {
        "kind": "nature",
        "label": "Chicken",
        "model": "assets/animals/FTF_Animal_Chicken_White.glb",
        "output": "chicken_orthographic.png",
        "action": "Idle",
    },
    "blackbear": {
        "kind": "nature",
        "label": "BlackBear",
        "model": "assets/animals/FTF_WildAnimal_BlackBear.glb",
        "output": "black_bear_orthographic.png",
        "action": "Idle",
    },
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render showcase icons for characters, crops and animals.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--samples", type=int, default=DEFAULT_SAMPLES)
    parser.add_argument("--exposure", type=float, default=DEFAULT_EXPOSURE)
    parser.add_argument(
        "--only",
        default="all",
        help="Comma-separated job ids: bandit,mage,pumpkin,cotton,redmaple,chicken,blackbear",
    )
    return parser.parse_args(argv)


def remove_unused_actions():
    """Prevent GLTF imports in later jobs from receiving .001 action names."""
    for action in list(bpy.data.actions):
        if action.users == 0:
            bpy.data.actions.remove(action)


def reset_scene():
    clear_scene()
    remove_unused_actions()


def hide_import_extras(objects):
    """Exclude cameras, lights and non-game test primitives bundled in GLBs."""
    for obj in objects:
        lower_name = obj.name.lower()
        if (
            obj.type in {"CAMERA", "LIGHT"}
            or obj.name in {"Cube", "棱角球"}
            or lower_name.startswith("icosphere")
        ):
            obj.hide_render = True
            obj.hide_set(True)


def set_neutral_face(objects):
    """Reset imported facial morph values to the game's neutral expression."""
    for obj in objects:
        if obj.type == "MESH" and obj.data.shape_keys is not None:
            for block in obj.data.shape_keys.key_blocks:
                if block.name == "Basis":
                    block.value = 0.0
                elif block.name == "Calm":
                    block.value = 1.0
                else:
                    block.value = 0.0
        if obj.name == "FunnyTongue":
            obj.hide_render = True
            obj.hide_set(True)


def apply_action(armature, action_name):
    if not action_name:
        return
    action = next((candidate for candidate in bpy.data.actions if candidate.name == action_name), None)
    if action is None:
        raise RuntimeError(f"{armature.name} does not contain the {action_name} action")
    armature.animation_data_create()
    armature.animation_data.action = action
    start, end = action.frame_range
    bpy.context.scene.frame_set(int(round((start + end) * 0.5)))


def setup_showcase_camera(bounds):
    """Create the same high three-quarter camera, with close adaptive framing."""
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    widest_dimension = max(dimensions.x, dimensions.y, dimensions.z)
    # The extra terms keep very wide animals and low crops inside the image,
    # while the 1.08 height margin makes the subject substantially larger than
    # the older generic item-icon framing.
    scene_size = max(
        dimensions.length * 0.86,
        dimensions.z * 1.08,
        widest_dimension * 1.04,
        0.8,
    )
    distance = max(dimensions.length * 6.0, 6.0)
    direction = Vector((3.3, 6.2, 1.45)).normalized()

    camera_data = bpy.data.cameras.new("ShowcaseCamera")
    camera = bpy.data.objects.new("ShowcaseCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scene_size
    camera.location = center + direction * distance
    point_at(camera, center)
    bpy.context.scene.camera = camera
    return center, scene_size


def visible_render_objects():
    return [
        obj
        for obj in bpy.context.scene.objects
        if obj.type in {"MESH", "ARMATURE"} and obj.visible_get()
    ]


def render_current_scene(output_path, size, samples, exposure):
    bounds = imported_bounds(visible_render_objects())
    target, scene_size = setup_showcase_camera(bounds)
    add_lights(target, scene_size)

    # Blender 4.4 exposes BLENDER_EEVEE_NEXT while Blender 5.1 renamed the
    # same realtime engine to BLENDER_EEVEE.  Keep this asset script usable
    # with either version used by the project.
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.filepath = str(output_path)
    scene.render.use_file_extension = True
    scene.render.image_settings.compression = 30
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = exposure
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = samples
    bpy.ops.render.render(write_still=True)
    return bounds, scene_size


def render_character(project, job, output_path, size, samples, exposure):
    reset_scene()

    character_objects = import_glb(project / job["model"])
    hide_collision_meshes(character_objects)
    hide_import_extras(character_objects)
    set_neutral_face(character_objects)
    character_root = make_transform_root(f"{job['label']}CharacterRoot", character_objects)
    # The source GLBs use the same orientation convention as the Cook/Farmer
    # showcase renders: turn the presentation root to face the camera.
    character_root.rotation_euler.z = math.radians(180.0)

    armature = find_armature(character_objects)
    apply_action(armature, job["action"])
    bpy.context.view_layer.update()
    add_arm_ik(armature, "R", RIGHT_HAND_TARGET, RIGHT_ELBOW_POLE)
    bpy.context.view_layer.update()

    weapon_objects = import_glb(project / job["weapon"])
    hide_collision_meshes(weapon_objects)
    hide_import_extras(weapon_objects)
    weapon_root = make_transform_root(f"{job['label']}WeaponRoot", weapon_objects)
    weapon_root.location = RIGHT_HAND_TARGET + job["weapon_offset"]
    weapon_root.scale = Vector((job["weapon_scale"],) * 3)
    weapon_root.rotation_euler = (0.0, 0.0, math.radians(job["weapon_yaw"]))
    bpy.context.view_layer.update()

    bounds, scene_size = render_current_scene(output_path, size, samples, exposure)
    print(
        f"[{job['label']}] Saved: {output_path}; "
        f"bounds={bounds}; ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def render_nature_asset(project, job, output_path, size, samples, exposure):
    reset_scene()

    objects = import_glb(project / job["model"])
    hide_collision_meshes(objects)
    hide_import_extras(objects)
    set_neutral_face(objects)

    armature = next((obj for obj in objects if obj.type == "ARMATURE"), None)
    if armature is not None:
        root = make_transform_root(f"{job['label']}Root", objects)
        root.rotation_euler.z = math.radians(180.0)
        apply_action(armature, job["action"])
    else:
        make_transform_root(f"{job['label']}Root", objects)
    bpy.context.view_layer.update()

    bounds, scene_size = render_current_scene(output_path, size, samples, exposure)
    print(
        f"[{job['label']}] Saved: {output_path}; "
        f"bounds={bounds}; ortho_scale={scene_size:.3f}; exposure={exposure}"
    )


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_dir = (project / args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    requested = [item.strip().lower() for item in args.only.split(",") if item.strip()]
    job_ids = list(RENDER_JOBS) if not requested or requested == ["all"] else requested
    unknown = [job_id for job_id in job_ids if job_id not in RENDER_JOBS]
    if unknown:
        raise SystemExit(f"Unknown job id(s): {', '.join(unknown)}")

    for job_id in job_ids:
        job = RENDER_JOBS[job_id]
        output_path = output_dir / job["output"]
        if job["kind"] == "character":
            render_character(project, job, output_path, args.size, args.samples, args.exposure)
        else:
            render_nature_asset(project, job, output_path, args.size, args.samples, args.exposure)


if __name__ == "__main__":
    main()
