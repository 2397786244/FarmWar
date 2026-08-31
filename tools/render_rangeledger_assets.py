"""Render Range Ledger's weapon and supply reference images.

The page uses transparent, square orthographic renders instead of reusing the
small gameplay icons.  Run from the project with:

    blender --background --python tools/render_rangeledger_assets.py -- \
        --project . --size 256 --overwrite
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from render_item_icons import (  # noqa: E402
    clear_scene,
    configure_render,
    imported_bounds,
    normalize_model,
    point_at,
    setup_camera_and_lights,
)


JOBS = [
	("mpx", "assets/tools/FTF_Weapon_MPX_Compact_IronSights.glb"),
	("m4", "assets/tools/M4.glb"),
	("ak47", "assets/tools/AK47.glb"),
	("ar15", "assets/tools/AR15.glb"),
    ("shotgun", "assets/tools/Shotgun.glb"),
    ("remington870", "assets/tools/Reminton870.glb"),
    ("p90", "assets/tools/P90.glb"),
    ("hunting_rifle", "assets/tools/HuntingRifle.glb"),
    ("crossbow", "assets/tools/Crossbow.glb"),
    ("suppressed_pistol", "assets/tools/SuppressedPistol.glb"),
    ("m17", "assets/tools/M17.glb"),
    ("future_m4", "assets/tools/FutureM4.glb"),
    ("future_mpx", "assets/tools/FTF_Weapon_FutureMPX_BlackGreen.glb"),
    ("grenade", "assets/tools/Grenade.glb"),
    ("ammo_supply_box", "assets/other_items/weapons/AmmoSupplyBox.glb"),
]


def orient_horizontal_orthographic_camera(bounds):
    """Keep long equipment models horizontal in the square reference cards."""
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    camera = bpy.context.scene.camera
    view_direction = (center - camera.location).normalized()
    screen_right = Vector((0.0, 0.0, 1.0))
    screen_right -= view_direction * screen_right.dot(view_direction)
    screen_right.normalize()
    screen_up = screen_right.cross(view_direction).normalized()
    camera.rotation_euler = Matrix((screen_right, screen_up, -view_direction)).transposed().to_euler()


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render Range Ledger reference images.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", default="assets/icons/rangeledger")
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--only", default="", help="Comma-separated image ids.")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--samples", type=int, default=48)
    return parser.parse_args(argv)


def render_job(project, output_root, image_id, relative_model, size, samples, overwrite):
    model = (project / relative_model).resolve()
    output_path = output_root / (image_id + ".png")
    if not model.is_file():
        raise FileNotFoundError(f"model is missing: {model}")
    if output_path.is_file() and not overwrite:
        print(f"[RangeLedger] SKIP {output_path}")
        return "skipped"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    clear_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(model))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    bounds = normalize_model(imported)
    setup_camera_and_lights(bounds)
    orient_horizontal_orthographic_camera(bounds)
    configure_render(output_path, size, samples)
    bpy.ops.render.render(write_still=True)
    print(f"[RangeLedger] RENDER {image_id}: {output_path}")
    return "rendered"


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_root = (project / args.output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    only = {value.strip() for value in args.only.split(",") if value.strip()}
    jobs = [(image_id, model) for image_id, model in JOBS if not only or image_id in only]
    if not jobs:
        raise SystemExit("No Range Ledger render jobs selected")

    counts = {"rendered": 0, "skipped": 0, "failed": 0}
    for index, (image_id, relative_model) in enumerate(jobs, 1):
        print(f"[RangeLedger] {index}/{len(jobs)} {image_id}")
        try:
            status = render_job(
                project,
                output_root,
                image_id,
                relative_model,
                args.size,
                args.samples,
                args.overwrite,
            )
        except Exception as exc:
            counts["failed"] += 1
            print(f"[RangeLedger] FAILED {image_id}: {exc}")
            continue
        counts[status] += 1
    print(f"[RangeLedger] Done: {counts}")
    if counts["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
