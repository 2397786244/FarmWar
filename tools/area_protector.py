# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Area Shield Generator
#
# Generates:
#   generated_farmtown_deployables/
#     FTF_Deployable_AreaShield_Generator_Yellow_v3.glb
#
# DESIGN
# - Deployable area shield generator with a cross-armed metallic base.
# - Projects a pale-yellow translucent rectangular shield field.
# - The field is NOT a solid wall; it represents a ballistic weakening zone.
# - Intended gameplay meaning: enemy bullets / shells that pass through the
#   field are slowed and weakened, while allied projectiles are unaffected.
# - Shield field size: 12 m x 12 m x 4 m.
#
# EXPORTED HIERARCHY
#   FTF_Deployable_AreaShield_Generator_Yellow_v2
#   |-- FTF_Deployable_AreaShield_Generator_Yellow_v2_Static
#   |-- ShieldVolume
#   |-- ShieldBounds
#   `-- ShieldEmitterTop
#
# NOTES
# - Only the cross-shaped base is exported visually in this revision.
# - ShieldBounds marks the center of the gameplay area if you still want to create the area effect in Godot.
# - ShieldEmitterTop marks the emission origin above the base.
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
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_deployables")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Deployable_AreaShield_Generator_Yellow_v3.glb")

ROOT_NAME = "FTF_Deployable_AreaShield_Generator_Yellow_v3"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV3_BASE_ONLY_NO_VISUAL_SHIELD"

CLEAR_SCENE = True
AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

SHIELD_SIZE = Vector((12.0, 12.0, 4.0))
SHIELD_BOTTOM_Z = 0.25
SHIELD_CENTER = Vector((0.0, 0.0, SHIELD_BOTTOM_Z + SHIELD_SIZE.z * 0.5))
EMITTER_TOP_LOCATION = Vector((0.0, 0.0, 1.08))


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



def make_principled_material(
    name,
    color,
    metallic=0.0,
    roughness=0.6,
    emission=None,
    emission_strength=0.0,
    alpha=1.0,
    blend_method="OPAQUE",
):
    material = bpy.data.materials.new(name)
    material.use_nodes = True

    # Blender 4.4 removed Material.shadow_method. Keep transparent-material
    # setup compatible with both older and newer Blender releases.
    if hasattr(material, "blend_method"):
        material.blend_method = blend_method
    if hasattr(material, "shadow_method"):
        material.shadow_method = "HASHED" if alpha < 1.0 else "OPAQUE"
    if hasattr(material, "use_transparency_overlap") and alpha < 1.0:
        material.use_transparency_overlap = False

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    material.diffuse_color = (*color, alpha)
    return material



def build_materials():
    return {
        "metal_dark": make_principled_material(
            "MAT_AS_MetalDark", (0.12, 0.14, 0.15), metallic=0.62, roughness=0.34
        ),
        "metal_mid": make_principled_material(
            "MAT_AS_MetalMid", (0.20, 0.22, 0.23), metallic=0.54, roughness=0.38
        ),
        "black": make_principled_material(
            "MAT_AS_Black", (0.03, 0.035, 0.04), metallic=0.18, roughness=0.72
        ),
        "node_yellow": make_principled_material(
            "MAT_AS_NodeYellow",
            (0.95, 0.84, 0.36),
            metallic=0.06,
            roughness=0.32,
            emission=(1.0, 0.88, 0.34),
            emission_strength=1.8,
        ),
        "shield_fill": make_principled_material(
            "MAT_AS_ShieldFill",
            (0.98, 0.94, 0.52),
            metallic=0.0,
            roughness=0.18,
            emission=(0.98, 0.92, 0.50),
            emission_strength=0.9,
            alpha=0.18,
            blend_method="BLEND",
        ),
        "shield_edge": make_principled_material(
            "MAT_AS_ShieldEdge",
            (1.0, 0.96, 0.62),
            metallic=0.0,
            roughness=0.10,
            emission=(1.0, 0.95, 0.62),
            emission_strength=2.3,
            alpha=0.46,
            blend_method="BLEND",
        ),
        "beam": make_principled_material(
            "MAT_AS_Beam",
            (0.98, 0.93, 0.56),
            metallic=0.0,
            roughness=0.10,
            emission=(1.0, 0.94, 0.58),
            emission_strength=2.0,
            alpha=0.35,
            blend_method="BLEND",
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
    for polygon in obj.data.polygons:
        polygon.use_smooth = False



def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True



def add_bevel(obj, width=0.02, segments=1):
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
        add_bevel(obj, bevel, 1)
    move_to_collection(obj, collection)
    return obj



def add_cube(name, location, dimensions, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel=bevel, smooth=smooth)



def add_cylinder(name, location, radius, depth, material, collection, rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return finish_mesh(bpy.context.object, name, material, collection, bevel=bevel, smooth=smooth)



def add_cylinder_between(name, start, end, radius, material, collection, vertices=12, bevel=0.0, smooth=True):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    if direction.length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")
    midpoint = (start_v + end_v) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    return add_cylinder(
        name,
        midpoint,
        radius,
        direction.length,
        material,
        collection,
        rotation=rotation,
        vertices=vertices,
        bevel=bevel,
        smooth=smooth,
    )



def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.20):
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
# Build base / field
# -----------------------------------------------------------------------------


def build_static_base(materials, collection, root):
    parts = []

    # Central base and cross arms.
    parts += [
        add_cylinder("Base_CoreLower", (0.0, 0.0, 0.22), 0.46, 0.24, materials["metal_dark"], collection, vertices=18, bevel=0.020),
        add_cylinder("Base_CoreUpper", (0.0, 0.0, 0.50), 0.34, 0.40, materials["metal_mid"], collection, vertices=18, bevel=0.020),
        add_cube("Base_Arm_X", (0.0, 0.0, 0.18), (2.20, 0.48, 0.18), materials["metal_dark"], collection, bevel=0.030),
        add_cube("Base_Arm_Y", (0.0, 0.0, 0.18), (0.48, 2.20, 0.18), materials["metal_dark"], collection, bevel=0.030),
        add_cube("Base_Plate_Center", (0.0, 0.0, 0.07), (1.16, 1.16, 0.08), materials["black"], collection, bevel=0.020),
    ]

    # Four stabilizer tips.
    tip_specs = [
        ("PX", (1.26, 0.0, 0.18), (0.42, 0.52, 0.16)),
        ("NX", (-1.26, 0.0, 0.18), (0.42, 0.52, 0.16)),
        ("PY", (0.0, 1.26, 0.18), (0.52, 0.42, 0.16)),
        ("NY", (0.0, -1.26, 0.18), (0.52, 0.42, 0.16)),
    ]
    for suffix, loc, dims in tip_specs:
        parts.append(add_cube(f"Base_Stabilizer_{suffix}", loc, dims, materials["metal_mid"], collection, bevel=0.018))

    # Emitter tower and four diagonal braces.
    parts += [
        add_cylinder("Emitter_Tower", (0.0, 0.0, 0.82), 0.16, 0.54, materials["metal_mid"], collection, vertices=16, bevel=0.012),
        add_cylinder("Emitter_Collar", (0.0, 0.0, 1.04), 0.23, 0.08, materials["black"], collection, vertices=18, bevel=0.008),
        add_cylinder("Emitter_Head", (0.0, 0.0, 1.12), 0.22, 0.12, materials["node_yellow"], collection, vertices=18, bevel=0.008),
    ]
    braces = [
        ((0.30, 0.30, 0.35), (0.14, 0.14, 0.92)),
        ((-0.30, 0.30, 0.35), (-0.14, 0.14, 0.92)),
        ((0.30, -0.30, 0.35), (0.14, -0.14, 0.92)),
        ((-0.30, -0.30, 0.35), (-0.14, -0.14, 0.92)),
    ]
    for idx, (a, b) in enumerate(braces):
        parts.append(add_cylinder_between(f"Emitter_Brace_{idx:02d}", a, b, 0.04, materials["metal_dark"], collection, 10, 0.006))

    # Yellow glow nodes on each arm tip.
    node_positions = [
        (1.26, 0.0, 0.34),
        (-1.26, 0.0, 0.34),
        (0.0, 1.26, 0.34),
        (0.0, -1.26, 0.34),
    ]
    for idx, pos in enumerate(node_positions):
        parts.append(add_cylinder(f"GlowNode_{idx:02d}", pos, 0.12, 0.11, materials["node_yellow"], collection, vertices=14, bevel=0.006))

    # A faint vertical beam from the emitter to the field.
    parts.append(add_cylinder_between(
        "Emitter_Beam",
        (0.0, 0.0, 1.18),
        (0.0, 0.0, SHIELD_BOTTOM_Z + 0.10),
        0.07,
        materials["beam"],
        collection,
        vertices=12,
        bevel=0.003,
    ))

    for part in parts:
        part.parent = root
    return parts



def build_shield_volume(materials, collection, root):
    meshes = []

    # Translucent fill cube.
    fill = add_cube(
        "ShieldFill",
        SHIELD_CENTER,
        (SHIELD_SIZE.x, SHIELD_SIZE.y, SHIELD_SIZE.z),
        materials["shield_fill"],
        collection,
        bevel=0.0,
        smooth=False,
    )
    fill.parent = root
    meshes.append(fill)

    # Edge frame for range readability.
    xh = SHIELD_SIZE.x * 0.5
    yh = SHIELD_SIZE.y * 0.5
    zh = SHIELD_SIZE.z * 0.5
    z0 = SHIELD_CENTER.z - zh
    z1 = SHIELD_CENTER.z + zh
    r = 0.055

    corners_bottom = [
        Vector((-xh, -yh, z0)),
        Vector((xh, -yh, z0)),
        Vector((xh, yh, z0)),
        Vector((-xh, yh, z0)),
    ]
    corners_top = [
        Vector((-xh, -yh, z1)),
        Vector((xh, -yh, z1)),
        Vector((xh, yh, z1)),
        Vector((-xh, yh, z1)),
    ]

    edge_index = 0
    for i in range(4):
        a = corners_bottom[i]
        b = corners_bottom[(i + 1) % 4]
        obj = add_cylinder_between(f"ShieldEdge_Bottom_{edge_index:02d}", a, b, r, materials["shield_edge"], collection, 8, 0.0)
        obj.parent = root
        meshes.append(obj)
        edge_index += 1
    for i in range(4):
        a = corners_top[i]
        b = corners_top[(i + 1) % 4]
        obj = add_cylinder_between(f"ShieldEdge_Top_{edge_index:02d}", a, b, r, materials["shield_edge"], collection, 8, 0.0)
        obj.parent = root
        meshes.append(obj)
        edge_index += 1
    for i in range(4):
        a = corners_bottom[i]
        b = corners_top[i]
        obj = add_cylinder_between(f"ShieldEdge_Vert_{edge_index:02d}", a, b, r, materials["shield_edge"], collection, 8, 0.0)
        obj.parent = root
        meshes.append(obj)
        edge_index += 1

    shield = join_meshes(meshes, "ShieldVolume_DEBUG", root)
    return shield


# -----------------------------------------------------------------------------
# Root / markers / validation
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.40)
    root["asset_type"] = "Deployable"
    root["deployable_category"] = "AreaShieldGenerator"
    root["shield_type"] = "BallisticWeakeningField"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["shield_width_m"] = SHIELD_SIZE.x
    root["shield_length_m"] = SHIELD_SIZE.y
    root["shield_height_m"] = SHIELD_SIZE.z
    root["revision"] = SCRIPT_REVISION
    root["logic_hint"] = "Enemy projectiles entering the field should be slowed and weakened; allied projectiles unaffected."
    return root



def create_runtime_markers(root, collection):
    shield_bounds = create_empty(
        "ShieldBounds",
        SHIELD_CENTER,
        collection,
        parent=root,
        display_type="CUBE",
        size=0.30,
    )
    shield_bounds["interaction_role"] = "ShieldAreaCenter"
    shield_bounds["recommended_box_extents_m"] = tuple(round(v * 0.5, 3) for v in SHIELD_SIZE)

    emitter_top = create_empty(
        "ShieldEmitterTop",
        EMITTER_TOP_LOCATION,
        collection,
        parent=root,
        display_type="SINGLE_ARROW",
        size=0.20,
    )
    emitter_top.rotation_euler = (math.radians(180.0), 0.0, 0.0)
    emitter_top["interaction_role"] = "ShieldProjectionOrigin"
    return shield_bounds, emitter_top



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



def validate_before_export(root):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Shield generator root must remain an Empty at world origin.")

    required_children = {STATIC_NAME, "ShieldBounds", "ShieldEmitterTop"}
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required export nodes: " + ", ".join(missing))

    shield_bounds = get_object("ShieldBounds")
    emitter_top = get_object("ShieldEmitterTop")
    if shield_bounds.parent != root or emitter_top.parent != root:
        raise RuntimeError("Shield marker hierarchy invalid.")

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("Cameras/lights must not remain in export scene: " + ", ".join(forbidden))

    bad_names = [obj.name for obj in bpy.context.scene.objects if obj.type == "MESH" and (obj.name.lower().startswith("ucx") or "collision" in obj.name.lower())]
    if bad_names:
        raise RuntimeError("Collision-like meshes are not allowed: " + ", ".join(bad_names))

    meshes = get_meshes_under_root(root)
    low, high = world_bbox(meshes)
    dimensions = high - low
    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
        f"  Shield gameplay area target: {SHIELD_SIZE.x:.1f} x {SHIELD_SIZE.y:.1f} x {SHIELD_SIZE.z:.1f} m\n"
        f"  Mesh objects: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Root children: {', '.join(sorted(required_children))}\n"
    )


# -----------------------------------------------------------------------------
# Build / export
# -----------------------------------------------------------------------------


def build_asset():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)

    base_parts = build_static_base(materials, collection, root)
    join_meshes(base_parts, STATIC_NAME, root)
    create_runtime_markers(root, collection)

    validate_before_export(root)
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
    print(f"\n=== Generating Area Shield Generator [{SCRIPT_REVISION}] ===\n")
    root = build_asset()
    export_asset(root)
    print("\n=== Finished ===")
    print("Godot nodes:")
    print(" - ShieldBounds: center marker for a 12m x 12m x 4m gameplay area.")
    print(" - ShieldEmitterTop: projection origin at the generator top.")
    print(" - No visual shield block is exported in this revision; create the area effect in Godot if needed.")


if __name__ == "__main__":
    main()
