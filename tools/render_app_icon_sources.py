"""Render front-facing orthographic source images for the application icon.

Run with Blender 4.4:
  blender --background --python tools/render_app_icon_sources.py -- [options]

The script renders the selected farm, weapon, vehicle, and drone models with
transparent backgrounds. For each model it chooses the horizontal axis that
produces the largest upright silhouette, so long objects are shown from the
side instead of being viewed end-on.
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from render_item_icons import (
    clear_scene,
    configure_render,
    imported_bounds,
    normalize_model,
    point_at,
)


DEFAULT_SIZE = 1024
JOBS = (
    ("wheat_front.png", "assets/plants/Wheat.glb"),
    ("sprout_blaster_front.png", "assets/tools/SproutBlaster.glb"),
    ("shotgun_front.png", "assets/tools/Shotgun.glb"),
    ("future_mpx_front.png", "assets/tools/FTF_Weapon_FutureMPX_BlackGreen.glb"),
    (
        "red_cargo_car_side.png",
        "assets/vehicles/FTF_Vehicle_NorthAmericanFarmTruck_Red_Open_7m.glb",
    ),
    ("normal_drone_front.png", "assets/tools/NormalDrone.glb"),
)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(
        description="Render front-facing source images for the application icon."
    )
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", default="assets/icons/app_icon_sources")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--samples", type=int, default=64)
    return parser.parse_args(argv)


def choose_front_direction(bounds):
    """View along the thinner horizontal axis to maximize the upright silhouette."""
    minimum, maximum = bounds
    dimensions = maximum - minimum
    if dimensions.x <= dimensions.y:
        return Vector((1.0, 0.0, 0.0)), dimensions.y
    return Vector((0.0, -1.0, 0.0)), dimensions.x


def setup_front_camera_and_lights(bounds):
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    direction, visible_width = choose_front_direction(bounds)
    visible_height = dimensions.z
    radius = max(dimensions.length * 0.5, 0.5)

    camera_data = bpy.data.cameras.new("AppIconCamera")
    camera = bpy.data.objects.new("AppIconCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(visible_width, visible_height, 0.1) * 1.14
    camera.location = center + direction * radius * 4.0
    point_at(camera, center)
    bpy.context.scene.camera = camera

    camera_right = direction.cross(Vector((0.0, 0.0, 1.0))).normalized()
    light_positions = (
        ("Key", 620.0, 4.0, center + direction * radius * 2.5 - camera_right * radius * 1.8 + Vector((0.0, 0.0, radius * 2.4))),
        ("Fill", 300.0, 3.0, center + direction * radius * 2.0 + camera_right * radius * 2.0 + Vector((0.0, 0.0, radius * 0.8))),
        ("Rim", 420.0, 2.5, center - direction * radius * 1.8 + Vector((0.0, 0.0, radius * 2.0))),
    )
    for name, energy, size, position in light_positions:
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = position
        point_at(light, center)
        bpy.context.scene.collection.objects.link(light)


def show_mature_wheat_only(objects):
    """Hide immature growth meshes and render the fully grown wheat stage."""
    for obj in objects:
        name = obj.name.upper()
        is_immature = (
            name.startswith("STAGE_01")
            or name.startswith("STAGE_02")
            or "_S01_" in name
            or "_S02_" in name
        )
        is_mature = name.startswith("STAGE_03") or "_S03_" in name
        if is_immature:
            obj.hide_render = True
            obj.hide_set(True)
        elif is_mature:
            obj.hide_render = False
            obj.hide_set(False)


def hide_collision_meshes(objects):
    """Exclude UCX helper geometry that must never appear in rendered icons."""
    for obj in objects:
        name = obj.name.upper()
        if name.startswith("UCX_") or "MESH_UCX_" in name:
            obj.hide_render = True
            obj.hide_set(True)


def render_source(model_path, output_path, size, samples):
    clear_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(model_path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    hide_collision_meshes(imported)
    if model_path.name == "Wheat.glb":
        show_mature_wheat_only(imported)
        bpy.context.view_layer.update()
    bounds = normalize_model(imported)
    setup_front_camera_and_lights(bounds)
    configure_render(output_path, size, samples)
    bpy.context.scene.view_settings.exposure = -0.5
    bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_root = (project / args.output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    for index, (output_name, relative_model_path) in enumerate(JOBS, 1):
        model_path = project / relative_model_path
        output_path = output_root / output_name
        if not model_path.is_file():
            raise FileNotFoundError(model_path)
        print(f"[AppIconSources] {index}/{len(JOBS)} {output_name}")
        render_source(model_path, output_path, args.size, args.samples)

    print(f"[AppIconSources] Done: {output_root}")


if __name__ == "__main__":
    main()
