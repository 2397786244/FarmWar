# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Tech Repair Wrench
#
# Generates:
#   generated_farmtown_tools/
#     FTF_Tool_RepairWrench_Tech_v2.glb
#
# DESIGN
# - Small handheld vehicle-repair tool.
# - Primary silhouette is a compact wrench, but with a slightly futuristic,
#   tech-assisted design language rather than a plain workshop spanner.
# - Dark metallic body, reinforced jaw assembly, and cyan repair-status lights.
# - One-handed tool intended for Godot.
#
# EXPORTED HIERARCHY
#   FTF_Tool_RepairWrench_Tech_v2
#   |-- FTF_Tool_RepairWrench_Tech_v2_Static
#   `-- RepairContactPoint
#
# NOTES
# - Root origin is centered at the hand-grip area.
# - RepairContactPoint marks the front work-contact position near the wrench jaw.
# - No cameras, lights, text, or collision meshes are exported.
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
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Tool_RepairWrench_Tech_v2.glb")

ROOT_NAME = "FTF_Tool_RepairWrench_Tech_v2"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV2_PREMERGE_ATTACHMENT_AUDIT"

CLEAR_SCENE = True
AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"
REPAIR_CONTACT_LOCATION = Vector((0.0, -0.78, 0.22))


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
        "metal_dark": make_material("MAT_TRW_MetalDark", (0.12, 0.14, 0.15), metallic=0.70, roughness=0.32),
        "metal_mid": make_material("MAT_TRW_MetalMid", (0.22, 0.24, 0.26), metallic=0.62, roughness=0.36),
        "grip": make_material("MAT_TRW_Grip", (0.05, 0.06, 0.07), metallic=0.08, roughness=0.80),
        "accent": make_material("MAT_TRW_Accent", (0.34, 0.72, 0.78), metallic=0.14, roughness=0.26),
        "glow": make_material(
            "MAT_TRW_Glow",
            (0.44, 0.90, 0.96),
            metallic=0.0,
            roughness=0.16,
            emission=(0.18, 0.85, 0.95),
            emission_strength=2.0,
        ),
    }


# -----------------------------------------------------------------------------
# Object helpers
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
    for poly in obj.data.polygons:
        poly.use_smooth = False



def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for poly in obj.data.polygons:
        poly.use_smooth = True



def add_bevel(obj, width=0.01, segments=1):
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



def add_cylinder(name, location, radius, depth, material, collection, rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, material, collection, bevel=bevel, smooth=smooth)



def add_cylinder_between(name, start, end, radius, material, collection, vertices=16, bevel=0.0, smooth=True):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    if direction.length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")
    midpoint = (start_v + end_v) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    return add_cylinder(name, midpoint, radius, direction.length, material, collection, rotation=rotation, vertices=vertices, bevel=bevel, smooth=smooth)



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



def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.12):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    collection.objects.link(obj)
    return obj


# -----------------------------------------------------------------------------
# Build wrench
# -----------------------------------------------------------------------------


def build_static_tool(materials, collection, root):
    parts = []

    # Rear grip with slightly ergonomic tech profile.
    parts += [
        add_cube("Grip_Main", (0.0, 0.06, -0.08), (0.16, 0.32, 0.46), materials["grip"], collection, bevel=0.020, rotation=(math.radians(-12.0), 0.0, 0.0)),
        add_cube("Grip_BackCap", (0.0, 0.17, -0.10), (0.18, 0.08, 0.26), materials["metal_dark"], collection, bevel=0.012, rotation=(math.radians(-12.0), 0.0, 0.0)),
        add_cube("Grip_SideStrip_L", (-0.058, 0.03, -0.05), (0.02, 0.22, 0.24), materials["glow"], collection, bevel=0.004),
        add_cube("Grip_SideStrip_R", (0.058, 0.03, -0.05), (0.02, 0.22, 0.24), materials["glow"], collection, bevel=0.004),
    ]

    # Central body / handle spine.
    parts += [
        add_cube("Body_Spine", (0.0, -0.18, 0.05), (0.12, 0.62, 0.12), materials["metal_mid"], collection, bevel=0.016),
        add_cube("Body_Core", (0.0, -0.40, 0.16), (0.20, 0.38, 0.20), materials["metal_dark"], collection, bevel=0.018),
        add_cube("Body_TopModule", (0.0, -0.36, 0.28), (0.16, 0.28, 0.10), materials["accent"], collection, bevel=0.012),
        add_cube("Body_StatusLight", (0.0, -0.36, 0.34), (0.09, 0.16, 0.05), materials["glow"], collection, bevel=0.006),
    ]

    # Forward neck leading to wrench head.
    parts += [
        add_cube("Neck_Block", (0.0, -0.61, 0.17), (0.16, 0.16, 0.18), materials["metal_mid"], collection, bevel=0.012),
        add_cylinder_between("Neck_Link_L", (-0.05, -0.55, 0.18), (-0.07, -0.69, 0.22), 0.030, materials["metal_dark"], collection, vertices=10, bevel=0.004),
        add_cylinder_between("Neck_Link_R", (0.05, -0.55, 0.18), (0.07, -0.69, 0.22), 0.030, materials["metal_dark"], collection, vertices=10, bevel=0.004),
    ]

    # Tech wrench head: robust C-shaped jaw with a small tech module.
    parts += [
        add_cube("Jaw_Base", (0.0, -0.78, 0.20), (0.22, 0.18, 0.20), materials["metal_dark"], collection, bevel=0.014),
        add_cube("Jaw_BackBridge", (0.0, -0.81, 0.29), (0.20, 0.10, 0.16), materials["metal_mid"], collection, bevel=0.012),
        add_cube("Jaw_Upper", (0.0, -0.86, 0.37), (0.22, 0.20, 0.12), materials["metal_mid"], collection, bevel=0.012),
        add_cube("Jaw_Lower", (0.0, -0.86, 0.07), (0.22, 0.20, 0.12), materials["metal_mid"], collection, bevel=0.012),
        add_cube("Jaw_FixedTip", (0.0, -0.98, 0.37), (0.16, 0.06, 0.12), materials["metal_dark"], collection, bevel=0.008),
        add_cube("Jaw_AdjustableTip", (0.0, -0.98, 0.07), (0.16, 0.06, 0.12), materials["metal_dark"], collection, bevel=0.008),
        add_cube("Jaw_TechModule", (0.0, -0.77, 0.41), (0.12, 0.12, 0.07), materials["accent"], collection, bevel=0.008),
        add_cube("Jaw_TechGlow", (0.0, -0.77, 0.455), (0.08, 0.08, 0.03), materials["glow"], collection, bevel=0.004),
    ]

    # Adjustment wheel to sell the wrench silhouette.
    parts += [
        add_cylinder("Adjust_Wheel", (0.0, -0.79, 0.20), 0.06, 0.07, materials["metal_mid"], collection, rotation=(math.radians(90.0), 0.0, 0.0), vertices=14, bevel=0.004),
        add_cube("Adjust_WheelGrip", (0.0, -0.75, 0.20), (0.08, 0.03, 0.02), materials["glow"], collection, bevel=0.003),
    ]

    for part in parts:
        part.parent = root
    return parts


# -----------------------------------------------------------------------------
# Root / validation / export
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.20)
    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "RepairWrench"
    root["visual_style"] = "SmallTechWrench"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["revision"] = SCRIPT_REVISION
    return root



def create_runtime_markers(root, collection):
    point = create_empty(
        "RepairContactPoint",
        REPAIR_CONTACT_LOCATION,
        collection,
        parent=root,
        display_type="SINGLE_ARROW",
        size=0.10,
    )
    point.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    point["interaction_role"] = "RepairContactPoint"
    point["local_forward_axis"] = "-Y"
    return point



def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)



def get_meshes_under_root(root):
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
    bpy.context.view_layer.update()
    a_low, a_high = world_bbox([obj_a])
    b_low, b_high = world_bbox([obj_b])
    dx = max(0.0, b_low.x - a_high.x, a_low.x - b_high.x)
    dy = max(0.0, b_low.y - a_high.y, a_low.y - b_high.y)
    dz = max(0.0, b_low.z - a_high.z, a_low.z - b_high.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)



def validate_attachment_pairs():
    pairs = [
        ("Grip_Main", "Body_Spine", 0.005),
        ("Grip_BackCap", "Grip_Main", 0.005),
        ("Grip_SideStrip_L", "Grip_Main", 0.005),
        ("Grip_SideStrip_R", "Grip_Main", 0.005),
        ("Body_Spine", "Body_Core", 0.005),
        ("Body_TopModule", "Body_Core", 0.005),
        ("Body_StatusLight", "Body_TopModule", 0.005),
        ("Neck_Block", "Body_Core", 0.005),
        ("Neck_Link_L", "Neck_Block", 0.005),
        ("Neck_Link_R", "Neck_Block", 0.005),
        ("Jaw_Base", "Neck_Block", 0.005),
        ("Jaw_BackBridge", "Jaw_Base", 0.005),
        ("Jaw_Upper", "Jaw_BackBridge", 0.005),
        ("Jaw_Lower", "Jaw_Base", 0.005),
        ("Jaw_FixedTip", "Jaw_Upper", 0.005),
        ("Jaw_AdjustableTip", "Jaw_Lower", 0.005),
        ("Jaw_TechModule", "Jaw_Upper", 0.005),
        ("Jaw_TechGlow", "Jaw_TechModule", 0.005),
        ("Adjust_Wheel", "Jaw_Base", 0.005),
        ("Adjust_WheelGrip", "Adjust_Wheel", 0.005),
    ]
    failures = []
    for first_name, second_name, allowed_gap in pairs:
        first = get_object(first_name)
        second = get_object(second_name)
        distance = aabb_distance(first, second)
        if distance > allowed_gap:
            failures.append(f"{first_name} -> {second_name}: gap {distance:.4f} m > allowed {allowed_gap:.4f} m")
    if failures:
        raise RuntimeError("FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures))
    print(f"[VALID] Attachment audit passed: {len(pairs)} checks.")



def validate_asset(root):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Repair wrench root must remain an Empty at world origin.")

    required_children = {STATIC_NAME, "RepairContactPoint"}
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required export nodes: " + ", ".join(missing))

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("Cameras/lights must not remain in export scene: " + ", ".join(forbidden))

    collision_like = [obj.name for obj in bpy.context.scene.objects if obj.type == "MESH" and (obj.name.lower().startswith("ucx") or "collision" in obj.name.lower())]
    if collision_like:
        raise RuntimeError("Collision-like meshes are not allowed: " + ", ".join(collision_like))

    meshes = get_meshes_under_root(root)
    if len(meshes) != 1 or meshes[0].name != STATIC_NAME:
        raise RuntimeError(
            f"Expected exactly one merged static mesh named {STATIC_NAME}; "
            f"found: {', '.join(obj.name for obj in meshes)}"
        )

    low, high = world_bbox(meshes)
    dims = high - low
    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dims.x:.2f} m x {dims.y:.2f} m x {dims.z:.2f} m\n"
        f"  Mesh objects: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Root children: {', '.join(sorted(required_children))}\n"
    )



def build_asset():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)

    parts = build_static_tool(materials, collection, root)

    # Attachment checks must run before joining, while the original part names
    # still exist. After bpy.ops.object.join(), only STATIC_NAME remains.
    validate_attachment_pairs()

    join_meshes(parts, STATIC_NAME, root)
    create_runtime_markers(root, collection)
    validate_asset(root)
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
    print(f"\n=== Generating Tech Repair Wrench [{SCRIPT_REVISION}] ===\n")
    root = build_asset()
    export_asset(root)
    print("\n=== Finished ===")
    print("Godot nodes:")
    print(" - RepairContactPoint: front contact position for repair interactions.")
    print(" - Static mesh contains the full small tech wrench body.")


if __name__ == "__main__":
    main()
