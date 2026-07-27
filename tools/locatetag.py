# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Rider Vehicle Locator Tag
#
# Generates:
#   generated_farmtown_props/
#     FTF_Prop_VehicleLocatorTag_White_v1.glb
#     FTF_Prop_VehicleLocatorTag_White_v1.blend
#
# DESIGN
# - Compact magnetic vehicle locator tag fired by the Rider locator launcher.
# - White, low-profile puck body with a dark technical ring.
# - Central red signal lamp; no antenna and no explosive-device styling.
# - Flat black magnetic back for attachment to vehicle body panels.
# - The signal lamp remains a separate node so it can blink in Godot.
#
# EXPORTED HIERARCHY
#   FTF_Prop_VehicleLocatorTag_White_v1
#   |-- FTF_Prop_VehicleLocatorTag_White_v1_Static
#   |-- SignalLight
#   `-- VehicleAttachPoint
#
# AXIS / ATTACHMENT STANDARD
# - Projectile / visible front direction in Blender: local -Y.
# - Flat magnetic contact surface: local +Y side.
# - VehicleAttachPoint is at the centre of the magnetic contact plane.
# - Recommended Godot attachment: align the tag's local +Y with the vehicle
#   surface normal pointing away from the vehicle.
# - No cameras, lights, text, weapons, knife geometry or collision meshes.
#
# Run:
#   blender --background --factory-startup --python vehicle_locator_tag_white.py
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# -----------------------------------------------------------------------------
# PATHS / CONSTANTS
# -----------------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_props")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Prop_VehicleLocatorTag_White_v1.glb")
OUTPUT_BLEND = os.path.join(OUTPUT_DIR, "FTF_Prop_VehicleLocatorTag_White_v1.blend")

ROOT_NAME = "FTF_Prop_VehicleLocatorTag_White_v1"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV1_MAGNETIC_PUCK_RED_SIGNAL"

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
ATTACHMENT_NORMAL_AXIS = "+Y"
VEHICLE_ATTACH_LOCATION = Vector((0.0, 0.0, 0.0))

# Approximate finished size: 0.24 m diameter x 0.09 m deep.
MAX_ALLOWED_DIAMETER = 0.28
MAX_ALLOWED_DEPTH = 0.12


# -----------------------------------------------------------------------------
# SCENE / MATERIALS
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



def make_material(
    name,
    color,
    roughness=0.7,
    metallic=0.0,
    emission=None,
    emission_strength=0.0,
):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    if emission is not None and emission_strength > 0.0:
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (*emission, 1.0)
        emit.inputs["Strength"].default_value = emission_strength
        links.new(emit.outputs["Emission"], output.inputs["Surface"])
    else:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    return material



def build_materials():
    return {
        "white": make_material(
            "MAT_VLT_CleanWhite", (0.90, 0.91, 0.93), 0.54, 0.12
        ),
        "white_alt": make_material(
            "MAT_VLT_SoftWhite", (0.73, 0.76, 0.80), 0.62, 0.18
        ),
        "black": make_material(
            "MAT_VLT_MagneticBlack", (0.012, 0.015, 0.018), 0.86, 0.10
        ),
        "gunmetal": make_material(
            "MAT_VLT_TechnicalRing", (0.10, 0.12, 0.14), 0.48, 0.46
        ),
        "red_bezel": make_material(
            "MAT_VLT_RedBezel", (0.34, 0.012, 0.016), 0.58, 0.18
        ),
        "red_glow": make_material(
            "MAT_VLT_RedSignalGlow",
            (0.98, 0.05, 0.06),
            emission=(0.96, 0.015, 0.02),
            emission_strength=2.4,
        ),
    }


# -----------------------------------------------------------------------------
# OBJECT HELPERS
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



def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj



def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)



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



def add_bevel(obj, width=0.003, segments=1):
    modifier = obj.modifiers.new("LowPolyBevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
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
            print(f"[WARN] Could not apply {modifier.name} on {obj.name}: {exc}")



def finish_mesh(
    obj,
    name,
    material,
    collection,
    parent=None,
    bevel=0.0,
    smooth=False,
):
    obj.name = name
    assign_material(obj, material)
    if smooth:
        set_smooth_shading(obj)
    else:
        set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel, 1)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj



def add_cube(
    name,
    location,
    dimensions,
    material,
    collection,
    parent=None,
    bevel=0.0,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(
        obj,
        name,
        material,
        collection,
        parent=parent,
        bevel=bevel,
        smooth=False,
    )



def add_cylinder_between(
    name,
    start,
    end,
    radius,
    material,
    collection,
    parent=None,
    vertices=18,
    bevel=0.0,
    smooth=True,
):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    if direction.length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")

    midpoint = (start_v + end_v) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=midpoint,
        rotation=rotation,
    )
    return finish_mesh(
        bpy.context.object,
        name,
        material,
        collection,
        parent=parent,
        bevel=bevel,
        smooth=smooth,
    )



def add_torus_y(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    collection,
    parent=None,
    major_segments=20,
    minor_segments=6,
):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    return finish_mesh(
        bpy.context.object,
        name,
        material,
        collection,
        parent=parent,
        smooth=True,
    )



def create_empty(
    name,
    location,
    collection,
    parent=None,
    display_type="PLAIN_AXES",
    size=0.04,
):
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.parent = parent
    collection.objects.link(obj)
    return obj


# -----------------------------------------------------------------------------
# ROOT / RUNTIME NODES
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(
        ROOT_NAME,
        (0.0, 0.0, 0.0),
        collection,
        display_type="PLAIN_AXES",
        size=0.08,
    )
    root["asset_type"] = "ProjectileProp"
    root["role_owner"] = "Rider"
    root["prop_category"] = "VehicleLocatorTag"
    root["visual_style"] = "WhiteMagneticPuckRedSignal"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["attachment_normal_axis"] = ATTACHMENT_NORMAL_AXIS
    root["vehicle_attach_node"] = "VehicleAttachPoint"
    root["signal_light_node"] = "SignalLight"
    root["contains_antenna"] = False
    root["contains_explosive_styling"] = False
    root["has_collision_mesh"] = False
    root["revision"] = SCRIPT_REVISION
    return root



def create_attach_point(root, collection):
    attach = create_empty(
        "VehicleAttachPoint",
        VEHICLE_ATTACH_LOCATION,
        collection,
        parent=root,
        display_type="SINGLE_ARROW",
        size=0.055,
    )
    # Empty arrows point +Z by default. -90 degrees around X maps +Z to +Y.
    attach.rotation_euler = (math.radians(-90.0), 0.0, 0.0)
    attach["interaction_role"] = "VehicleSurfaceAttachment"
    attach["surface_normal_axis"] = "+Y"
    attach["contact_plane"] = "Y=0"
    return attach


# -----------------------------------------------------------------------------
# BUILD LOCATOR TAG
# -----------------------------------------------------------------------------


def build_static_body(materials, collection, root):
    parts = []

    # Flat black magnetic contact base. Its back face is exactly on Y=0.
    parts.append(add_cylinder_between(
        "Magnet_BlackContactBase",
        (0.0, 0.0, 0.0),
        (0.0, -0.018, 0.0),
        0.105,
        materials["black"],
        collection,
        parent=root,
        vertices=20,
        bevel=0.002,
    ))

    # Three broad embedded magnetic pads make the back logically readable
    # without protruding beyond the attachment plane.
    for index, angle_deg in enumerate((90.0, 210.0, 330.0)):
        angle = math.radians(angle_deg)
        x = math.cos(angle) * 0.055
        z = math.sin(angle) * 0.055
        parts.append(add_cylinder_between(
            f"Magnet_Pad_{index:02d}",
            (x, -0.001, z),
            (x, -0.010, z),
            0.021,
            materials["gunmetal"],
            collection,
            parent=root,
            vertices=14,
            bevel=0.001,
        ))

    # Dark technical ring forms a strong silhouette between the magnet and the
    # white shell. It overlaps both neighbours so no floating seam is created.
    parts.append(add_cylinder_between(
        "Body_DarkTechnicalRing",
        (0.0, -0.014, 0.0),
        (0.0, -0.038, 0.0),
        0.120,
        materials["gunmetal"],
        collection,
        parent=root,
        vertices=20,
        bevel=0.003,
    ))

    # Main white puck shell.
    parts.append(add_cylinder_between(
        "Body_WhiteMainShell",
        (0.0, -0.032, 0.0),
        (0.0, -0.064, 0.0),
        0.112,
        materials["white"],
        collection,
        parent=root,
        vertices=20,
        bevel=0.004,
    ))

    # Slightly smaller front cap gives the face a friendly electronic-device
    # appearance rather than a mine or explosive shape.
    parts.append(add_cylinder_between(
        "Body_WhiteFrontCap",
        (0.0, -0.058, 0.0),
        (0.0, -0.074, 0.0),
        0.095,
        materials["white_alt"],
        collection,
        parent=root,
        vertices=20,
        bevel=0.003,
    ))

    # Embedded face ring frames the red lamp while remaining flush with the cap.
    parts.append(add_torus_y(
        "Body_FrontTechnicalRing",
        (0.0, -0.071, 0.0),
        0.065,
        0.008,
        materials["gunmetal"],
        collection,
        parent=root,
        major_segments=20,
        minor_segments=6,
    ))

    # Wide red bezel is static; the actual light inside remains a separate node.
    parts.append(add_cylinder_between(
        "Signal_RedBezel",
        (0.0, -0.069, 0.0),
        (0.0, -0.078, 0.0),
        0.052,
        materials["red_bezel"],
        collection,
        parent=root,
        vertices=18,
        bevel=0.002,
    ))

    return parts



def build_signal_light(materials, collection, root):
    # Separate light mesh can be hidden, pulsed or material-modulated in Godot.
    return add_cylinder_between(
        "SignalLight",
        (0.0, -0.075, 0.0),
        (0.0, -0.089, 0.0),
        0.041,
        materials["red_glow"],
        collection,
        parent=root,
        vertices=18,
        bevel=0.002,
    )


# -----------------------------------------------------------------------------
# MERGE / VALIDATION
# -----------------------------------------------------------------------------


def join_meshes(objects, name, parent):
    if not objects:
        raise RuntimeError("No static locator tag meshes available for merge.")

    for obj in objects:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = name
    merged.parent = parent
    set_flat_shading(merged)
    return merged



def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)



def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]



def world_bbox(obj):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = Vector((
        min(p.x for p in points),
        min(p.y for p in points),
        min(p.z for p in points),
    ))
    high = Vector((
        max(p.x for p in points),
        max(p.y for p in points),
        max(p.z for p in points),
    ))
    return low, high



def combined_bbox(objects):
    lows = []
    highs = []
    for obj in objects:
        low, high = world_bbox(obj)
        lows.append(low)
        highs.append(high)
    return (
        Vector((
            min(v.x for v in lows),
            min(v.y for v in lows),
            min(v.z for v in lows),
        )),
        Vector((
            max(v.x for v in highs),
            max(v.y for v in highs),
            max(v.z for v in highs),
        )),
    )



def aabb_distance(obj_a, obj_b):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)
    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)



def validate_before_export(root, static_mesh, signal_light, attach_point):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Locator tag root must remain an Empty at origin.")

    required_children = {STATIC_NAME, "SignalLight", "VehicleAttachPoint"}
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required locator tag nodes: " + ", ".join(missing))

    if static_mesh.parent != root:
        raise RuntimeError("Static locator body must be a direct child of root.")
    if signal_light.parent != root:
        raise RuntimeError("SignalLight must be a direct child of root.")
    if attach_point.parent != root:
        raise RuntimeError("VehicleAttachPoint must be a direct child of root.")
    if (attach_point.location - VEHICLE_ATTACH_LOCATION).length > 0.0001:
        raise RuntimeError("VehicleAttachPoint moved away from contact-plane centre.")

    forbidden_scene = [
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type in {"CAMERA", "LIGHT"}
    ]
    if forbidden_scene:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(forbidden_scene))

    forbidden_names = [
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and (
            obj.name.lower().startswith("ucx")
            or "collision" in obj.name.lower()
            or "antenna" in obj.name.lower()
            or "explosive" in obj.name.lower()
        )
    ]
    if forbidden_names:
        raise RuntimeError("Forbidden locator geometry remains: " + ", ".join(forbidden_names))

    # The lamp must physically overlap its bezel / static face.
    lamp_gap = aabb_distance(signal_light, static_mesh)
    if lamp_gap > 0.002:
        raise RuntimeError(
            f"SignalLight is floating: gap {lamp_gap:.4f} m > 0.0020 m"
        )

    meshes = get_meshes_under_root(root)
    low, high = combined_bbox(meshes)
    dimensions = high - low
    if dimensions.x > MAX_ALLOWED_DIAMETER or dimensions.z > MAX_ALLOWED_DIAMETER:
        raise RuntimeError(
            f"Locator tag diameter too large: {max(dimensions.x, dimensions.z):.3f} m"
        )
    if dimensions.y > MAX_ALLOWED_DEPTH:
        raise RuntimeError(f"Locator tag depth too large: {dimensions.y:.3f} m")

    # Contact plane must not extend into +Y, otherwise the model would clip
    # through the vehicle surface when aligned at VehicleAttachPoint.
    if high.y > 0.001:
        raise RuntimeError(
            f"Geometry extends behind attachment plane: max Y={high.y:.4f} m"
        )

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale: " + obj.name)
    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dimensions.x:.3f} m x {dimensions.y:.3f} m x {dimensions.z:.3f} m\n"
        f"  Visual mesh nodes: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Separate blinking node: {signal_light.name}\n"
        f"  Attachment node: {attach_point.name} at Y=0\n"
        f"  Attachment normal: +Y\n"
        f"  Antenna: NONE\n"
        f"  Explosive styling: NONE\n"
    )


# -----------------------------------------------------------------------------
# BUILD / EXPORT
# -----------------------------------------------------------------------------


def build_locator_tag():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)
    attach_point = create_attach_point(root, collection)

    static_parts = build_static_body(materials, collection, root)
    if not MERGE_STATIC_MESHES:
        raise RuntimeError("This asset requires MERGE_STATIC_MESHES=True.")
    static_mesh = join_meshes(static_parts, STATIC_NAME, root)

    signal_light = build_signal_light(materials, collection, root)
    apply_transforms_and_modifiers(signal_light)

    validate_before_export(root, static_mesh, signal_light, attach_point)
    return root



def select_hierarchy(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root



def export_assets(root):
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
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print("[EXPORT] GLB=" + OUTPUT_GLB)
    print("[EXPORT] BLEND=" + OUTPUT_BLEND)



def main():
    print(f"\n=== Generating Rider Vehicle Locator Tag [{SCRIPT_REVISION}] ===\n")
    root = build_locator_tag()
    export_assets(root)
    print("\n=== Finished ===")
    print("Godot nodes:")
    print(" - SignalLight: pulse or blink this mesh/material.")
    print(" - VehicleAttachPoint: align this point to the vehicle hit surface.")
    print(" - Local +Y is the attachment surface normal.")


if __name__ == "__main__":
    main()
