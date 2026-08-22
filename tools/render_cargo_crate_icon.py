"""Render the gameplay medium cargo crate as a lower-exposure orthographic icon."""

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


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render a cargo crate icon.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--output",
        default="assets/icons/app_icon_sources/cargo_crate_medium_front.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--exposure", type=float, default=-0.8)
    return parser.parse_args(argv)


def hide_collision_meshes(objects):
    for obj in objects:
        name = obj.name.upper()
        if name.startswith("UCX_") or "MESH_UCX_" in name:
            obj.hide_render = True
            obj.hide_set(True)


def setup_camera_and_lights(bounds):
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    radius = max(dimensions.length * 0.5, 0.5)

    camera_data = bpy.data.cameras.new("CargoCrateIconCamera")
    camera = bpy.data.objects.new("CargoCrateIconCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "PERSP"
    camera.data.lens = 70.0
    direction = Vector((0.0, -1.0, 0.0))
    camera.location = center + direction * radius * 4.0
    point_at(camera, center)
    bpy.context.scene.camera = camera

    for name, energy, size, direction_value in (
        ("Key", 420.0, 3.0, (-3.0, -4.0, 5.0)),
        ("Fill", 180.0, 2.5, (4.0, -1.5, 2.0)),
        ("Rim", 260.0, 2.0, (1.0, 4.0, 4.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = center + radius * 3.0 * Vector(direction_value).normalized()
        point_at(light, center)
        bpy.context.scene.collection.objects.link(light)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    model_path = project / "assets/other_items/crates/FTF_Prop_WoodenCrate_0_3m_Cube.glb"
    output_path = (project / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    clear_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(model_path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    hide_collision_meshes(imported)
    bounds = normalize_model(imported)
    setup_camera_and_lights(bounds)
    configure_render(output_path, args.size, args.samples)
    bpy.context.scene.view_settings.exposure = args.exposure
    bpy.ops.render.render(write_still=True)
    print(f"[CargoCrateIcon] Saved: {output_path}; exposure={args.exposure}")


if __name__ == "__main__":
    main()
