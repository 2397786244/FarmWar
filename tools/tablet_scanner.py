# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Handheld Tablet Scanner
#
# Generates:
#   generated_farmtown_tools/
#     FTF_Tool_HandheldScanner_Tablet_v1.glb
#
# DESIGN
# - Palm-sized handheld scanner with a compact tablet silhouette.
# - Front face contains a large illuminated screen.
# - Rear face contains a short black cylindrical scanning lens.
# - Low-poly, readable game asset for Godot.
#
# EXPORTED HIERARCHY
#   FTF_Tool_HandheldScanner_Tablet_v1
#   |-- FTF_Tool_HandheldScanner_Tablet_v1_Static
#   |-- ScanOrigin
#   `-- ScreenCenter
#
# AXES
# - Authoring scan direction: local +Y from the rear lens.
# - Front screen faces local -Y.
# - Intended Godot scan direction after Blender/glTF conversion: local +Z.
#
# VALIDATION
# - All named parts are checked for attachment before mesh joining.
# - The validation fails when a component is floating.
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_tools")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Tool_HandheldScanner_Tablet_v1.glb")

ROOT_NAME = "FTF_Tool_HandheldScanner_Tablet_v1"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV1_PALM_TABLET_REAR_LENS"

CLEAR_SCENE = True
AUTHORING_SCAN_AXIS = "+Y"
INTENDED_GODOT_SCAN_AXIS = "+Z"
SCAN_ORIGIN_LOCATION = Vector((0.0, 0.151, 0.055))
SCREEN_CENTER_LOCATION = Vector((0.0, -0.039, 0.025))


# -----------------------------------------------------------------------------
# Scene / materials
# -----------------------------------------------------------------------------


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


def make_material(name, color, metallic=0.0, roughness=0.6, emission=None, emission_strength=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    material.diffuse_color = (*color, 1.0)
    return material


def build_materials():
    return {
        "case": make_material("MAT_HTS_Case", (0.16, 0.18, 0.19), metallic=0.52, roughness=0.42),
        "case_dark": make_material("MAT_HTS_CaseDark", (0.055, 0.065, 0.075), metallic=0.34, roughness=0.66),
        "edge": make_material("MAT_HTS_Edge", (0.26, 0.29, 0.30), metallic=0.60, roughness=0.34),
        "screen": make_material(
            "MAT_HTS_Screen",
            (0.08, 0.27, 0.30),
            metallic=0.02,
            roughness=0.18,
            emission=(0.10, 0.68, 0.76),
            emission_strength=1.5,
        ),
        "screen_ui": make_material(
            "MAT_HTS_ScreenUI",
            (0.50, 0.95, 0.88),
            metallic=0.0,
            roughness=0.14,
            emission=(0.38, 1.0, 0.88),
            emission_strength=2.0,
        ),
        "lens_black": make_material("MAT_HTS_LensBlack", (0.015, 0.018, 0.022), metallic=0.56, roughness=0.30),
        "lens_glass": make_material(
            "MAT_HTS_LensGlass",
            (0.06, 0.12, 0.18),
            metallic=0.10,
            roughness=0.10,
            emission=(0.08, 0.30, 0.46),
            emission_strength=0.8,
        ),
        "button": make_material(
            "MAT_HTS_Button",
            (0.27, 0.72, 0.64),
            metallic=0.12,
            roughness=0.30,
            emission=(0.18, 0.75, 0.63),
            emission_strength=0.7,
        ),
    }


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


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


def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def add_bevel(obj, width=0.006, segments=1):
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier


def finish_mesh(obj, name, material, collection, bevel=0.0, smooth=False):
    obj.name = name
    assign_material(obj, material)
    if smooth:
        set_smooth_shading(obj)
    else:
        set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    move_to_collection(obj, collection)
    return obj


def add_cube(name, location, dimensions, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel=bevel, smooth=smooth)


def add_cylinder(name, location, radius, depth, material, collection, rotation=(0.0, 0.0, 0.0), vertices=18, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return finish_mesh(bpy.context.object, name, material, collection, bevel=bevel, smooth=smooth)


def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.06):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    collection.objects.link(obj)
    return obj


def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for modifier in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError as exc:
            print(f"[WARN] Could not apply {modifier.name} on {obj.name}: {exc}")


def join_meshes(meshes, new_name, parent):
    if not meshes:
        raise RuntimeError(f"No meshes to join for {new_name}")
    for obj in meshes:
        apply_transforms_and_modifiers(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = new_name
    merged.parent = parent
    set_flat_shading(merged)
    return merged


# -----------------------------------------------------------------------------
# Geometry
# -----------------------------------------------------------------------------


def build_scanner(materials, collection, root):
    parts = []

    # Palm-sized tablet body: 20 cm wide, 30 cm tall, approximately 4.5 cm thick.
    parts += [
        add_cube("Case_Main", (0.0, 0.0, 0.0), (0.20, 0.045, 0.30), materials["case"], collection, bevel=0.010),
        add_cube("Case_BackPlate", (0.0, 0.026, 0.0), (0.172, 0.014, 0.266), materials["case_dark"], collection, bevel=0.008),
    ]

    # Four reinforced corner pads, embedded into the main case.
    corner_specs = [
        ("TL", (-0.086, -0.001, 0.132)),
        ("TR", (0.086, -0.001, 0.132)),
        ("BL", (-0.086, -0.001, -0.132)),
        ("BR", (0.086, -0.001, -0.132)),
    ]
    for suffix, location in corner_specs:
        parts.append(
            add_cube(
                f"CornerPad_{suffix}",
                location,
                (0.032, 0.051, 0.040),
                materials["edge"],
                collection,
                bevel=0.006,
            )
        )

    # Front screen assembly. The backplate overlaps the main case, while the
    # luminous panel overlaps the backplate by 2 mm to avoid a floating face.
    parts += [
        add_cube("Screen_Backplate", (0.0, -0.026, 0.018), (0.166, 0.012, 0.236), materials["case_dark"], collection, bevel=0.007),
        add_cube("Screen_Panel", (0.0, -0.033, 0.018), (0.148, 0.006, 0.216), materials["screen"], collection, bevel=0.005),
        add_cube("Screen_UI_Top", (0.0, -0.0365, 0.096), (0.108, 0.003, 0.010), materials["screen_ui"], collection, bevel=0.002),
        add_cube("Screen_UI_Mid", (-0.025, -0.0365, 0.026), (0.072, 0.003, 0.008), materials["screen_ui"], collection, bevel=0.002),
        add_cube("Screen_UI_Bottom", (0.018, -0.0365, -0.068), (0.092, 0.003, 0.009), materials["screen_ui"], collection, bevel=0.002),
        add_cylinder("Screen_UI_Radar", (0.035, -0.0368, 0.018), 0.030, 0.003, materials["screen_ui"], collection, rotation=(math.radians(90.0), 0.0, 0.0), vertices=16, bevel=0.001, smooth=False),
    ]

    # Small physical controls on the right edge.
    parts += [
        add_cube("SideButton_Upper", (0.104, 0.0, 0.060), (0.012, 0.024, 0.038), materials["button"], collection, bevel=0.004),
        add_cube("SideButton_Lower", (0.104, 0.0, 0.010), (0.012, 0.024, 0.028), materials["case_dark"], collection, bevel=0.004),
    ]

    # Rear grip rail gives the hand a stable holding surface and attaches to the back plate.
    parts += [
        add_cube("RearGrip_Rail", (0.0, 0.045, -0.065), (0.105, 0.035, 0.105), materials["case_dark"], collection, bevel=0.008),
        add_cube("RearGrip_Pad", (0.0, 0.065, -0.065), (0.082, 0.014, 0.082), materials["edge"], collection, bevel=0.007),
    ]

    # Rear black short cylindrical scanning lens, mounted near the upper half.
    # The cylinder axis is local Y.
    parts += [
        add_cube("Lens_Mount", (0.0, 0.039, 0.068), (0.088, 0.034, 0.082), materials["case_dark"], collection, bevel=0.010),
        add_cylinder("Lens_Barrel", (0.0, 0.086, 0.068), 0.034, 0.090, materials["lens_black"], collection, rotation=(math.radians(90.0), 0.0, 0.0), vertices=20, bevel=0.004, smooth=True),
        add_cylinder("Lens_Rim", (0.0, 0.134, 0.068), 0.041, 0.020, materials["lens_black"], collection, rotation=(math.radians(90.0), 0.0, 0.0), vertices=20, bevel=0.003, smooth=True),
        add_cylinder("Lens_Glass", (0.0, 0.145, 0.068), 0.031, 0.006, materials["lens_glass"], collection, rotation=(math.radians(90.0), 0.0, 0.0), vertices=20, bevel=0.001, smooth=True),
        add_cube("Lens_StatusLight", (0.032, 0.058, 0.108), (0.016, 0.012, 0.016), materials["button"], collection, bevel=0.003),
    ]

    for obj in parts:
        obj.parent = root
    return parts


# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def world_bbox(objects):
    points = []
    bpy.context.view_layer.update()
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("No mesh points available for bounds calculation.")
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def get_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Missing expected object: {name}")
    return obj


def aabb_distance(obj_a, obj_b):
    a_low, a_high = world_bbox([obj_a])
    b_low, b_high = world_bbox([obj_b])
    dx = max(0.0, b_low.x - a_high.x, a_low.x - b_high.x)
    dy = max(0.0, b_low.y - a_high.y, a_low.y - b_high.y)
    dz = max(0.0, b_low.z - a_high.z, a_low.z - b_high.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def validate_premerge():
    pairs = [
        ("Case_Main", "Case_BackPlate", 0.005),
        ("Case_Main", "CornerPad_TL", 0.005),
        ("Case_Main", "CornerPad_TR", 0.005),
        ("Case_Main", "CornerPad_BL", 0.005),
        ("Case_Main", "CornerPad_BR", 0.005),
        ("Case_Main", "Screen_Backplate", 0.005),
        ("Screen_Backplate", "Screen_Panel", 0.005),
        ("Screen_Panel", "Screen_UI_Top", 0.002),
        ("Screen_Panel", "Screen_UI_Mid", 0.002),
        ("Screen_Panel", "Screen_UI_Bottom", 0.002),
        ("Screen_Panel", "Screen_UI_Radar", 0.002),
        ("Case_Main", "SideButton_Upper", 0.005),
        ("Case_Main", "SideButton_Lower", 0.005),
        ("Case_BackPlate", "RearGrip_Rail", 0.005),
        ("RearGrip_Rail", "RearGrip_Pad", 0.005),
        ("Case_BackPlate", "Lens_Mount", 0.005),
        ("Lens_Mount", "Lens_Barrel", 0.005),
        ("Lens_Barrel", "Lens_Rim", 0.005),
        ("Lens_Rim", "Lens_Glass", 0.005),
        ("Lens_Mount", "Lens_StatusLight", 0.005),
    ]

    failures = []
    for first_name, second_name, allowed_gap in pairs:
        distance = aabb_distance(get_object(first_name), get_object(second_name))
        if distance > allowed_gap:
            failures.append(
                f"{first_name} -> {second_name}: gap {distance:.4f} m > allowed {allowed_gap:.4f} m"
            )

    if failures:
        raise RuntimeError("FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures))
    print(f"[VALID] Pre-merge floating-part audit passed: {len(pairs)} checks.")


def validate_postmerge(root):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Scanner root must remain an Empty at world origin.")

    required_children = {STATIC_NAME, "ScanOrigin", "ScreenCenter"}
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required export nodes: " + ", ".join(missing))

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("Cameras/lights must not remain in export scene: " + ", ".join(forbidden))

    collision_like = [
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and (obj.name.lower().startswith("ucx") or "collision" in obj.name.lower())
    ]
    if collision_like:
        raise RuntimeError("Collision-like meshes are not allowed: " + ", ".join(collision_like))

    meshes = get_meshes_under(root)
    if len(meshes) != 1 or meshes[0].name != STATIC_NAME:
        raise RuntimeError("Expected exactly one merged scanner static mesh.")

    low, high = world_bbox(meshes)
    dims = high - low
    if dims.x > 0.25 or dims.z > 0.34:
        raise RuntimeError(
            f"Scanner is no longer palm-sized. Got {dims.x:.3f} m wide x {dims.z:.3f} m tall."
        )

    meshes[0].data.calc_loop_triangles()
    triangles = len(meshes[0].data.loop_triangles)
    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dims.x:.3f} m x {dims.y:.3f} m x {dims.z:.3f} m\n"
        f"  Triangles: {triangles}\n"
        f"  Root children: {', '.join(sorted(required_children))}\n"
    )


# -----------------------------------------------------------------------------
# Root / export
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.10)
    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "Scanner"
    root["visual_style"] = "PalmSizedTabletRearLens"
    root["authoring_scan_axis"] = AUTHORING_SCAN_AXIS
    root["intended_godot_scan_axis"] = INTENDED_GODOT_SCAN_AXIS
    root["revision"] = SCRIPT_REVISION
    return root


def create_runtime_markers(root, collection):
    scan_origin = create_empty(
        "ScanOrigin",
        SCAN_ORIGIN_LOCATION,
        collection,
        parent=root,
        display_type="SINGLE_ARROW",
        size=0.055,
    )
    scan_origin.rotation_euler = (math.radians(-90.0), 0.0, 0.0)
    scan_origin["interaction_role"] = "ScanRayOrigin"
    scan_origin["local_scan_axis"] = "+Y"

    screen_center = create_empty(
        "ScreenCenter",
        SCREEN_CENTER_LOCATION,
        collection,
        parent=root,
        display_type="PLAIN_AXES",
        size=0.040,
    )
    screen_center["interaction_role"] = "ScreenEffectAnchor"
    return scan_origin, screen_center


def build_asset():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)

    parts = build_scanner(materials, collection, root)
    create_runtime_markers(root, collection)

    # Components remain independent until the floating-part audit passes.
    validate_premerge()
    join_meshes(parts, STATIC_NAME, root)
    validate_postmerge(root)
    return root


def select_hierarchy(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_asset(root):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    select_hierarchy(root)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
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
    print("[EXPORT] GLB=" + OUTPUT_GLB)


def main():
    print(f"\n=== Generating Handheld Tablet Scanner [{SCRIPT_REVISION}] ===\n")
    root = build_asset()
    export_asset(root)
    print("\n=== Finished ===")
    print("Godot nodes:")
    print(" - ScanOrigin: scanning ray/effect origin in front of the rear cylindrical lens.")
    print(" - ScreenCenter: anchor for screen UI or scan feedback effects.")
    print(" - Static: merged tablet body, front screen, controls, rear grip, and lens.")


if __name__ == "__main__":
    main()
