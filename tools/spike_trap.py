# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Boar Spike Trap (Green)
#
# Generates:
#   generated_farmtown_traps/
#     FTF_Trap_BoarSpike_Green_v1.glb
#
# DESIGN
# - Ground-hugging square spike trap with a 4 m x 4 m footprint.
# - Green metallic outer frame and many vertical upward spikes.
# - Visual language inspired by a brutal boar trap / caltrop field, but built
#   as a clean low-poly gameplay asset suitable for Godot.
# - Static deployable trap; no moving parts.
#
# EXPORTED HIERARCHY
#   FTF_Trap_BoarSpike_Green_v1
#   |-- FTF_Trap_BoarSpike_Green_v1_Static
#   `-- TrapBounds
#
# NOTES
# - Root origin is centered on the trap footprint at ground level.
# - TrapBounds marks the center of the 4m x 4m gameplay area.
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
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_traps")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Trap_BoarSpike_Green_v1.glb")

ROOT_NAME = "FTF_Trap_BoarSpike_Green_v1"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV1_4X4_GREEN_METAL_SPIKES"

CLEAR_SCENE = True
AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

TRAP_SIZE = Vector((4.0, 4.0, 1.45))
TRAP_BOUNDS_CENTER = Vector((0.0, 0.0, 0.70))


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
        "green": make_material("MAT_BST_Green", (0.24, 0.42, 0.22), metallic=0.62, roughness=0.38),
        "green_dark": make_material("MAT_BST_GreenDark", (0.14, 0.24, 0.14), metallic=0.56, roughness=0.44),
        "green_light": make_material("MAT_BST_GreenLight", (0.36, 0.56, 0.30), metallic=0.48, roughness=0.34),
        "steel": make_material("MAT_BST_Steel", (0.55, 0.58, 0.60), metallic=0.74, roughness=0.28),
        "dark": make_material("MAT_BST_Dark", (0.08, 0.09, 0.10), metallic=0.28, roughness=0.72),
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
        add_bevel(obj, bevel)
    move_to_collection(obj, collection)
    return obj



def add_cube(name, location, dimensions, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel, smooth)



def add_cylinder(name, location, radius, depth, material, collection, rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, material, collection, bevel, smooth)



def add_pyramid_spike(name, location, base_size, height, material, collection):
    bpy.ops.mesh.primitive_cone_add(
        vertices=4,
        radius1=base_size * 0.5,
        radius2=0.0,
        depth=height,
        location=(location[0], location[1], location[2] + height * 0.5),
        rotation=(0.0, 0.0, math.radians(45.0)),
    )
    obj = bpy.context.object
    return finish_mesh(obj, name, material, collection, bevel=0.004, smooth=False)



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



def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.20):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    collection.objects.link(obj)
    return obj


# -----------------------------------------------------------------------------
# Build trap
# -----------------------------------------------------------------------------


def build_static_trap(materials, collection, root):
    parts = []

    # Low ground frame.
    parts += [
        add_cube("Base_FloorPlate", (0.0, 0.0, 0.05), (3.84, 3.84, 0.10), materials["green_dark"], collection, bevel=0.018),
        add_cube("Base_FrameX", (0.0, 0.0, 0.14), (4.00, 0.28, 0.18), materials["green"], collection, bevel=0.020),
        add_cube("Base_FrameY", (0.0, 0.0, 0.14), (0.28, 4.00, 0.18), materials["green"], collection, bevel=0.020),
        add_cube("Base_CenterPlate", (0.0, 0.0, 0.13), (3.40, 3.40, 0.12), materials["green_light"], collection, bevel=0.014),
    ]

    # Corner caps keep the silhouette heavier and more boar-trap-like.
    corner_positions = [
        (-1.78, -1.78, 0.17),
        (1.78, -1.78, 0.17),
        (1.78, 1.78, 0.17),
        (-1.78, 1.78, 0.17),
    ]
    for i, pos in enumerate(corner_positions):
        parts.append(add_cube(f"CornerCap_{i:02d}", pos, (0.36, 0.36, 0.22), materials["dark"], collection, bevel=0.012))

    # Structural ribs.
    rib_positions = [-1.05, 0.0, 1.05]
    for idx, x in enumerate(rib_positions):
        parts.append(add_cube(f"Rib_X_{idx:02d}", (x, 0.0, 0.18), (0.10, 3.54, 0.10), materials["green_dark"], collection, bevel=0.008))
    for idx, y in enumerate(rib_positions):
        parts.append(add_cube(f"Rib_Y_{idx:02d}", (0.0, y, 0.18), (3.54, 0.10, 0.10), materials["green_dark"], collection, bevel=0.008))

    # Dense spike field, vertical upward spikes.
    spike_coords = [-1.35, -0.75, -0.15, 0.45, 1.05, 1.55]
    spike_id = 0
    for x in spike_coords:
        for y in spike_coords:
            # Slight height variation keeps it more organic / brutal.
            height = 0.82
            if (abs(x) < 0.2 and abs(y) < 0.2):
                height = 1.05
            elif (abs(x) > 1.3 or abs(y) > 1.3):
                height = 0.95
            elif ((int((x + 2.0) * 10) + int((y + 2.0) * 10)) % 2) == 0:
                height = 0.88
            parts.append(add_pyramid_spike(
                f"Spike_{spike_id:02d}",
                (x, y, 0.20),
                0.26,
                height,
                materials["steel"],
                collection,
            ))
            spike_id += 1

    # Larger central beast-catching spikes for the boar-trap feel.
    heroic_spikes = [
        (-0.55, -0.55), (0.55, -0.55), (-0.55, 0.55), (0.55, 0.55),
        (0.0, -0.95), (0.0, 0.95), (-0.95, 0.0), (0.95, 0.0),
    ]
    for idx, (x, y) in enumerate(heroic_spikes):
        parts.append(add_pyramid_spike(f"HeroSpike_{idx:02d}", (x, y, 0.20), 0.34, 1.18, materials["steel"], collection))

    # Short side teeth on the outer rim.
    tooth_positions = [-1.20, -0.40, 0.40, 1.20]
    for idx, x in enumerate(tooth_positions):
        parts.append(add_pyramid_spike(f"SideTooth_N_{idx:02d}", (x, -1.82, 0.18), 0.18, 0.42, materials["steel"], collection))
        parts.append(add_pyramid_spike(f"SideTooth_S_{idx:02d}", (x, 1.82, 0.18), 0.18, 0.42, materials["steel"], collection))
    for idx, y in enumerate(tooth_positions):
        parts.append(add_pyramid_spike(f"SideTooth_W_{idx:02d}", (-1.82, y, 0.18), 0.18, 0.42, materials["steel"], collection))
        parts.append(add_pyramid_spike(f"SideTooth_E_{idx:02d}", (1.82, y, 0.18), 0.18, 0.42, materials["steel"], collection))

    for part in parts:
        part.parent = root
    return parts


# -----------------------------------------------------------------------------
# Root / validation / export
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.32)
    root["asset_type"] = "Trap"
    root["trap_category"] = "BoarSpikeTrap"
    root["role_style"] = "GroundHazard"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["footprint_m"] = (4.0, 4.0)
    root["revision"] = SCRIPT_REVISION
    return root



def create_runtime_markers(root, collection):
    trap_bounds = create_empty(
        "TrapBounds",
        TRAP_BOUNDS_CENTER,
        collection,
        parent=root,
        display_type="CUBE",
        size=0.24,
    )
    trap_bounds["interaction_role"] = "TrapAreaCenter"
    trap_bounds["recommended_box_extents_m"] = (2.0, 2.0, 0.75)
    return trap_bounds



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



def validate_asset(root):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Trap root must remain an Empty at world origin.")

    required_children = {STATIC_NAME, "TrapBounds"}
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
    low, high = world_bbox(meshes)
    dims = high - low

    if abs(dims.x - 4.0) > 0.20 or abs(dims.y - 4.0) > 0.20:
        raise RuntimeError(f"Trap footprint drifted from 4m x 4m. Got {dims.x:.3f} m x {dims.y:.3f} m")

    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Footprint: {dims.x:.2f} m x {dims.y:.2f} m\n"
        f"  Height: {dims.z:.2f} m\n"
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

    parts = build_static_trap(materials, collection, root)
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
    print(f"\n=== Generating Boar Spike Trap [{SCRIPT_REVISION}] ===\n")
    root = build_asset()
    export_asset(root)
    print("\n=== Finished ===")
    print("Godot nodes:")
    print(" - TrapBounds: center marker for the 4m x 4m gameplay hazard area.")
    print(" - Static mesh contains the full green metallic spike trap body.")


if __name__ == "__main__":
    main()
