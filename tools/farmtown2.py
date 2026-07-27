# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town - One Story Closed House
# PATCHED: preserves global material references during clear_scene().
# PATCHED V2: fixes reversed left/right gable roof slope rotations.
#
# Generates two non-enterable, one-story North American farm-town houses:
#   1) FTF_House_OneStory_RoofBrickRed.glb
#   2) FTF_House_OneStory_RoofLightBlue.glb
#
# ASSET CONTRACT:
# - Godot 4.x GLB-ready static environment asset
# - Native Blender coordinates: Z up
# - Visual front direction: local -Y
# - Root origin: ground-center (0, 0, 0)
# - One root Empty per exported asset
# - Closed front door; no interior; not enterable
# - No yard, fence, collision shell, lights, cameras, textures, or decals
# - Stylized low-poly, clean large color blocks, readable at gameplay distance
# - No floating visible parts
# - All static meshes merged before GLB export
#
# Run:
# Blender > Scripting > New > paste > Run Script
#
# Or:
# blender --background --factory-startup --python generate_farmtown_one_story_house.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# USER SETTINGS
# ---------------------------------------------------------------------

CLEAR_SCENE_BEFORE_EACH_VARIANT = True
JOIN_STATIC_MESHES_FOR_EXPORT = True

ROOT_NAME = "HouseOneStory"

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)

OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_houses")

# Approximate outer building dimensions in meters.
HOUSE_WIDTH = 10.8
HOUSE_DEPTH = 8.4
FOUNDATION_HEIGHT = 0.30
WALL_HEIGHT = 3.20
ROOF_RISE = 2.05
ROOF_OVERHANG = 0.42

# Closed door dimensions.
DOOR_WIDTH = 1.25
DOOR_HEIGHT = 2.25


# ---------------------------------------------------------------------
# SCENE / COLLECTION HELPERS
# ---------------------------------------------------------------------

def clear_scene():
    """Delete all scene objects and unused datablocks."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # Keep materials alive here.
    #
    # Materials are created at module load time, before the first house is
    # generated. Removing unused materials in this function would invalidate
    # the global MAT_* references and cause:
    # ReferenceError: StructRNA of type Material has been removed
    #
    # Meshes, curves, images, cameras and lights can still be safely cleaned.
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def configure_scene_units():
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


def apply_object_transforms_and_modifiers(obj):
    """Apply object scale/rotation and all supported modifiers."""
    if obj.type != "MESH":
        return

    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    for modifier in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError:
            print(f"[WARN] Could not apply modifier '{modifier.name}' on '{obj.name}'.")


def add_bevel(obj, width=0.03, segments=1):
    """Small bevel for readable low-poly edges."""
    modifier = obj.modifiers.new("LowPolyBevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier


def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_material(name, color, metallic=0.0, roughness=0.65):
    material = bpy.data.materials.get(name)

    if material is None:
        material = bpy.data.materials.new(name)

    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


MAT_FOUNDATION = make_material("MAT_House_Foundation_Stone", (0.29, 0.30, 0.29), 0.0, 0.88)
MAT_WALL = make_material("MAT_House_Wall_WarmCream", (0.73, 0.62, 0.48), 0.0, 0.80)
MAT_TRIM = make_material("MAT_House_Trim_OffWhite", (0.82, 0.81, 0.74), 0.0, 0.72)
MAT_DOOR = make_material("MAT_House_Door_DarkWood", (0.18, 0.095, 0.045), 0.0, 0.74)
MAT_WINDOW = make_material("MAT_House_Window_DarkBlue", (0.075, 0.16, 0.22), 0.05, 0.35)
MAT_CHIMNEY = make_material("MAT_House_Chimney_Brick", (0.40, 0.16, 0.10), 0.0, 0.85)
MAT_ROOF_BRICK_RED = make_material("MAT_House_Roof_BrickRed", (0.48, 0.09, 0.055), 0.0, 0.72)
MAT_ROOF_LIGHT_BLUE = make_material("MAT_House_Roof_LightBlue", (0.23, 0.48, 0.62), 0.0, 0.70)
MAT_ROOF_RIDGE_DARK = make_material("MAT_House_Roof_RidgeDark", (0.12, 0.16, 0.18), 0.0, 0.72)


# ---------------------------------------------------------------------
# MESH CREATION HELPERS
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
    bevel_width=0.0,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    assign_material(obj, material)
    set_flat_shading(obj)

    if bevel_width > 0.0:
        add_bevel(obj, bevel_width, segments=1)

    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_gable_triangle(
    name,
    y_center,
    thickness,
    wall_width,
    wall_top_z,
    ridge_z,
    material,
    parent,
    collection,
):
    """Create a shallow triangular prism that closes one roof gable."""
    half_width = wall_width * 0.5
    y_front = y_center - thickness * 0.5
    y_back = y_center + thickness * 0.5

    vertices = [
        (-half_width, y_front, wall_top_z),
        ( half_width, y_front, wall_top_z),
        (0.0,         y_front, ridge_z),
        (-half_width, y_back, wall_top_z),
        ( half_width, y_back, wall_top_z),
        (0.0,         y_back, ridge_z),
    ]

    faces = [
        (0, 2, 1),
        (3, 4, 5),
        (0, 1, 4, 3),
        (1, 2, 5, 4),
        (2, 0, 3, 5),
    ]

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)

    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    return obj


def add_window_front(name, x, y, z, width, height, parent, collection):
    """Add an opaque front-facing decorative window and chunky exterior frame."""
    panel_depth = 0.045
    trim_depth = 0.060
    trim_thickness = 0.13

    add_cube(name + "_Pane", (x, y, z), (width, panel_depth, height),
             MAT_WINDOW, parent, collection, bevel_width=0.012)

    add_cube(name + "_TrimTop",
             (x, y - 0.010, z + height * 0.5 - trim_thickness * 0.5),
             (width + trim_thickness * 2.0, trim_depth, trim_thickness),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimBottom",
             (x, y - 0.010, z - height * 0.5 + trim_thickness * 0.5),
             (width + trim_thickness * 2.0, trim_depth, trim_thickness),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimLeft",
             (x - width * 0.5 + trim_thickness * 0.5, y - 0.010, z),
             (trim_thickness, trim_depth, height),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimRight",
             (x + width * 0.5 - trim_thickness * 0.5, y - 0.010, z),
             (trim_thickness, trim_depth, height),
             MAT_TRIM, parent, collection, bevel_width=0.010)


def add_window_side(name, x, y, z, width, height, parent, collection):
    """Add an opaque side-facing decorative window and chunky exterior frame."""
    panel_depth = 0.045
    trim_depth = 0.060
    trim_thickness = 0.13

    add_cube(name + "_Pane", (x, y, z), (panel_depth, width, height),
             MAT_WINDOW, parent, collection, bevel_width=0.012)

    add_cube(name + "_TrimTop",
             (x - 0.010, y, z + height * 0.5 - trim_thickness * 0.5),
             (trim_depth, width + trim_thickness * 2.0, trim_thickness),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimBottom",
             (x - 0.010, y, z - height * 0.5 + trim_thickness * 0.5),
             (trim_depth, width + trim_thickness * 2.0, trim_thickness),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimNear",
             (x - 0.010, y - width * 0.5 + trim_thickness * 0.5, z),
             (trim_depth, trim_thickness, height),
             MAT_TRIM, parent, collection, bevel_width=0.010)

    add_cube(name + "_TrimFar",
             (x - 0.010, y + width * 0.5 - trim_thickness * 0.5, z),
             (trim_depth, trim_thickness, height),
             MAT_TRIM, parent, collection, bevel_width=0.010)


# ---------------------------------------------------------------------
# ASSET BUILD
# ---------------------------------------------------------------------

def create_root(root_name, collection, variant_name):
    root = bpy.data.objects.new(root_name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.75

    root["asset_type"] = "StaticEnvironmentBuilding"
    root["variant"] = variant_name
    root["authoring_space"] = "NativeBlender"
    root["up_axis"] = "+Z"
    root["visual_forward_axis"] = "-Y"
    root["ground_origin"] = "0,0,0"
    root["enterable"] = False
    root["door_state"] = "closed"
    root["collision_mesh_generated"] = False
    root["static_meshes_merged_on_export"] = JOIN_STATIC_MESHES_FOR_EXPORT

    collection.objects.link(root)
    return root


def build_house_variant(variant_name, roof_material):
    """
    Build one sealed one-story house.
    Front direction: local -Y.
    """
    collection = get_or_create_collection("COL_" + variant_name)
    root = create_root(ROOT_NAME + "_" + variant_name, collection, variant_name)

    wall_center_z = FOUNDATION_HEIGHT + WALL_HEIGHT * 0.5
    wall_top_z = FOUNDATION_HEIGHT + WALL_HEIGHT
    ridge_z = wall_top_z + ROOF_RISE

    # Foundation and sealed exterior shell
    add_cube("Foundation", (0.0, 0.0, FOUNDATION_HEIGHT * 0.5),
             (HOUSE_WIDTH + 0.25, HOUSE_DEPTH + 0.25, FOUNDATION_HEIGHT),
             MAT_FOUNDATION, root, collection, bevel_width=0.045)

    add_cube("ExteriorWalls_ClosedShell", (0.0, 0.0, wall_center_z),
             (HOUSE_WIDTH, HOUSE_DEPTH, WALL_HEIGHT),
             MAT_WALL, root, collection, bevel_width=0.020)

    # Eave trim
    trim_z = wall_top_z - 0.16
    trim_h = 0.22
    trim_t = 0.13

    add_cube("EaveTrim_Front", (0.0, -(HOUSE_DEPTH * 0.5 + trim_t * 0.35), trim_z),
             (HOUSE_WIDTH + 0.15, trim_t, trim_h),
             MAT_TRIM, root, collection, bevel_width=0.010)

    add_cube("EaveTrim_Back", (0.0, HOUSE_DEPTH * 0.5 + trim_t * 0.35, trim_z),
             (HOUSE_WIDTH + 0.15, trim_t, trim_h),
             MAT_TRIM, root, collection, bevel_width=0.010)

    add_cube("EaveTrim_Left", (-(HOUSE_WIDTH * 0.5 + trim_t * 0.35), 0.0, trim_z),
             (trim_t, HOUSE_DEPTH, trim_h),
             MAT_TRIM, root, collection, bevel_width=0.010)

    add_cube("EaveTrim_Right", (HOUSE_WIDTH * 0.5 + trim_t * 0.35, 0.0, trim_z),
             (trim_t, HOUSE_DEPTH, trim_h),
             MAT_TRIM, root, collection, bevel_width=0.010)

    # Gable closures
    add_gable_triangle("GableFront", -(HOUSE_DEPTH * 0.5 + 0.015), 0.10,
                       HOUSE_WIDTH, wall_top_z, ridge_z,
                       MAT_WALL, root, collection)

    add_gable_triangle("GableBack", HOUSE_DEPTH * 0.5 + 0.015, 0.10,
                       HOUSE_WIDTH, wall_top_z, ridge_z,
                       MAT_WALL, root, collection)

    # Gable roof
    half_roof_span = HOUSE_WIDTH * 0.5 + ROOF_OVERHANG
    roof_depth = HOUSE_DEPTH + ROOF_OVERHANG * 2.0
    roof_slope_length = math.sqrt(half_roof_span ** 2 + ROOF_RISE ** 2)
    roof_pitch = math.atan2(ROOF_RISE, half_roof_span)

    roof_slab_length = roof_slope_length + 0.20
    roof_slab_thickness = 0.22
    roof_center_z = wall_top_z + ROOF_RISE * 0.5

    # Correct gable roof slopes:
    # ridge lies along Y. Each panel slopes downward as it moves away from X=0.
    add_cube("Roof_RightSlope", (half_roof_span * 0.5, 0.0, roof_center_z),
             (roof_slab_length, roof_depth, roof_slab_thickness),
             roof_material, root, collection, bevel_width=0.025,
             rotation=(0.0, roof_pitch, 0.0))

    add_cube("Roof_LeftSlope", (-half_roof_span * 0.5, 0.0, roof_center_z),
             (roof_slab_length, roof_depth, roof_slab_thickness),
             roof_material, root, collection, bevel_width=0.025,
             rotation=(0.0, -roof_pitch, 0.0))

    add_cube("Roof_RidgeCap", (0.0, 0.0, ridge_z + 0.05),
             (0.25, roof_depth + 0.05, 0.18),
             MAT_ROOF_RIDGE_DARK, root, collection, bevel_width=0.020)

    # Closed front door. Front is local -Y.
    front_y = -(HOUSE_DEPTH * 0.5 + 0.035)
    door_z = FOUNDATION_HEIGHT + DOOR_HEIGHT * 0.5
    door_trim_t = 0.15
    door_trim_depth = 0.14

    add_cube("Door_Closed", (0.0, front_y, door_z),
             (DOOR_WIDTH, 0.12, DOOR_HEIGHT),
             MAT_DOOR, root, collection, bevel_width=0.018)

    add_cube("DoorFrame_Left",
             (-(DOOR_WIDTH * 0.5 + door_trim_t * 0.5), front_y - 0.010, door_z),
             (door_trim_t, door_trim_depth, DOOR_HEIGHT + 0.12),
             MAT_TRIM, root, collection, bevel_width=0.012)

    add_cube("DoorFrame_Right",
             ((DOOR_WIDTH * 0.5 + door_trim_t * 0.5), front_y - 0.010, door_z),
             (door_trim_t, door_trim_depth, DOOR_HEIGHT + 0.12),
             MAT_TRIM, root, collection, bevel_width=0.012)

    add_cube("DoorFrame_Top",
             (0.0, front_y - 0.010, FOUNDATION_HEIGHT + DOOR_HEIGHT + 0.08),
             (DOOR_WIDTH + door_trim_t * 2.0, door_trim_depth, door_trim_t),
             MAT_TRIM, root, collection, bevel_width=0.012)

    add_cube("FrontDoorStep", (0.0, -(HOUSE_DEPTH * 0.5 + 0.45), 0.14),
             (1.80, 0.72, 0.28),
             MAT_FOUNDATION, root, collection, bevel_width=0.035)

    # Decorative opaque windows, no actual wall openings
    front_window_z = FOUNDATION_HEIGHT + 1.85

    add_window_front("FrontWindow_Left", -3.05, -(HOUSE_DEPTH * 0.5 + 0.038),
                     front_window_z, 1.45, 1.18, root, collection)
    add_window_front("FrontWindow_Right", 3.05, -(HOUSE_DEPTH * 0.5 + 0.038),
                     front_window_z, 1.45, 1.18, root, collection)

    back_window_z = FOUNDATION_HEIGHT + 1.90
    add_window_front("BackWindow_Left", -2.55, HOUSE_DEPTH * 0.5 + 0.038,
                     back_window_z, 1.55, 1.18, root, collection)
    add_window_front("BackWindow_Right", 2.55, HOUSE_DEPTH * 0.5 + 0.038,
                     back_window_z, 1.55, 1.18, root, collection)

    side_x_left = -(HOUSE_WIDTH * 0.5 + 0.038)
    side_x_right = HOUSE_WIDTH * 0.5 + 0.038

    add_window_side("LeftWallWindow_Front", side_x_left, -2.15,
                    FOUNDATION_HEIGHT + 1.90, 1.42, 1.15, root, collection)
    add_window_side("LeftWallWindow_Back", side_x_left, 2.15,
                    FOUNDATION_HEIGHT + 1.90, 1.42, 1.15, root, collection)

    add_window_side("RightWallWindow_Front", side_x_right, -2.15,
                    FOUNDATION_HEIGHT + 1.90, 1.42, 1.15, root, collection)
    add_window_side("RightWallWindow_Back", side_x_right, 2.15,
                    FOUNDATION_HEIGHT + 1.90, 1.42, 1.15, root, collection)

    # Attached chimney
    chimney_x = 2.05
    chimney_y = 1.25
    chimney_bottom_z = wall_top_z + 0.90
    chimney_height = 1.70

    add_cube("BrickChimney",
             (chimney_x, chimney_y, chimney_bottom_z + chimney_height * 0.5),
             (0.72, 0.72, chimney_height),
             MAT_CHIMNEY, root, collection, bevel_width=0.018)

    add_cube("ChimneyCap",
             (chimney_x, chimney_y, chimney_bottom_z + chimney_height + 0.08),
             (0.90, 0.90, 0.16),
             MAT_FOUNDATION, root, collection, bevel_width=0.018)

    return root, collection


# ---------------------------------------------------------------------
# EXPORT / VALIDATION
# ---------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def merge_static_meshes_for_export(root, merged_mesh_name):
    """
    Merge all visual static meshes. Materials remain as material slots.
    Suitable because the building is non-enterable and non-animated.
    """
    meshes = get_meshes_under_root(root)

    if not meshes:
        raise RuntimeError("No meshes found to merge.")

    for obj in meshes:
        apply_object_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = merged_mesh_name
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
        min(v.x for v in lows),
        min(v.y for v in lows),
        min(v.z for v in lows),
    ))

    high = Vector((
        max(v.x for v in highs),
        max(v.y for v in highs),
        max(v.z for v in highs),
    ))

    return low, high


def validate_asset(root):
    """Basic export validation."""
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")

    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root must be at origin (0, 0, 0).")

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no visual meshes found.")

    scene_cameras_lights = [
        obj.name for obj in bpy.context.scene.objects
        if obj.type in {"CAMERA", "LIGHT"}
    ]
    if scene_cameras_lights:
        raise RuntimeError(
            "VALIDATION FAILED: cameras/lights remain in scene: "
            + ", ".join(scene_cameras_lights)
        )

    failures = []
    for obj in meshes:
        upper = obj.name.upper()

        if upper.startswith(("UCX_", "MESH_UCX_", "COL_", "COLLISION_")):
            failures.append("collision mesh name found: " + obj.name)

        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale found: " + obj.name)

        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale found: " + obj.name)

        for vertex in obj.data.vertices:
            world_vertex = obj.matrix_world @ vertex.co
            if not all(math.isfinite(v) for v in world_vertex):
                failures.append("non-finite vertex found: " + obj.name)
                break

    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    bpy.context.view_layer.update()
    low, high = bbox_world(meshes)
    dimensions = high - low

    if low.z < -0.015:
        raise RuntimeError(
            f"VALIDATION FAILED: model penetrates below ground: {low.z:.4f}m"
        )

    if low.z > 0.035:
        raise RuntimeError(
            f"VALIDATION FAILED: model floats above ground: {low.z:.4f}m"
        )

    triangle_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangle_count += len(obj.data.loop_triangles)

    print(
        f"[VALID] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f}m x {dimensions.y:.2f}m x {dimensions.z:.2f}m\n"
        f"  Ground min Z: {low.z:.4f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangle_count}\n"
        f"  Forward: local -Y\n"
        f"  Enterable: False\n"
    )


def select_root_for_export(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    select_root_for_export(root)

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

    print(f"[EXPORT] GLB exported: {filepath}")


def build_and_export_variant(variant_name, roof_material, output_filename):
    if CLEAR_SCENE_BEFORE_EACH_VARIANT:
        clear_scene()

    configure_scene_units()
    root, _collection = build_house_variant(variant_name, roof_material)

    if JOIN_STATIC_MESHES_FOR_EXPORT:
        merge_static_meshes_for_export(root, variant_name + "_Mesh")

    validate_asset(root)

    output_path = os.path.join(OUTPUT_DIR, output_filename)
    export_glb(root, output_path)
    return output_path


# ---------------------------------------------------------------------
# BUILD BOTH COLOR VARIANTS
# ---------------------------------------------------------------------

if __name__ == "__main__":
    print("\n=== Generating Farm Town One-Story Houses ===\n")

    red_path = build_and_export_variant(
        "FTF_House_OneStory_RoofBrickRed",
        MAT_ROOF_BRICK_RED,
        "FTF_House_OneStory_RoofBrickRed.glb",
    )

    blue_path = build_and_export_variant(
        "FTF_House_OneStory_RoofLightBlue",
        MAT_ROOF_LIGHT_BLUE,
        "FTF_House_OneStory_RoofLightBlue.glb",
    )

    print("\n=== Finished ===")
    print("Generated files:")
    print(" - " + red_path)
    print(" - " + blue_path)
    print(
        "\nGodot note: add StaticBody3D + CollisionShape3D separately "
        "after import. The GLB intentionally contains no collision mesh."
    )
