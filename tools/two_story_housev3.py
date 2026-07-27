# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - Two-Story North American House (Enterable, Interior Ramps)
#
# Generates one GLB:
#   FTF_House_NorthAmerican_TwoStory_Ramp.glb
#
# DESIGN
# - Enterable two-story North American residential house
# - Front and rear doors are separate openable mesh nodes
# - Door widths are slightly larger than previous small-building doors
# - Interior contains two walkable ramp segments:
#     1) first ramp from first floor to a half-level landing
#     2) second ramp turns and continues to the second floor
#   This simulates a turning stair circulation using gentle ramps
#   in the 15-25 degree range.
# - Empty playable interior (no furniture)
# - Real wall openings for doors and windows
# - Static meshes are merged on export except the openable doors
#
# OUTPUT
#   generated_farmtown_buildings/FTF_House_NorthAmerican_TwoStory_Ramp.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_two_story_house_ramp_v3.py
# ---------------------------------------------------------------------

import bpy
import bmesh
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# PATHS / EXPORT
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_buildings")
OUTPUT_FILE = "FTF_House_NorthAmerican_TwoStory_Ramp_v3.glb"

ROOT_NAME = "FTF_House_NorthAmerican_TwoStory_Ramp_v3"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True


# ---------------------------------------------------------------------
# DIMENSIONS
# ---------------------------------------------------------------------

FOUNDATION_H = 0.28
GROUND_FLOOR_T = 0.10
UPPER_FLOOR_T = 0.10

HOUSE_W = 11.8   # X
HOUSE_D = 9.6    # Y
WALL_T = 0.18

FIRST_WALL_H = 3.25
SECOND_WALL_H = 3.05

ROOF_RISE = 2.55
ROOF_OVERHANG = 0.34

# Doors
FRONT_DOOR_W = 1.60
FRONT_DOOR_H = 2.35
BACK_DOOR_W = 1.35
BACK_DOOR_H = 2.22
DOOR_T = 0.07

# Windows
LOWER_WINDOW_W = 1.35
LOWER_WINDOW_H = 1.55
LOWER_WINDOW_BOTTOM = FOUNDATION_H + 0.80

UPPER_WINDOW_W = 1.20
UPPER_WINDOW_H = 1.35
UPPER_WINDOW_BOTTOM = FOUNDATION_H + FIRST_WALL_H + UPPER_FLOOR_T + 0.78

WINDOW_GLASS_T = 0.025

# Interior circulation
TARGET_SECOND_FLOOR_Z = FOUNDATION_H + FIRST_WALL_H + UPPER_FLOOR_T  # finished second-floor walking surface
HALF_LEVEL_Z = TARGET_SECOND_FLOOR_Z * 0.5

RAMP_WIDTH = 1.65
RAMP_THICKNESS = 0.16
LANDING_W = 2.10
LANDING_D = 2.10

# Each ramp rises about half the floor-to-floor height
RAMP_RISE_1 = HALF_LEVEL_Z
RAMP_RISE_2 = TARGET_SECOND_FLOOR_Z - HALF_LEVEL_Z
RAMP_ANGLE_DEG = 22.0
RAMP_ANGLE_RAD = math.radians(RAMP_ANGLE_DEG)
RAMP_RUN_1 = RAMP_RISE_1 / math.tan(RAMP_ANGLE_RAD)
RAMP_RUN_2 = RAMP_RISE_2 / math.tan(RAMP_ANGLE_RAD)

# Porch
PORCH_W = 3.0
PORCH_D = 1.55
PORCH_POST_H = 2.55


# ---------------------------------------------------------------------
# SCENE HELPERS
# ---------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def configure_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def get_or_create_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for poly in obj.data.polygons:
        poly.use_smooth = False


def add_bevel(obj, width=0.012):
    mod = obj.modifiers.new("LowPolyBevel", "BEVEL")
    mod.width = width
    mod.segments = 1
    mod.limit_method = "ANGLE"
    return mod


def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for mod in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError as exc:
            print(f"[WARN] Could not apply modifier {mod.name} on {obj.name}: {exc}")


# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_material(name, color, roughness=0.76, metallic=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, alpha)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "surface_render_method"):
            try:
                enum_items = mat.bl_rna.properties["surface_render_method"].enum_items.keys()
                if "BLENDED" in enum_items:
                    mat.surface_render_method = "BLENDED"
                elif "DITHERED" in enum_items:
                    mat.surface_render_method = "DITHERED"
            except Exception as exc:
                print(f"[WARN] Could not set surface_render_method on {name}: {exc}")
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build_materials():
    return {
        "foundation": make_material("MAT_House_Foundation", (0.32, 0.32, 0.33), 0.88),
        "floor": make_material("MAT_House_Floor", (0.47, 0.34, 0.23), 0.86),
        "wall": make_material("MAT_House_Siding", (0.84, 0.83, 0.79), 0.82),
        "wall_accent": make_material("MAT_House_Accent", (0.70, 0.74, 0.79), 0.80),
        "trim": make_material("MAT_House_Trim", (0.93, 0.92, 0.88), 0.72),
        "roof": make_material("MAT_House_Roof", (0.40, 0.17, 0.12), 0.78),
        "roof_dark": make_material("MAT_House_RoofDark", (0.14, 0.12, 0.10), 0.82),
        "door": make_material("MAT_House_Door", (0.26, 0.16, 0.09), 0.82),
        "glass": make_material("MAT_House_Glass", (0.10, 0.16, 0.20), 0.18, 0.03, alpha=0.45),
        "metal": make_material("MAT_House_Metal", (0.20, 0.20, 0.22), 0.70),
        "porch": make_material("MAT_House_Porch", (0.58, 0.45, 0.32), 0.84),
        "railing": make_material("MAT_House_Railing", (0.90, 0.89, 0.84), 0.74),
    }


# ---------------------------------------------------------------------
# BASIC GEOMETRY
# ---------------------------------------------------------------------

def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.80
    root["asset_type"] = "EnterableBuilding"
    root["visual_forward_axis"] = "-Y"
    root["up_axis"] = "+Z"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = True
    root["front_door_node"] = "Door_Front"
    root["back_door_node"] = "Door_Back"
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES
    collection.objects.link(root)
    return root


def add_oriented_box(name, center_xy, z_center, len_x, depth_y, height_z, angle_z, material, parent, collection, bevel=0.0, no_merge=False):
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(center_xy.x, center_xy.y, z_center),
        rotation=(0.0, 0.0, angle_z),
    )
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (len_x, depth_y, height_z)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj.parent = parent
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def add_cube(name, location, dimensions, material, parent, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), no_merge=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj.parent = parent
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def create_polygon_prism(name, points_xy, z0, z1, material, parent, collection, bevel=0.0):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm = bmesh.new()

    verts_bottom = [bm.verts.new((p.x, p.y, z0)) for p in points_xy]
    face = bm.faces.new(verts_bottom)
    ret = bmesh.ops.extrude_face_region(bm, geom=[face])
    verts_extruded = [ele for ele in ret["geom"] if isinstance(ele, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts_extruded, vec=Vector((0.0, 0.0, z1 - z0)))

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    return obj


def add_gable_triangle(name, center_x, center_y, thickness_y, width_x, wall_top_z, ridge_z, material, parent, collection):
    half_w = width_x * 0.5
    front_y = center_y - thickness_y * 0.5
    back_y = center_y + thickness_y * 0.5
    verts = [
        (center_x - half_w, front_y, wall_top_z),
        (center_x + half_w, front_y, wall_top_z),
        (center_x,          front_y, ridge_z),
        (center_x - half_w, back_y, wall_top_z),
        (center_x + half_w, back_y, wall_top_z),
        (center_x,          back_y, ridge_z),
    ]
    faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    return obj


def edge_data(p0, p1):
    v = Vector((p1.x - p0.x, p1.y - p0.y, 0.0))
    length = v.length
    t = v.normalized()
    n = Vector((t.y, -t.x, 0.0))  # outward for CCW
    angle = math.atan2(t.y, t.x)
    return length, t, n, angle


def point_on_edge(p0, p1, d_along, offset_normal=0.0):
    length, t, n, _ = edge_data(p0, p1)
    return Vector((p0.x, p0.y, 0.0)) + t * d_along + n * offset_normal


def set_origin_to_world_point(obj, point):
    scene = bpy.context.scene
    old_cursor = scene.cursor.location.copy()
    scene.cursor.location = point
    set_active(obj)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    scene.cursor.location = old_cursor


# ---------------------------------------------------------------------
# WALLS WITH REAL OPENINGS
# ---------------------------------------------------------------------

def build_wall_with_openings(prefix, p0, p1, z_bottom, wall_height, wall_thickness, openings, material, parent, collection, bevel=0.008):
    """
    openings: list of dicts:
      center, width, bottom, height
      bottom/height are absolute world z coordinates.
    """
    length, t, n, angle = edge_data(p0, p1)

    openings = sorted(openings, key=lambda o: o["center"])
    intervals = {0.0, length}
    for op in openings:
        intervals.add(op["center"] - op["width"] * 0.5)
        intervals.add(op["center"] + op["width"] * 0.5)
    xs = sorted(intervals)

    piece_index = 0
    for i in range(len(xs) - 1):
        a = xs[i]
        b = xs[i + 1]
        if b - a <= 1e-6:
            continue
        mid = (a + b) * 0.5
        active = None
        for op in openings:
            lo = op["center"] - op["width"] * 0.5
            hi = op["center"] + op["width"] * 0.5
            if lo <= mid <= hi:
                active = op
                break

        center = point_on_edge(p0, p1, mid, 0.0)

        if active is None:
            add_oriented_box(
                f"{prefix}_Full_{piece_index}",
                center,
                z_bottom + wall_height * 0.5,
                b - a,
                wall_thickness,
                wall_height,
                angle,
                material, parent, collection, bevel=bevel
            )
            piece_index += 1
        else:
            lower_h = active["bottom"] - z_bottom
            if lower_h > 0.001:
                add_oriented_box(
                    f"{prefix}_Lower_{piece_index}",
                    center,
                    z_bottom + lower_h * 0.5,
                    b - a,
                    wall_thickness,
                    lower_h,
                    angle,
                    material, parent, collection, bevel=bevel
                )
                piece_index += 1

            top = active["bottom"] + active["height"]
            upper_h = z_bottom + wall_height - top
            if upper_h > 0.001:
                add_oriented_box(
                    f"{prefix}_Upper_{piece_index}",
                    center,
                    top + upper_h * 0.5,
                    b - a,
                    wall_thickness,
                    upper_h,
                    angle,
                    material, parent, collection, bevel=bevel
                )
                piece_index += 1


def add_glass_in_opening(name, p0, p1, center_d, width_along, bottom_z, height, material, parent, collection):
    _, _, _, angle = edge_data(p0, p1)
    center = point_on_edge(p0, p1, center_d, 0.0)
    add_oriented_box(
        name,
        center,
        bottom_z + height * 0.5,
        max(0.06, width_along - 0.12),
        WINDOW_GLASS_T,
        max(0.06, height - 0.12),
        angle,
        material, parent, collection, bevel=0.002
    )


def add_window_frames(name, p0, p1, center_d, width_along, bottom_z, height, mats, parent, collection):
    _, _, _, angle = edge_data(p0, p1)
    trim_w = 0.10
    trim_d = 0.055
    out_off = -(WALL_T * 0.5 + trim_d * 0.35)
    in_off = +(WALL_T * 0.5 + trim_d * 0.35)

    for side_name, off in (("Outer", out_off), ("Inner", in_off)):
        add_oriented_box(
            f"{name}_{side_name}_Top",
            point_on_edge(p0, p1, center_d, off),
            bottom_z + height - trim_w * 0.5,
            width_along + trim_w * 2,
            trim_d,
            trim_w,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )
        add_oriented_box(
            f"{name}_{side_name}_Bottom",
            point_on_edge(p0, p1, center_d, off),
            bottom_z + trim_w * 0.5,
            width_along + trim_w * 2,
            trim_d,
            trim_w,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )
        add_oriented_box(
            f"{name}_{side_name}_Left",
            point_on_edge(p0, p1, center_d - width_along * 0.5 + trim_w * 0.5, off),
            bottom_z + height * 0.5,
            trim_w,
            trim_d,
            height,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )
        add_oriented_box(
            f"{name}_{side_name}_Right",
            point_on_edge(p0, p1, center_d + width_along * 0.5 - trim_w * 0.5, off),
            bottom_z + height * 0.5,
            trim_w,
            trim_d,
            height,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )


def add_door_frame(name, p0, p1, center_d, width_along, bottom_z, height, mats, parent, collection):
    _, _, _, angle = edge_data(p0, p1)
    trim_w = 0.11
    trim_d = 0.06
    out_off = -(WALL_T * 0.5 + trim_d * 0.35)
    in_off = +(WALL_T * 0.5 + trim_d * 0.35)

    for side_name, off in (("Outer", out_off), ("Inner", in_off)):
        add_oriented_box(
            f"{name}_{side_name}_Top",
            point_on_edge(p0, p1, center_d, off),
            bottom_z + height + trim_w * 0.5,
            width_along + trim_w * 2,
            trim_d,
            trim_w,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )
        add_oriented_box(
            f"{name}_{side_name}_Left",
            point_on_edge(p0, p1, center_d - width_along * 0.5 + trim_w * 0.5, off),
            bottom_z + height * 0.5,
            trim_w,
            trim_d,
            height + trim_w,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )
        add_oriented_box(
            f"{name}_{side_name}_Right",
            point_on_edge(p0, p1, center_d + width_along * 0.5 - trim_w * 0.5, off),
            bottom_z + height * 0.5,
            trim_w,
            trim_d,
            height + trim_w,
            angle,
            mats["trim"], parent, collection, bevel=0.003
        )


def add_hinged_door(name, p0, p1, center_d, width_along, height, thickness, bottom_z, material, parent, collection, hinge="left"):
    _, _, _, angle = edge_data(p0, p1)
    center = point_on_edge(p0, p1, center_d, 0.0)
    obj = add_oriented_box(
        name,
        center,
        bottom_z + height * 0.5,
        width_along,
        thickness,
        height,
        angle,
        material, parent, collection,
        bevel=0.006, no_merge=True
    )
    if hinge == "left":
        hinge_d = center_d - width_along * 0.5
    else:
        hinge_d = center_d + width_along * 0.5

    hinge_point = point_on_edge(p0, p1, hinge_d, 0.0)
    hinge_point.z = bottom_z + height * 0.5
    set_origin_to_world_point(obj, hinge_point)

    obj["is_door"] = True
    obj["hinge"] = hinge
    return obj


# ---------------------------------------------------------------------
# BUILD HOUSE
# ---------------------------------------------------------------------

def build_house():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    left = -HOUSE_W * 0.5
    right = HOUSE_W * 0.5
    front = -HOUSE_D * 0.5
    back = HOUSE_D * 0.5

    A = Vector((left, front, 0.0))
    B = Vector((right, front, 0.0))
    C = Vector((right, back, 0.0))
    D = Vector((left, back, 0.0))

    footprint = [A, B, C, D]

    # Foundation
    create_polygon_prism("Foundation", footprint, 0.0, FOUNDATION_H, mats["foundation"], root, collection, bevel=0.018)

    # Ground floor (slightly inset)
    inset = 0.10
    ground_floor_poly = [
        Vector((left + inset, front + inset, 0.0)),
        Vector((right - inset, front + inset, 0.0)),
        Vector((right - inset, back - inset, 0.0)),
        Vector((left + inset, back - inset, 0.0)),
    ]
    create_polygon_prism("GroundFloor", ground_floor_poly, FOUNDATION_H, FOUNDATION_H + GROUND_FLOOR_T, mats["floor"], root, collection, bevel=0.004)

    # Second floor slab with a right-side front opening for the ramp system.
    # The ramp sits to the RIGHT of the front door, first rising forward (+Y),
    # then turning LEFT (-X) toward the second-floor level.
    upper_z0 = FOUNDATION_H + FIRST_WALL_H
    upper_z1 = upper_z0 + UPPER_FLOOR_T

    # house interior clearance with walls:
    clear_left = left + WALL_T
    clear_right = right - WALL_T
    clear_front = front + WALL_T
    clear_back = back - WALL_T

    # Opening / void zone for the ramp system.
    shaft_x0 = -1.30
    shaft_x1 = clear_right - 0.10
    shaft_y0 = clear_front + 0.25
    shaft_y1 = 2.60

    # Left slab spans the full depth up to the opening boundary.
    add_cube("UpperFloor_Left",
             ((clear_left + shaft_x0) * 0.5, (clear_front + clear_back) * 0.5, (upper_z0 + upper_z1) * 0.5),
             (shaft_x0 - clear_left, clear_back - clear_front, UPPER_FLOOR_T),
             mats["floor"], root, collection, bevel=0.004)

    # Rear-right slab behind the front opening.
    add_cube("UpperFloor_RearRight",
             ((shaft_x0 + shaft_x1) * 0.5, (shaft_y1 + clear_back) * 0.5, (upper_z0 + upper_z1) * 0.5),
             (shaft_x1 - shaft_x0, clear_back - shaft_y1, UPPER_FLOOR_T),
             mats["floor"], root, collection, bevel=0.004)

    # Exterior walls: first floor
    front_len = HOUSE_W
    back_len = HOUSE_W
    side_len = HOUSE_D

    # First floor openings
    front_openings = [
        {"center": front_len * 0.5, "width": FRONT_DOOR_W, "bottom": FOUNDATION_H, "height": FRONT_DOOR_H},
        {"center": 1.60, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
        {"center": front_len - 1.60, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
    ]
    back_openings = [
        {"center": back_len * 0.5, "width": BACK_DOOR_W, "bottom": FOUNDATION_H, "height": BACK_DOOR_H},
        {"center": 1.80, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
        {"center": back_len - 1.80, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
    ]
    left_openings = [
        {"center": 2.10, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
        {"center": side_len - 2.10, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
    ]
    right_openings = [
        {"center": 2.10, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
        {"center": side_len - 2.10, "width": LOWER_WINDOW_W, "bottom": LOWER_WINDOW_BOTTOM, "height": LOWER_WINDOW_H},
    ]

    build_wall_with_openings("Wall1_Front", A, B, FOUNDATION_H, FIRST_WALL_H, WALL_T, front_openings, mats["wall"], root, collection)
    build_wall_with_openings("Wall1_Right", B, C, FOUNDATION_H, FIRST_WALL_H, WALL_T, right_openings, mats["wall"], root, collection)
    build_wall_with_openings("Wall1_Back", D, C, FOUNDATION_H, FIRST_WALL_H, WALL_T, back_openings, mats["wall"], root, collection)
    build_wall_with_openings("Wall1_Left", D, A, FOUNDATION_H, FIRST_WALL_H, WALL_T, left_openings, mats["wall"], root, collection)

    # Exterior walls: second floor
    second_z = upper_z0
    front_openings_2 = [
        {"center": 2.05, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": front_len * 0.5, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": front_len - 2.05, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
    ]
    back_openings_2 = [
        {"center": 2.05, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": back_len * 0.5, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": back_len - 2.05, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
    ]
    left_openings_2 = [
        {"center": 2.30, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": side_len - 2.30, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
    ]
    right_openings_2 = [
        {"center": 2.30, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
        {"center": side_len - 2.30, "width": UPPER_WINDOW_W, "bottom": UPPER_WINDOW_BOTTOM, "height": UPPER_WINDOW_H},
    ]

    build_wall_with_openings("Wall2_Front", A, B, second_z, SECOND_WALL_H, WALL_T, front_openings_2, mats["wall"], root, collection)
    build_wall_with_openings("Wall2_Right", B, C, second_z, SECOND_WALL_H, WALL_T, right_openings_2, mats["wall"], root, collection)
    build_wall_with_openings("Wall2_Back", D, C, second_z, SECOND_WALL_H, WALL_T, back_openings_2, mats["wall"], root, collection)
    build_wall_with_openings("Wall2_Left", D, A, second_z, SECOND_WALL_H, WALL_T, left_openings_2, mats["wall"], root, collection)

    # Glass + window frames
    for center in [1.60, front_len - 1.60]:
        add_glass_in_opening(f"Glass_Front_L1_{center:.2f}", A, B, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Front_L1_{center:.2f}", A, B, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats, root, collection)
    for center in [1.80, back_len - 1.80]:
        add_glass_in_opening(f"Glass_Back_L1_{center:.2f}", D, C, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Back_L1_{center:.2f}", D, C, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats, root, collection)
    for center in [2.10, side_len - 2.10]:
        add_glass_in_opening(f"Glass_Left_L1_{center:.2f}", D, A, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Left_L1_{center:.2f}", D, A, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats, root, collection)
        add_glass_in_opening(f"Glass_Right_L1_{center:.2f}", B, C, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Right_L1_{center:.2f}", B, C, center, LOWER_WINDOW_W, LOWER_WINDOW_BOTTOM, LOWER_WINDOW_H, mats, root, collection)

    for center in [2.05, front_len * 0.5, front_len - 2.05]:
        add_glass_in_opening(f"Glass_Front_L2_{center:.2f}", A, B, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Front_L2_{center:.2f}", A, B, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats, root, collection)
        add_glass_in_opening(f"Glass_Back_L2_{center:.2f}", D, C, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Back_L2_{center:.2f}", D, C, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats, root, collection)
    for center in [2.30, side_len - 2.30]:
        add_glass_in_opening(f"Glass_Left_L2_{center:.2f}", D, A, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Left_L2_{center:.2f}", D, A, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats, root, collection)
        add_glass_in_opening(f"Glass_Right_L2_{center:.2f}", B, C, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats["glass"], root, collection)
        add_window_frames(f"Frame_Right_L2_{center:.2f}", B, C, center, UPPER_WINDOW_W, UPPER_WINDOW_BOTTOM, UPPER_WINDOW_H, mats, root, collection)

    # Doors
    front_door_center = front_len * 0.5
    back_door_center = back_len * 0.5
    add_hinged_door("Door_Front", A, B, front_door_center, FRONT_DOOR_W, FRONT_DOOR_H, DOOR_T, FOUNDATION_H, mats["door"], root, collection, hinge="left")
    add_hinged_door("Door_Back", D, C, back_door_center, BACK_DOOR_W, BACK_DOOR_H, DOOR_T, FOUNDATION_H, mats["door"], root, collection, hinge="left")
    add_door_frame("Frame_DoorFront", A, B, front_door_center, FRONT_DOOR_W, FOUNDATION_H, FRONT_DOOR_H, mats, root, collection)
    add_door_frame("Frame_DoorBack", D, C, back_door_center, BACK_DOOR_W, FOUNDATION_H, BACK_DOOR_H, mats, root, collection)

    # Porch
    porch_y = front - PORCH_D * 0.5 - 0.08
    add_cube("PorchBase",
             (0.0, porch_y, 0.14),
             (PORCH_W, PORCH_D, 0.28),
             mats["foundation"], root, collection, bevel=0.014)
    add_cube("PorchDeck",
             (0.0, porch_y, FOUNDATION_H + 0.05),
             (PORCH_W - 0.10, PORCH_D - 0.10, 0.10),
             mats["porch"], root, collection, bevel=0.008)
    add_cube("PorchRoof",
             (0.0, front - PORCH_D + 0.28, FOUNDATION_H + 2.78),
             (PORCH_W + 0.28, PORCH_D + 0.12, 0.16),
             mats["roof"], root, collection, bevel=0.008)
    for idx, x in enumerate([-1.05, 1.05]):
        add_cube(f"PorchPost_{idx}",
                 (x, porch_y + 0.10, FOUNDATION_H + PORCH_POST_H * 0.5),
                 (0.20, 0.20, PORCH_POST_H),
                 mats["trim"], root, collection, bevel=0.004)

    # Roof
    wall2_top = second_z + SECOND_WALL_H
    ridge_z = wall2_top + ROOF_RISE
    half_span = HOUSE_W * 0.5 + ROOF_OVERHANG
    roof_depth = HOUSE_D + ROOF_OVERHANG * 2.0
    roof_len = math.sqrt(half_span ** 2 + ROOF_RISE ** 2) + 0.16
    pitch = math.atan2(ROOF_RISE, half_span)
    roof_center_z = wall2_top + ROOF_RISE * 0.5

    add_cube("Roof_Right",
             (half_span * 0.5, 0.0, roof_center_z),
             (roof_len, roof_depth, 0.22),
             mats["roof"], root, collection, bevel=0.012, rotation=(0.0, pitch, 0.0))
    add_cube("Roof_Left",
             (-half_span * 0.5, 0.0, roof_center_z),
             (roof_len, roof_depth, 0.22),
             mats["roof"], root, collection, bevel=0.012, rotation=(0.0, -pitch, 0.0))
    add_cube("Roof_Ridge",
             (0.0, 0.0, ridge_z + 0.04),
             (0.20, roof_depth + 0.04, 0.14),
             mats["roof_dark"], root, collection, bevel=0.006)
    add_gable_triangle("Gable_Front", 0.0, front - 0.01, 0.08, HOUSE_W, wall2_top, ridge_z, mats["wall_accent"], root, collection)
    add_gable_triangle("Gable_Back", 0.0, back + 0.01, 0.08, HOUSE_W, wall2_top, ridge_z, mats["wall_accent"], root, collection)

    # Interior ramp system
    # Final requested layout:
    # - placed to the RIGHT of the front door
    # - first ramp goes FORWARD (+Y)
    # - reaches a half-level landing
    # - then turns LEFT and rises toward the second floor (-X)
    ramp1_x = clear_right - 1.15
    ramp1_start_y = clear_front + 0.55
    ramp1_end_y = ramp1_start_y + RAMP_RUN_1

    add_cube("Ramp_1",
             (ramp1_x, (ramp1_start_y + ramp1_end_y) * 0.5, FOUNDATION_H + RAMP_RISE_1 * 0.5),
             (RAMP_WIDTH, math.sqrt(RAMP_RUN_1 ** 2 + RAMP_RISE_1 ** 2), RAMP_THICKNESS),
             mats["porch"], root, collection, bevel=0.006,
             rotation=(math.atan2(RAMP_RISE_1, RAMP_RUN_1), 0.0, 0.0))

    landing_x = clear_right - LANDING_W * 0.5 - 0.20
    landing_y = ramp1_end_y + LANDING_D * 0.5
    add_cube("RampLanding",
             (landing_x, landing_y, HALF_LEVEL_Z + RAMP_THICKNESS * 0.5),
             (LANDING_W, LANDING_D, RAMP_THICKNESS),
             mats["porch"], root, collection, bevel=0.006)

    # Ramp 2 turns LEFT and runs toward -X to reach the second floor.
    ramp2_low_x = landing_x - LANDING_W * 0.5
    ramp2_high_x = ramp2_low_x - RAMP_RUN_2
    ramp2_y = landing_y

    add_cube("Ramp_2",
             ((ramp2_low_x + ramp2_high_x) * 0.5, ramp2_y, HALF_LEVEL_Z + RAMP_RISE_2 * 0.5),
             (math.sqrt(RAMP_RUN_2 ** 2 + RAMP_RISE_2 ** 2), RAMP_WIDTH, RAMP_THICKNESS),
             mats["porch"], root, collection, bevel=0.006,
             rotation=(0.0, math.atan2(RAMP_RISE_2, RAMP_RUN_2), 0.0))

    # Upper landing platform where ramp 2 arrives.
    upper_landing_center_x = shaft_x0 + 0.75
    upper_landing_center_y = ramp2_y
    add_cube("UpperLanding",
             (upper_landing_center_x, upper_landing_center_y, TARGET_SECOND_FLOOR_Z + RAMP_THICKNESS * 0.5),
             (1.10, RAMP_WIDTH + 0.35, RAMP_THICKNESS),
             mats["porch"], root, collection, bevel=0.006)

    # Simple interior guardrails along exposed edges of ramp opening
    rail_z = FOUNDATION_H + FIRST_WALL_H + 0.55
    rail_post_h = 1.05

    # Left edge of upper opening
    add_cube("Rail_UpperOpening_Left",
             (shaft_x0 - 0.04, (shaft_y0 + shaft_y1) * 0.5, rail_z),
             (0.08, shaft_y1 - shaft_y0, 0.10),
             mats["railing"], root, collection, bevel=0.003)
    # Front edge of opening
    add_cube("Rail_UpperOpening_Front",
             ((shaft_x0 + shaft_x1) * 0.5, shaft_y0 - 0.04, rail_z),
             (shaft_x1 - shaft_x0, 0.08, 0.10),
             mats["railing"], root, collection, bevel=0.003)

    for idx, (x, y) in enumerate([
        (shaft_x0 - 0.04, shaft_y0),
        (shaft_x0 - 0.04, shaft_y1),
        (shaft_x1, shaft_y0 - 0.04),
        (shaft_x0, shaft_y0 - 0.04),
    ]):
        add_cube(f"RailPost_{idx}",
                 (x, y, FOUNDATION_H + FIRST_WALL_H + rail_post_h * 0.5),
                 (0.08, 0.08, rail_post_h),
                 mats["railing"], root, collection, bevel=0.002)

    # Exterior steps at back
    add_cube("BackStep",
             (0.0, back + 0.42, 0.10),
             (1.65, 0.52, 0.20),
             mats["foundation"], root, collection, bevel=0.010)

    return root


# ---------------------------------------------------------------------
# MERGE / VALIDATE / EXPORT
# ---------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def get_static_meshes_for_merge(root):
    result = []
    for obj in get_meshes_under_root(root):
        if obj.get("no_merge", False):
            continue
        result.append(obj)
    return result


def merge_static_meshes(root):
    meshes = get_static_meshes_for_merge(root)
    if not meshes:
        raise RuntimeError("No static meshes found to merge.")
    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = ROOT_NAME + "_Static"
    merged.parent = root
    merged["no_merge"] = False
    set_flat_shading(merged)
    return merged


def bbox_world(meshes):
    lows = []
    highs = []
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lows.append(p)
            highs.append(p)
    low = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
    high = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
    return low, high


def validate_asset(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root must remain at origin.")

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root.")

    front_door = bpy.data.objects.get("Door_Front")
    back_door = bpy.data.objects.get("Door_Back")
    if front_door is None or back_door is None:
        raise RuntimeError("VALIDATION FAILED: door nodes missing.")
    if not front_door.get("no_merge", False) or not back_door.get("no_merge", False):
        raise RuntimeError("VALIDATION FAILED: a door node was merged unexpectedly.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(bad_scene))

    if not (15.0 <= RAMP_ANGLE_DEG <= 25.0):
        raise RuntimeError(f"VALIDATION FAILED: ramp angle {RAMP_ANGLE_DEG} not in requested range.")

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0 or obj.scale.y < 0 or obj.scale.z < 0:
            failures.append("negative scale: " + obj.name)
    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    bpy.context.view_layer.update()
    low, high = bbox_world(meshes)
    dims = high - low

    if low.z < -0.02:
        raise RuntimeError(f"VALIDATION FAILED: geometry below ground ({low.z:.4f}m).")
    if low.z > 0.04:
        raise RuntimeError(f"VALIDATION FAILED: geometry floats above ground ({low.z:.4f}m).")

    tri_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tri_count += len(obj.data.loop_triangles)

    print(
        f"[VALID] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Ground min Z: {low.z:.4f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {tri_count}\n"
        f"  Enterable: True\n"
        f"  Ramp angle: {RAMP_ANGLE_DEG:.1f} degrees\n"
        f"  Front door width: {FRONT_DOOR_W:.2f}m\n"
        f"  Back door width: {BACK_DOOR_W:.2f}m\n"
    )


def select_for_export(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    select_for_export(root)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print(f"[EXPORT] {filepath}")


# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------

if __name__ == "__main__":
    print("\n=== Generating Two-Story North American House with Interior Ramps ===\n")

    root = build_house()

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - Enterable two-story house.")
    print(" - Front and back doors are separate openable nodes.")
    print(" - Interior circulation uses two ramp segments with a turning landing.")
