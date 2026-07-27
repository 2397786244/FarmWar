# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - One-Story Enterable Grocery Store
#
# Generates one enterable grocery/general store GLB:
#   FTF_GroceryStore_OneStory_Enterable.glb
#
# KEY REQUIREMENTS IMPLEMENTED
# - One-story grocery / general store
# - Enterable empty interior space
# - Front faces local -Y
# - Front facade: one wider door, enough for two people to enter
# - Front facade: two windows
# - Side facade: one window
# - Back facade: one small door
# - Front door and back door are separate Mesh nodes
# - Door meshes are NOT merged into the static mesh
# - Each door's origin is placed at a hinge edge so it can rotate around the hinge
# - Static building parts are merged before GLB export
# - No interior props/furniture
# - No collision mesh, no text, no lights, no cameras
#
# OUTPUT
#   generated_farmtown_shops/FTF_GroceryStore_OneStory_Enterable.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_grocery_store.py
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
OUTPUT_FILE = "FTF_GroceryStore_OneStory_Enterable.glb"

ROOT_NAME = "FTF_GroceryStore_OneStory_Enterable"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

# Building dimensions (meters)
FOUNDATION_H = 0.28
FLOOR_THICKNESS = 0.10

STORE_W = 10.60
STORE_D = 8.20
WALL_H = 3.30
WALL_T = 0.20

ROOF_OVERHANG = 0.18
ROOF_THICKNESS = 0.22
PARAPET_H = 0.42
PARAPET_T = 0.16

# Open interior size is created by separate wall segments and floor.
# Doors
FRONT_DOOR_W = 1.95
FRONT_DOOR_H = 2.35
FRONT_DOOR_T = 0.08

BACK_DOOR_W = 0.95
BACK_DOOR_H = 2.10
BACK_DOOR_T = 0.08

# Windows
FRONT_WINDOW_W = 1.70
FRONT_WINDOW_H = 1.35

SIDE_WINDOW_W = 1.55   # width along Y on side wall
SIDE_WINDOW_H = 1.30

# Z placements
DOOR_BOTTOM_Z = FOUNDATION_H
WINDOW_CENTER_Z = FOUNDATION_H + 1.95

# ---------------------------------------------------------------------
# HELPERS
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


def add_bevel(obj, width=0.015):
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

def make_material(name, color, roughness=0.72, metallic=0.0):
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
        "foundation": make_material("MAT_Grocery_FoundationStone", (0.30, 0.31, 0.30), 0.88),
        "floor": make_material("MAT_Grocery_Floor_Wood", (0.55, 0.43, 0.30), 0.84),
        "wall_outer": make_material("MAT_Grocery_Wall_Clapboard", (0.71, 0.61, 0.48), 0.82),
        "wall_inner": make_material("MAT_Grocery_Wall_Interior", (0.78, 0.75, 0.69), 0.78),
        "trim": make_material("MAT_Grocery_Trim_OffWhite", (0.86, 0.84, 0.79), 0.70),
        "roof": make_material("MAT_Grocery_Roof_MutedRedBrown", (0.40, 0.18, 0.12), 0.74),
        "roof_dark": make_material("MAT_Grocery_RoofDark", (0.14, 0.13, 0.11), 0.76),
        "window": make_material("MAT_Grocery_Window_DarkBlue", (0.07, 0.15, 0.20), 0.34, 0.03),
        "door": make_material("MAT_Grocery_Door_DarkWood", (0.17, 0.09, 0.05), 0.78),
        "awning": make_material("MAT_Grocery_Awning_Green", (0.26, 0.42, 0.27), 0.72),
    }


# ---------------------------------------------------------------------
# MESH CREATION
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
    """
    Create a door mesh with its origin on the hinge edge.
    The door is created closed in the doorway.
    - hinge_side 'left' means the hinge is at the door's local -X edge when viewed
      on the facade plane.
    """
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
            bevel=0.012,
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
            bevel=0.012,
            no_merge=True,
        )
        set_origin_to_world_point(obj, Vector((hx, hy, hz + height * 0.5)))

    obj["is_door"] = True
    obj["hinge_side"] = hinge_side
    obj["facing"] = facing
    return obj


def add_front_window(name, x, y, z, width, height, mats, parent, collection):
    panel_depth = 0.05
    trim_t = 0.12
    trim_depth = 0.07

    add_cube(name + "_Pane", (x, y, z), (width, panel_depth, height),
             mats["window"], parent, collection, bevel=0.008)

    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (width + trim_t * 2, trim_depth, trim_t),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (width + trim_t * 2, trim_depth, trim_t),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Left", (x - width * 0.5 + trim_t * 0.5, y, z),
             (trim_t, trim_depth, height),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Right", (x + width * 0.5 - trim_t * 0.5, y, z),
             (trim_t, trim_depth, height),
             mats["trim"], parent, collection, bevel=0.005)


def add_side_window(name, x, y, z, width_y, height, mats, parent, collection):
    panel_depth = 0.05
    trim_t = 0.12
    trim_depth = 0.07

    add_cube(name + "_Pane", (x, y, z), (panel_depth, width_y, height),
             mats["window"], parent, collection, bevel=0.008)

    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (trim_depth, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (trim_depth, width_y + trim_t * 2, trim_t),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Near", (x, y - width_y * 0.5 + trim_t * 0.5, z),
             (trim_depth, trim_t, height),
             mats["trim"], parent, collection, bevel=0.005)

    add_cube(name + "_Far", (x, y + width_y * 0.5 - trim_t * 0.5, z),
             (trim_depth, trim_t, height),
             mats["trim"], parent, collection, bevel=0.005)


# ---------------------------------------------------------------------
# BUILD MODEL
# ---------------------------------------------------------------------

def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.70

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

    wall_mid_z = FOUNDATION_H + WALL_H * 0.5
    roof_z = FOUNDATION_H + WALL_H + ROOF_THICKNESS * 0.5

    # Foundation and floor
    add_cube(
        "Foundation",
        (0.0, 0.0, FOUNDATION_H * 0.5),
        (STORE_W + 0.22, STORE_D + 0.22, FOUNDATION_H),
        mats["foundation"],
        root,
        collection,
        bevel=0.035,
    )

    add_cube(
        "InteriorFloor",
        (0.0, 0.0, FOUNDATION_H + FLOOR_THICKNESS * 0.5),
        (STORE_W - WALL_T * 2.0, STORE_D - WALL_T * 2.0, FLOOR_THICKNESS),
        mats["floor"],
        root,
        collection,
        bevel=0.010,
    )

    # FRONT WALL: split around front door opening
    front_left_seg_w = 2.90
    front_right_seg_w = 2.90
    front_header_w = FRONT_DOOR_W

    front_left_cx = left_x + front_left_seg_w * 0.5
    front_right_cx = right_x - front_right_seg_w * 0.5
    front_header_cx = 0.0

    add_cube(
        "Wall_Front_Left",
        (front_left_cx, front_y + WALL_T * 0.5, wall_mid_z),
        (front_left_seg_w, WALL_T, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Wall_Front_Right",
        (front_right_cx, front_y + WALL_T * 0.5, wall_mid_z),
        (front_right_seg_w, WALL_T, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Wall_Front_Header",
        (front_header_cx, front_y + WALL_T * 0.5, FOUNDATION_H + FRONT_DOOR_H + (WALL_H - FRONT_DOOR_H) * 0.5),
        (front_header_w, WALL_T, WALL_H - FRONT_DOOR_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.010,
    )

    # BACK WALL: split around small back door opening
    back_left_seg_w = 4.70
    back_right_seg_w = 4.70
    back_header_w = BACK_DOOR_W

    add_cube(
        "Wall_Back_Left",
        (-BACK_DOOR_W * 0.5 - back_left_seg_w * 0.5, back_y - WALL_T * 0.5, wall_mid_z),
        (back_left_seg_w, WALL_T, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Wall_Back_Right",
        (BACK_DOOR_W * 0.5 + back_right_seg_w * 0.5, back_y - WALL_T * 0.5, wall_mid_z),
        (back_right_seg_w, WALL_T, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Wall_Back_Header",
        (0.0, back_y - WALL_T * 0.5, FOUNDATION_H + BACK_DOOR_H + (WALL_H - BACK_DOOR_H) * 0.5),
        (back_header_w, WALL_T, WALL_H - BACK_DOOR_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.010,
    )

    # LEFT SIDE WALL: full
    add_cube(
        "Wall_Left",
        (left_x + WALL_T * 0.5, 0.0, wall_mid_z),
        (WALL_T, STORE_D, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )

    # RIGHT SIDE WALL: full
    add_cube(
        "Wall_Right",
        (right_x - WALL_T * 0.5, 0.0, wall_mid_z),
        (WALL_T, STORE_D, WALL_H),
        mats["wall_outer"],
        root,
        collection,
        bevel=0.012,
    )

    # Roof slab
    add_cube(
        "Roof_Slab",
        (0.0, 0.0, roof_z),
        (STORE_W + ROOF_OVERHANG * 2.0, STORE_D + ROOF_OVERHANG * 2.0, ROOF_THICKNESS),
        mats["roof"],
        root,
        collection,
        bevel=0.015,
    )

    # Parapet / storefront cap
    parapet_z = FOUNDATION_H + WALL_H + PARAPET_H * 0.5
    add_cube(
        "Parapet_Front",
        (0.0, front_y + WALL_T * 0.5, parapet_z),
        (STORE_W, PARAPET_T, PARAPET_H),
        mats["trim"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "Parapet_Back",
        (0.0, back_y - WALL_T * 0.5, parapet_z),
        (STORE_W, PARAPET_T, PARAPET_H),
        mats["trim"],
        root,
        collection,
        bevel=0.010,
    )

    # Simple front awning above main door
    add_cube(
        "FrontAwning",
        (0.0, front_y - 0.45, FOUNDATION_H + FRONT_DOOR_H + 0.18),
        (3.25, 0.90, 0.12),
        mats["awning"],
        root,
        collection,
        bevel=0.010,
    )

    # Front door frame
    front_frame_t = 0.14
    front_frame_depth = 0.12
    add_cube(
        "FrontDoorFrame_Left",
        (-FRONT_DOOR_W * 0.5 - front_frame_t * 0.5, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H * 0.5),
        (front_frame_t, front_frame_depth, FRONT_DOOR_H + 0.10),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "FrontDoorFrame_Right",
        (FRONT_DOOR_W * 0.5 + front_frame_t * 0.5, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H * 0.5),
        (front_frame_t, front_frame_depth, FRONT_DOOR_H + 0.10),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "FrontDoorFrame_Top",
        (0.0, front_y + WALL_T * 0.5 - 0.01, DOOR_BOTTOM_Z + FRONT_DOOR_H + 0.07),
        (FRONT_DOOR_W + front_frame_t * 2.0, front_frame_depth, front_frame_t),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )

    # Back door frame
    back_frame_t = 0.12
    back_frame_depth = 0.11
    add_cube(
        "BackDoorFrame_Left",
        (-BACK_DOOR_W * 0.5 - back_frame_t * 0.5, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H * 0.5),
        (back_frame_t, back_frame_depth, BACK_DOOR_H + 0.08),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "BackDoorFrame_Right",
        (BACK_DOOR_W * 0.5 + back_frame_t * 0.5, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H * 0.5),
        (back_frame_t, back_frame_depth, BACK_DOOR_H + 0.08),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "BackDoorFrame_Top",
        (0.0, back_y - WALL_T * 0.5 + 0.01, DOOR_BOTTOM_Z + BACK_DOOR_H + 0.06),
        (BACK_DOOR_W + back_frame_t * 2.0, back_frame_depth, back_frame_t),
        mats["trim"],
        root,
        collection,
        bevel=0.006,
    )

    # Front windows: two
    add_front_window(
        "FrontWindow_Left",
        -3.10,
        front_y - 0.04,
        WINDOW_CENTER_Z,
        FRONT_WINDOW_W,
        FRONT_WINDOW_H,
        mats,
        root,
        collection,
    )
    add_front_window(
        "FrontWindow_Right",
        3.10,
        front_y - 0.04,
        WINDOW_CENTER_Z,
        FRONT_WINDOW_W,
        FRONT_WINDOW_H,
        mats,
        root,
        collection,
    )

    # Side window: one on right side
    add_side_window(
        "RightSideWindow",
        right_x + 0.04,
        0.25,
        WINDOW_CENTER_Z,
        SIDE_WINDOW_W,
        SIDE_WINDOW_H,
        mats,
        root,
        collection,
    )

    # Doors as separate, hinge-ready mesh nodes
    front_hinge_x = -FRONT_DOOR_W * 0.5
    front_hinge_y = front_y - FRONT_DOOR_T * 0.5
    add_hinged_door(
        "Door_Front",
        (front_hinge_x, front_hinge_y, DOOR_BOTTOM_Z),
        FRONT_DOOR_W,
        FRONT_DOOR_T,
        FRONT_DOOR_H,
        mats["door"],
        root,
        collection,
        hinge_side="left",
        facing="front",
    )

    back_hinge_x = -BACK_DOOR_W * 0.5
    back_hinge_y = back_y + BACK_DOOR_T * 0.5
    add_hinged_door(
        "Door_Back",
        (back_hinge_x, back_hinge_y, DOOR_BOTTOM_Z),
        BACK_DOOR_W,
        BACK_DOOR_T,
        BACK_DOOR_H,
        mats["door"],
        root,
        collection,
        hinge_side="left",
        facing="back",
    )

    # Small front and rear steps
    add_cube(
        "Step_Front",
        (0.0, front_y - 0.58, 0.12),
        (2.55, 0.70, 0.24),
        mats["foundation"],
        root,
        collection,
        bevel=0.020,
    )
    add_cube(
        "Step_Back",
        (0.0, back_y + 0.42, 0.10),
        (1.35, 0.55, 0.20),
        mats["foundation"],
        root,
        collection,
        bevel=0.018,
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

    scene_bad = [
        obj.name for obj in bpy.context.scene.objects
        if obj.type in {"CAMERA", "LIGHT"}
    ]
    if scene_bad:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(scene_bad))

    # Door node checks
    front_door = bpy.data.objects.get("Door_Front")
    back_door = bpy.data.objects.get("Door_Back")
    if front_door is None or back_door is None:
        raise RuntimeError("VALIDATION FAILED: door nodes missing.")

    if not front_door.get("is_door", False) or not back_door.get("is_door", False):
        raise RuntimeError("VALIDATION FAILED: door flags missing.")

    if not front_door.get("no_merge", False) or not back_door.get("no_merge", False):
        raise RuntimeError("VALIDATION FAILED: door nodes were incorrectly marked for merge.")

    # Check doors still have local geometry and are separate from static mesh
    if front_door.name == ROOT_NAME + "_Static" or back_door.name == ROOT_NAME + "_Static":
        raise RuntimeError("VALIDATION FAILED: a door was merged into the static mesh.")

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
        f"  Front door node kept separate: {front_door.name}\n"
        f"  Back door node kept separate:  {back_door.name}\n"
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
    print("\n=== Generating Enterable Grocery Store ===\n")

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
    print(" - Interior is empty and enterable.")
    print(" - Door_Front and Door_Back remain separate mesh nodes.")
    print(" - Their origins are placed on hinge edges for rotation in Blender/Godot.")
