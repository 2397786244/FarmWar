# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - Large Closed House, Detached Family-Room Wing + Terrace
# V4: widened the main-house / family-wing connector; retains V3 overlap fixes and rear garage door.
#
# OUTPUT:
#   generated_farmtown_houses/FTF_House_Large_PorchTerrace_BrownRed_v3.glb
#
# KEY DESIGN RULES
# - Main house: one story, brown-red gable roof, horizontal wood clapboard walls.
# - Front: recessed closed entrance, small porch canopy, two white columns.
# - Attached family-room wing: physically separated from the main roof by a gap,
#   linked by a wide low enclosed connector beneath the main eave.
# - Terrace: sits above wing; terrace door is on a rooftop access block placed
#   far from the main roof, so there is no intersection with the main house.
# - Main rear facade: garage door replaces the old two rear windows.
# - Static, non-enterable model; no yard, collision shell, lights, cameras, or textures.
# - Visual front: local -Y. Root origin: ground center (0, 0, 0).
# - Static geometry is merged before GLB export.
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_large_house_v3.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# OUTPUT / CORE SETTINGS
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_houses")
OUTPUT_FILE = "FTF_House_Large_PorchTerrace_BrownRed_v4.glb"

ROOT_NAME = "FTF_House_Large_PorchTerrace_BrownRed_v4"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE_BEFORE_BUILD = True
JOIN_STATIC_MESHES_FOR_EXPORT = True

# ---------------------------------------------------------------------
# DIMENSIONS IN METERS
# ---------------------------------------------------------------------

FOUNDATION_H = 0.32

# Main house. Front is local -Y.
MAIN_CX = -2.40
MAIN_CY = 0.00
MAIN_W = 11.60
MAIN_D = 8.40
MAIN_WALL_H = 3.30
MAIN_ROOF_RISE = 2.10
MAIN_ROOF_OVERHANG = 0.45

# Recessed front entrance.
ENTRY_RECESS_W = 3.10
ENTRY_RECESS_D = 0.95
ENTRY_RECESS_H = 2.80
FRONT_DOOR_W = 1.30
FRONT_DOOR_H = 2.25

# Rear garage door on the main house. Back is local +Y.
GARAGE_W = 4.65
GARAGE_H = 2.45

# Family-room wing. It begins to the right of the main roof overhang.
# Main roof max X = MAIN_CX + MAIN_W/2 + MAIN_ROOF_OVERHANG = 3.85.
# Wing min X = 4.45, leaving a visible 0.60m gap before the connector.
WING_CX = 7.70
WING_CY = -0.70
WING_W = 6.50
WING_D = 6.00
WING_WALL_H = 3.05

# Low connector only: it touches wall faces but stays well below main roof/eave.
# Wide enclosed passage between main house and family-room wing.
# The passage runs along X, so CONNECTOR_D controls its usable width along Y.
# 3.20m reads as a comfortable two-player-wide connector in a third-person game.
CONNECTOR_CX = 3.92
CONNECTOR_CY = -0.35
CONNECTOR_W = 1.18
CONNECTOR_D = 3.20
CONNECTOR_H = 2.72

# Terrace / balcony above wing.
TERRACE_DECK_T = 0.14
TERRACE_RAIL_H = 1.05
TERRACE_RAIL_T = 0.09

# Rooftop terrace access block. It is deliberately placed at far-right/rear of wing.
ACCESS_W = 2.00
ACCESS_D = 1.60
ACCESS_H = 2.38
ACCESS_CX_OFFSET = 1.45
ACCESS_CY_OFFSET = 0.80
TERRACE_DOOR_W = 1.10
TERRACE_DOOR_H = 2.12

# Visual wall cladding.
BOARD_H = 0.20
BOARD_GAP = 0.07
BOARD_THICK = 0.045
BOARD_OUTSET = 0.028


# ---------------------------------------------------------------------
# SCENE / OBJECT HELPERS
# ---------------------------------------------------------------------

def clear_scene():
    """Clear scene first. Materials are created only after this function runs."""
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
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


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
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def set_flat_shading(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = False


def add_bevel(obj, width=0.02):
    modifier = obj.modifiers.new("LowPolyBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    return modifier


def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return

    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    for modifier in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError as exc:
            print(f"[WARN] Cannot apply {modifier.name} on {obj.name}: {exc}")


# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_material(name, color, roughness=0.72, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def build_materials():
    return {
        "foundation": make_material("MAT_FTF_FoundationStone", (0.29, 0.30, 0.29), 0.88),
        "wall": make_material("MAT_FTF_TanWoodPlank", (0.68, 0.55, 0.39), 0.84),
        "wall_dark": make_material("MAT_FTF_TanWoodShadow", (0.55, 0.43, 0.29), 0.86),
        "trim": make_material("MAT_FTF_WhiteTrim", (0.86, 0.85, 0.79), 0.70),
        "roof": make_material("MAT_FTF_BrownRedRoof", (0.42, 0.16, 0.10), 0.74),
        "roof_dark": make_material("MAT_FTF_RoofRidgeDark", (0.14, 0.13, 0.11), 0.76),
        "door": make_material("MAT_FTF_ClosedDoorDarkWood", (0.17, 0.09, 0.045), 0.78),
        "garage": make_material("MAT_FTF_GarageDoorMutedBrown", (0.31, 0.22, 0.14), 0.82),
        "window": make_material("MAT_FTF_WindowDarkBlue", (0.065, 0.14, 0.20), 0.34, 0.03),
        "chimney": make_material("MAT_FTF_BrickChimney", (0.39, 0.16, 0.10), 0.87),
        "terrace": make_material("MAT_FTF_TerraceWood", (0.46, 0.34, 0.24), 0.84),
    }


# ---------------------------------------------------------------------
# MESH PRIMITIVES
# ---------------------------------------------------------------------

def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_cube(
    name,
    location,
    dimensions,
    material,
    parent,
    collection,
    bevel=0.0,
    rotation=(0.0, 0.0, 0.0),
):
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
    move_to_collection(obj, collection)
    return obj


def add_gable_triangle(
    name,
    center_x,
    center_y,
    thickness_y,
    width_x,
    wall_top_z,
    ridge_z,
    material,
    parent,
    collection,
):
    half_width = width_x * 0.5
    front_y = center_y - thickness_y * 0.5
    back_y = center_y + thickness_y * 0.5

    verts = [
        (center_x - half_width, front_y, wall_top_z),
        (center_x + half_width, front_y, wall_top_z),
        (center_x, front_y, ridge_z),
        (center_x - half_width, back_y, wall_top_z),
        (center_x + half_width, back_y, wall_top_z),
        (center_x, back_y, ridge_z),
    ]
    faces = [
        (0, 2, 1),
        (3, 4, 5),
        (0, 1, 4, 3),
        (1, 2, 5, 4),
        (2, 0, 3, 5),
    ]

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    return obj


def boolean_cut_box(target, name, location, dimensions):
    """Cut a true recess/aperture into target; the cutter is deleted afterward."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    cutter = bpy.context.object
    cutter.name = name
    cutter.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    modifier = target.modifiers.new(name + "_Boolean", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter

    set_active(target)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


# ---------------------------------------------------------------------
# VISUAL DETAIL HELPERS
# ---------------------------------------------------------------------

def add_clapboard_front_back(
    prefix,
    center_x,
    width_x,
    y_face,
    outward_sign,
    z_start,
    height,
    mats,
    parent,
    collection,
):
    """Horizontal clapboard strips on a front/back facade section."""
    if width_x <= 0.02 or height <= 0.02:
        return

    pitch = BOARD_H + BOARD_GAP
    count = int((height - 0.10) / pitch) + 1

    for i in range(count):
        z = z_start + 0.12 + i * pitch
        if z + BOARD_H * 0.5 > z_start + height - 0.06:
            break

        add_cube(
            f"{prefix}_Board_{i:02d}",
            (center_x, y_face + outward_sign * BOARD_OUTSET, z),
            (width_x, BOARD_THICK, BOARD_H),
            mats["wall_dark"] if i % 2 else mats["wall"],
            parent,
            collection,
            bevel=0.003,
        )


def add_clapboard_side(
    prefix,
    x_face,
    outward_sign,
    center_y,
    depth_y,
    z_start,
    height,
    mats,
    parent,
    collection,
):
    """Horizontal clapboard strips on a left/right facade section."""
    if depth_y <= 0.02 or height <= 0.02:
        return

    pitch = BOARD_H + BOARD_GAP
    count = int((height - 0.10) / pitch) + 1

    for i in range(count):
        z = z_start + 0.12 + i * pitch
        if z + BOARD_H * 0.5 > z_start + height - 0.06:
            break

        add_cube(
            f"{prefix}_Board_{i:02d}",
            (x_face + outward_sign * BOARD_OUTSET, center_y, z),
            (BOARD_THICK, depth_y, BOARD_H),
            mats["wall_dark"] if i % 2 else mats["wall"],
            parent,
            collection,
            bevel=0.003,
        )


def add_front_window(name, x, y, z, width, height, mats, parent, collection):
    """Decorative sealed window panel and four-piece white frame, front/back facing."""
    panel_depth = 0.052
    trim_t = 0.12
    trim_depth = 0.070

    add_cube(name + "_Pane", (x, y, z), (width, panel_depth, height),
             mats["window"], parent, collection, bevel=0.009)

    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (width + trim_t * 2, trim_depth, trim_t),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (width + trim_t * 2, trim_depth, trim_t),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Left", (x - width * 0.5 + trim_t * 0.5, y, z),
             (trim_t, trim_depth, height),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Right", (x + width * 0.5 - trim_t * 0.5, y, z),
             (trim_t, trim_depth, height),
             mats["trim"], parent, collection, bevel=0.006)


def add_side_window(name, x, y, z, width_y, height, mats, parent, collection):
    """Decorative sealed window panel and frame, left/right facing."""
    panel_depth = 0.052
    trim_t = 0.12
    trim_depth = 0.070

    add_cube(name + "_Pane", (x, y, z), (panel_depth, width_y, height),
             mats["window"], parent, collection, bevel=0.009)

    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (trim_depth, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (trim_depth, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Near", (x, y - width_y * 0.5 + trim_t * 0.5, z),
             (trim_depth, trim_t, height),
             mats["trim"], parent, collection, bevel=0.006)
    add_cube(name + "_Far", (x, y + width_y * 0.5 - trim_t * 0.5, z),
             (trim_depth, trim_t, height),
             mats["trim"], parent, collection, bevel=0.006)


def add_closed_garage_door(name, cx, y, z_bottom, width, height, mats, parent, collection):
    """Sealed sectional garage door on outer back wall, with trim and horizontal seams."""
    panel_depth = 0.08
    center_z = z_bottom + height * 0.5

    add_cube(name + "_Panel", (cx, y, center_z), (width, panel_depth, height),
             mats["garage"], parent, collection, bevel=0.012)

    # Horizontal sections make the door read as a garage door rather than a plain wall.
    section_count = 5
    seam_h = 0.055
    for i in range(1, section_count):
        seam_z = z_bottom + height * (i / section_count)
        add_cube(name + f"_Seam_{i}", (cx, y - 0.045, seam_z),
                 (width - 0.12, 0.035, seam_h),
                 mats["door"], parent, collection, bevel=0.003)

    frame_t = 0.16
    frame_d = 0.105
    add_cube(name + "_FrameLeft", (cx - width * 0.5 - frame_t * 0.5, y, center_z),
             (frame_t, frame_d, height + 0.12), mats["trim"], parent, collection, bevel=0.007)
    add_cube(name + "_FrameRight", (cx + width * 0.5 + frame_t * 0.5, y, center_z),
             (frame_t, frame_d, height + 0.12), mats["trim"], parent, collection, bevel=0.007)
    add_cube(name + "_FrameTop", (cx, y, z_bottom + height + 0.07),
             (width + frame_t * 2, frame_d, frame_t), mats["trim"], parent, collection, bevel=0.007)


def add_terrace_railing(
    prefix,
    min_x,
    max_x,
    min_y,
    max_y,
    deck_top_z,
    mats,
    parent,
    collection,
):
    """Open white balustrade: rails plus spaced posts, not opaque wall blocks."""
    rail_center_z = deck_top_z + TERRACE_RAIL_H * 0.5
    top_rail_z = deck_top_z + TERRACE_RAIL_H - 0.07
    bottom_rail_z = deck_top_z + 0.18
    post_w = 0.11

    # Top and bottom perimeter rails.
    for label, y in (("Front", min_y), ("Back", max_y)):
        add_cube(prefix + "_" + label + "_Top", ((min_x + max_x) * 0.5, y, top_rail_z),
                 (max_x - min_x, TERRACE_RAIL_T, 0.11), mats["trim"], parent, collection, bevel=0.005)
        add_cube(prefix + "_" + label + "_Bottom", ((min_x + max_x) * 0.5, y, bottom_rail_z),
                 (max_x - min_x, TERRACE_RAIL_T, 0.09), mats["trim"], parent, collection, bevel=0.005)

    for label, x in (("Left", min_x), ("Right", max_x)):
        add_cube(prefix + "_" + label + "_Top", (x, (min_y + max_y) * 0.5, top_rail_z),
                 (TERRACE_RAIL_T, max_y - min_y, 0.11), mats["trim"], parent, collection, bevel=0.005)
        add_cube(prefix + "_" + label + "_Bottom", (x, (min_y + max_y) * 0.5, bottom_rail_z),
                 (TERRACE_RAIL_T, max_y - min_y, 0.09), mats["trim"], parent, collection, bevel=0.005)

    # Posts spaced at about 1.05m. Duplicates at corners are avoided with a set.
    points = set()

    def add_line_posts_x(y_value):
        count = max(2, int((max_x - min_x) / 1.05) + 1)
        for i in range(count + 1):
            t = i / count
            points.add((round(min_x + (max_x - min_x) * t, 4), round(y_value, 4)))

    def add_line_posts_y(x_value):
        count = max(2, int((max_y - min_y) / 1.05) + 1)
        for i in range(count + 1):
            t = i / count
            points.add((round(x_value, 4), round(min_y + (max_y - min_y) * t, 4)))

    add_line_posts_x(min_y)
    add_line_posts_x(max_y)
    add_line_posts_y(min_x)
    add_line_posts_y(max_x)

    for index, (px, py) in enumerate(sorted(points)):
        add_cube(prefix + f"_Post_{index:02d}",
                 (px, py, rail_center_z),
                 (post_w, post_w, TERRACE_RAIL_H),
                 mats["trim"], parent, collection, bevel=0.004)


# ---------------------------------------------------------------------
# LAYOUT CHECKS
# ---------------------------------------------------------------------

def ranges_overlap(a_min, a_max, b_min, b_max, tolerance=0.001):
    return max(a_min, b_min) < min(a_max, b_max) - tolerance


def validate_layout_before_build():
    """
    Explicitly verify the corrected layout mathematically before building.
    This prevents the original wing/main body and terrace-door/roof overlap.
    """
    main_left = MAIN_CX - MAIN_W * 0.5
    main_right_roof = MAIN_CX + MAIN_W * 0.5 + MAIN_ROOF_OVERHANG
    main_front = MAIN_CY - MAIN_D * 0.5
    main_back = MAIN_CY + MAIN_D * 0.5

    wing_left = WING_CX - WING_W * 0.5
    wing_right = WING_CX + WING_W * 0.5
    wing_front = WING_CY - WING_D * 0.5
    wing_back = WING_CY + WING_D * 0.5

    # Wing body must not occupy main house or roof footprint.
    if wing_left <= main_right_roof + 0.10:
        raise RuntimeError(
            "LAYOUT FAILED: wing starts too close to/intersects main roof. "
            f"wing_left={wing_left:.2f}, main_roof_right={main_right_roof:.2f}"
        )

    # Connector should only bridge the deliberate gap and stay below eave.
    connector_left = CONNECTOR_CX - CONNECTOR_W * 0.5
    connector_right = CONNECTOR_CX + CONNECTOR_W * 0.5
    connector_front = CONNECTOR_CY - CONNECTOR_D * 0.5
    connector_back = CONNECTOR_CY + CONNECTOR_D * 0.5

    if not (connector_left < main_right_roof and connector_right > wing_left):
        raise RuntimeError("LAYOUT FAILED: connector does not bridge main-to-wing gap.")

    if CONNECTOR_H >= MAIN_WALL_H - 0.05:
        raise RuntimeError("LAYOUT FAILED: connector is too tall near main eave.")

    if not ranges_overlap(connector_front, connector_back, main_front, main_back):
        raise RuntimeError("LAYOUT FAILED: connector does not meet main side wall.")

    if not ranges_overlap(connector_front, connector_back, wing_front, wing_back):
        raise RuntimeError("LAYOUT FAILED: connector does not meet wing side wall.")

    # Rooftop access block must live entirely inside terrace wing footprint,
    # and far right of main roof footprint.
    access_cx = WING_CX + ACCESS_CX_OFFSET
    access_cy = WING_CY + ACCESS_CY_OFFSET
    access_left = access_cx - ACCESS_W * 0.5
    access_right = access_cx + ACCESS_W * 0.5
    access_front = access_cy - ACCESS_D * 0.5
    access_back = access_cy + ACCESS_D * 0.5

    if not (wing_left + 0.15 <= access_left and access_right <= wing_right - 0.15):
        raise RuntimeError("LAYOUT FAILED: terrace access block extends beyond wing X bounds.")
    if not (wing_front + 0.15 <= access_front and access_back <= wing_back - 0.15):
        raise RuntimeError("LAYOUT FAILED: terrace access block extends beyond wing Y bounds.")
    if access_left <= main_right_roof + 0.10:
        raise RuntimeError("LAYOUT FAILED: terrace access block is too close to main roof.")

    print(
        "[LAYOUT OK]\n"
        f"  Main roof right edge: {main_right_roof:.2f}m\n"
        f"  Wing left edge:      {wing_left:.2f}m\n"
        f"  Clear gap:           {wing_left - main_right_roof:.2f}m\n"
        f"  Connector height:    {CONNECTOR_H:.2f}m (< main eave {MAIN_WALL_H:.2f}m)\n"
        f"  Terrace block X:     {access_left:.2f}m..{access_right:.2f}m\n"
    )


# ---------------------------------------------------------------------
# MAIN MODEL BUILD
# ---------------------------------------------------------------------

def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.8

    root["asset_type"] = "StaticEnvironmentBuilding"
    root["visual_forward_axis"] = "-Y"
    root["up_axis"] = "+Z"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = False
    root["front_door_state"] = "closed"
    root["garage_door_state"] = "closed"
    root["terrace_door_state"] = "closed"
    root["collision_mesh_generated"] = False
    root["static_meshes_merged_on_export"] = JOIN_STATIC_MESHES_FOR_EXPORT

    collection.objects.link(root)
    return root


def build_house():
    if CLEAR_SCENE_BEFORE_BUILD:
        clear_scene()

    configure_scene()
    validate_layout_before_build()

    collection = get_or_create_collection(COLLECTION_NAME)
    mats = build_materials()
    root = create_root(collection)

    # Derived main bounds.
    main_left = MAIN_CX - MAIN_W * 0.5
    main_right = MAIN_CX + MAIN_W * 0.5
    main_front = MAIN_CY - MAIN_D * 0.5
    main_back = MAIN_CY + MAIN_D * 0.5
    main_wall_top = FOUNDATION_H + MAIN_WALL_H
    main_ridge_z = main_wall_top + MAIN_ROOF_RISE

    # Derived wing bounds.
    wing_left = WING_CX - WING_W * 0.5
    wing_right = WING_CX + WING_W * 0.5
    wing_front = WING_CY - WING_D * 0.5
    wing_back = WING_CY + WING_D * 0.5
    wing_wall_top = FOUNDATION_H + WING_WALL_H

    # -------------------------------------------------------------
    # Foundations
    # -------------------------------------------------------------
    add_cube("Foundation_Main", (MAIN_CX, MAIN_CY, FOUNDATION_H * 0.5),
             (MAIN_W + 0.22, MAIN_D + 0.22, FOUNDATION_H),
             mats["foundation"], root, collection, bevel=0.04)

    add_cube("Foundation_Wing", (WING_CX, WING_CY, FOUNDATION_H * 0.5),
             (WING_W + 0.20, WING_D + 0.20, FOUNDATION_H),
             mats["foundation"], root, collection, bevel=0.04)

    add_cube("Foundation_Connector", (CONNECTOR_CX, CONNECTOR_CY, FOUNDATION_H * 0.5),
             (CONNECTOR_W, CONNECTOR_D, FOUNDATION_H),
             mats["foundation"], root, collection, bevel=0.03)

    # -------------------------------------------------------------
    # Main house closed body and true recessed entrance
    # -------------------------------------------------------------
    main_body = add_cube(
        "MainBody_ClosedShell",
        (MAIN_CX, MAIN_CY, FOUNDATION_H + MAIN_WALL_H * 0.5),
        (MAIN_W, MAIN_D, MAIN_WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.018,
    )

    boolean_cut_box(
        main_body,
        "FrontEntryRecessCut",
        (
            MAIN_CX,
            main_front + ENTRY_RECESS_D * 0.5,
            FOUNDATION_H + ENTRY_RECESS_H * 0.5,
        ),
        (ENTRY_RECESS_W, ENTRY_RECESS_D + 0.06, ENTRY_RECESS_H),
    )

    # Eave trims.
    trim_z = main_wall_top - 0.14
    add_cube("MainEave_Front", (MAIN_CX, main_front - 0.015, trim_z),
             (MAIN_W + 0.14, 0.12, 0.22), mats["trim"], root, collection, bevel=0.01)
    add_cube("MainEave_Back", (MAIN_CX, main_back + 0.015, trim_z),
             (MAIN_W + 0.14, 0.12, 0.22), mats["trim"], root, collection, bevel=0.01)
    add_cube("MainEave_Left", (main_left - 0.015, MAIN_CY, trim_z),
             (0.12, MAIN_D, 0.22), mats["trim"], root, collection, bevel=0.01)
    add_cube("MainEave_Right", (main_right + 0.015, MAIN_CY, trim_z),
             (0.12, MAIN_D, 0.22), mats["trim"], root, collection, bevel=0.01)

    # Main wall clapboards - rear is split around garage door.
    front_side_w = (MAIN_W - ENTRY_RECESS_W) * 0.5
    add_clapboard_front_back(
        "MainFront_Left",
        main_left + front_side_w * 0.5,
        front_side_w,
        main_front,
        -1.0,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )
    add_clapboard_front_back(
        "MainFront_Right",
        main_right - front_side_w * 0.5,
        front_side_w,
        main_front,
        -1.0,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )

    # Rear: no rear windows. Wood boards surround the central garage door.
    rear_side_w = (MAIN_W - GARAGE_W) * 0.5
    add_clapboard_front_back(
        "MainBack_LeftOfGarage",
        main_left + rear_side_w * 0.5,
        rear_side_w,
        main_back,
        1.0,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )
    add_clapboard_front_back(
        "MainBack_RightOfGarage",
        main_right - rear_side_w * 0.5,
        rear_side_w,
        main_back,
        1.0,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )
    garage_top_z = FOUNDATION_H + GARAGE_H
    add_clapboard_front_back(
        "MainBack_AboveGarage",
        MAIN_CX,
        GARAGE_W,
        main_back,
        1.0,
        garage_top_z,
        MAIN_WALL_H - GARAGE_H,
        mats, root, collection,
    )

    # Left wall can stay fully visible.
    add_clapboard_side(
        "MainLeft",
        main_left,
        -1.0,
        MAIN_CY,
        MAIN_D,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )

    # Right wall is split to leave clean connector junction (no cladding penetration).
    connector_front = CONNECTOR_CY - CONNECTOR_D * 0.5
    connector_back = CONNECTOR_CY + CONNECTOR_D * 0.5
    right_front_depth = connector_front - main_front
    right_back_depth = main_back - connector_back
    add_clapboard_side(
        "MainRight_FrontOfConnector",
        main_right,
        1.0,
        main_front + right_front_depth * 0.5,
        right_front_depth,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )
    add_clapboard_side(
        "MainRight_BackOfConnector",
        main_right,
        1.0,
        connector_back + right_back_depth * 0.5,
        right_back_depth,
        FOUNDATION_H,
        MAIN_WALL_H,
        mats, root, collection,
    )

    # Recess interior boards.
    entry_back_y = main_front + ENTRY_RECESS_D - 0.035
    add_clapboard_front_back(
        "EntryRecess_BackWall",
        MAIN_CX,
        ENTRY_RECESS_W,
        entry_back_y,
        1.0,
        FOUNDATION_H,
        ENTRY_RECESS_H,
        mats, root, collection,
    )

    # Recessed closed front door + trim.
    door_z = FOUNDATION_H + FRONT_DOOR_H * 0.5
    add_cube("FrontDoor_Closed", (MAIN_CX, entry_back_y + 0.025, door_z),
             (FRONT_DOOR_W, 0.09, FRONT_DOOR_H), mats["door"], root, collection, bevel=0.014)
    door_frame_t = 0.14
    add_cube("FrontDoorFrame_Left",
             (MAIN_CX - FRONT_DOOR_W * 0.5 - door_frame_t * 0.5, entry_back_y + 0.02, door_z),
             (door_frame_t, 0.12, FRONT_DOOR_H + 0.10), mats["trim"], root, collection, bevel=0.008)
    add_cube("FrontDoorFrame_Right",
             (MAIN_CX + FRONT_DOOR_W * 0.5 + door_frame_t * 0.5, entry_back_y + 0.02, door_z),
             (door_frame_t, 0.12, FRONT_DOOR_H + 0.10), mats["trim"], root, collection, bevel=0.008)
    add_cube("FrontDoorFrame_Top",
             (MAIN_CX, entry_back_y + 0.02, FOUNDATION_H + FRONT_DOOR_H + 0.07),
             (FRONT_DOOR_W + door_frame_t * 2, 0.12, door_frame_t), mats["trim"], root, collection, bevel=0.008)

    # Front porch canopy and exactly two white support columns.
    canopy_y = main_front - 0.55
    canopy_z = FOUNDATION_H + ENTRY_RECESS_H - 0.08
    add_cube("FrontPorchCanopy", (MAIN_CX, canopy_y, canopy_z),
             (3.55, 1.35, 0.18), mats["roof"], root, collection, bevel=0.018)

    for label, x in (("Left", MAIN_CX - 1.28), ("Right", MAIN_CX + 1.28)):
        add_cube(
            "FrontPorchColumn_" + label,
            (x, canopy_y + 0.22, FOUNDATION_H + 1.32),
            (0.28, 0.28, 2.64),
            mats["trim"],
            root,
            collection,
            bevel=0.014,
        )

    add_cube("FrontEntryStep", (MAIN_CX, main_front - 0.78, 0.15),
             (2.25, 0.88, 0.30), mats["foundation"], root, collection, bevel=0.03)

    # Main building windows: front + left side only. Rear windows intentionally removed.
    window_z = FOUNDATION_H + 1.90
    add_front_window("MainFrontWindow_Left", MAIN_CX - 3.05, main_front - 0.065, window_z,
                     1.45, 1.16, mats, root, collection)
    add_front_window("MainFrontWindow_Right", MAIN_CX + 3.05, main_front - 0.065, window_z,
                     1.45, 1.16, mats, root, collection)
    add_side_window("MainLeftWindow_Front", main_left - 0.065, MAIN_CY - 2.05, window_z,
                    1.42, 1.16, mats, root, collection)
    add_side_window("MainLeftWindow_Back", main_left - 0.065, MAIN_CY + 2.05, window_z,
                    1.42, 1.16, mats, root, collection)

    # New rear garage door replaces old rear windows.
    add_closed_garage_door(
        "RearGarageDoor_Closed",
        MAIN_CX,
        main_back + 0.065,
        FOUNDATION_H,
        GARAGE_W,
        GARAGE_H,
        mats,
        root,
        collection,
    )

    # Gable closures and correct roof slopes.
    add_gable_triangle("MainGable_Front", MAIN_CX, main_front - 0.012, 0.10, MAIN_W,
                       main_wall_top, main_ridge_z, mats["wall"], root, collection)
    add_gable_triangle("MainGable_Back", MAIN_CX, main_back + 0.012, 0.10, MAIN_W,
                       main_wall_top, main_ridge_z, mats["wall"], root, collection)

    half_roof_span = MAIN_W * 0.5 + MAIN_ROOF_OVERHANG
    roof_depth = MAIN_D + MAIN_ROOF_OVERHANG * 2.0
    roof_len = math.sqrt(half_roof_span ** 2 + MAIN_ROOF_RISE ** 2) + 0.20
    roof_pitch = math.atan2(MAIN_ROOF_RISE, half_roof_span)
    roof_center_z = main_wall_top + MAIN_ROOF_RISE * 0.5

    # Correct roof geometry: both panels descend away from ridge X=MAIN_CX.
    add_cube("MainRoof_RightSlope",
             (MAIN_CX + half_roof_span * 0.5, MAIN_CY, roof_center_z),
             (roof_len, roof_depth, 0.22), mats["roof"], root, collection,
             bevel=0.024, rotation=(0.0, roof_pitch, 0.0))
    add_cube("MainRoof_LeftSlope",
             (MAIN_CX - half_roof_span * 0.5, MAIN_CY, roof_center_z),
             (roof_len, roof_depth, 0.22), mats["roof"], root, collection,
             bevel=0.024, rotation=(0.0, -roof_pitch, 0.0))
    add_cube("MainRoof_RidgeCap", (MAIN_CX, MAIN_CY, main_ridge_z + 0.04),
             (0.24, roof_depth + 0.05, 0.16), mats["roof_dark"], root, collection, bevel=0.016)

    # Chimney sits on main roof and does not touch wing/terrace.
    add_cube("MainChimney", (MAIN_CX + 2.10, MAIN_CY + 1.30, main_wall_top + 1.73),
             (0.74, 0.74, 1.86), mats["chimney"], root, collection, bevel=0.014)
    add_cube("MainChimneyCap", (MAIN_CX + 2.10, MAIN_CY + 1.30, main_wall_top + 2.71),
             (0.92, 0.92, 0.16), mats["foundation"], root, collection, bevel=0.012)

    # -------------------------------------------------------------
    # Wide low enclosed connector: 3.20m clear visual corridor width, deliberately below eave.
    # -------------------------------------------------------------
    connector = add_cube(
        "FamilyWing_LowConnector",
        (CONNECTOR_CX, CONNECTOR_CY, FOUNDATION_H + CONNECTOR_H * 0.5),
        (CONNECTOR_W, CONNECTOR_D, CONNECTOR_H),
        mats["wall"],
        root,
        collection,
        bevel=0.015,
    )
    # A small cap makes the connector intentional, but is under main roof height.
    add_cube(
        "FamilyWing_ConnectorCap",
        (CONNECTOR_CX, CONNECTOR_CY, FOUNDATION_H + CONNECTOR_H + 0.06),
        (CONNECTOR_W + 0.08, CONNECTOR_D + 0.08, 0.12),
        mats["roof_dark"],
        root,
        collection,
        bevel=0.010,
    )

    # -------------------------------------------------------------
    # Family-room wing: separate physical footprint; no overlap with main roof.
    # -------------------------------------------------------------
    add_cube(
        "FamilyWing_ClosedShell",
        (WING_CX, WING_CY, FOUNDATION_H + WING_WALL_H * 0.5),
        (WING_W, WING_D, WING_WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.016,
    )

    # Wing top trim.
    wing_trim_z = wing_wall_top - 0.11
    add_cube("WingTopTrim_Front", (WING_CX, wing_front - 0.01, wing_trim_z),
             (WING_W + 0.08, 0.10, 0.18), mats["trim"], root, collection, bevel=0.008)
    add_cube("WingTopTrim_Back", (WING_CX, wing_back + 0.01, wing_trim_z),
             (WING_W + 0.08, 0.10, 0.18), mats["trim"], root, collection, bevel=0.008)
    add_cube("WingTopTrim_Right", (wing_right + 0.01, WING_CY, wing_trim_z),
             (0.10, WING_D, 0.18), mats["trim"], root, collection, bevel=0.008)

    # Wing cladding on exposed faces; left side is partly visually hidden by connector.
    add_clapboard_front_back("WingFront", WING_CX, WING_W, wing_front, -1.0,
                             FOUNDATION_H, WING_WALL_H, mats, root, collection)
    add_clapboard_front_back("WingBack", WING_CX, WING_W, wing_back, 1.0,
                             FOUNDATION_H, WING_WALL_H, mats, root, collection)
    add_clapboard_side("WingRight", wing_right, 1.0, WING_CY, WING_D,
                       FOUNDATION_H, WING_WALL_H, mats, root, collection)

    # Left face cladding split around connector to avoid penetrating geometry.
    wing_connector_front = CONNECTOR_CY - CONNECTOR_D * 0.5
    wing_connector_back = CONNECTOR_CY + CONNECTOR_D * 0.5
    left_front_depth = wing_connector_front - wing_front
    left_back_depth = wing_back - wing_connector_back
    if left_front_depth > 0.10:
        add_clapboard_side("WingLeft_FrontOfConnector", wing_left, -1.0,
                           wing_front + left_front_depth * 0.5, left_front_depth,
                           FOUNDATION_H, WING_WALL_H, mats, root, collection)
    if left_back_depth > 0.10:
        add_clapboard_side("WingLeft_BackOfConnector", wing_left, -1.0,
                           wing_connector_back + left_back_depth * 0.5, left_back_depth,
                           FOUNDATION_H, WING_WALL_H, mats, root, collection)

    # Wing windows, all well outside main body / roof footprint.
    wing_window_z = FOUNDATION_H + 1.80
    add_front_window("WingFrontWindow_Left", WING_CX - 1.55, wing_front - 0.065,
                     wing_window_z, 1.42, 1.34, mats, root, collection)
    add_front_window("WingFrontWindow_Right", WING_CX + 1.55, wing_front - 0.065,
                     wing_window_z, 1.42, 1.34, mats, root, collection)
    add_side_window("WingRightWindow", wing_right + 0.065, WING_CY + 0.25,
                    wing_window_z, 2.05, 1.36, mats, root, collection)

    # -------------------------------------------------------------
    # Terrace over wing: deck + open railing
    # -------------------------------------------------------------
    deck_top_z = wing_wall_top + TERRACE_DECK_T
    add_cube("WingTerraceDeck",
             (WING_CX, WING_CY, wing_wall_top + TERRACE_DECK_T * 0.5),
             (WING_W - 0.12, WING_D - 0.12, TERRACE_DECK_T),
             mats["terrace"], root, collection, bevel=0.008)

    rail_min_x = wing_left + 0.18
    rail_max_x = wing_right - 0.18
    rail_min_y = wing_front + 0.18
    rail_max_y = wing_back - 0.18
    add_terrace_railing(
        "WingTerraceRail",
        rail_min_x, rail_max_x, rail_min_y, rail_max_y,
        deck_top_z, mats, root, collection,
    )

    # Rooftop access block: far right/rear of wing, no main roof intersection.
    access_cx = WING_CX + ACCESS_CX_OFFSET
    access_cy = WING_CY + ACCESS_CY_OFFSET
    access_bottom_z = deck_top_z
    access_center_z = access_bottom_z + ACCESS_H * 0.5
    add_cube("TerraceAccessBlock",
             (access_cx, access_cy, access_center_z),
             (ACCESS_W, ACCESS_D, ACCESS_H),
             mats["wall"], root, collection, bevel=0.014)

    add_cube("TerraceAccessBlockCap",
             (access_cx, access_cy, access_bottom_z + ACCESS_H + 0.08),
             (ACCESS_W + 0.12, ACCESS_D + 0.12, 0.16),
             mats["roof_dark"], root, collection, bevel=0.010)

    # Closed terrace door faces toward the front side of the terrace.
    terrace_door_y = access_cy - ACCESS_D * 0.5 - 0.048
    terrace_door_z = access_bottom_z + TERRACE_DOOR_H * 0.5
    add_cube("TerraceDoor_Closed",
             (access_cx, terrace_door_y, terrace_door_z),
             (TERRACE_DOOR_W, 0.09, TERRACE_DOOR_H),
             mats["door"], root, collection, bevel=0.012)

    terrace_frame_t = 0.12
    add_cube("TerraceDoorFrame_Left",
             (access_cx - TERRACE_DOOR_W * 0.5 - terrace_frame_t * 0.5, terrace_door_y, terrace_door_z),
             (terrace_frame_t, 0.115, TERRACE_DOOR_H + 0.08),
             mats["trim"], root, collection, bevel=0.006)
    add_cube("TerraceDoorFrame_Right",
             (access_cx + TERRACE_DOOR_W * 0.5 + terrace_frame_t * 0.5, terrace_door_y, terrace_door_z),
             (terrace_frame_t, 0.115, TERRACE_DOOR_H + 0.08),
             mats["trim"], root, collection, bevel=0.006)
    add_cube("TerraceDoorFrame_Top",
             (access_cx, terrace_door_y, access_bottom_z + TERRACE_DOOR_H + 0.06),
             (TERRACE_DOOR_W + terrace_frame_t * 2, 0.115, terrace_frame_t),
             mats["trim"], root, collection, bevel=0.006)

    return root


# ---------------------------------------------------------------------
# MERGE / VALIDATE / EXPORT
# ---------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def merge_static_meshes(root):
    meshes = meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes found to merge.")

    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = ROOT_NAME + "_Mesh"
    merged.parent = root
    set_flat_shading(merged)
    return merged


def bbox_world(meshes):
    lows = []
    highs = []

    for obj in meshes:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            lows.append(point)
            highs.append(point)

    low = Vector((
        min(point.x for point in lows),
        min(point.y for point in lows),
        min(point.z for point in lows),
    ))
    high = Vector((
        max(point.x for point in highs),
        max(point.y for point in highs),
        max(point.z for point in highs),
    ))
    return low, high


def validate_asset(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")

    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root must remain at (0,0,0).")

    meshes = meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root.")

    forbidden_scene_types = [
        obj.name for obj in bpy.context.scene.objects
        if obj.type in {"CAMERA", "LIGHT"}
    ]
    if forbidden_scene_types:
        raise RuntimeError(
            "VALIDATION FAILED: cameras/lights remain: "
            + ", ".join(forbidden_scene_types)
        )

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0 or obj.scale.y < 0 or obj.scale.z < 0:
            failures.append("negative scale: " + obj.name)
        if obj.name.upper().startswith(("UCX_", "COL_", "COLLISION_")):
            failures.append("collision mesh naming found: " + obj.name)

    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    bpy.context.view_layer.update()
    low, high = bbox_world(meshes)
    dims = high - low

    if low.z < -0.02:
        raise RuntimeError(f"VALIDATION FAILED: geometry below ground ({low.z:.4f}m).")
    if low.z > 0.04:
        raise RuntimeError(f"VALIDATION FAILED: geometry floats above ground ({low.z:.4f}m).")

    triangle_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangle_count += len(obj.data.loop_triangles)

    print(
        f"[VALID] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Ground min Z: {low.z:.4f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangle_count}\n"
        f"  Front: local -Y\n"
        f"  Enterable: False\n"
    )


def select_for_export(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    select_for_export(root)

    bpy.ops.export_scene.gltf(
        filepath=path,
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
    print(f"[EXPORT] {path}")


if __name__ == "__main__":
    print("\n=== Generating V4 Large Farm Town House ===\n")

    root = build_house()

    if JOIN_STATIC_MESHES_FOR_EXPORT:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nGodot note: attach StaticBody3D + simple CollisionShape3D separately.")
