# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - Parish Office (Non-Enterable)
#
# Generates one static GLB parish office:
#   FTF_ParishOffice_NorthAmerican.glb
#
# DESIGN
# - Small to medium North-American church parish office
# - Non-enterable
# - Front faces local -Y
# - Main two-story office block
# - Side one-story meeting/admin wing
# - Entrance porch / canopy
# - Multiple windows
# - Closed doors
# - Suitable as a church-campus support building
#
# OUTPUT
#   generated_farmtown_buildings/FTF_ParishOffice_NorthAmerican.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmtown_parish_office.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_buildings")
OUTPUT_FILE = "FTF_ParishOffice_NorthAmerican.glb"

ROOT_NAME = "FTF_ParishOffice_NorthAmerican"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

FOUNDATION_H = 0.28

MAIN_W = 9.4
MAIN_D = 10.2
MAIN_WALL_H = 6.2
MAIN_ROOF_RISE = 2.4
MAIN_ROOF_OVERHANG = 0.35

WING_W = 5.4
WING_D = 7.0
WING_WALL_H = 3.8
WING_ROOF_H = 0.20

PORCH_W = 3.4
PORCH_D = 1.7
PORCH_H = 2.9

DOOR_W = 1.35
DOOR_H = 2.25
SIDE_DOOR_W = 1.05
SIDE_DOOR_H = 2.15

WINDOW_W = 1.25
WINDOW_H = 1.35
UPPER_WINDOW_W = 1.05
UPPER_WINDOW_H = 1.15
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
        "foundation": make_material("MAT_Parish_Foundation", (0.31, 0.31, 0.30), 0.88),
        "wall": make_material("MAT_Parish_Wall", (0.79, 0.77, 0.71), 0.82),
        "trim": make_material("MAT_Parish_Trim", (0.89, 0.87, 0.82), 0.72),
        "roof": make_material("MAT_Parish_Roof", (0.38, 0.18, 0.12), 0.75),
        "roof_dark": make_material("MAT_Parish_RoofDark", (0.14, 0.12, 0.11), 0.78),
        "window": make_material("MAT_Parish_Window", (0.08, 0.14, 0.19), 0.34, 0.03),
        "door": make_material("MAT_Parish_Door", (0.18, 0.10, 0.05), 0.80),
        "accent": make_material("MAT_Parish_Accent", (0.56, 0.45, 0.30), 0.82),
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


def add_gable_triangle(name, center_x, center_y, thickness_y, width_x, wall_top_z, ridge_z, material, parent, collection):
    half_w = width_x * 0.5
    front_y = center_y - thickness_y * 0.5
    back_y = center_y + thickness_y * 0.5
    verts = [
        (center_x - half_w, front_y, wall_top_z),
        (center_x + half_w, front_y, wall_top_z),
        (center_x, front_y, ridge_z),
        (center_x - half_w, back_y, wall_top_z),
        (center_x + half_w, back_y, wall_top_z),
        (center_x, back_y, ridge_z),
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


def add_closed_door_front(name, x, y, z_bottom, width, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, z_bottom + height * 0.5), (width, 0.09, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, z_bottom + height + 0.07), (width + 0.26, 0.12, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Left", (x - width * 0.5 - 0.07, y, z_bottom + height * 0.5), (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Right", (x + width * 0.5 + 0.07, y, z_bottom + height * 0.5), (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


def add_closed_door_side(name, x, y, z_bottom, width_y, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, z_bottom + height * 0.5), (0.09, width_y, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_Top", (x, y, z_bottom + height + 0.07), (0.12, width_y + 0.26, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Near", (x, y - width_y * 0.5 - 0.07, z_bottom + height * 0.5), (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Far", (x, y + width_y * 0.5 + 0.07, z_bottom + height * 0.5), (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


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


def build_office():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    main_cx = 0.0
    main_cy = 0.0
    wing_cx = 5.9
    wing_cy = 1.2
    porch_cx = 0.0
    porch_cy = -(MAIN_D * 0.5 + PORCH_D * 0.5 - 0.15)

    left_x = -MAIN_W * 0.5
    right_x = MAIN_W * 0.5
    front_y = -MAIN_D * 0.5
    back_y = MAIN_D * 0.5

    wing_left = wing_cx - WING_W * 0.5
    wing_right = wing_cx + WING_W * 0.5
    wing_front = wing_cy - WING_D * 0.5
    wing_back = wing_cy + WING_D * 0.5

    main_wall_top = FOUNDATION_H + MAIN_WALL_H
    main_ridge_z = main_wall_top + MAIN_ROOF_RISE

    # Foundations
    add_cube("Foundation_Main", (main_cx, main_cy, FOUNDATION_H * 0.5), (MAIN_W + 0.16, MAIN_D + 0.16, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Wing", (wing_cx, wing_cy, FOUNDATION_H * 0.5), (WING_W + 0.14, WING_D + 0.14, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Porch", (porch_cx, porch_cy, FOUNDATION_H * 0.5), (PORCH_W + 0.10, PORCH_D + 0.10, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.02)

    # Main masses
    add_cube("Body_Main", (main_cx, main_cy, FOUNDATION_H + MAIN_WALL_H * 0.5), (MAIN_W, MAIN_D, MAIN_WALL_H), mats["wall"], root, collection, bevel=0.016)
    add_cube("Body_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H * 0.5), (WING_W, WING_D, WING_WALL_H), mats["wall"], root, collection, bevel=0.014)
    add_cube("Body_Porch", (porch_cx, porch_cy, FOUNDATION_H + PORCH_H * 0.5), (PORCH_W, PORCH_D, PORCH_H), mats["wall"], root, collection, bevel=0.012)

    # Main roof
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

    # Wing and porch roofs
    add_cube("Roof_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H + WING_ROOF_H * 0.5),
             (WING_W + 0.25, WING_D + 0.25, WING_ROOF_H), mats["roof"], root, collection, bevel=0.012)
    add_cube("Roof_Porch", (porch_cx, porch_cy - 0.08, FOUNDATION_H + PORCH_H + 0.20),
             (PORCH_W + 0.20, PORCH_D + 0.18, 0.18), mats["roof"], root, collection, bevel=0.010, rotation=(math.radians(8.0), 0.0, 0.0))

    # Doors
    add_closed_door_front("Door_MainFront", 0.0, porch_cy - PORCH_D * 0.5 - 0.05, FOUNDATION_H, DOOR_W, DOOR_H, mats, root, collection)
    add_closed_door_side("Door_WingSide", wing_right + 0.05, wing_cy, FOUNDATION_H, SIDE_DOOR_W, SIDE_DOOR_H, mats, root, collection)
    add_closed_door_front("Door_RearService", -2.0, back_y + 0.05, FOUNDATION_H, 1.05, 2.10, mats, root, collection)

    # Porch columns
    for idx, x in enumerate([-0.95, 0.95]):
        add_cube(f"PorchColumn_{idx}", (x, porch_cy, FOUNDATION_H + 1.30), (0.24, 0.24, 2.60), mats["trim"], root, collection, bevel=0.008)

    # Windows - front
    add_front_window("FrontLowerWindow_L", -2.45, front_y - 0.05, FOUNDATION_H + 1.80, WINDOW_W, WINDOW_H, mats, root, collection)
    add_front_window("FrontLowerWindow_R", 2.45, front_y - 0.05, FOUNDATION_H + 1.80, WINDOW_W, WINDOW_H, mats, root, collection)
    add_front_window("FrontUpperWindow_L", -2.45, front_y - 0.05, FOUNDATION_H + 4.60, UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)
    add_front_window("FrontUpperWindow_R", 2.45, front_y - 0.05, FOUNDATION_H + 4.60, UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # Side windows main block
    side_ys = [-2.8, 0.2, 3.2]
    for i, y in enumerate(side_ys):
        add_side_window(f"MainLeftWindow_Lower_{i}", left_x - 0.05, y, FOUNDATION_H + 1.85, 1.20, 1.30, mats, root, collection)
        add_side_window(f"MainLeftWindow_Upper_{i}", left_x - 0.05, y, FOUNDATION_H + 4.65, 0.95, 1.10, mats, root, collection)

    # Back windows main block
    add_front_window("BackWindow_L", -2.35, back_y + 0.05, FOUNDATION_H + 1.85, WINDOW_W, WINDOW_H, mats, root, collection)
    add_front_window("BackWindow_R", 2.35, back_y + 0.05, FOUNDATION_H + 1.85, WINDOW_W, WINDOW_H, mats, root, collection)
    add_front_window("BackUpperWindow_L", -2.35, back_y + 0.05, FOUNDATION_H + 4.65, UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)
    add_front_window("BackUpperWindow_R", 2.35, back_y + 0.05, FOUNDATION_H + 4.65, UPPER_WINDOW_W, UPPER_WINDOW_H, mats, root, collection)

    # Wing windows
    add_front_window("WingFrontWindow", wing_cx, wing_front - 0.05, FOUNDATION_H + 1.70, 1.50, 1.35, mats, root, collection)
    add_front_window("WingBackWindow", wing_cx, wing_back + 0.05, FOUNDATION_H + 1.70, 1.50, 1.35, mats, root, collection)

    # Accent trim and step
    add_cube("Accent_PorchTrim", (0.0, porch_cy - PORCH_D * 0.5 - 0.01, FOUNDATION_H + 2.60), (PORCH_W, 0.10, 0.16), mats["accent"], root, collection, bevel=0.004)
    add_cube("Step_MainFront", (0.0, porch_cy - PORCH_D * 0.5 - 0.50, 0.14), (2.25, 0.82, 0.28), mats["foundation"], root, collection, bevel=0.016)

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
        raise RuntimeError("VALIDATION FAILED: no meshes under root.")

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


if __name__ == "__main__":
    print("\n=== Generating Parish Office ===\n")
    root = build_office()

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
