"""Render a straight-on perspective projection of the FutureMPX model.

Run with Blender 4.4:
  blender --background --python tools/render_future_mpx_perspective.py -- [options]
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from render_item_icons import (  # noqa: E402
    clear_scene,
    configure_render,
    imported_bounds,
    normalize_model,
    point_at,
)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render a perspective FutureMPX icon.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--output",
        default="assets/icons/app_icon_sources/future_mpx_perspective_front.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--exposure", type=float, default=-0.5)
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
    direction = (
        Vector((1.0, 0.0, 0.0))
        if dimensions.x <= dimensions.y
        else Vector((0.0, -1.0, 0.0))
    )

    camera_data = bpy.data.cameras.new("FutureMPXPerspectiveCamera")
    camera = bpy.data.objects.new("FutureMPXPerspectiveCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "PERSP"
    camera.data.lens = 70.0
    camera.location = center + direction * radius * 4.0
    point_at(camera, center)
    bpy.context.scene.camera = camera

    for name, energy, size, direction in (
        ("Key", 620.0, 4.0, (-3.0, -4.0, 6.0)),
        ("Fill", 300.0, 3.0, (4.0, -1.5, 2.5)),
        ("Rim", 420.0, 2.5, (1.0, 4.0, 4.5)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = center + Vector(direction).normalized() * radius * 3.5
        point_at(light, center)
        bpy.context.scene.collection.objects.link(light)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    model_path = project / "assets/tools/FTF_Weapon_FutureMPX_BlackGreen.glb"
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
    print(f"[FutureMPXPerspective] Saved: {output_path}; exposure={args.exposure}")


if __name__ == "__main__":
    main()
