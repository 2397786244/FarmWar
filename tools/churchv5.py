# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town Pack - Rural Church (Light) + Parish Office
#
# This single script exports BOTH assets:
#   1) FTF_RuralChurch_Large_TwoStory_Light.glb
#   2) FTF_ParishOffice_NorthAmerican.glb
#
# USER-REQUESTED FIXES INCLUDED
# - Church:
#   * Only keep the light church version
#   * Remove the side doors to avoid the remaining side-door nesting / occlusion issue
# - Parish office:
#   * Keep the rear service door
#   * Remove the overlapping rear lower-left window that conflicted with the rear door
# - Additional church fix in this version:
#   * Remove annex windows and reduce side-window count to prevent any remaining overlap
#   * Remove all front/back windows on the cross-wing (transept) block
#
# COMMON
# - Front faces local -Y
# - Root at ground origin
# - Non-enterable
# - No yard, no collision shell, no lights, no cameras, no text
# - Static meshes merged before GLB export
#
# OUTPUT DIRECTORY
#   generated_farmtown_buildings/
#
# Run:
#   blender --background --factory-startup --python generate_church_and_parish_pack.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# GLOBAL EXPORT SETTINGS
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_buildings")

CLEAR_SCENE_BEFORE_ASSET = True
MERGE_STATIC_MESHES = True


# ---------------------------------------------------------------------
# SHARED HELPERS
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


def add_cylinder(name, location, radius, depth, material, parent, collection,
                 vertices=16, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_cone(name, location, radius1, depth, material, parent, collection,
             vertices=8, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=0.0,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_gable_triangle(name, center_x, center_y, thickness_y, width_x,
                       wall_top_z, ridge_z, material, parent, collection):
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


def add_cross(name, location, material, parent, collection, height=1.55, arm_width=0.95, thickness=0.12):
    x, y, z = location
    add_cube(name + "_Vertical", (x, y, z + height * 0.5),
             (thickness, thickness, height), material, parent, collection, bevel=0.005)
    add_cube(name + "_Horizontal", (x, y, z + height * 0.70),
             (arm_width, thickness, thickness), material, parent, collection, bevel=0.005)


def add_front_window(name, x, y, z, width, height, panel_t, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.075
    add_cube(name + "_Pane", (x, y, z), (width, panel_t, height),
             mats["window"], parent, collection, bevel=0.007)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (width + trim_t * 2, trim_d, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (width + trim_t * 2, trim_d, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Left", (x - width * 0.5 + trim_t * 0.5, y, z),
             (trim_t, trim_d, height), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Right", (x + width * 0.5 - trim_t * 0.5, y, z),
             (trim_t, trim_d, height), mats["trim"], parent, collection, bevel=0.004)


def add_side_window(name, x, y, z, width_y, height, panel_t, mats, parent, collection):
    trim_t = 0.12
    trim_d = 0.075
    add_cube(name + "_Pane", (x, y, z), (panel_t, width_y, height),
             mats["window"], parent, collection, bevel=0.007)
    add_cube(name + "_Top", (x, y, z + height * 0.5 - trim_t * 0.5),
             (trim_d, width_y + trim_t * 2, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Bottom", (x, y, z - height * 0.5 + trim_t * 0.5),
             (trim_d, width_y + trim_t * 2, trim_t), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Near", (x, y - width_y * 0.5 + trim_t * 0.5, z),
             (trim_d, trim_t, height), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_Far", (x, y + width_y * 0.5 - trim_t * 0.5, z),
             (trim_d, trim_t, height), mats["trim"], parent, collection, bevel=0.004)


def add_round_window(name, x, y, z, diameter, panel_t, mats, parent, collection, facing="front"):
    if facing in ("front", "back"):
        add_cylinder(name + "_Pane", (x, y, z), diameter * 0.5, panel_t,
                     mats["window"], parent, collection, vertices=16,
                     rotation=(math.radians(90), 0.0, 0.0), bevel=0.003)
        add_cylinder(name + "_Trim", (x, y, z), diameter * 0.5 + 0.08, 0.08,
                     mats["trim"], parent, collection, vertices=16,
                     rotation=(math.radians(90), 0.0, 0.0), bevel=0.003)
    else:
        add_cylinder(name + "_Pane", (x, y, z), diameter * 0.5, panel_t,
                     mats["window"], parent, collection, vertices=16,
                     rotation=(0.0, math.radians(90), 0.0), bevel=0.003)
        add_cylinder(name + "_Trim", (x, y, z), diameter * 0.5 + 0.08, 0.08,
                     mats["trim"], parent, collection, vertices=16,
                     rotation=(0.0, math.radians(90), 0.0), bevel=0.003)


def add_closed_door_front(name, x, y, bottom_z, width, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, bottom_z + height * 0.5),
             (width, 0.09, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_FrameTop", (x, y, bottom_z + height + 0.07),
             (width + 0.28, 0.12, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_FrameLeft", (x - width * 0.5 - 0.07, y, bottom_z + height * 0.5),
             (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_FrameRight", (x + width * 0.5 + 0.07, y, bottom_z + height * 0.5),
             (0.14, 0.12, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


def add_closed_door_side(name, x, y, bottom_z, width_y, height, mats, parent, collection):
    add_cube(name + "_Panel", (x, y, bottom_z + height * 0.5),
             (0.09, width_y, height), mats["door"], parent, collection, bevel=0.008)
    add_cube(name + "_FrameTop", (x, y, bottom_z + height + 0.07),
             (0.12, width_y + 0.28, 0.14), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_FrameNear", (x, y - width_y * 0.5 - 0.07, bottom_z + height * 0.5),
             (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)
    add_cube(name + "_FrameFar", (x, y + width_y * 0.5 + 0.07, bottom_z + height * 0.5),
             (0.12, 0.14, height + 0.10), mats["trim"], parent, collection, bevel=0.004)


def add_buttress_front(name, x, y, z_bottom, height, mats, parent, collection):
    add_cube(name, (x, y, z_bottom + height * 0.5),
             (0.48, 0.52, height), mats["trim"], parent, collection, bevel=0.004)


def add_buttress_side(name, x, y, z_bottom, height, mats, parent, collection):
    add_cube(name, (x, y, z_bottom + height * 0.5),
             (0.52, 0.48, height), mats["trim"], parent, collection, bevel=0.004)


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
    merged.name = root.name + "_Static"
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

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(forbidden))

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


# ---------------------------------------------------------------------
# CHURCH
# ---------------------------------------------------------------------

def church_materials():
    return {
        "foundation": make_material("MAT_Church_Foundation", (0.31, 0.31, 0.30), 0.88),
        "wall": make_material("MAT_Church_Wall", (0.85, 0.84, 0.79), 0.82),
        "wall_shadow": make_material("MAT_Church_WallShadow", (0.74, 0.73, 0.68), 0.85),
        "trim": make_material("MAT_Church_Trim", (0.92, 0.90, 0.85), 0.72),
        "roof": make_material("MAT_Church_Roof", (0.43, 0.17, 0.11), 0.74),
        "roof_dark": make_material("MAT_Church_RoofDark", (0.13, 0.12, 0.11), 0.76),
        "door": make_material("MAT_Church_Door", (0.18, 0.10, 0.055), 0.80),
        "window": make_material("MAT_Church_Window", (0.10, 0.16, 0.22), 0.34, 0.03),
        "steeple": make_material("MAT_Church_Steeple", (0.84, 0.83, 0.80), 0.78),
        "accent": make_material("MAT_Church_Accent", (0.57, 0.47, 0.31), 0.82),
    }


def create_root(root_name, collection):
    root = bpy.data.objects.new(root_name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.85
    root["asset_type"] = "StaticEnvironmentBuilding"
    root["visual_forward_axis"] = "-Y"
    root["up_axis"] = "+Z"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = False
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES
    collection.objects.link(root)
    return root


def validate_church_layout():
    NAVE_D = 18.8
    ANNEX_D = 7.1
    TRANSEPT_D = 6.7

    nave_front = -NAVE_D * 0.5
    nave_back = NAVE_D * 0.5

    annex_front = -2.25 - ANNEX_D * 0.5
    annex_back = -2.25 + ANNEX_D * 0.5

    tran_front = 1.10 - TRANSEPT_D * 0.5
    tran_back = 1.10 + TRANSEPT_D * 0.5

    exposed_front_len = annex_front - nave_front
    exposed_back_len = nave_back - tran_back

    if exposed_front_len < 2.0 or exposed_back_len < 2.0:
        raise RuntimeError("Church layout invalid: exposed nave side segments too small.")


def build_church():
    if CLEAR_SCENE_BEFORE_ASSET:
        clear_scene()
    configure_scene()
    validate_church_layout()

    root_name = "FTF_RuralChurch_Large_TwoStory_Light"
    collection = get_or_create_collection("COL_" + root_name)
    mats = church_materials()
    root = create_root(root_name, collection)

    FOUNDATION_H = 0.34
    NAVE_W = 11.6
    NAVE_D = 18.8
    NAVE_WALL_H = 6.7
    NAVE_ROOF_RISE = 3.3
    NAVE_ROOF_OVERHANG = 0.45

    TOWER_W = 5.4
    TOWER_D = 4.7
    TOWER_WALL_H = 10.4
    TOWER_BELFRY_H = 1.55
    SPIRE_BASE_H = 0.70
    SPIRE_H = 5.8

    PORCH_W = 4.7
    PORCH_D = 2.1
    PORCH_H = 3.25

    TRANSEPT_W = 17.2
    TRANSEPT_D = 6.7
    TRANSEPT_WALL_H = 6.0
    TRANSEPT_ROOF_RISE = 2.5
    TRANSEPT_ROOF_OVERHANG = 0.35

    CHANCEL_W = 8.8
    CHANCEL_D = 6.8
    CHANCEL_WALL_H = 6.0
    CHANCEL_ROOF_RISE = 2.4

    ANNEX_W = 4.1
    ANNEX_D = 7.1
    ANNEX_WALL_H = 4.1
    ANNEX_ROOF_H = 0.22

    WINDOW_PANEL_T = 0.06
    FRONT_DOOR_W = 1.7
    FRONT_DOOR_H = 2.55

    nave_cx = 0.0
    nave_cy = 0.0
    transept_cx = 0.0
    transept_cy = 1.10
    chancel_cx = 0.0
    chancel_cy = nave_cy + NAVE_D * 0.5 + CHANCEL_D * 0.5 - 0.35
    tower_cx = 0.0
    tower_cy = nave_cy - NAVE_D * 0.5 - TOWER_D * 0.5 + 0.12
    porch_cx = 0.0
    porch_cy = tower_cy - TOWER_D * 0.5 - PORCH_D * 0.5 + 0.18
    annex_l_cx = -(NAVE_W * 0.5 + ANNEX_W * 0.5 - 0.28)
    annex_l_cy = -2.25
    annex_r_cx = +(NAVE_W * 0.5 + ANNEX_W * 0.5 - 0.28)
    annex_r_cy = -2.25

    nave_left = nave_cx - NAVE_W * 0.5
    nave_right = nave_cx + NAVE_W * 0.5
    nave_front = nave_cy - NAVE_D * 0.5
    nave_back = nave_cy + NAVE_D * 0.5
    nave_wall_top = FOUNDATION_H + NAVE_WALL_H
    nave_ridge_z = nave_wall_top + NAVE_ROOF_RISE

    tran_left = transept_cx - TRANSEPT_W * 0.5
    tran_right = transept_cx + TRANSEPT_W * 0.5
    tran_front = transept_cy - TRANSEPT_D * 0.5
    tran_back = transept_cy + TRANSEPT_D * 0.5
    tran_wall_top = FOUNDATION_H + TRANSEPT_WALL_H
    tran_ridge_z = tran_wall_top + TRANSEPT_ROOF_RISE

    chancel_back = chancel_cy + CHANCEL_D * 0.5
    chancel_wall_top = FOUNDATION_H + CHANCEL_WALL_H
    chancel_ridge_z = chancel_wall_top + CHANCEL_ROOF_RISE

    tower_front = tower_cy - TOWER_D * 0.5
    tower_back = tower_cy + TOWER_D * 0.5

    # Foundations
    add_cube("Foundation_Nave", (nave_cx, nave_cy, FOUNDATION_H * 0.5),
             (NAVE_W + 0.22, NAVE_D + 0.22, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.04)
    add_cube("Foundation_Transept", (transept_cx, transept_cy, FOUNDATION_H * 0.5),
             (TRANSEPT_W + 0.18, TRANSEPT_D + 0.18, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.04)
    add_cube("Foundation_Chancel", (chancel_cx, chancel_cy, FOUNDATION_H * 0.5),
             (CHANCEL_W + 0.16, CHANCEL_D + 0.16, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.04)
    add_cube("Foundation_Tower", (tower_cx, tower_cy, FOUNDATION_H * 0.5),
             (TOWER_W + 0.18, TOWER_D + 0.18, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.035)
    add_cube("Foundation_Porch", (porch_cx, porch_cy, FOUNDATION_H * 0.5),
             (PORCH_W + 0.08, PORCH_D + 0.08, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Annex_Left", (annex_l_cx, annex_l_cy, FOUNDATION_H * 0.5),
             (ANNEX_W + 0.12, ANNEX_D + 0.12, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Annex_Right", (annex_r_cx, annex_r_cy, FOUNDATION_H * 0.5),
             (ANNEX_W + 0.12, ANNEX_D + 0.12, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)

    # Main bodies
    add_cube("Body_Nave", (nave_cx, nave_cy, FOUNDATION_H + NAVE_WALL_H * 0.5),
             (NAVE_W, NAVE_D, NAVE_WALL_H), mats["wall"], root, collection, bevel=0.018)
    add_cube("Body_Transept", (transept_cx, transept_cy, FOUNDATION_H + TRANSEPT_WALL_H * 0.5),
             (TRANSEPT_W, TRANSEPT_D, TRANSEPT_WALL_H), mats["wall"], root, collection, bevel=0.016)
    add_cube("Body_Chancel", (chancel_cx, chancel_cy, FOUNDATION_H + CHANCEL_WALL_H * 0.5),
             (CHANCEL_W, CHANCEL_D, CHANCEL_WALL_H), mats["wall"], root, collection, bevel=0.016)
    add_cube("Body_Tower", (tower_cx, tower_cy, FOUNDATION_H + TOWER_WALL_H * 0.5),
             (TOWER_W, TOWER_D, TOWER_WALL_H), mats["wall"], root, collection, bevel=0.018)
    add_cube("Body_Porch", (porch_cx, porch_cy, FOUNDATION_H + PORCH_H * 0.5),
             (PORCH_W, PORCH_D, PORCH_H), mats["wall"], root, collection, bevel=0.014)
    add_cube("Body_Annex_Left", (annex_l_cx, annex_l_cy, FOUNDATION_H + ANNEX_WALL_H * 0.5),
             (ANNEX_W, ANNEX_D, ANNEX_WALL_H), mats["wall"], root, collection, bevel=0.014)
    add_cube("Body_Annex_Right", (annex_r_cx, annex_r_cy, FOUNDATION_H + ANNEX_WALL_H * 0.5),
             (ANNEX_W, ANNEX_D, ANNEX_WALL_H), mats["wall"], root, collection, bevel=0.014)

    # Roofs
    nave_half_span = NAVE_W * 0.5 + NAVE_ROOF_OVERHANG
    nave_roof_depth = NAVE_D + NAVE_ROOF_OVERHANG * 2.0
    nave_roof_len = math.sqrt(nave_half_span ** 2 + NAVE_ROOF_RISE ** 2) + 0.20
    nave_pitch = math.atan2(NAVE_ROOF_RISE, nave_half_span)
    nave_roof_center_z = nave_wall_top + NAVE_ROOF_RISE * 0.5

    add_cube("Roof_Nave_Right", (nave_cx + nave_half_span * 0.5, nave_cy, nave_roof_center_z),
             (nave_roof_len, nave_roof_depth, 0.22), mats["roof"], root, collection, bevel=0.022,
             rotation=(0.0, nave_pitch, 0.0))
    add_cube("Roof_Nave_Left", (nave_cx - nave_half_span * 0.5, nave_cy, nave_roof_center_z),
             (nave_roof_len, nave_roof_depth, 0.22), mats["roof"], root, collection, bevel=0.022,
             rotation=(0.0, -nave_pitch, 0.0))
    add_cube("Roof_Nave_Ridge", (nave_cx, nave_cy, nave_ridge_z + 0.04),
             (0.24, nave_roof_depth + 0.05, 0.16), mats["roof_dark"], root, collection, bevel=0.012)

    add_gable_triangle("Gable_Nave_Front", nave_cx, nave_front - 0.012, 0.10, NAVE_W,
                       nave_wall_top, nave_ridge_z, mats["wall"], root, collection)
    add_gable_triangle("Gable_Nave_Back", nave_cx, nave_back + 0.012, 0.10, NAVE_W,
                       nave_wall_top, nave_ridge_z, mats["wall"], root, collection)

    tran_half_span_y = TRANSEPT_D * 0.5 + TRANSEPT_ROOF_OVERHANG
    tran_roof_width_x = TRANSEPT_W + TRANSEPT_ROOF_OVERHANG * 2.0
    tran_roof_len = math.sqrt(tran_half_span_y ** 2 + TRANSEPT_ROOF_RISE ** 2) + 0.18
    tran_pitch = math.atan2(TRANSEPT_ROOF_RISE, tran_half_span_y)
    tran_roof_center_z = tran_wall_top + TRANSEPT_ROOF_RISE * 0.5

    add_cube("Roof_Transept_Front", (transept_cx, transept_cy - tran_half_span_y * 0.5, tran_roof_center_z),
             (tran_roof_width_x, tran_roof_len, 0.22), mats["roof"], root, collection, bevel=0.020,
             rotation=(tran_pitch, 0.0, 0.0))
    add_cube("Roof_Transept_Back", (transept_cx, transept_cy + tran_half_span_y * 0.5, tran_roof_center_z),
             (tran_roof_width_x, tran_roof_len, 0.22), mats["roof"], root, collection, bevel=0.020,
             rotation=(-tran_pitch, 0.0, 0.0))
    add_cube("Roof_Transept_Ridge", (transept_cx, transept_cy, tran_ridge_z + 0.04),
             (tran_roof_width_x + 0.05, 0.24, 0.16), mats["roof_dark"], root, collection, bevel=0.012)

    chanc_half_span = CHANCEL_W * 0.5 + 0.38
    chanc_roof_depth = CHANCEL_D + 0.70
    chanc_roof_len = math.sqrt(chanc_half_span ** 2 + CHANCEL_ROOF_RISE ** 2) + 0.18
    chanc_pitch = math.atan2(CHANCEL_ROOF_RISE, chanc_half_span)
    chanc_roof_center_z = chancel_wall_top + CHANCEL_ROOF_RISE * 0.5

    add_cube("Roof_Chancel_Right", (chancel_cx + chanc_half_span * 0.5, chancel_cy, chanc_roof_center_z),
             (chanc_roof_len, chanc_roof_depth, 0.22), mats["roof"], root, collection, bevel=0.018,
             rotation=(0.0, chanc_pitch, 0.0))
    add_cube("Roof_Chancel_Left", (chancel_cx - chanc_half_span * 0.5, chancel_cy, chanc_roof_center_z),
             (chanc_roof_len, chanc_roof_depth, 0.22), mats["roof"], root, collection, bevel=0.018,
             rotation=(0.0, -chanc_pitch, 0.0))
    add_cube("Roof_Chancel_Ridge", (chancel_cx, chancel_cy, chancel_ridge_z + 0.04),
             (0.22, chanc_roof_depth + 0.04, 0.16), mats["roof_dark"], root, collection, bevel=0.010)
    add_gable_triangle("Gable_Chancel_Back", chancel_cx, chancel_back + 0.010, 0.10, CHANCEL_W,
                       chancel_wall_top, chancel_ridge_z, mats["wall"], root, collection)

    add_cube("Roof_Porch", (porch_cx, porch_cy - 0.10, FOUNDATION_H + PORCH_H + 0.22),
             (PORCH_W + 0.30, PORCH_D + 0.18, 0.18), mats["roof"], root, collection, bevel=0.014,
             rotation=(math.radians(9.0), 0.0, 0.0))
    add_cube("Roof_Annex_Left", (annex_l_cx, annex_l_cy, FOUNDATION_H + ANNEX_WALL_H + ANNEX_ROOF_H * 0.5),
             (ANNEX_W + 0.25, ANNEX_D + 0.25, ANNEX_ROOF_H), mats["roof"], root, collection, bevel=0.012)
    add_cube("Roof_Annex_Right", (annex_r_cx, annex_r_cy, FOUNDATION_H + ANNEX_WALL_H + ANNEX_ROOF_H * 0.5),
             (ANNEX_W + 0.25, ANNEX_D + 0.25, ANNEX_ROOF_H), mats["roof"], root, collection, bevel=0.012)

    belfry_z = FOUNDATION_H + TOWER_WALL_H + TOWER_BELFRY_H * 0.5
    add_cube("Tower_Belfry", (tower_cx, tower_cy, belfry_z),
             (TOWER_W - 0.45, TOWER_D - 0.45, TOWER_BELFRY_H), mats["trim"], root, collection, bevel=0.014)

    spire_base_z = FOUNDATION_H + TOWER_WALL_H + TOWER_BELFRY_H + SPIRE_BASE_H * 0.5
    add_cube("Tower_SpireBase", (tower_cx, tower_cy, spire_base_z),
             (2.05, 2.05, SPIRE_BASE_H), mats["steeple"], root, collection, bevel=0.010)

    spire_center_z = FOUNDATION_H + TOWER_WALL_H + TOWER_BELFRY_H + SPIRE_BASE_H + SPIRE_H * 0.5
    add_cone("Tower_Spire", (tower_cx, tower_cy, spire_center_z),
             1.55, SPIRE_H, mats["steeple"], root, collection, vertices=8, bevel=0.004)
    add_cross("Tower_Cross", (tower_cx, tower_cy, FOUNDATION_H + TOWER_WALL_H + TOWER_BELFRY_H + SPIRE_BASE_H + SPIRE_H),
              mats["trim"], root, collection, height=1.40, arm_width=0.85, thickness=0.10)

    # Trims
    belt_z = FOUNDATION_H + 3.25
    add_cube("Nave_Belt_Front", (nave_cx, nave_front - 0.008, belt_z),
             (NAVE_W + 0.12, 0.10, 0.22), mats["trim"], root, collection, bevel=0.006)
    add_cube("Nave_Belt_Back", (nave_cx, nave_back + 0.008, belt_z),
             (NAVE_W + 0.12, 0.10, 0.22), mats["trim"], root, collection, bevel=0.006)
    add_cube("Nave_Belt_Left", (nave_left - 0.008, nave_cy, belt_z),
             (0.10, NAVE_D, 0.22), mats["trim"], root, collection, bevel=0.006)
    add_cube("Nave_Belt_Right", (nave_right + 0.008, nave_cy, belt_z),
             (0.10, NAVE_D, 0.22), mats["trim"], root, collection, bevel=0.006)

    tower_cornice_z = FOUNDATION_H + TOWER_WALL_H - 0.20
    add_cube("Tower_Cornice_Front", (tower_cx, tower_front - 0.01, tower_cornice_z),
             (TOWER_W + 0.12, 0.10, 0.26), mats["trim"], root, collection, bevel=0.006)
    add_cube("Tower_Cornice_Back", (tower_cx, tower_back + 0.01, tower_cornice_z),
             (TOWER_W + 0.12, 0.10, 0.26), mats["trim"], root, collection, bevel=0.006)
    add_cube("Tower_Cornice_Left", (tower_cx - TOWER_W * 0.5 - 0.01, tower_cy, tower_cornice_z),
             (0.10, TOWER_D, 0.26), mats["trim"], root, collection, bevel=0.006)
    add_cube("Tower_Cornice_Right", (tower_cx + TOWER_W * 0.5 + 0.01, tower_cy, tower_cornice_z),
             (0.10, TOWER_D, 0.26), mats["trim"], root, collection, bevel=0.006)

    # Doors
    add_closed_door_front("Door_MainFront", 0.0, porch_cy - PORCH_D * 0.5 - 0.05,
                          FOUNDATION_H, FRONT_DOOR_W, FRONT_DOOR_H, mats, root, collection)
    # User requested fix: remove side doors entirely.
    add_closed_door_front("Door_RearService", 0.0, chancel_back + 0.06,
                          FOUNDATION_H, 1.20, 2.18, mats, root, collection)

    for idx, x in enumerate([-1.32, 1.32]):
        add_cube(f"PorchColumn_{idx}", (x, porch_cy, FOUNDATION_H + 1.45),
                 (0.28, 0.28, 2.90), mats["trim"], root, collection, bevel=0.008)

    # Windows
    add_front_window("TowerWindow_Lower", 0.0, tower_front - 0.05, FOUNDATION_H + 1.95,
                     1.18, 2.00, WINDOW_PANEL_T, mats, root, collection)
    add_round_window("Tower_Oculus", 0.0, tower_front - 0.05, FOUNDATION_H + 5.05,
                     1.15, WINDOW_PANEL_T, mats, root, collection, facing="front")
    add_front_window("Tower_Belfry_Front", 0.0, tower_front - 0.05, FOUNDATION_H + 8.55,
                     0.95, 1.45, WINDOW_PANEL_T, mats, root, collection)
    add_side_window("Tower_Belfry_Left", tower_cx - TOWER_W * 0.5 - 0.05, tower_cy,
                    FOUNDATION_H + 8.55, 0.95, 1.35, WINDOW_PANEL_T, mats, root, collection)
    add_side_window("Tower_Belfry_Right", tower_cx + TOWER_W * 0.5 + 0.05, tower_cy,
                    FOUNDATION_H + 8.55, 0.95, 1.35, WINDOW_PANEL_T, mats, root, collection)
    add_round_window("Nave_FrontOculus", 0.0, nave_front - 0.05, FOUNDATION_H + 6.10,
                     1.12, WINDOW_PANEL_T, mats, root, collection, facing="front")

    # Reduced side-window set to avoid any overlap with the annex / side-building zone.
    # We only keep windows on the clearly exposed rear-side wall segments.
    nave_exposed_window_ys = [5.35, 8.15]
    for i, y in enumerate(nave_exposed_window_ys):
        add_side_window(f"NaveLeftWindow_Lower_{i}", nave_left - 0.05, y,
                        FOUNDATION_H + 1.90, 1.15, 2.45, WINDOW_PANEL_T, mats, root, collection)
        add_side_window(f"NaveRightWindow_Lower_{i}", nave_right + 0.05, y,
                        FOUNDATION_H + 1.90, 1.15, 2.45, WINDOW_PANEL_T, mats, root, collection)
        add_side_window(f"NaveLeftWindow_Upper_{i}", nave_left - 0.05, y,
                        FOUNDATION_H + 4.95, 0.95, 1.45, WINDOW_PANEL_T, mats, root, collection)
        add_side_window(f"NaveRightWindow_Upper_{i}", nave_right + 0.05, y,
                        FOUNDATION_H + 4.95, 0.95, 1.45, WINDOW_PANEL_T, mats, root, collection)

    # User-requested fix:
    # remove all front and back windows from the cross-wing / transept block
    # (both lower and upper levels) to eliminate remaining overlap / nesting issues.

    add_side_window("ChancelLeftWindow", -(CHANCEL_W * 0.5) - 0.05, chancel_cy,
                    FOUNDATION_H + 2.15, 1.35, 2.20, WINDOW_PANEL_T, mats, root, collection)
    add_side_window("ChancelRightWindow", (CHANCEL_W * 0.5) + 0.05, chancel_cy,
                    FOUNDATION_H + 2.15, 1.35, 2.20, WINDOW_PANEL_T, mats, root, collection)
    add_front_window("ChancelRearWindow", 0.0, chancel_back + 0.05, FOUNDATION_H + 2.35,
                     1.55, 2.35, WINDOW_PANEL_T, mats, root, collection)

    # User-requested safety fix:
    # remove annex (side-building) windows entirely to eliminate any remaining nesting / overlap risk.

    nave_buttress_ys = [-8.10, 5.95, 8.85]
    for i, y in enumerate(nave_buttress_ys):
        add_buttress_side(f"NaveButtress_L_{i}", nave_left - 0.25, y, FOUNDATION_H, 3.3, mats, root, collection)
        add_buttress_side(f"NaveButtress_R_{i}", nave_right + 0.25, y, FOUNDATION_H, 3.3, mats, root, collection)

    tran_buttress_xs = [-7.0, -2.8, 2.8, 7.0]
    for i, x in enumerate(tran_buttress_xs):
        add_buttress_front(f"TranseptButtress_F_{i}", x, tran_front - 0.25, FOUNDATION_H, 3.1, mats, root, collection)
        add_buttress_front(f"TranseptButtress_B_{i}", x, tran_back + 0.25, FOUNDATION_H, 3.1, mats, root, collection)

    add_cube("Accent_PorchTrim", (porch_cx, porch_cy - PORCH_D * 0.5 - 0.01, FOUNDATION_H + 2.95),
             (PORCH_W, 0.10, 0.18), mats["accent"], root, collection, bevel=0.005)
    add_cube("Accent_EntryLintel", (0.0, nave_front - 0.01, FOUNDATION_H + 2.78),
             (2.55, 0.08, 0.16), mats["accent"], root, collection, bevel=0.005)
    add_cube("Step_MainFront", (0.0, porch_cy - PORCH_D * 0.5 - 0.58, 0.16),
             (2.95, 0.92, 0.32), mats["foundation"], root, collection, bevel=0.018)

    return root


# ---------------------------------------------------------------------
# PARISH OFFICE
# ---------------------------------------------------------------------

def parish_materials():
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


def build_parish_office():
    if CLEAR_SCENE_BEFORE_ASSET:
        clear_scene()
    configure_scene()

    root_name = "FTF_ParishOffice_NorthAmerican"
    collection = get_or_create_collection("COL_" + root_name)
    mats = parish_materials()
    root = create_root(root_name, collection)

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
    PANEL_T = 0.05

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

    wing_right = wing_cx + WING_W * 0.5
    wing_front = wing_cy - WING_D * 0.5
    wing_back = wing_cy + WING_D * 0.5

    main_wall_top = FOUNDATION_H + MAIN_WALL_H
    main_ridge_z = main_wall_top + MAIN_ROOF_RISE

    add_cube("Foundation_Main", (main_cx, main_cy, FOUNDATION_H * 0.5),
             (MAIN_W + 0.16, MAIN_D + 0.16, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Wing", (wing_cx, wing_cy, FOUNDATION_H * 0.5),
             (WING_W + 0.14, WING_D + 0.14, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.03)
    add_cube("Foundation_Porch", (porch_cx, porch_cy, FOUNDATION_H * 0.5),
             (PORCH_W + 0.10, PORCH_D + 0.10, FOUNDATION_H), mats["foundation"], root, collection, bevel=0.02)

    add_cube("Body_Main", (main_cx, main_cy, FOUNDATION_H + MAIN_WALL_H * 0.5),
             (MAIN_W, MAIN_D, MAIN_WALL_H), mats["wall"], root, collection, bevel=0.016)
    add_cube("Body_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H * 0.5),
             (WING_W, WING_D, WING_WALL_H), mats["wall"], root, collection, bevel=0.014)
    add_cube("Body_Porch", (porch_cx, porch_cy, FOUNDATION_H + PORCH_H * 0.5),
             (PORCH_W, PORCH_D, PORCH_H), mats["wall"], root, collection, bevel=0.012)

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

    add_gable_triangle("Gable_Main_Front", main_cx, front_y - 0.01, 0.10, MAIN_W,
                       main_wall_top, main_ridge_z, mats["wall"], root, collection)
    add_gable_triangle("Gable_Main_Back", main_cx, back_y + 0.01, 0.10, MAIN_W,
                       main_wall_top, main_ridge_z, mats["wall"], root, collection)

    add_cube("Roof_Wing", (wing_cx, wing_cy, FOUNDATION_H + WING_WALL_H + WING_ROOF_H * 0.5),
             (WING_W + 0.25, WING_D + 0.25, WING_ROOF_H), mats["roof"], root, collection, bevel=0.012)
    add_cube("Roof_Porch", (porch_cx, porch_cy - 0.08, FOUNDATION_H + PORCH_H + 0.20),
             (PORCH_W + 0.20, PORCH_D + 0.18, 0.18), mats["roof"], root, collection, bevel=0.010,
             rotation=(math.radians(8.0), 0.0, 0.0))

    # Doors
    add_closed_door_front("Door_MainFront", 0.0, porch_cy - PORCH_D * 0.5 - 0.05,
                          FOUNDATION_H, DOOR_W, DOOR_H, mats, root, collection)
    add_closed_door_side("Door_WingSide", wing_right + 0.05, wing_cy,
                         FOUNDATION_H, SIDE_DOOR_W, SIDE_DOOR_H, mats, root, collection)
    add_closed_door_front("Door_RearService", -2.0, back_y + 0.05,
                          FOUNDATION_H, 1.05, 2.10, mats, root, collection)

    for idx, x in enumerate([-0.95, 0.95]):
        add_cube(f"PorchColumn_{idx}", (x, porch_cy, FOUNDATION_H + 1.30),
                 (0.24, 0.24, 2.60), mats["trim"], root, collection, bevel=0.008)

    # Front windows
    add_front_window("FrontLowerWindow_L", -2.45, front_y - 0.05, FOUNDATION_H + 1.80,
                     1.25, 1.35, PANEL_T, mats, root, collection)
    add_front_window("FrontLowerWindow_R", 2.45, front_y - 0.05, FOUNDATION_H + 1.80,
                     1.25, 1.35, PANEL_T, mats, root, collection)
    add_front_window("FrontUpperWindow_L", -2.45, front_y - 0.05, FOUNDATION_H + 4.60,
                     1.05, 1.15, PANEL_T, mats, root, collection)
    add_front_window("FrontUpperWindow_R", 2.45, front_y - 0.05, FOUNDATION_H + 4.60,
                     1.05, 1.15, PANEL_T, mats, root, collection)

    # Left side windows
    side_ys = [-2.8, 0.2, 3.2]
    for i, y in enumerate(side_ys):
        add_side_window(f"MainLeftWindow_Lower_{i}", left_x - 0.05, y, FOUNDATION_H + 1.85,
                        1.20, 1.30, PANEL_T, mats, root, collection)
        add_side_window(f"MainLeftWindow_Upper_{i}", left_x - 0.05, y, FOUNDATION_H + 4.65,
                        0.95, 1.10, PANEL_T, mats, root, collection)

    # Back windows main block
    # User-requested fix: remove the overlapping lower-left rear window.
    add_front_window("BackWindow_R", 2.35, back_y + 0.05, FOUNDATION_H + 1.85,
                     1.25, 1.35, PANEL_T, mats, root, collection)
    add_front_window("BackUpperWindow_L", -2.35, back_y + 0.05, FOUNDATION_H + 4.65,
                     1.05, 1.15, PANEL_T, mats, root, collection)
    add_front_window("BackUpperWindow_R", 2.35, back_y + 0.05, FOUNDATION_H + 4.65,
                     1.05, 1.15, PANEL_T, mats, root, collection)

    # Wing windows
    add_front_window("WingFrontWindow", wing_cx, wing_front - 0.05, FOUNDATION_H + 1.70,
                     1.50, 1.35, PANEL_T, mats, root, collection)
    add_front_window("WingBackWindow", wing_cx, wing_back + 0.05, FOUNDATION_H + 1.70,
                     1.50, 1.35, PANEL_T, mats, root, collection)

    add_cube("Accent_PorchTrim", (0.0, porch_cy - PORCH_D * 0.5 - 0.01, FOUNDATION_H + 2.60),
             (PORCH_W, 0.10, 0.16), mats["accent"], root, collection, bevel=0.004)
    add_cube("Step_MainFront", (0.0, porch_cy - PORCH_D * 0.5 - 0.50, 0.14),
             (2.25, 0.82, 0.28), mats["foundation"], root, collection, bevel=0.016)

    return root


# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------

if __name__ == "__main__":
    print("\n=== Generating Church + Parish Office Pack ===\n")

    generated = []

    church_root = build_church()
    if MERGE_STATIC_MESHES:
        merge_static_meshes(church_root)
    validate_asset(church_root)
    church_path = os.path.join(OUTPUT_DIR, "FTF_RuralChurch_Large_TwoStory_Light.glb")
    export_glb(church_root, church_path)
    generated.append(church_path)

    parish_root = build_parish_office()
    if MERGE_STATIC_MESHES:
        merge_static_meshes(parish_root)
    validate_asset(parish_root)
    parish_path = os.path.join(OUTPUT_DIR, "FTF_ParishOffice_NorthAmerican.glb")
    export_glb(parish_root, parish_path)
    generated.append(parish_path)

    print("\n=== Finished ===")
    print("Generated:")
    for path in generated:
        print(" - " + path)
    print("\nNotes:")
    print(" - Church side doors were removed.")
    print(" - Parish office overlapping rear lower-left window was removed.")
