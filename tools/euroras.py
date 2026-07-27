# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - European Style Restaurant (Non-Enterable)
#
# Generates one static GLB restaurant asset:
#   FTF_Restaurant_European_Style.glb
#
# DESIGN
# - European-style small-town restaurant / bistro
# - Distinct from the earlier house / church / grocery layouts
# - Main two-story dining block
# - Rear / side kitchen-service wing
# - Front entrance canopy
# - Multiple arched-style windows
# - Closed doors
# - Non-enterable
# - Front faces local -Y
# - Root origin at ground center (0, 0, 0)
# - No yard, no collision shell, no lights, no cameras, no text
# - Static visual meshes are merged before GLB export
#
# OUTPUT
#   generated_farmtown_buildings/FTF_Restaurant_European_Style.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_european_restaurant.py
# ---------------------------------------------------------------------

import bpy
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
OUTPUT_FILE = "FTF_Restaurant_European_Style.glb"

ROOT_NAME = "FTF_Restaurant_European_Style"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True


# ---------------------------------------------------------------------
# DIMENSIONS (meters)
# ---------------------------------------------------------------------

FOUNDATION_H = 0.28

# Main restaurant block
MAIN_W = 11.2
MAIN_D = 9.8
MAIN_WALL_H = 6.2
MAIN_ROOF_RISE = 2.8
MAIN_ROOF_OVERHANG = 0.35

# Kitchen / service wing
WING_W = 5.8
WING_D = 6.8
WING_WALL_H = 3.8
WING_ROOF_H = 0.20

# Front entrance canopy / vestibule
CANOPY_W = 3.2
CANOPY_D = 1.9
CANOPY_H = 2.95

# Side bay / front projection for asymmetry
BAY_W = 3.2
BAY_D = 2.2
BAY_WALL_H = 4.2
BAY_ROOF_H = 0.18

# Doors / windows
FRONT_DOOR_W = 1.45
FRONT_DOOR_H = 2.30

SIDE_DOOR_W = 1.00
SIDE_DOOR_H = 2.15

SERVICE_DOOR_W = 1.00
SERVICE_DOOR_H = 2.10

LOWER_WINDOW_W = 1.55
LOWER_WINDOW_H = 1.95

UPPER_WINDOW_W = 1.25
UPPER_WINDOW_H = 1.45

PANEL_T = 0.05


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

def make_material(name, color, roughness=0.76, metallic=0.0):
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
        "foundation": make_material("MAT_Restaurant_Foundation", (0.31, 0.31, 0.30), 0.88),
        "wall": make_material("MAT_Restaurant_Stucco", (0.80, 0.73, 0.63), 0.80),
        "trim": make_material("MAT_Restaurant_Trim", (0.89, 0.85, 0.77), 0.72),
        "roof": make_material("MAT_Restaurant_Roof", (0.23, 0.23, 0.25), 0.78),
        "roof_dark": make_material("MAT_Restaurant_RoofDark", (0.11, 0.11, 0.12), 0.80),
        "window": make_material("MAT_Restaurant_Window", (0.08, 0.13, 0.18), 0.34, 0.03),
        "door": make_material("MAT_Restaurant_Door", (0.20, 0.11, 0.06), 0.80),
        "awning": make_material("MAT_Restaurant_Awning", (0.49, 0.18, 0.14), 0.76),
        "accent": make_material("MAT_Restaurant_Accent", (0.58, 0.42, 0.28), 0.80),
        "chimney": make_material("MAT_Restaurant_Chimney", (0.43, 0.18, 0.12), 0.86),
    }


# ---------------------------------------------------------------------
# PRIMITIVES
# ---------------------------------------------------------------------

def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_cube(name, location, dimensions, material, parent, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
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


def add_cylinder(name, location, radius, depth, material, parent, collection, vertices=16, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    move_to_collection(obj, collection)
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


# ---------------------------------------------------------------------
# DETAIL HELPERS
# ---------------------------------------------------------------------

def add_front_window(name, x, y, z, width, height, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.07
    add_cube(name + "_Pane", (x, y, z), (width, PANEL_T, height), mats["window"], parent, collection, bevel=0.006)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5), (width + trim_t * 2, trim_d, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5), (width + trim_t * 2, trim_d, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Left", (x - width * 0.5 + trim_t * 0.5, y, z), (trim_t, trim_d, height), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Right", (x + width * 0.5 - trim_t * 0.5, y, z), (trim_t, trim_d, height), mats["trim"], parent, collection, bevel=0.004)


def add_side_window(name, x, y, z, width_y, height, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.07
    add_cube(name + "_Pane", (x, y, z), (PANEL_T, width_y, height), mats["window"], parent, collection, bevel=0.006)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5), (trim_d, width_y + trim_t * 2, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5), (trim_d, width_y + trim_t * 2, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Near", (x, y - width_y * 0.5 + trim_t * 0.5, z), (trim_d, trim_t, height), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Far", (x, y + width_y * 0.5 - trim_t * 0.5, z), (trim_d, trim_t, height), mats["trim"], parent, collection, bevel=0.004)


def add_arched_front_window(name, x, y, z_center, width, rect_height, mats, parent, collection):
    """
    Simple low-poly arched window: a rectangular lower body plus a round top.
    """
    trim_t = 0.12
    rect_z = z_center - 0.22
    arch_radius = width * 0.5
    arch_center_z = rect_z + rect_height * 0.5
    total_h = rect_height + arch_radius

    # glass
    add_cube(name + "_RectPane", (x, y, rect_z), (width, PANEL_T, rect_height), mats["window"], parent, collection, bevel=0.006)
    add_cylinder(name + "_ArchPane", (x, y, arch_center_z), arch_radius, PANEL_T, mats["window"], parent, collection,
                 vertices=16, rotation=(math.radians(90), 0.0, 0.0), bevel=0.003)

    # trim
    add_cube(name + "_BottomTrim", (x, y, rect_z - rect_height * 0.5 + trim_t * 0.5), (width + trim_t * 2, 0.07, trim_t), mats["trim"], parent, collection, bevel=0.003)
    add_cube(name + "_LeftTrim", (x - width * 0.5 + trim_t * 0.5, y, rect_z), (trim_t, 0.07, rect_height), mats["trim"], parent, collection, bevel=0.003)
    add_cube(name + "_RightTrim", (x + width * 0.5 - trim_t * 0.5, y, rect_z), (trim_t, 0.07, rect_height), mats["trim"], parent, collection, bevel=0.003)
    add_cylinder(name + "_ArchTrim", (x, y, arch_center_z), arch_radius + 0.08, 0.07, mats["trim"], parent, collection,
                 vertices=16, rotation=(math.radians(90), 0.0, 0.0), bevel=0.003)

    return total_h


def add_closed_door_front(name, x, y, bottom_z, width, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, bottom_z + height * 0.5), (width, 0.09, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, bottom_z + height + 0.07), (width + 0.26, 0.12, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Left", (x - width * 0.5 - 0.07, y, bottom_z + height * 0.5), (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Right", (x + width * 0.5 + 0.07, y, bottom_z + height * 0.5), (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


def add_closed_door_side(name, x, y, bottom_z, width_y, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, bottom_z + height * 0.5), (0.09, width_y, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, bottom_z + height + 0.07), (0.12, width_y + 0.26, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Near", (x, y - width_y * 0.5 - 0.07, bottom_z + height * 0.5), (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Far", (x, y + width_y * 0.5 + 0.07, bottom_z + height * 0.5), (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


# ---------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------

def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.75
    root["asset_type"] = "StaticEnvironmentBuilding"
    root["visual_forward_axis"] = "-Y"
    root["up_axis"] = "+Z"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = False
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES
    collection.objects.link(root)
    return root


def build_restaurant():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    main_cx = 0.0
    main_cy = 0.0

    wing_cx = 5.2
    wing_cy = 1.9

    canopy_cx = 0.0
    canopy_cy = -(MAIN_D * 0.5 + CANOPY_D * 0.5 - 0.15)

    bay_cx = -3.25
    bay_cy = -(MAIN_D * 0.5 + BAY_D * 0.5 - 0.20)

    left_x = -MAIN_W * 0.5
    right_x = MAIN_W * 0.5
    front_y = -MAIN_D * 0.5
    back_y = MAIN_D * 0.5

    wing_right = wing_cx + WING_W * 0.5
    wing_left = wing_cx - WING_W * 0.5
    wing_front = wing_cy - WING_D * 0.5
    wing_back = wing_cy + WING_D * 0.5

    main_wall_top = FOUNDATION_H + MAIN_WALL_H
    main_ridge_z = main_wall_top + MAIN_ROOF_RISE

    # ---------------------------------------------------------
    # Foundations
    # ---------------------------------------------------------
    add_cube("Foundation_Main", (main_cx, main_cy, FOUNDATION_H * 0.5),
             (MAIN_W + 0.16, MAIN_D + 0.16, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Wing", (wing_cx, wing_cy, FOUNDATION_H * 0.5),
             (WING_W + 0.14, WING_D + 0.14, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Canopy", (canopy_cx, canopy_cy, FOUNDATION_H * 0.5),
             (CANOPY_W + 0.08, CANOPY_D + 0.08, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.02)
    add_cube("Foundation_Bay", (bay_cx, bay_cy, FOUNDATION_H * 0.5),
             (BAY_W + 0.08, BAY_D + 0.08, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.02)

    # ---------------------------------------------------------
    # Main masses
    # ---------------------------------------------------------
    add_cube("Body_Main", (main_cx, main_cy, FOUNDATION_H + MAIN_WALL_H * 0.5),
             (MAIN_W, MAIN_D, MAIN_WALL_H), mats["wall"], root, collection, bevel=0.016)
    add_cube("Body_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H * 0.5),
             (WING_W, WING_D, WING_WALL_H), mats["wall"], root, collection, bevel=0.014)
    add_cube("Body_CanopyVestibule", (canopy_cx, canopy_cy, FOUNDATION_H + CANOPY_H * 0.5),
             (CANOPY_W, CANOPY_D, CANOPY_H), mats["wall"], root, collection, bevel=0.012)
    add_cube("Body_FrontBay", (bay_cx, bay_cy, FOUNDATION_H + BAY_WALL_H * 0.5),
             (BAY_W, BAY_D, BAY_WALL_H), mats["wall"], root, collection, bevel=0.012)

    # ---------------------------------------------------------
    # Roofs
    # ---------------------------------------------------------
    half_span = MAIN_W * 0.5 + MAIN_ROOF_OVERHANG
    roof_depth = MAIN_D + MAIN_ROOF_OVERHANG * 2.0
    roof_len = math.sqrt(half_span ** 2 + MAIN_ROOF_RISE ** 2) + 0.18
    pitch = math.atan2(MAIN_ROOF_RISE, half_span)
    roof_center_z = main_wall_top + MAIN_ROOF_RISE * 0.5

    add_cube("Roof_Main_Right", (main_cx + half_span * 0.5, main_cy, roof_center_z),
             (roof_len, roof_depth, 0.22), mats["roof"], root, collection, bevel=0.018, rotation=(0.0, pitch, 0.0))
    add_cube("Roof_Main_Left", (main_cx - half_span * 0.5, main_cy, roof_center_z),
             (roof_len, roof_depth, 0.22), mats["roof"], root, collection, bevel=0.018, rotation=(0.0, -pitch, 0.0))
    add_cube("Roof_Main_Ridge", (main_cx, main_cy, main_ridge_z + 0.04),
             (0.22, roof_depth + 0.05, 0.16), mats["roof_dark"], root, collection, bevel=0.010)

    add_gable_triangle("Gable_Main_Front", main_cx, front_y - 0.01, 0.10, MAIN_W, main_wall_top, main_ridge_z, mats["wall"], root, collection)
    add_gable_triangle("Gable_Main_Back", main_cx, back_y + 0.01, 0.10, MAIN_W, main_wall_top, main_ridge_z, mats["wall"], root, collection)

    add_cube("Roof_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H + WING_ROOF_H * 0.5),
             (WING_W + 0.22, WING_D + 0.22, WING_ROOF_H), mats["roof"], root, collection, bevel=0.012)

    add_cube("Roof_Canopy", (canopy_cx, canopy_cy - 0.05, FOUNDATION_H + CANOPY_H + 0.18),
             (CANOPY_W + 0.16, CANOPY_D + 0.18, 0.18), mats["awning"], root, collection, bevel=0.010,
             rotation=(math.radians(7.0), 0.0, 0.0))

    add_cube("Roof_Bay", (bay_cx, bay_cy, FOUNDATION_H + BAY_WALL_H + BAY_ROOF_H * 0.5),
             (BAY_W + 0.16, BAY_D + 0.16, BAY_ROOF_H), mats["roof"], root, collection, bevel=0.010)

    # Chimneys
    add_cube("Chimney_Main", (2.65, 1.55, main_wall_top + 1.35),
             (0.70, 0.70, 2.20), mats["chimney"], root, collection, bevel=0.008)
    add_cube("Chimney_Cap", (2.65, 1.55, main_wall_top + 2.52),
             (0.86, 0.86, 0.16), mats["foundation"], root, collection, bevel=0.006)

    # ---------------------------------------------------------
    # Doors
    # ---------------------------------------------------------
    add_closed_door_front("Door_MainFront", 0.0, canopy_cy - CANOPY_D * 0.5 - 0.05,
                          FOUNDATION_H, FRONT_DOOR_W, FRONT_DOOR_H, mats, root, collection)
    add_closed_door_side("Door_SidePatio", left_x - 0.05, 1.15,
                         FOUNDATION_H, SIDE_DOOR_W, SIDE_DOOR_H, mats, root, collection)
    add_closed_door_front("Door_ServiceRear", wing_cx, wing_back + 0.05,
                          FOUNDATION_H, SERVICE_DOOR_W, SERVICE_DOOR_H, mats, root, collection)

    # Canopy columns
    for idx, x in enumerate([-0.92, 0.92]):
        add_cube(f"CanopyColumn_{idx}", (x, canopy_cy, FOUNDATION_H + 1.30),
                 (0.24, 0.24, 2.60), mats["trim"], root, collection, bevel=0.006)

    # ---------------------------------------------------------
    # Windows
    # ---------------------------------------------------------
    # Front facade: large arched windows around centered entry
    add_arched_front_window("FrontArchWindow_L", -3.05, front_y - 0.05,
                            FOUNDATION_H + 2.05, 1.58, 1.48, mats, root, collection)
    add_arched_front_window("FrontArchWindow_R", 3.05, front_y - 0.05,
                            FOUNDATION_H + 2.05, 1.58, 1.48, mats, root, collection)

    # Front bay window
    add_arched_front_window("FrontBayArchWindow", bay_cx, bay_cy - BAY_D * 0.5 - 0.05,
                            FOUNDATION_H + 1.95, 1.48, 1.40, mats, root, collection)

    # Upper front windows
    add_front_window("FrontUpperWindow_L", -2.20, front_y - 0.05, FOUNDATION_H + 4.85,
                     UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)
    add_front_window("FrontUpperWindow_R", 2.20, front_y - 0.05, FOUNDATION_H + 4.85,
                     UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # Left side windows
    left_side_ys = [-2.35, 2.15]
    for i, y in enumerate(left_side_ys):
        add_side_window(f"LeftLowerWindow_{i}", left_x - 0.05, y, FOUNDATION_H + 2.00,
                        LOWER_WINDOW_W, LOWER_WINDOW_H, mats, root, collection)
        add_side_window(f"LeftUpperWindow_{i}", left_x - 0.05, y, FOUNDATION_H + 4.85,
                        UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # Right side windows - on exposed portions of main block only
    add_side_window("RightMainLowerWindow", right_x + 0.05, -2.35, FOUNDATION_H + 2.00,
                    LOWER_WINDOW_W, LOWER_WINDOW_H, mats, root, collection)
    add_side_window("RightMainUpperWindow", right_x + 0.05, -2.35, FOUNDATION_H + 4.85,
                    UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # Wing windows
    add_front_window("WingFrontWindow", wing_cx, wing_front - 0.05, FOUNDATION_H + 1.80,
                     1.45, 1.55, mats, root, collection)
    add_side_window("WingRightWindow", wing_right + 0.05, wing_cy, FOUNDATION_H + 1.80,
                    1.60, 1.50, mats, root, collection)

    # Rear windows
    add_front_window("BackWindow_Left", -2.55, back_y + 0.05, FOUNDATION_H + 2.00,
                     LOWER_WINDOW_W, LOWER_WINDOW_H, mats, root, collection)
    add_front_window("BackWindow_Right", 1.25, back_y + 0.05, FOUNDATION_H + 2.00,
                     LOWER_WINDOW_W, LOWER_WINDOW_H, mats, root, collection)
    add_front_window("BackUpperWindow_Left", -2.55, back_y + 0.05, FOUNDATION_H + 4.85,
                     UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)
    add_front_window("BackUpperWindow_Right", 1.25, back_y + 0.05, FOUNDATION_H + 4.85,
                     UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # ---------------------------------------------------------
    # Decorative accents
    # ---------------------------------------------------------
    # Front string course
    add_cube("FrontStringCourse", (0.0, front_y - 0.01, FOUNDATION_H + 3.20),
             (MAIN_W, 0.08, 0.18), mats["accent"], root, collection, bevel=0.004)
    add_cube("BayAccentTrim", (bay_cx, bay_cy - BAY_D * 0.5 - 0.01, FOUNDATION_H + 2.85),
             (BAY_W, 0.08, 0.16), mats["accent"], root, collection, bevel=0.004)

    # Window boxes below front ground-floor windows
    for idx, x in enumerate([-3.05, 3.05]):
        add_cube(f"WindowBox_{idx}", (x, front_y - 0.18, FOUNDATION_H + 0.98),
                 (1.55, 0.30, 0.20), mats["accent"], root, collection, bevel=0.004)

    # Front step
    add_cube("Step_MainFront", (0.0, canopy_cy - CANOPY_D * 0.5 - 0.48, 0.14),
             (2.30, 0.82, 0.28), mats["foundation"], root, collection, bevel=0.016)

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


def merge_static_meshes(root):
    meshes = get_meshes_under_root(root)
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
    merged.name = ROOT_NAME + "_Static"
    merged.parent = root
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
        raise RuntimeError("VALIDATION FAILED: no meshes found under root.")

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
        f"  Style: European small-town restaurant / bistro\n"
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
    print("\n=== Generating European Style Restaurant ===\n")

    root = build_restaurant()

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - New European-style restaurant, not directly based on the earlier assets.")
    print(" - Non-enterable static building.")
