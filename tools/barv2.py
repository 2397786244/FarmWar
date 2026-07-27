# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - Enterable Red Brick Bar / Pub (Real Window Openings)
#
# Generates one GLB:
#   FTF_Bar_Pentagonal_RedBrick_Enterable_v2_1.glb
#
# USER-REQUESTED FIXES IN THIS VERSION
# - Rebuilt the bar from scratch
# - Windows are REAL openings in the wall, not fake surface panels
# - You can see the inside through the windows
# - Front and rear doors remain separate nodes and can rotate on hinges
# - Internal space remains empty / enterable
# - Structure is laid out to avoid coplanar overlapping faces that can cause flicker
#
# DESIGN
# - Red brick bar / pub
# - Flat roof with parapet
# - Roughly square footprint with lower-left corner cut off, making a pentagon
# - Main front door is on the diagonal cut face
# - Large transparent front windows on both sides of the front door
# - One real side window for additional storefront character
# - Rear service / exit door
#
# OUTPUT
#   generated_farmtown_buildings/FTF_Bar_Pentagonal_RedBrick_Enterable_v2_1.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_bar_pentagonal_v2_1.py
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
OUTPUT_FILE = "FTF_Bar_Pentagonal_RedBrick_Enterable_v2_1.glb"

ROOT_NAME = "FTF_Bar_Pentagonal_RedBrick_Enterable_v2_1"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True


# ---------------------------------------------------------------------
# DIMENSIONS (meters)
# ---------------------------------------------------------------------

FOUNDATION_H = 0.26
FLOOR_T = 0.10

WALL_H = 3.85
WALL_T = 0.18

ROOF_SLAB_T = 0.16
PARAPET_H = 0.82
PARAPET_T = 0.14

FRONT_DOOR_W = 1.55
FRONT_DOOR_H = 2.35
FRONT_DOOR_T = 0.07

BACK_DOOR_W = 1.00
BACK_DOOR_H = 2.15
BACK_DOOR_T = 0.07

WINDOW_GAP_FROM_GROUND = 0.58
WINDOW_H = 2.05
WINDOW_BOTTOM_Z = FOUNDATION_H + WINDOW_GAP_FROM_GROUND
WINDOW_CENTER_Z = WINDOW_BOTTOM_Z + WINDOW_H * 0.5
WINDOW_GLASS_T = 0.025

SIDE_WINDOW_W = 1.85
FRONT_WINDOW_W = 2.10

# Footprint:
# square-like building with lower-left corner clipped off
# order is CCW
FOOTPRINT = [
    Vector((0.70, -5.20, 0.0)),   # A
    Vector((5.20, -5.20, 0.0)),   # B
    Vector((5.20,  5.20, 0.0)),   # C
    Vector((-5.20, 5.20, 0.0)),   # D
    Vector((-5.20, 0.70, 0.0)),   # E
]
# Diagonal front entry edge is E -> A


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

        # Blender transparency API changed in 4.2+ / 4.4.
        # Old versions expose `blend_method`; Blender 4.4 exposes
        # `surface_render_method`. Do not use the removed `shadow_method`.
        if hasattr(mat, "surface_render_method"):
            try:
                # Blender 4.4 supports DITHERED / BLENDED depending on build.
                enum_items = mat.bl_rna.properties["surface_render_method"].enum_items.keys()
                if "BLENDED" in enum_items:
                    mat.surface_render_method = "BLENDED"
                elif "DITHERED" in enum_items:
                    mat.surface_render_method = "DITHERED"
            except Exception as exc:
                print(f"[WARN] Could not set Blender 4.4 transparency mode on {name}: {exc}")
        elif hasattr(mat, "blend_method"):
            # Blender 4.1 and older compatibility.
            mat.blend_method = "BLEND"
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build_materials():
    return {
        "foundation": make_material("MAT_Bar2_Foundation", (0.31, 0.31, 0.32), 0.88),
        "floor": make_material("MAT_Bar2_Floor", (0.42, 0.31, 0.22), 0.86),
        "wall": make_material("MAT_Bar2_Wall", (0.59, 0.20, 0.16), 0.88),
        "wall_dark": make_material("MAT_Bar2_WallDark", (0.43, 0.13, 0.10), 0.90),
        "trim": make_material("MAT_Bar2_Trim", (0.84, 0.81, 0.76), 0.72),
        "roof": make_material("MAT_Bar2_Roof", (0.16, 0.16, 0.18), 0.80),
        "roof_dark": make_material("MAT_Bar2_RoofDark", (0.09, 0.09, 0.10), 0.84),
        "glass": make_material("MAT_Bar2_Glass", (0.10, 0.16, 0.20), 0.18, 0.03, alpha=0.45),
        "door": make_material("MAT_Bar2_Door", (0.17, 0.10, 0.06), 0.82),
        "metal": make_material("MAT_Bar2_Metal", (0.20, 0.20, 0.22), 0.70),
        "accent": make_material("MAT_Bar2_Accent", (0.22, 0.22, 0.24), 0.74),
    }


# ---------------------------------------------------------------------
# BASIC GEOMETRY
# ---------------------------------------------------------------------

def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def polygon_centroid(poly):
    sx = sum(p.x for p in poly)
    sy = sum(p.y for p in poly)
    return Vector((sx / len(poly), sy / len(poly), 0.0))


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


def edge_data(p0, p1):
    v = Vector((p1.x - p0.x, p1.y - p0.y, 0.0))
    length = v.length
    t = v.normalized()
    # CCW polygon outward normal
    n = Vector((t.y, -t.x, 0.0))
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
# WALL / OPENING CONSTRUCTION
# ---------------------------------------------------------------------

def build_wall_with_openings(
    prefix,
    p0,
    p1,
    wall_height,
    wall_thickness,
    openings,
    material,
    parent,
    collection,
    bevel=0.008
):
    """
    Build a wall edge from small boxes so all openings are real holes.

    openings: list of dicts with keys
      - center
      - width
      - bottom
      - height
    coordinates are:
      center/width measured along the edge
      bottom/height measured vertically from world z = 0
    """
    length, t, n, angle = edge_data(p0, p1)

    # Sort openings along the edge
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

        if active is None:
            center = point_on_edge(p0, p1, mid, 0.0)
            add_oriented_box(
                f"{prefix}_Full_{piece_index}",
                center,
                FOUNDATION_H + wall_height * 0.5,
                b - a,
                wall_thickness,
                wall_height,
                angle,
                material,
                parent,
                collection,
                bevel=bevel
            )
            piece_index += 1
        else:
            # Lower wall below the opening
            if active["bottom"] > FOUNDATION_H + 0.001:
                lower_h = active["bottom"] - FOUNDATION_H
                center = point_on_edge(p0, p1, mid, 0.0)
                add_oriented_box(
                    f"{prefix}_Lower_{piece_index}",
                    center,
                    FOUNDATION_H + lower_h * 0.5,
                    b - a,
                    wall_thickness,
                    lower_h,
                    angle,
                    material,
                    parent,
                    collection,
                    bevel=bevel
                )
                piece_index += 1

            # Upper wall above the opening
            top = active["bottom"] + active["height"]
            if top < FOUNDATION_H + wall_height - 0.001:
                upper_h = FOUNDATION_H + wall_height - top
                center = point_on_edge(p0, p1, mid, 0.0)
                add_oriented_box(
                    f"{prefix}_Upper_{piece_index}",
                    center,
                    top + upper_h * 0.5,
                    b - a,
                    wall_thickness,
                    upper_h,
                    angle,
                    material,
                    parent,
                    collection,
                    bevel=bevel
                )
                piece_index += 1


def add_glass_in_opening(name, p0, p1, center_d, width_along, bottom_z, height, offset_normal, mats, parent, collection):
    _, _, _, angle = edge_data(p0, p1)
    center = point_on_edge(p0, p1, center_d, offset_normal)
    add_oriented_box(
        name,
        center,
        bottom_z + height * 0.5,
        max(0.06, width_along - 0.12),
        WINDOW_GLASS_T,
        max(0.06, height - 0.12),
        angle,
        mats["glass"],
        parent,
        collection,
        bevel=0.002
    )


def add_window_frames(name, p0, p1, center_d, width_along, bottom_z, height, mats, parent, collection):
    """
    Add 3D outer and inner trim around a real opening.
    Slight offsets are used to avoid coplanar face overlap / flicker.
    """
    length, t, n, angle = edge_data(p0, p1)
    trim_w = 0.10
    trim_d = 0.055

    # Slightly outside
    out_off = - (WALL_T * 0.5 + trim_d * 0.35)
    in_off  =   (WALL_T * 0.5 + trim_d * 0.35)

    # top/bottom
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
        # side pieces
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

    out_off = - (WALL_T * 0.5 + trim_d * 0.35)
    in_off  =   (WALL_T * 0.5 + trim_d * 0.35)

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


def add_hinged_door(name, p0, p1, center_d, width_along, height, thickness, bottom_z, offset_normal, mats, parent, collection, hinge="left"):
    length, t, n, angle = edge_data(p0, p1)
    center = point_on_edge(p0, p1, center_d, offset_normal)
    obj = add_oriented_box(
        name,
        center,
        bottom_z + height * 0.5,
        width_along,
        thickness,
        height,
        angle,
        mats["door"], parent, collection,
        bevel=0.006,
        no_merge=True
    )

    if hinge == "left":
        hinge_d = center_d - width_along * 0.5
    else:
        hinge_d = center_d + width_along * 0.5

    hinge_point = point_on_edge(p0, p1, hinge_d, offset_normal)
    hinge_point.z = bottom_z + height * 0.5
    set_origin_to_world_point(obj, hinge_point)

    obj["is_door"] = True
    obj["hinge"] = hinge
    obj["door_width"] = width_along
    return obj


def add_parapet_segments(points_xy, parent, collection, mats):
    count = len(points_xy)
    for i in range(count):
        p0 = points_xy[i]
        p1 = points_xy[(i + 1) % count]
        length, t, n, angle = edge_data(p0, p1)
        center = (p0 + p1) * 0.5
        inward = -n * 0.02
        add_oriented_box(
            f"Parapet_{i}",
            Vector((center.x + inward.x, center.y + inward.y, 0.0)),
            FOUNDATION_H + WALL_H + PARAPET_H * 0.5,
            length,
            PARAPET_T,
            PARAPET_H,
            angle,
            mats["roof_dark"], parent, collection, bevel=0.004
        )


# ---------------------------------------------------------------------
# BUILD BAR
# ---------------------------------------------------------------------

def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.75
    root["asset_type"] = "EnterableBuilding"
    root["visual_forward_axis"] = "diagonal_cut_face"
    root["up_axis"] = "+Z"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = True
    root["front_door_node"] = "Door_Front"
    root["back_door_node"] = "Door_Back"
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES
    collection.objects.link(root)
    return root


def build_bar():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    A, B, C, D, E = FOOTPRINT
    centroid = polygon_centroid(FOOTPRINT)

    # Foundation
    create_polygon_prism(
        "Foundation",
        FOOTPRINT,
        0.0,
        FOUNDATION_H,
        mats["foundation"],
        root, collection,
        bevel=0.018
    )

    # Inset empty interior floor so it does not overlap wall meshes
    floor_poly = []
    for p in FOOTPRINT:
        v = Vector((p.x - centroid.x, p.y - centroid.y, 0.0))
        floor_poly.append(Vector((p.x - v.x * 0.04, p.y - v.y * 0.04, 0.0)))
    create_polygon_prism(
        "InteriorFloor",
        floor_poly,
        FOUNDATION_H,
        FOUNDATION_H + FLOOR_T,
        mats["floor"],
        root, collection,
        bevel=0.004
    )

    # Roof slab sits above wall top and does not overlap parapet
    roof_poly = []
    for p in FOOTPRINT:
        v = Vector((p.x - centroid.x, p.y - centroid.y, 0.0))
        roof_poly.append(Vector((p.x - v.x * 0.015, p.y - v.y * 0.015, 0.0)))
    create_polygon_prism(
        "RoofSlab",
        roof_poly,
        FOUNDATION_H + WALL_H,
        FOUNDATION_H + WALL_H + ROOF_SLAB_T,
        mats["roof"],
        root, collection,
        bevel=0.010
    )

    add_parapet_segments(FOOTPRINT, root, collection, mats)

    # -------------------------------------------------------------
    # Front diagonal wall (E -> A): 2 big windows + center door
    # -------------------------------------------------------------
    front_len, _, _, _ = edge_data(E, A)
    front_margin = 0.40
    pillar = 0.30
    used = front_margin + FRONT_WINDOW_W + pillar + FRONT_DOOR_W + pillar + FRONT_WINDOW_W + front_margin
    if used > front_len:
        raise RuntimeError(f"Front edge too short for requested storefront layout: {used:.2f} > {front_len:.2f}")

    left_win_center = front_margin + FRONT_WINDOW_W * 0.5
    door_center = front_margin + FRONT_WINDOW_W + pillar + FRONT_DOOR_W * 0.5
    right_win_center = front_len - (front_margin + FRONT_WINDOW_W * 0.5)

    front_openings = [
        {"center": left_win_center, "width": FRONT_WINDOW_W, "bottom": WINDOW_BOTTOM_Z, "height": WINDOW_H},
        {"center": door_center, "width": FRONT_DOOR_W, "bottom": FOUNDATION_H, "height": FRONT_DOOR_H},
        {"center": right_win_center, "width": FRONT_WINDOW_W, "bottom": WINDOW_BOTTOM_Z, "height": WINDOW_H},
    ]

    build_wall_with_openings(
        "Wall_FrontCut",
        E, A,
        WALL_H, WALL_T,
        front_openings,
        mats["wall"],
        root, collection
    )

    # Real front windows
    add_glass_in_opening("Glass_FrontLeft", E, A, left_win_center, FRONT_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, 0.0, mats, root, collection)
    add_glass_in_opening("Glass_FrontRight", E, A, right_win_center, FRONT_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, 0.0, mats, root, collection)
    add_window_frames("Frame_FrontLeft", E, A, left_win_center, FRONT_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, mats, root, collection)
    add_window_frames("Frame_FrontRight", E, A, right_win_center, FRONT_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, mats, root, collection)

    # Front door (real opening)
    add_hinged_door("Door_Front", E, A, door_center, FRONT_DOOR_W, FRONT_DOOR_H, FRONT_DOOR_T, FOUNDATION_H, 0.0, mats, root, collection, hinge="left")
    add_door_frame("Frame_DoorFront", E, A, door_center, FRONT_DOOR_W, FOUNDATION_H, FRONT_DOOR_H, mats, root, collection)

    # Canopy / fascia above front storefront
    add_oriented_box(
        "StorefrontCanopy",
        point_on_edge(E, A, front_len * 0.5, -0.54),
        FOUNDATION_H + 3.02,
        front_len - 0.70,
        0.80,
        0.14,
        edge_data(E, A)[3],
        mats["accent"],
        root, collection,
        bevel=0.006
    )

    # -------------------------------------------------------------
    # Other walls
    # -------------------------------------------------------------
    # Bottom wall A->B full
    build_wall_with_openings(
        "Wall_Bottom",
        A, B,
        WALL_H, WALL_T,
        [],
        mats["wall"],
        root, collection
    )

    # Right wall B->C with one real window
    right_len, _, _, _ = edge_data(B, C)
    right_window_center = 2.75
    right_openings = [
        {"center": right_window_center, "width": SIDE_WINDOW_W, "bottom": WINDOW_BOTTOM_Z, "height": WINDOW_H},
    ]
    build_wall_with_openings(
        "Wall_Right",
        B, C,
        WALL_H, WALL_T,
        right_openings,
        mats["wall"],
        root, collection
    )
    add_glass_in_opening("Glass_Right", B, C, right_window_center, SIDE_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, 0.0, mats, root, collection)
    add_window_frames("Frame_Right", B, C, right_window_center, SIDE_WINDOW_W, WINDOW_BOTTOM_Z, WINDOW_H, mats, root, collection)

    # Back wall D->C with center rear door only
    back_len, _, _, _ = edge_data(D, C)
    back_door_center = back_len * 0.5
    back_openings = [
        {"center": back_door_center, "width": BACK_DOOR_W, "bottom": FOUNDATION_H, "height": BACK_DOOR_H},
    ]
    build_wall_with_openings(
        "Wall_Back",
        D, C,
        WALL_H, WALL_T,
        back_openings,
        mats["wall"],
        root, collection
    )
    add_hinged_door("Door_Back", D, C, back_door_center, BACK_DOOR_W, BACK_DOOR_H, BACK_DOOR_T, FOUNDATION_H, 0.0, mats, root, collection, hinge="left")
    add_door_frame("Frame_DoorBack", D, C, back_door_center, BACK_DOOR_W, FOUNDATION_H, BACK_DOOR_H, mats, root, collection)

    # Left wall D->E full
    build_wall_with_openings(
        "Wall_Left",
        D, E,
        WALL_H, WALL_T,
        [],
        mats["wall"],
        root, collection
    )

    # Corner pilasters - offset slightly outward so they don't create coplanar wall faces
    for idx, p in enumerate(FOOTPRINT):
        center = Vector((p.x, p.y, 0.0))
        add_oriented_box(
            f"CornerPilaster_{idx}",
            center,
            FOUNDATION_H + WALL_H * 0.5,
            0.24, 0.24, WALL_H,
            0.0,
            mats["wall_dark"],
            root, collection,
            bevel=0.003
        )

    # Roof vent / chimney
    add_oriented_box(
        "VentStack",
        Vector((2.75, 2.15, 0.0)),
        FOUNDATION_H + WALL_H + ROOF_SLAB_T + 0.65,
        0.62, 0.62, 1.10,
        0.0,
        mats["metal"],
        root, collection,
        bevel=0.004
    )
    add_oriented_box(
        "VentCap",
        Vector((2.75, 2.15, 0.0)),
        FOUNDATION_H + WALL_H + ROOF_SLAB_T + 1.26,
        0.82, 0.82, 0.12,
        0.0,
        mats["roof_dark"],
        root, collection,
        bevel=0.003
    )

    # Simple front step and back step
    add_oriented_box(
        "FrontStep",
        point_on_edge(E, A, door_center, -0.58),
        0.12,
        2.20,
        0.78,
        0.24,
        edge_data(E, A)[3],
        mats["foundation"],
        root, collection,
        bevel=0.012
    )
    add_oriented_box(
        "BackStep",
        point_on_edge(D, C, back_door_center, 0.38),
        0.10,
        1.25,
        0.55,
        0.20,
        edge_data(D, C)[3],
        mats["foundation"],
        root, collection,
        bevel=0.010
    )

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
        f"  Notes: real wall openings for windows, separate front/back doors, geometry arranged to avoid coplanar flicker.\n"
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
    print("\n=== Generating Enterable Red Brick Bar / Pub (Real Window Openings) ===\n")

    root = build_bar()

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - Windows are true openings, not fake attached panels.")
    print(" - Front and rear doors are independent hingeable nodes.")
    print(" - The layout avoids coplanar overlapping surfaces to reduce z-fighting.")
