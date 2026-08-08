import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
sys.path.insert(0, SCRIPT_DIR)

from generate_ontario_school import (
    aabb,
    clear_scene,
    cube,
    export_glb,
    make_material,
    overlap_extents,
    render_preview,
)


DEFAULT_OUTPUT = os.path.join(
    PROJECT_ROOT,
    "assets",
    "buildings",
    "FTF_Building_Canadian_Rural_House_LowPoly_11x8m.glb",
)
DEFAULT_PREVIEW = "/tmp/ftf_canadian_rural_house_lowpoly_preview.png"
MAX_SHALLOW_EMBED_DEPTH = 0.045


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=DEFAULT_PREVIEW)
    parser.add_argument("--no-preview", action="store_true")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def create_front_window(prefix, x, materials, width, height, z=1.92):
    frame, glass = materials
    glass_width = width - 0.34
    glass_height = height - 0.34
    vertical_frame_height = height - 0.25
    objects = [
        cube(prefix + "_Glass", (x, -4.002, z), (glass_width, 0.06, glass_height), glass, 0.012),
    ]
    frame_y = -4.018
    objects.extend(
        [
            cube(prefix + "_Frame_L", (x - width * 0.5 + 0.08, frame_y, z), (0.13, 0.06, vertical_frame_height), frame, 0.016),
            cube(prefix + "_Frame_R", (x + width * 0.5 - 0.08, frame_y, z), (0.13, 0.06, vertical_frame_height), frame, 0.016),
            cube(prefix + "_Frame_T", (x, frame_y, z + height * 0.5 - 0.08), (width, 0.06, 0.13), frame, 0.016),
            cube(prefix + "_Frame_B", (x, frame_y, z - height * 0.5 + 0.08), (width, 0.06, 0.13), frame, 0.016),
            cube(prefix + "_Mullion_V", (x, -4.038, z), (0.08, 0.04, glass_height), frame, 0.010),
            cube(prefix + "_Mullion_H", (x, -4.044, z), (glass_width, 0.04, 0.08), frame, 0.010),
        ]
    )
    return objects


def create_side_window(prefix, y, side, materials, width=1.35, height=1.40):
    frame, glass = materials
    glass_width = width - 0.30
    glass_height = height - 0.30
    vertical_frame_height = height - 0.24
    z = 1.90
    sign = -1.0 if side == "L" else 1.0
    surface_x = 5.502 * sign
    frame_x = 5.518 * sign
    mullion_x = 5.538 * sign
    mullion_cross_x = 5.544 * sign
    objects = [
        cube(prefix + "_Glass", (surface_x, y, z), (0.06, glass_width, glass_height), glass, 0.010),
        cube(prefix + "_Frame_L", (frame_x, y - width * 0.5 + 0.07, z), (0.06, 0.12, vertical_frame_height), frame, 0.016),
        cube(prefix + "_Frame_R", (frame_x, y + width * 0.5 - 0.07, z), (0.06, 0.12, vertical_frame_height), frame, 0.016),
        cube(prefix + "_Frame_T", (frame_x, y, z + height * 0.5 - 0.07), (0.06, width, 0.12), frame, 0.016),
        cube(prefix + "_Frame_B", (frame_x, y, z - height * 0.5 + 0.07), (0.06, width, 0.12), frame, 0.016),
        cube(prefix + "_Mullion_V", (mullion_x, y, z), (0.04, 0.07, glass_height), frame, 0.010),
        cube(prefix + "_Mullion_H", (mullion_cross_x, y, z), (0.04, glass_width, 0.07), frame, 0.010),
    ]
    return objects


def create_hip_roof(name, material):
    eave_z = 3.34
    ridge_z = 4.78
    thickness = 0.14
    top = [
        (-6.00, -4.50, eave_z),
        (6.00, -4.50, eave_z),
        (6.00, 4.50, eave_z),
        (-6.00, 4.50, eave_z),
        (-1.80, 0.0, ridge_z),
        (1.80, 0.0, ridge_z),
    ]
    bottom = [(x, y, z - thickness) for x, y, z in top]
    vertices = top + bottom
    faces = [
        (0, 1, 5, 4),
        (3, 4, 5, 2),
        (0, 3, 4),
        (1, 5, 2),
        (10, 11, 7, 6),
        (9, 8, 11, 10),
        (6, 10, 9),
        (7, 8, 11),
        (0, 6, 7, 1),
        (1, 7, 8, 2),
        (2, 8, 9, 3),
        (3, 9, 10, 0),
        (4, 10, 11, 5),
    ]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def create_rectangular_ring(name, outer_x, outer_y, inner_x, inner_y, bottom_z, top_z, material):
    outer = [(-outer_x, -outer_y), (outer_x, -outer_y), (outer_x, outer_y), (-outer_x, outer_y)]
    inner = [(-inner_x, -inner_y), (inner_x, -inner_y), (inner_x, inner_y), (-inner_x, inner_y)]
    vertices = []
    for z in (bottom_z, top_z):
        vertices.extend([(x, y, z) for x, y in outer])
        vertices.extend([(x, y, z) for x, y in inner])
    faces = [
        (8, 9, 13, 12),
        (9, 10, 14, 13),
        (10, 11, 15, 14),
        (11, 8, 12, 15),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
        (0, 1, 9, 8),
        (1, 2, 10, 9),
        (2, 3, 11, 10),
        (3, 0, 8, 11),
        (4, 12, 13, 5),
        (5, 13, 14, 6),
        (6, 14, 15, 7),
        (7, 15, 12, 4),
    ]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    ring = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ring)
    ring.data.materials.append(material)
    return ring


def add_eave_trim(parts, name, material):
    parts.append(create_rectangular_ring(name, 6.12, 4.62, 6.00, 4.50, 3.20, 3.35, material))


def add_wall_top_fascia(parts, name, material):
    parts.append(create_rectangular_ring(name, 5.56, 4.06, 5.50, 4.00, 3.15, 3.35, material))


def validate_parts(parts):
    if not parts:
        raise RuntimeError("No rural house geometry was created")
    for obj in parts:
        if obj.type != "MESH":
            raise RuntimeError(f"Unexpected non-mesh part: {obj.name}")
        minimum, _maximum = aabb(obj)
        if minimum.z < -0.03:
            raise RuntimeError(f"Part below ground: {obj.name} z={minimum.z:.4f}")

    deep_overlaps = []
    shallow_count = 0
    for index, first in enumerate(parts):
        for second in parts[index + 1 :]:
            if "Hip_Roof" in {first.name, second.name} and (
                "Chimney" in first.name or "Chimney" in second.name
            ):
                shallow_count += 1
                continue
            if "Hip_Roof" in {first.name, second.name} and "White_Eave_Trim" in {
                first.name,
                second.name,
            }:
                shallow_count += 1
                continue
            if "Wall_Top_Fascia" in {first.name, second.name} and (
                "Main_House_Block" in {first.name, second.name}
                or "Hip_Roof" in {first.name, second.name}
            ):
                shallow_count += 1
                continue
            if {first.name, second.name} == {"Wall_Top_Fascia", "White_Eave_Trim"}:
                shallow_count += 1
                continue
            extent = overlap_extents(first, second)
            if extent is None:
                continue
            if min(extent.x, extent.y, extent.z) <= MAX_SHALLOW_EMBED_DEPTH:
                shallow_count += 1
                continue
            deep_overlaps.append((first.name, second.name, extent.x * extent.y * extent.z))
    if deep_overlaps:
        preview = ", ".join(
            f"{first}/{second}={volume:.5f}" for first, second, volume in deep_overlaps[:8]
        )
        raise RuntimeError(f"Deep overlapping modules detected ({len(deep_overlaps)}): {preview}")

    minimum = Vector(
        (
            min(aabb(obj)[0].x for obj in parts),
            min(aabb(obj)[0].y for obj in parts),
            min(aabb(obj)[0].z for obj in parts),
        )
    )
    maximum = Vector(
        (
            max(aabb(obj)[1].x for obj in parts),
            max(aabb(obj)[1].y for obj in parts),
            max(aabb(obj)[1].z for obj in parts),
        )
    )
    size = maximum - minimum
    if minimum.z > 0.0001 or minimum.z < -0.03:
        raise RuntimeError(f"House does not sit on ground: z_min={minimum.z:.5f}")
    if not (10.0 <= size.x <= 13.0 and 7.0 <= size.y <= 10.0 and 4.5 <= size.z <= 6.0):
        raise RuntimeError(f"Unexpected house bounds: {tuple(round(value, 4) for value in size)}")
    print(
        "VALID modules=%d shallow_embeds=%d bounds_min=%s bounds_max=%s size=%s"
        % (
            len(parts),
            shallow_count,
            tuple(round(value, 4) for value in minimum),
            tuple(round(value, 4) for value in maximum),
            tuple(round(value, 4) for value in size),
        )
    )


def join_parts(parts):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = "FTF_Building_Canadian_Rural_House_LowPoly_11x8m"
    merged.data.name = "MESH_FTF_Building_Canadian_Rural_House_LowPoly_11x8m"
    merged.select_set(False)
    return merged


def build_house():
    wall = make_material("MAT_Rural_House_Red_Brown_Wall", "#87452D", roughness=0.88)
    roof = make_material("MAT_Rural_House_Brown_Hip_Roof", "#4A2E24", roughness=0.86)
    trim = make_material("MAT_Rural_House_White_Trim", "#E1DDD1", roughness=0.76)
    glass = make_material("MAT_Rural_House_Window_BlueGray", "#496A73", roughness=0.32, metallic=0.04)
    door = make_material("MAT_Rural_House_Door_DarkBrown", "#3C2923", roughness=0.78)
    chimney = make_material("MAT_Rural_House_Chimney_Brick", "#7D3D2E", roughness=0.88)
    chimney_cap = make_material("MAT_Rural_House_Chimney_Cap", "#D7D1C2", roughness=0.72)

    parts = [
        cube("Main_House_Block", (0.0, 0.0, 1.60), (11.0, 8.0, 3.20), wall, 0.04),
    ]

    add_wall_top_fascia(parts, "Wall_Top_Fascia", wall)
    add_eave_trim(parts, "White_Eave_Trim", trim)
    parts.append(create_hip_roof("Hip_Roof", roof))

    parts.extend(create_front_window("Front_Window_Left", -4.30, (trim, glass), 1.35, 1.55, 1.90))
    parts.extend(create_front_window("Front_Window_Right", 2.45, (trim, glass), 3.75, 1.85, 1.92))
    parts.extend(create_side_window("Left_Side_Window", -1.30, "L", (trim, glass)))
    parts.extend(create_side_window("Right_Side_Window", 1.10, "R", (trim, glass)))

    parts.extend(
        [
            cube("Front_Door", (-2.25, -4.04, 1.18), (1.25, 0.08, 2.36), door, 0.022),
            cube("Front_Door_Frame_Left", (-2.965, -4.09, 1.18), (0.20, 0.06, 2.36), trim, 0.018),
            cube("Front_Door_Frame_Right", (-1.535, -4.09, 1.18), (0.20, 0.06, 2.36), trim, 0.018),
            cube("Front_Door_Frame_Top", (-2.25, -4.09, 2.45), (1.70, 0.06, 0.18), trim, 0.018),
            cube("Front_Door_Handle", (-1.86, -4.15, 1.20), (0.10, 0.04, 0.10), trim, 0.010),
        ]
    )

    chimney_surface_z = 4.204
    parts.extend(
        [
            cube("Chimney_Base", (3.40, 1.00, chimney_surface_z + 0.05), (0.82, 0.82, 0.10), chimney, 0.022),
            cube("Chimney_Stack", (3.40, 1.00, 4.94), (0.56, 0.56, 1.28), chimney, 0.022),
            cube("Chimney_Cap", (3.40, 1.00, 5.65), (0.70, 0.70, 0.14), chimney_cap, 0.018),
        ]
    )

    validate_parts(parts)
    return parts


def main():
    args = parse_args()
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    parts = build_house()
    merged = join_parts(parts)
    mesh_count = len([obj for obj in bpy.context.scene.objects if obj.type == "MESH"])
    if mesh_count != 1:
        raise RuntimeError(f"Expected one merged mesh, found {mesh_count}")
    if not args.no_preview:
        render_preview(merged, os.path.abspath(args.preview))
    export_glb(merged, args.output)
    merged.data.calc_loop_triangles()
    print(
        "EXPORTED %s meshes=%d triangles=%d materials=%d"
        % (os.path.abspath(args.output), mesh_count, len(merged.data.loop_triangles), len(merged.data.materials))
    )


if __name__ == "__main__":
    main()
