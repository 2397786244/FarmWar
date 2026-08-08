import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(
    PROJECT_ROOT,
    "assets",
    "buildings",
    "FTF_Building_School_Ontario_LowPoly_24x16m.glb",
)
DEFAULT_PREVIEW = "/tmp/ftf_ontario_school_lowpoly_preview.png"


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=DEFAULT_PREVIEW)
    parser.add_argument("--no-preview", action="store_true")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index : index + 2], 16) / 255.0 for index in range(0, 8, 2))


def make_material(name, color, roughness=0.8, metallic=0.0):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return material


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def finish(obj, material, bevel=0.0):
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("LowPolyEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def cube(name, location, dimensions, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.dimensions = dimensions
    apply_transform(obj)
    return finish(obj, material, bevel)


def cylinder(name, location, radius, depth, material, rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    apply_transform(obj)
    return finish(obj, material, bevel)


def create_front_window(prefix, x, z, materials):
    frame, glass = materials
    width = 1.82
    height = 1.72
    glass_width = 1.42
    glass_height = 1.30
    vertical_frame_height = height - 0.28
    objects = []

    objects.append(cube(prefix + "_Glass", (x, -7.005, z), (glass_width, 0.06, glass_height), glass, 0.012))
    frame_y = -7.045
    objects.extend(
        [
            cube(prefix + "_Frame_L", (x - 0.85, frame_y, z), (0.14, 0.08, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_R", (x + 0.85, frame_y, z), (0.14, 0.08, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_T", (x, frame_y, z + 0.79), (width, 0.08, 0.14), frame, 0.018),
            cube(prefix + "_Frame_B", (x, frame_y, z - 0.79), (width, 0.08, 0.14), frame, 0.018),
        ]
    )
    mullion_y = -7.10
    mullion_cross_y = -7.14
    objects.extend(
        [
            cube(prefix + "_Mullion_V", (x, mullion_y, z), (0.08, 0.04, glass_height), frame, 0.012),
            cube(prefix + "_Mullion_H", (x, mullion_cross_y, z), (glass_width, 0.04, 0.08), frame, 0.012),
        ]
    )
    return objects


def create_side_window(prefix, y, z, side, materials):
    frame, glass = materials
    width = 1.82
    height = 1.72
    glass_width = 1.42
    glass_height = 1.30
    vertical_frame_height = height - 0.28
    surface_x = -12.005 if side == "L" else 12.005
    frame_x = -12.045 if side == "L" else 12.045
    mullion_x = -12.10 if side == "L" else 12.10
    mullion_cross_x = -12.14 if side == "L" else 12.14
    objects = []

    objects.append(cube(prefix + "_Glass", (surface_x, y, z), (0.06, glass_width, glass_height), glass, 0.012))
    objects.extend(
        [
            cube(prefix + "_Frame_L", (frame_x, y - 0.85, z), (0.08, 0.14, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_R", (frame_x, y + 0.85, z), (0.08, 0.14, vertical_frame_height), frame, 0.018),
            cube(prefix + "_Frame_T", (frame_x, y, z + 0.79), (0.08, width, 0.14), frame, 0.018),
            cube(prefix + "_Frame_B", (frame_x, y, z - 0.79), (0.08, width, 0.14), frame, 0.018),
            cube(prefix + "_Mullion_V", (mullion_x, y, z), (0.04, 0.08, glass_height), frame, 0.012),
            cube(prefix + "_Mullion_H", (mullion_cross_x, y, z), (0.04, glass_width, 0.08), frame, 0.012),
        ]
    )
    return objects


def add_clock(parts, tower_front_y, materials):
    clock_face, clock_hand, clock_frame = materials
    center_y = tower_front_y - 0.08
    parts.append(
        cylinder(
            "Clock_Face",
            (0.0, center_y, 9.35),
            0.66,
            0.10,
            clock_face,
            rotation=(math.radians(90.0), 0.0, 0.0),
            vertices=16,
            bevel=0.015,
        )
    )
    parts.append(
        cylinder(
            "Clock_Center",
            (0.0, tower_front_y - 0.19, 9.35),
            0.08,
            0.04,
            clock_frame,
            rotation=(math.radians(90.0), 0.0, 0.0),
            vertices=12,
            bevel=0.008,
        )
    )
    parts.extend(
        [
            cube("Clock_Hand_Hour", (0.0, tower_front_y - 0.24, 9.58), (0.08, 0.04, 0.42), clock_hand, 0.008),
            cube("Clock_Hand_Minute", (0.18, tower_front_y - 0.28, 9.35), (0.36, 0.04, 0.08), clock_hand, 0.008),
        ]
    )


def aabb(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(point.x for point in corners), min(point.y for point in corners), min(point.z for point in corners)))
    maximum = Vector((max(point.x for point in corners), max(point.y for point in corners), max(point.z for point in corners)))
    return minimum, maximum


def overlap_volume(first, second):
    extent = overlap_extents(first, second)
    if extent is None:
        return 0.0
    return extent.x * extent.y * extent.z


def overlap_extents(first, second):
    first_min, first_max = aabb(first)
    second_min, second_max = aabb(second)
    extent = Vector(
        (
            min(first_max.x, second_max.x) - max(first_min.x, second_min.x),
            min(first_max.y, second_max.y) - max(first_min.y, second_min.y),
            min(first_max.z, second_max.z) - max(first_min.z, second_min.z),
        )
    )
    if min(extent.x, extent.y, extent.z) <= 0.00001:
        return None
    return extent


def validate_parts(parts):
    if not parts:
        raise RuntimeError("No school geometry was created")
    for obj in parts:
        if obj.type != "MESH":
            raise RuntimeError(f"Unexpected non-mesh part: {obj.name}")
        if min(abs(value) for value in obj.scale) < 0.000001:
            raise RuntimeError(f"Zero scale on {obj.name}")
        minimum, maximum = aabb(obj)
        if minimum.z < -0.03:
            raise RuntimeError(f"Part below ground: {obj.name} z={minimum.z:.4f}")

    overlaps = []
    for index, first in enumerate(parts):
        for second in parts[index + 1 :]:
            extent = overlap_extents(first, second)
            if extent is None:
                continue
            volume = extent.x * extent.y * extent.z
            if min(extent.x, extent.y, extent.z) > 0.045:
                overlaps.append((first.name, second.name, volume))
    if overlaps:
        preview = ", ".join(f"{first}/{second}={volume:.5f}" for first, second, volume in overlaps[:8])
        raise RuntimeError(f"Overlapping modules detected ({len(overlaps)}): {preview}")

    minimum = Vector((min(aabb(obj)[0].x for obj in parts), min(aabb(obj)[0].y for obj in parts), min(aabb(obj)[0].z for obj in parts)))
    maximum = Vector((max(aabb(obj)[1].x for obj in parts), max(aabb(obj)[1].y for obj in parts), max(aabb(obj)[1].z for obj in parts)))
    size = maximum - minimum
    if minimum.z > 0.0001 or minimum.z < -0.03:
        raise RuntimeError(f"School does not sit on ground: z_min={minimum.z:.5f}")
    if size.x < 23.0 or size.x > 27.0 or size.y < 15.0 or size.y > 19.0 or size.z < 9.5 or size.z > 11.5:
        raise RuntimeError(f"Unexpected school bounds: {tuple(round(value, 4) for value in size)}")
    print(
        "VALID modules=%d bounds_min=%s bounds_max=%s size=%s"
        % (
            len(parts),
            tuple(round(value, 4) for value in minimum),
            tuple(round(value, 4) for value in maximum),
            tuple(round(value, 4) for value in size),
        )
    )


def build_school():
    wall = make_material("MAT_School_Warm_Ochre", "#B88643", roughness=0.88)
    wall_shadow = make_material("MAT_School_Ochre_Shadow", "#8E6732", roughness=0.90)
    foundation = make_material("MAT_School_Concrete", "#69727A", roughness=0.92)
    trim = make_material("MAT_School_Cream_Trim", "#E7D5AD", roughness=0.78)
    roof = make_material("MAT_School_Charcoal_Roof", "#424B55", roughness=0.82, metallic=0.05)
    roof_edge = make_material("MAT_School_Roof_Edge", "#27313A", roughness=0.78, metallic=0.08)
    glass = make_material("MAT_School_Window_BlueGray", "#557B87", roughness=0.34, metallic=0.04)
    door = make_material("MAT_School_Door_DarkBlue", "#273F4B", roughness=0.76)
    clock_face = make_material("MAT_School_Clock_Face", "#F0EAD8", roughness=0.62)
    clock_hand = make_material("MAT_School_Clock_Hand", "#252B31", roughness=0.70, metallic=0.05)
    clock_frame = make_material("MAT_School_Clock_Frame", "#59646C", roughness=0.58, metallic=0.15)

    parts = []
    window_materials = (trim, glass)

    # Main body: a sealed shell keeps the building inaccessible without needing interior props.
    parts.extend(
        [
            cube("Foundation_Platform", (0.0, 0.0, 0.15), (24.8, 14.8, 0.30), foundation, 0.08),
            cube("Main_Building_Block", (0.0, 0.0, 3.80), (24.0, 14.0, 7.00), wall, 0.045),
            cube("Main_Base_Band", (0.0, -7.03, 0.76), (23.4, 0.10, 0.72), wall_shadow, 0.025),
            cube("Main_Floor_Band_Front", (0.0, -7.03, 3.58), (23.3, 0.10, 0.22), trim, 0.025),
            cube("Main_Floor_Band_Left", (-12.03, 0.0, 3.58), (0.10, 13.3, 0.22), trim, 0.025),
            cube("Main_Floor_Band_Right", (12.03, 0.0, 3.58), (0.10, 13.3, 0.22), trim, 0.025),
        ]
    )

    # Main flat roof and parapet, with every lower face exactly touching the support below.
    parts.extend(
        [
            cube("Main_Roof_Slab", (0.0, 0.0, 7.45), (24.6, 14.6, 0.32), roof, 0.045),
            cube("Main_Roof_Front_Parapet", (0.0, -7.21, 7.70), (24.1, 0.18, 0.20), roof_edge, 0.025),
            cube("Main_Roof_Back_Parapet", (0.0, 7.21, 7.70), (24.1, 0.18, 0.20), roof_edge, 0.025),
            cube("Main_Roof_Left_Parapet", (-12.21, 0.0, 7.70), (0.18, 14.1, 0.20), roof_edge, 0.025),
            cube("Main_Roof_Right_Parapet", (12.21, 0.0, 7.70), (0.18, 14.1, 0.20), roof_edge, 0.025),
        ]
    )

    # Symmetrical two-floor windows; each overlay is offset from the sealed wall to prevent z-fighting.
    front_xs = (-9.3, -6.2, -3.1, 3.1, 6.2, 9.3)
    for floor_index, z in enumerate((2.05, 5.25), start=1):
        for window_index, x in enumerate(front_xs, start=1):
            parts.extend(create_front_window(f"Front_Window_{floor_index}_{window_index}", x, z, window_materials))
        for window_index, y in enumerate((-4.3, 0.0, 4.3), start=1):
            parts.extend(create_side_window(f"Left_Window_{floor_index}_{window_index}", y, z, "L", window_materials))
            parts.extend(create_side_window(f"Right_Window_{floor_index}_{window_index}", y, z, "R", window_materials))

    # Front entrance, fully outside the sealed body and supported by a stepped foundation.
    parts.extend(
        [
            cube("Entry_Lower_Step", (0.0, -9.45, 0.07), (3.15, 0.52, 0.16), foundation, 0.035),
            cube("Entry_Upper_Step", (0.0, -8.95, 0.22), (3.15, 0.52, 0.16), foundation, 0.035),
            cube("Entry_Landing", (0.0, -7.95, 0.37), (4.70, 1.54, 0.18), foundation, 0.035),
            cube("Entry_Door", (0.0, -7.10, 1.65), (1.35, 0.08, 2.40), door, 0.025),
            cube("Entry_Door_Frame_L", (-0.78, -7.15, 1.65), (0.16, 0.06, 2.40), trim, 0.018),
            cube("Entry_Door_Frame_R", (0.78, -7.15, 1.65), (0.16, 0.06, 2.40), trim, 0.018),
            cube("Entry_Door_Frame_Top", (0.0, -7.15, 2.93), (1.72, 0.06, 0.16), trim, 0.018),
            cube("Entry_Door_Handle", (0.44, -7.20, 1.65), (0.10, 0.04, 0.10), trim, 0.012),
            cube("Entry_Post_L", (-2.00, -8.15, 1.80), (0.28, 0.28, 2.70), trim, 0.025),
            cube("Entry_Post_R", (2.00, -8.15, 1.80), (0.28, 0.28, 2.70), trim, 0.025),
            cube("Entry_Canopy", (0.0, -8.05, 3.24), (4.80, 1.50, 0.20), roof, 0.035),
            cube("Entry_Canopy_Edge", (0.0, -8.80, 3.40), (4.50, 0.12, 0.12), roof_edge, 0.018),
        ]
    )

    # Central clock tower rises from the main roof and remains a closed, non-enterable volume.
    parts.extend(
        [
            cube("Clock_Tower_Base", (0.0, 0.0, 8.00), (5.20, 4.40, 0.80), wall_shadow, 0.035),
            cube("Clock_Tower_Block", (0.0, 0.0, 9.25), (5.00, 4.20, 1.70), wall, 0.035),
            cube("Clock_Tower_Roof", (0.0, 0.0, 10.24), (5.30, 4.50, 0.30), roof, 0.035),
            cube("Clock_Tower_Roof_Front_Edge", (0.0, -2.28, 10.48), (5.18, 0.16, 0.18), roof_edge, 0.018),
            cube("Clock_Tower_Roof_Back_Edge", (0.0, 2.28, 10.48), (5.18, 0.16, 0.18), roof_edge, 0.018),
            cube("Clock_Tower_Roof_Left_Edge", (-2.68, 0.0, 10.48), (0.16, 4.35, 0.18), roof_edge, 0.018),
            cube("Clock_Tower_Roof_Right_Edge", (2.68, 0.0, 10.48), (0.16, 4.35, 0.18), roof_edge, 0.018),
        ]
    )
    add_clock(parts, -2.10, (clock_face, clock_hand, clock_frame))

    validate_parts(parts)
    return parts


def join_parts(parts):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = "FTF_Building_School_Ontario_LowPoly_24x16m"
    merged.data.name = "MESH_FTF_Building_School_Ontario_LowPoly_24x16m"
    merged.select_set(False)
    return merged


def render_preview(merged, path):
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (31.0, -34.0, 24.0)
    camera.rotation_euler = (Vector((0.0, 0.0, 4.7)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 52.0

    key_data = bpy.data.lights.new("PreviewKey", "AREA")
    key = bpy.data.objects.new("PreviewKey", key_data)
    bpy.context.collection.objects.link(key)
    key.location = (4.0, -12.0, 28.0)
    key.data.energy = 1800.0
    key.data.shape = "DISK"
    key.data.size = 18.0
    key.rotation_euler = (Vector((0.0, 0.0, 3.0)) - key.location).to_track_quat("-Z", "Y").to_euler()

    fill_data = bpy.data.lights.new("PreviewFill", "AREA")
    fill = bpy.data.objects.new("PreviewFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-22.0, 8.0, 16.0)
    fill.data.energy = 900.0
    fill.data.size = 14.0
    fill.rotation_euler = (Vector((0.0, 0.0, 3.0)) - fill.location).to_track_quat("-Z", "Y").to_euler()

    ground_material = make_material("MAT_Preview_Ground", "#B8C0C5", roughness=0.95)
    ground = cube("Preview_Ground", (0.0, 0.0, -0.06), (44.0, 42.0, 0.12), ground_material, 0.0)
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.world.color = (0.055, 0.075, 0.095)
    bpy.context.view_layer.objects.active = merged
    merged.select_set(True)
    ground.select_set(False)
    bpy.ops.render.render(write_still=True)
    merged.select_set(False)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.objects.remove(key, do_unlink=True)
    bpy.data.objects.remove(fill, do_unlink=True)
    bpy.data.objects.remove(ground, do_unlink=True)


def export_glb(merged, path):
    output_dir = os.path.dirname(os.path.abspath(path))
    os.makedirs(output_dir, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    merged.select_set(True)
    bpy.context.view_layer.objects.active = merged
    bpy.ops.export_scene.gltf(
        filepath=os.path.abspath(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    merged.select_set(False)


def main():
    args = parse_args()
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    parts = build_school()
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
