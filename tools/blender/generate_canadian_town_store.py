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
    cylinder,
    export_glb,
    make_material,
    overlap_extents,
    render_preview,
)


DEFAULT_OUTPUT = os.path.join(
    PROJECT_ROOT,
    "assets",
    "buildings",
    "FTF_Building_Canadian_Town_Store_LowPoly_12x10m.glb",
)
DEFAULT_PREVIEW = "/tmp/ftf_canadian_town_store_lowpoly_preview.png"
MAX_SHALLOW_EMBED_DEPTH = 0.045


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=DEFAULT_PREVIEW)
    parser.add_argument("--no-preview", action="store_true")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def create_front_window(prefix, x, materials, width=2.72, height=1.90):
    frame, glass = materials
    glass_width = width - 0.38
    glass_height = height - 0.38
    vertical_frame_height = height - 0.28
    z = 2.08
    objects = [
        cube(prefix + "_Glass", (x, -4.515, z), (glass_width, 0.06, glass_height), glass, 0.012),
    ]
    frame_y = -4.525
    objects.extend(
        [
            cube(prefix + "_Frame_L", (x - width * 0.5 + 0.09, frame_y, z), (0.14, 0.06, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_R", (x + width * 0.5 - 0.09, frame_y, z), (0.14, 0.06, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_T", (x, frame_y, z + height * 0.5 - 0.09), (width, 0.06, 0.14), frame, 0.018),
            cube(prefix + "_Frame_B", (x, frame_y, z - height * 0.5 + 0.09), (width, 0.06, 0.14), frame, 0.018),
        ]
    )
    mullion_y = -4.56
    mullion_cross_y = -4.59
    objects.extend(
        [
            cube(prefix + "_Mullion_V", (x, mullion_y, z), (0.09, 0.04, glass_height), frame, 0.012),
            cube(prefix + "_Mullion_H", (x, mullion_cross_y, z), (glass_width, 0.04, 0.09), frame, 0.012),
        ]
    )
    return objects


def create_side_window(prefix, y, materials, width=1.55, height=1.55):
    frame, glass = materials
    glass_width = width - 0.34
    glass_height = height - 0.34
    vertical_frame_height = height - 0.25
    z = 2.05
    surface_x = -6.005
    frame_x = -6.025
    mullion_x = -6.06
    mullion_cross_x = -6.09
    objects = [
        cube(prefix + "_Glass", (surface_x, y, z), (0.06, glass_width, glass_height), glass, 0.012),
        cube(prefix + "_Frame_L", (frame_x, y - width * 0.5 + 0.08, z), (0.06, 0.13, vertical_frame_height), frame, 0.018),
        cube(prefix + "_Frame_R", (frame_x, y + width * 0.5 - 0.08, z), (0.06, 0.13, vertical_frame_height), frame, 0.018),
        cube(prefix + "_Frame_T", (frame_x, y, z + height * 0.5 - 0.08), (0.06, width, 0.13), frame, 0.018),
        cube(prefix + "_Frame_B", (frame_x, y, z - height * 0.5 + 0.08), (0.06, width, 0.13), frame, 0.018),
        cube(prefix + "_Mullion_V", (mullion_x, y, z), (0.04, 0.08, glass_height), frame, 0.012),
        cube(prefix + "_Mullion_H", (mullion_cross_x, y, z), (0.04, glass_width, 0.08), frame, 0.012),
    ]
    return objects


def add_perimeter_band(parts, name, z, material, height=0.14):
    parts.extend(
        [
            cube(name + "_Front", (0.0, -4.53, z), (12.0, 0.10, height), material, 0.018),
            cube(name + "_Back", (0.0, 4.53, z), (12.0, 0.10, height), material, 0.018),
            cube(name + "_Left", (-6.03, 0.0, z), (0.10, 9.0, height), material, 0.018),
            cube(name + "_Right", (6.03, 0.0, z), (0.10, 9.0, height), material, 0.018),
        ]
    )


def validate_parts(parts):
    if not parts:
        raise RuntimeError("No town store geometry was created")
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
        raise RuntimeError(f"Store does not sit on ground: z_min={minimum.z:.5f}")
    if not (11.0 <= size.x <= 14.0 and 9.0 <= size.y <= 12.0 and 4.5 <= size.z <= 6.0):
        raise RuntimeError(f"Unexpected store bounds: {tuple(round(value, 4) for value in size)}")
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
    merged.name = "FTF_Building_Canadian_Town_Store_LowPoly_12x10m"
    merged.data.name = "MESH_FTF_Building_Canadian_Town_Store_LowPoly_12x10m"
    merged.select_set(False)
    return merged


def build_store():
    concrete = make_material("MAT_Store_Concrete_Grey", "#777A76", roughness=0.90)
    concrete_shadow = make_material("MAT_Store_Concrete_Shadow", "#555B5A", roughness=0.92)
    stone = make_material("MAT_Store_Foundation_Stone", "#B3AAA0", roughness=0.88)
    cream = make_material("MAT_Store_Cream_Trim", "#E4DED1", roughness=0.78)
    roof = make_material("MAT_Store_Roof_Charcoal", "#383E42", roughness=0.84, metallic=0.05)
    roof_edge = make_material("MAT_Store_Roof_Edge", "#242B30", roughness=0.78, metallic=0.10)
    red = make_material("MAT_Store_Stripe_Red", "#B63B32", roughness=0.80)
    white = make_material("MAT_Store_Stripe_White", "#E7E6DE", roughness=0.78)
    blue = make_material("MAT_Store_Stripe_Blue", "#274F80", roughness=0.80)
    glass = make_material("MAT_Store_Window_BlueBlack", "#29404B", roughness=0.30, metallic=0.04)
    door = make_material("MAT_Store_Door_BlueBlack", "#24333A", roughness=0.72)
    equipment = make_material("MAT_Store_Rooftop_Equipment", "#6A6C68", roughness=0.86, metallic=0.08)
    vent = make_material("MAT_Store_Rooftop_Vent", "#343B3D", roughness=0.80, metallic=0.10)

    parts = [
        cube("Foundation_Platform", (0.0, 0.0, 0.15), (12.4, 9.4, 0.30), stone, 0.07),
        cube("Main_Store_Back_Block", (0.0, 0.25, 2.15), (12.0, 8.50, 3.70), concrete, 0.045),
        cube("Main_Store_Front_Left", (-4.95, -4.25, 2.15), (2.10, 0.52, 3.70), concrete, 0.045),
        cube("Main_Store_Front_Right", (2.00, -4.25, 2.15), (8.00, 0.52, 3.70), concrete, 0.045),
        cube("Entry_Recess_Header", (-3.00, -4.25, 3.45), (1.80, 0.52, 1.10), concrete, 0.035),
    ]

    add_perimeter_band(parts, "Stripe_White_Lower", 3.23, white, 0.14)
    add_perimeter_band(parts, "Stripe_Red", 3.41, red, 0.14)
    add_perimeter_band(parts, "Stripe_White_Upper", 3.59, white, 0.14)
    add_perimeter_band(parts, "Stripe_Blue", 3.77, blue, 0.14)

    parts.extend(
        [
            cube("Main_Roof_Slab", (0.0, 0.0, 4.15), (12.5, 9.5, 0.32), roof, 0.04),
            cube("Roof_Front_Parapet", (0.0, -4.67, 4.40), (12.1, 0.18, 0.20), roof_edge, 0.022),
            cube("Roof_Back_Parapet", (0.0, 4.67, 4.40), (12.1, 0.18, 0.20), roof_edge, 0.022),
            cube("Roof_Left_Parapet", (-6.17, 0.0, 4.40), (0.18, 8.7, 0.20), roof_edge, 0.022),
            cube("Roof_Right_Parapet", (6.17, 0.0, 4.40), (0.18, 8.7, 0.20), roof_edge, 0.022),
        ]
    )

    parts.extend(create_front_window("Front_Window_Right", 2.35, (cream, glass), width=3.70, height=1.90))

    parts.extend(
        [
            cube("Entry_Door", (-3.00, -4.03, 1.575), (1.25, 0.08, 2.55), door, 0.022),
            cube("Entry_Door_Frame_L", (-3.73, -4.10, 1.60), (0.14, 0.06, 2.60), cream, 0.018),
            cube("Entry_Door_Frame_R", (-2.27, -4.10, 1.60), (0.14, 0.06, 2.60), cream, 0.018),
            cube("Entry_Door_Frame_Top", (-3.00, -4.52, 2.97), (1.60, 0.06, 0.14), cream, 0.018),
            cube("Entry_Door_Handle", (-2.63, -4.16, 1.65), (0.10, 0.04, 0.10), cream, 0.012),
            cube("Entry_Pier_Left", (-3.74, -4.55, 1.60), (0.30, 0.28, 2.60), stone, 0.025),
            cube("Entry_Pier_Right", (-2.26, -4.55, 1.60), (0.30, 0.28, 2.60), stone, 0.025),
        ]
    )

    parts.extend(
        [
            cube("Rooftop_Equipment_Base", (-3.15, 1.35, 4.41), (2.20, 1.45, 0.22), equipment, 0.035),
            cube("Rooftop_Equipment_Box", (-3.15, 1.35, 4.86), (1.70, 1.05, 0.68), equipment, 0.035),
            cube("Rooftop_Equipment_Vent", (-3.15, 1.35, 5.23), (0.62, 0.48, 0.12), vent, 0.018),
            cube("Rooftop_Small_Box", (-1.65, 2.20, 4.50), (0.78, 0.68, 0.38), vent, 0.025),
        ]
    )

    validate_parts(parts)
    return parts


def main():
    args = parse_args()
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    parts = build_store()
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
