"""Render project item GLBs into transparent square icons with Blender.

Run with:
  blender --background --python tools/render_item_icons.py -- [options]
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector


DEFAULT_SIZE = 128
GLB_PATTERN = re.compile(r'path="res://([^"]+\.glb)"', re.IGNORECASE)
SCENE_PATTERN = re.compile(r'path="res://([^"]+\.tscn)"', re.IGNORECASE)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Render item icon PNGs from project GLBs.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", default="assets/icons/items")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--only", default="", help="Comma-separated item ids.")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--samples", type=int, default=32)
    return parser.parse_args(argv)


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def res_path(project, value):
    if not value:
        return None
    relative = value[6:] if value.startswith("res://") else value
    path = (project / relative).resolve()
    return path if path.is_file() else None


def first_glb_from_scene(project, scene_path, visited=None):
    visited = visited or set()
    if scene_path is None or scene_path in visited or not scene_path.is_file():
        return None
    visited.add(scene_path)
    text = scene_path.read_text(encoding="utf-8", errors="ignore")
    for match in GLB_PATTERN.finditer(text):
        candidate = res_path(project, match.group(1))
        if candidate is not None:
            return candidate
    for match in SCENE_PATTERN.finditer(text):
        nested = res_path(project, match.group(1))
        candidate = first_glb_from_scene(project, nested, visited)
        if candidate is not None:
            return candidate
    return None


def add_job(jobs, item_id, category, model, output_name=None):
    if model is None:
        jobs.append({"id": item_id, "category": category, "model": None, "output_name": output_name or item_id})
        return
    key = (category, output_name or item_id)
    if any((job["category"], job["output_name"]) == key for job in jobs):
        return
    jobs.append({"id": item_id, "category": category, "model": model, "output_name": output_name or item_id})


def collect_jobs(project):
    jobs = []
    ingredients = read_json(project / "data/ingredient_definitions.json").get("ingredients", {})
    for item_id, definition in ingredients.items():
        models = definition.get("models", {})
        whole = res_path(project, models.get("whole_item") or models.get("harvest_drop", ""))
        add_job(jobs, item_id, "ingredients", whole)
        chopped = res_path(project, models.get("chopped_item", ""))
        if chopped is not None:
            add_job(jobs, item_id, "ingredients", chopped, item_id + "_chopped")

    dishes = read_json(project / "data/dish_definitions.json").get("dishes", {})
    for item_id, definition in dishes.items():
        add_job(jobs, item_id, "dishes", res_path(project, definition.get("model_path", "")))

    definition_files = [
        ("primary_weapon_definitions.json", "weapons", "weapons"),
        ("special_tool_definitions.json", "tools", "tools"),
        ("tool_definitions.json", "tools", "tools"),
    ]
    seen_tools = set()
    for filename, key, category in definition_files:
        for definition in read_json(project / "data" / filename).get(key, []):
            item_id = str(definition.get("id", ""))
            if not item_id or item_id in seen_tools:
                continue
            scene_value = definition.get("tool_scene") or definition.get("path", "")
            scene_path = res_path(project, scene_value)
            model = first_glb_from_scene(project, scene_path)
            add_job(jobs, item_id, category, model)
            if model is not None:
                seen_tools.add(item_id)
    return jobs


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def imported_bounds(objects):
    points = []
    for obj in objects:
        if obj.type not in {"MESH", "CURVE", "SURFACE", "META", "FONT"} or not obj.visible_get():
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("Imported GLB has no renderable geometry")
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def normalize_model(objects):
    minimum, maximum = imported_bounds(objects)
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    maximum_dimension = max(dimensions.x, dimensions.y, dimensions.z, 0.0001)
    scale = 2.0 / maximum_dimension
    roots = [obj for obj in objects if obj.parent is None]
    for obj in roots:
        obj.location = (obj.location - center) * scale
        obj.scale *= scale
    bpy.context.view_layer.update()
    return imported_bounds(objects)


def point_at(obj, target):
    obj.rotation_euler = ((target - obj.location).to_track_quat("-Z", "Y")).to_euler()


def setup_camera_and_lights(bounds):
    minimum, maximum = bounds
    center = (minimum + maximum) * 0.5
    dimensions = maximum - minimum
    radius = max(dimensions.length * 0.5, 0.5)

    camera_data = bpy.data.cameras.new("IconCamera")
    camera = bpy.data.objects.new("IconCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(dimensions.x, dimensions.z, dimensions.y) * 1.32
    direction = Vector((1.7, -2.3, 1.45)).normalized()
    camera.location = center + direction * radius * 4.0
    point_at(camera, center)
    bpy.context.scene.camera = camera

    for name, energy, size, direction in [
        ("Key", 900.0, 4.0, Vector((-3.0, -4.0, 6.0))),
        ("Fill", 520.0, 3.0, Vector((4.0, -1.5, 2.5))),
        ("Rim", 700.0, 2.5, Vector((1.0, 4.0, 4.5))),
    ]:
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = center + direction.normalized() * radius * 3.5
        point_at(light, center)
        bpy.context.scene.collection.objects.link(light)


def configure_render(output_path, size, samples):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = samples
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = str(output_path)
    scene.render.image_settings.color_depth = "8"
    scene.world.color = (0.025, 0.025, 0.025)
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.use_file_extension = True
    scene.render.image_settings.compression = 30
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.resolution_percentage = 100


def render_job(job, output_root, size, samples, overwrite):
    model = job["model"]
    output_path = output_root / job["category"] / (job["output_name"] + ".png")
    if model is None:
        return "missing_model", output_path
    if output_path.is_file() and not overwrite:
        return "skipped", output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    clear_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(model))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    bounds = normalize_model(imported)
    setup_camera_and_lights(bounds)
    configure_render(output_path, size, samples)
    bpy.ops.render.render(write_still=True)
    return "rendered", output_path


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_root = (project / args.output).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    only = {value.strip() for value in args.only.split(",") if value.strip()}
    jobs = [job for job in collect_jobs(project) if not only or job["id"] in only]
    manifest = {"schema_version": 1, "items": []}
    for index, job in enumerate(jobs, 1):
        print(f"[ItemIcons] {index}/{len(jobs)} {job['category']}/{job['output_name']}")
        try:
            status, output_path = render_job(job, output_root, args.size, args.samples, args.overwrite)
            error = ""
        except Exception as exc:  # Continue so one broken asset does not abort the batch.
            status, output_path, error = "failed", output_root / job["category"] / (job["output_name"] + ".png"), str(exc)
            print(f"[ItemIcons] FAILED {job['id']}: {error}")
        manifest["items"].append({
            "id": job["id"],
            "category": job["category"],
            "icon": "res://" + output_path.relative_to(project).as_posix(),
            "status": status,
            "error": error,
        })
    manifest_path = output_root / "icon_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    counts = {status: sum(1 for item in manifest["items"] if item["status"] == status) for status in {item["status"] for item in manifest["items"]}}
    print(f"[ItemIcons] Done: {counts}; manifest={manifest_path}")


if __name__ == "__main__":
    main()
