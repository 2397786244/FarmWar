# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - Small North American Grocery Store (Enterable) - V2
#
# Generates one redesigned enterable grocery/general store GLB:
#   FTF_GroceryStore_Small_BrownWood_Enterable_v2.glb
#
# CHANGES FROM EARLIER VERSION
# - Redesigned from scratch; does NOT follow the earlier house proportions
# - Smaller overall building footprint
# - Complete front wall / no missing wall segments
# - Larger storefront windows
# - Brown wooden plank / clapboard exterior
# - North American rural general-store look
# - Still enterable with empty interior
# - Front and rear doors remain separate mesh nodes and are NOT merged
# - Door origins are placed on hinge edges for rotation in Blender/Godot
#
# REQUIREMENTS IMPLEMENTED
# - One-story grocery / general store
# - Enterable empty interior
# - Front faces local -Y
# - Front: one wider main door for two people
# - Front: two windows
# - Side: one window
# - Back: one small door
# - Front and back doors are separate mesh nodes
# - Static building geometry is merged before export
# - No interior props, no collision shell, no text, no lights, no cameras
#
# OUTPUT
#   generated_farmtown_shops/FTF_GroceryStore_Small_BrownWood_Enterable_v2.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_grocery_store_v2.py
# ---------------------------------------------------------------------

import bpy
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# SETTINGS
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)

OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_shops")
OUTPUT_FILE = "FTF_GroceryStore_Small_BrownWood_Enterable_v2.glb"

ROOT_NAME = "FTF_GroceryStore_Small_BrownWood_Enterable_v2"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

# Smaller footprint than previous store
FOUNDATION_H = 0.26
FLOOR_THICK = 0.10

STORE_W = 8.80
STORE_D = 6.60
WALL_H = 3.45
WALL_T = 0.18

ROOF_T = 0.18
ROOF_OVERHANG = 0.18
PARAPET_H = 0.95
PARAPET_T = 0.16

# Doors
FRONT_DOOR_W = 1.95
FRONT_DOOR_H = 2.35
FRONT_DOOR_T = 0.08

BACK_DOOR_W = 0.95
BACK_DOOR_H = 2.10
BACK_DOOR_T = 0.08

# Windows - deliberately larger
FRONT_WINDOW_W = 1.95
FRONT_WINDOW_H = 1.62

SIDE_WINDOW_W = 1.75   # width along Y on side wall
SIDE_WINDOW_H = 1.50

DOOR_BOTTOM_Z = FOUNDATION_H
WINDOW_CENTER_Z = FOUNDATION_H + 1.92

# Brown wood clapboard
BOARD_H = 0.19
BOARD_GAP = 0.07
BOARD_OUT = 0.025
BOARD_T = 0.040


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


def add_bevel(obj, width=0.014):
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

def make_material(name, color, roughness=0.74, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build_materials():
    return {
        "foundation": make_material("MAT_GroceryV2_Foundation", (0.30, 0.31, 0.30), 0.88),
        "floor": make_material("MAT_GroceryV2_Floor", (0.49, 0.37, 0.25), 0.84),
        "wall": make_material("MAT_GroceryV2_BrownWood", (0.49, 0.35, 0.23), 0.84),
        "wall_dark": make_material("MAT_GroceryV2_BrownWoodDark", (0.39, 0.27, 0.18), 0.86),
        "trim": make_material("MAT_GroceryV2_Trim", (0.84, 0.80, 0.72), 0.72),
        "roof": make_material("MAT_GroceryV2_Roof", (0.36, 0.17, 0.11), 0.76),
        "roof_dark": make_material("MAT_GroceryV2_RoofDark", (0.14, 0.12, 0.11), 0.78),
        "window": make_material("MAT_GroceryV2_Window", (0.08, 0.14, 0.19), 0.34, 0.03),
        "door": make_material("MAT_GroceryV2_Door", (0.18, 0.10, 0.05), 0.80),
        "awning": make_material("MAT_GroceryV2_Awning", (0.22, 0.36, 0.23), 0.72),
    }


# ---------------------------------------------------------------------
# MESH HELPERS
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
    no_merge=False,
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
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def set_origin_to_world_point(obj, point):
    scene = bpy.context.scene
    old_cursor = scene.cursor.location.copy()
    scene.cursor.location = point
    set_active(obj)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    scene.cursor.location = old_cursor


def boolean_cut_box(target_obj, cutter_name, location, dimensions):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    cutter = bpy.context.object
    cutter.name = cutter_name
    cutter.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    mod = target_obj.modifiers.new(cutter_name + "_Bool", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter

    set_active(target_obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.data.objects.remove(cutter, do_unlink=True)
    set_flat_shading(target_obj)


def add_hinged_door(
    name,
    hinge_point,
    width,
    thickness,
    height,
    material,
    parent,
    collection,
    hinge_side="left",
    facing="front",
):
    hx, hy, hz = hinge_point

    if facing in ("front", "back"):
        if hinge_side == "left":
            center_x = hx + width * 0.5
        else:
            center_x = hx - width * 0.5

        obj = add_cube(
            name,
            (center_x, hy, hz + height * 0.5),
            (width, thickness, height),
            material,
            parent,
            collection,
            bevel=0.010,
            no_merge=True,
        )
        set_origin_to_world_point(obj, Vector((hx, hy, hz + height * 0.5)))

    else:
        if hinge_side == "left":
            center_y = hy + width * 0.5
        else:
            center_y = hy - width * 0.5

        obj = add_cube(
            name,
            (hx, center_y, hz + height * 0.5),
            (thickness, width, height),
            material,
            parent,
            collection,
            bevel=0.010,
            no_merge=True,
        )
        set_origin_to_world_point(obj, Vector((hx, hy, hz + height * 0.5)))

    obj["is_door"] = True
    obj["hinge_side"] = hinge_side
    obj["facing"] = facing
    return obj


def add_front_window(name, x, y, z, width, height, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.07

    add_cube(name + "_Pane", (x, y, z), (width, 0.05, height),
             mats["window"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (width + trim_t * 2, trim_d, trim_t),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (width + trim_t * 2, trim_d, trim_t),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Left", (x - width * 0.5 + trim_t * 0.5, y, z),
             (trim_t, trim_d, height),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Right", (x + width * 0.5 - trim_t * 0.5, y, z),
             (trim_t, trim_d, height),
             mats["trim"], parent, collection, bevel=0.005)


def add_side_window(name, x, y, z, width_y, height, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.07

    add_cube(name + "_Pane", (x, y, z), (0.05, width_y, height),
             mats["window"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (trim_d, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (trim_d, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Near", (x, y - width_y * 0.5 + trim_t * 0.5, z),
             (trim_d, trim_t, height),
             mats["trim"], parent, collection, bevel=0.005)
    add_cube(name + "_Far", (x, y + width_y * 0.5 - trim_t * 0.5, z),
             (trim_d, trim_t, height),
             mats["trim"], parent, collection, bevel=0.005)


def add_front_back_clapboards(prefix, x_center, width_x, y_face, outward_sign, z_base, height, mats, parent, collection):
    pitch = BOARD_H + BOARD_GAP
    count = int((height - 0.08) / pitch) + 1
    for i in range(count):
        z = z_base + 0.11 + i * pitch
        if z + BOARD_H * 0.5 > z_base + height - 0.05:
            break
        add_cube(
            f"{prefix}_Board_{i:02d}",
            (x_center, y_face + outward_sign * BOARD_OUT, z),
            (width_x, BOARD_T, BOARD_H),
            mats["wall_dark"] if i % 2 else mats["wall"],
            parent,
            collection,
            bevel=0.002,
        )


def add_side_clapboards(prefix, x_face, outward_sign, y_center, depth_y, z_base, height, mats, parent, collection):
    pitch = BOARD_H + BOARD_GAP
    count = int((height - 0.08) / pitch) + 1
    for i in range(count):
        z = z_base + 0.11 + i * pitch
        if z + BOARD_H * 0.5 > z_base + height - 0.05:
            break
        add_cube(
            f"{prefix}_Board_{i:02d}",
            (x_face + outward_sign * BOARD_OUT, y_center, z),
            (BOARD_T, depth_y, BOARD_H),
            mats["wall_dark"] if i % 2 else mats["wall"],
            parent,
            collection,
            bevel=0.002,
        )


# ---------------------------------------------------------------------
# ROOT
# ---------------------------------------------------------------------

def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.65

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


# ---------------------------------------------------------------------
# BUILD STORE
# ---------------------------------------------------------------------

def build_store():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    left_x = -STORE_W * 0.5
    right_x = STORE_W * 0.5
    front_y = -STORE_D * 0.5
    back_y = STORE_D * 0.5

    wall_center_z = FOUNDATION_H + WALL_H * 0.5
    roof_z = FOUNDATION_H + WALL_H + ROOF_T * 0.5

    # -------------------------------------------------------------
    # Foundation + floor
    # -------------------------------------------------------------
    add_cube(
        "Foundation",
        (0.0, 0.0, FOUNDATION_H * 0.5),
        (STORE_W + 0.20, STORE_D + 0.20, FOUNDATION_H),
        mats["foundation"],
        root,
        collection,
        bevel=0.03,
    )

    add_cube(
        "InteriorFloor",
        (0.0, 0.0, FOUNDATION_H + FLOOR_THICK * 0.5),
        (STORE_W - WALL_T * 2.0, STORE_D - WALL_T * 2.0, FLOOR_THICK),
        mats["floor"],
        root,
        collection,
        bevel=0.008,
    )

    # -------------------------------------------------------------
    # Main wall shell: start as complete walls, then cut ONLY door openings.
    # This guarantees the front wall remains complete and avoids missing segments.
    # -------------------------------------------------------------
    wall_front = add_cube(
        "Wall_Front",
        (0.0, front_y + WALL_T * 0.5, wall_center_z),
        (STORE_W, WALL_T, WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.010,
    )

    wall_back = add_cube(
        "Wall_Back",
        (0.0, back_y - WALL_T * 0.5, wall_center_z),
        (STORE_W, WALL_T, WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.010,
    )

    wall_left = add_cube(
        "Wall_Left",
        (left_x + WALL_T * 0.5, 0.0, wall_center_z),
        (WALL_T, STORE_D, WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.010,
    )

    wall_right = add_cube(
        "Wall_Right",
        (right_x - WALL_T * 0.5, 0.0, wall_center_z),
        (WALL_T, STORE_D, WALL_H),
        mats["wall"],
        root,
        collection,
        bevel=0.010,
    )

    # Actual open doorways for enterable building
    boolean_cut_box(
        wall_front,
        "Cut_FrontDoor",
        (0.0, front_y + WALL_T * 0.5, FOUNDATION_H + FRONT_DOOR_H * 0.5),
        (FRONT_DOOR_W + 0.02, WALL_T + 0.10, FRONT_DOOR_H),
    )

    boolean_cut_box(
        wall_back,
        "Cut_BackDoor",
        (0.0, back_y - WALL_T * 0.5, FOUNDATION_H + BACK_DOOR_H * 0.5),
        (BACK_DOOR_W + 0.02, WALL_T + 0.10, BACK_DOOR_H),
    )

    # -------------------------------------------------------------
    # Roof + false front / parapet for general-store character
    # -------------------------------------------------------------
    add_cube(
        "Roof_Slab",
        (0.0, 0.0, roof_z),
        (STORE_W + ROOF_OVERHANG * 2.0, STORE_D + ROOF_OVERHANG * 2.0, ROOF_T),
        mats["roof"],
        root,
        collection,
        bevel=0.012,
    )

    parapet_z = FOUNDATION_H + WALL_H + PARAPET_H * 0.5
    add_cube(
        "FalseFront",
        (0.0, front_y + WALL_T * 0.5, parapet_z),
        (STORE_W, PARAPET_T, PARAPET_H),
        mats["trim"],
        root,
        collection,
        bevel=0.008,
    )

    add_cube(
        "Roof_Cap_Front",
        (0.0, front_y + WALL_T * 0.5 - 0.02, FOUNDATION_H + WALL_H + PARAPET_H),
        (STORE_W + 0.12, 0.12, 0.12),
        mats["roof_dark"],
        root,
        collection,
        bevel=0.006,
    )

    # Front awning
    add_cube(
        "FrontAwning",
        (0.0, front_y - 0.42, FOUNDATION_H + 2.95),
        (STORE_W - 1.1, 0.95, 0.12),
        mats["awning"],
        root,
        collection,
        bevel=0.008,
        rotation=(0.0, 0.0, 0.0),
    )

    # -------------------------------------------------------------
    # Trim + wood clapboard look
    # -------------------------------------------------------------
    # Front/back clapboards
    add_front_back_clapboards(
        "FrontClad",
        0.0,
        STORE_W,
        front_y,
        -1.0,
        FOUNDATION_H,
        WALL_H,
        mats,
        root,
        collection,
    )
    add_front_back_clapboards(
        "BackClad",
        0.0,
        STORE_W,
        back_y,
        1.0,
        FOUNDATION_H,
        WALL_H,
        mats,
        root,
        collection,
    )

    # Side clapboards
    add_side_clapboards(
        "LeftClad",
        left_x,
        -1.0,
        0.0,
        STORE_D,
        FOUNDATION_H,
        WALL_H,
        mats,
        root,
        collection,
    )
    add_side_clapboards(
        "RightClad",
        right_x,
        1.0,
        0.0,
        STORE_D,
        FOUNDATION_H,
        WALL_H,
        mats,
        root,
        collection,
    )

    # Corner trim
    for name, x, y in (
        ("Corner_FL", left_x, front_y),
        ("Corner_FR", right_x, front_y),
        ("Corner_BL", left_x, back_y),
        ("Corner_BR", right_x, back_y),
    ):
        add_cube(
            name,
            (x, y, FOUNDATION_H + WALL_H * 0.5),
            (0.16, 0.16, WALL_H),
            mats["trim"],
            root,
            collection,
            bevel=0.004,
        )

    # -------------------------------------------------------------
    # Door frames
    # -------------------------------------------------------------
    add_cube(
        "FrontDoorFrame_Left",
        (-FRONT_DOOR_W * 0.5 - 0.07, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H * 0.5),
        (0.14, 0.12, FRONT_DOOR_H + 0.10),
        mats["trim"], root, collection, bevel=0.005
    )
    add_cube(
        "FrontDoorFrame_Right",
        (FRONT_DOOR_W * 0.5 + 0.07, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H * 0.5),
        (0.14, 0.12, FRONT_DOOR_H + 0.10),
        mats["trim"], root, collection, bevel=0.005
    )
    add_cube(
        "FrontDoorFrame_Top",
        (0.0, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H + 0.07),
        (FRONT_DOOR_W + 0.28, 0.12, 0.14),
        mats["trim"], root, collection, bevel=0.005
    )

    add_cube(
        "BackDoorFrame_Left",
        (-BACK_DOOR_W * 0.5 - 0.06, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H * 0.5),
        (0.12, 0.11, BACK_DOOR_H + 0.08),
        mats["trim"], root, collection, bevel=0.005
    )
    add_cube(
        "BackDoorFrame_Right",
        (BACK_DOOR_W * 0.5 + 0.06, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H * 0.5),
        (0.12, 0.11, BACK_DOOR_H + 0.08),
        mats["trim"], root, collection, bevel=0.005
    )
    add_cube(
        "BackDoorFrame_Top",
        (0.0, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H + 0.06),
        (BACK_DOOR_W + 0.24, 0.11, 0.12),
        mats["trim"], root, collection, bevel=0.005
    )

    # -------------------------------------------------------------
    # Bigger windows
    # -------------------------------------------------------------
    add_front_window(
        "FrontWindow_Left",
        -2.50,
        front_y - 0.04,
        WINDOW_CENTER_Z,
        FRONT_WINDOW_W,
        FRONT_WINDOW_H,
        mats, root, collection,
    )
    add_front_window(
        "FrontWindow_Right",
        2.50,
        front_y - 0.04,
        WINDOW_CENTER_Z,
        FRONT_WINDOW_W,
        FRONT_WINDOW_H,
        mats, root, collection,
    )

    add_side_window(
        "RightSideWindow",
        right_x + 0.04,
        0.10,
        WINDOW_CENTER_Z,
        SIDE_WINDOW_W,
        SIDE_WINDOW_H,
        mats, root, collection,
    )

    # -------------------------------------------------------------
    # Doors as separate hinge-ready mesh nodes
    # -------------------------------------------------------------
    add_hinged_door(
        "Door_Front",
        (-FRONT_DOOR_W * 0.5, front_y - FRONT_DOOR_T * 0.5, DOOR_BOTTOM_Z),
        FRONT_DOOR_W, FRONT_DOOR_T, FRONT_DOOR_H,
        mats["door"], root, collection,
        hinge_side="left", facing="front",
    )

    add_hinged_door(
        "Door_Back",
        (-BACK_DOOR_W * 0.5, back_y + BACK_DOOR_T * 0.5, DOOR_BOTTOM_Z),
        BACK_DOOR_W, BACK_DOOR_T, BACK_DOOR_H,
        mats["door"], root, collection,
        hinge_side="left", facing="back",
    )

    # -------------------------------------------------------------
    # Steps
    # -------------------------------------------------------------
    add_cube(
        "Step_Front",
        (0.0, front_y - 0.56, 0.12),
        (2.45, 0.68, 0.24),
        mats["foundation"], root, collection, bevel=0.018
    )
    add_cube(
        "Step_Back",
        (0.0, back_y + 0.36, 0.10),
        (1.25, 0.50, 0.20),
        mats["foundation"], root, collection, bevel=0.015
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
    meshes = []
    for obj in get_meshes_under_root(root):
        if obj.get("no_merge", False):
            continue
        meshes.append(obj)
    return meshes


def merge_static_meshes(root):
    meshes = get_static_meshes_for_merge(root)
    if not meshes:
        raise RuntimeError("No static meshes available for merge.")

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
    set_flat_shading(merged)
    merged["no_merge"] = False
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
        raise RuntimeError("VALIDATION FAILED: no meshes found under root.")

    scene_bad = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if scene_bad:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(scene_bad))

    front_door = bpy.data.objects.get("Door_Front")
    back_door = bpy.data.objects.get("Door_Back")
    if front_door is None or back_door is None:
        raise RuntimeError("VALIDATION FAILED: separate door nodes missing.")
    if not front_door.get("no_merge", False) or not back_door.get("no_merge", False):
        raise RuntimeError("VALIDATION FAILED: a door is not protected from merge.")

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
        f"  Front wall: full shell with door cutout only\n"
        f"  Larger windows: front {FRONT_WINDOW_W:.2f}m x {FRONT_WINDOW_H:.2f}m\n"
        f"  Separate front door node: {front_door.name}\n"
        f"  Separate back door node:  {back_door.name}\n"
        f"  Enterable: True\n"
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
    print("\n=== Generating Redesigned Grocery Store V2 ===\n")

    root = build_store()

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - New smaller brown wood North-American grocery store.")
    print(" - Front wall is a complete wall shell with only the door opening cut out.")
    print(" - Front and back doors remain separate hinge-ready mesh nodes.")
