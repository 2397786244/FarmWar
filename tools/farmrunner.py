# Food-War FarmRunner
# Low-hover automatic seeding / harvesting device
# Blender 4.4+ Python script
#
# ASSET CONTRACT:
# - Godot 4.x GLB-ready
# - Root origin at ground-center (0, 0, 0)
# - Z up; visual forward = local -Y
# - Max footprint: 0.96 m x 0.96 m
# - Approx. hover height: 0.12 m above ground
# - Approx. total height: 0.86 m
# - Orange + black primary palette
# - One centered black intake / exhaust / seed-work module under the body
# - Top semi-transparent seed storage compartment
# - No loose floating visible parts
# - No preview lights, collision shells, textures, or projectile-like emitters
# - All static meshes are joined before GLB export
#
# Run:
# Blender > Scripting > New > paste this script > Run Script
# or:
# blender --background --factory-startup --python farm_runner.py
#
# Output:
# farm_runner.glb is exported beside this Python file.

import bpy
import math
import os
from mathutils import Vector

# ---------------------------------------------------------------------
# SETTINGS
# ---------------------------------------------------------------------

CLEAR_SCENE = True
ROOT_NAME = "FarmRunner"
JOIN_STATIC_MESHES_FOR_EXPORT = True

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
EXPORT_GLB_PATH = os.path.join(SCRIPT_DIR, "farm_runner.glb")

# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_principled_material(name, color, metallic=0.0, roughness=0.55, alpha=1.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, alpha)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    # Blender 4.x compatible best-effort transparency setup.
    try:
        mat.surface_render_method = "DITHERED"
    except Exception:
        pass
    try:
        mat.use_transparency_overlap = False
    except Exception:
        pass

    return mat


MAT_ORANGE = make_principled_material("MAT_OrangeShell", (0.92, 0.26, 0.045), 0.18, 0.42)
MAT_BLACK = make_principled_material("MAT_BlackChassis", (0.025, 0.035, 0.042), 0.35, 0.34)
MAT_DARK_GRAY = make_principled_material("MAT_DarkGray", (0.11, 0.13, 0.14), 0.45, 0.42)
MAT_SEED = make_principled_material("MAT_SeedAmber", (0.83, 0.52, 0.09), 0.03, 0.68)
MAT_GLASS = make_principled_material("MAT_SeedCompartment", (0.30, 0.66, 0.64), 0.08, 0.16, alpha=0.42)
MAT_GREEN = make_principled_material("MAT_StatusGreen", (0.18, 0.62, 0.26), 0.05, 0.28)

# ---------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------

def get_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for previous in list(obj.users_collection):
        previous.objects.unlink(obj)
    collection.objects.link(obj)


def set_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_bevel(obj, width=0.02):
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"


def add_empty(name, parent, collection, location=(0.0, 0.0, 0.0)):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=location)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cube(name, location, dimensions, material, parent, collection,
         rotation=(0.0, 0.0, 0.0), bevel_width=0.02):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_material(obj, material)
    if bevel_width > 0:
        add_bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cylinder(name, location, radius, depth, material, parent, collection,
             vertices=12, rotation=(0.0, 0.0, 0.0), bevel_width=0.016):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    set_material(obj, material)
    if bevel_width > 0:
        add_bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cone(name, location, radius_bottom, radius_top, depth, material, parent, collection,
         vertices=12, rotation=(0.0, 0.0, 0.0), bevel_width=0.014):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    set_material(obj, material)
    if bevel_width > 0:
        add_bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def sphere(name, location, scale, material, parent, collection, segments=10, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_material(obj, material)
    # Keep faceted low-poly silhouette; no smooth shading.
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def beam_between(name, start, end, radius, material, parent, collection, vertices=8):
    start = Vector(start)
    end = Vector(end)
    vector = end - start
    length = vector.length

    if length <= 0.0001:
        return None

    midpoint = (start + end) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(vector.normalized())
    obj.rotation_mode = "XYZ"
    set_material(obj, material)
    add_bevel(obj, min(radius * 0.35, 0.016))
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


# ---------------------------------------------------------------------
# ROOT
# ---------------------------------------------------------------------

if CLEAR_SCENE:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

collection = get_collection(ROOT_NAME)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
root = bpy.context.object
root.name = ROOT_NAME
move_to_collection(root, collection)

body_root = add_empty("Body", root, collection)
storage_root = add_empty("SeedStorage", root, collection)
work_root = add_empty("CentralWorkModule", root, collection)

root["asset_role"] = "Farmer_Exclusive_AutomaticSeederHarvester"
root["forward_axis"] = "-Y"
root["ground_origin"] = "0,0,0"
root["max_footprint_m"] = "0.96 x 0.96"
root["hover_height_m"] = "0.12"
root["approx_total_height_m"] = "0.86"
root["static_meshes_merged_on_export"] = True
root["single_bottom_intake_exhaust_module"] = True

# ---------------------------------------------------------------------
# MAIN BODY
# ---------------------------------------------------------------------

# Low black hover chassis. Its bottom stays above ground at 0.12m.
cube(
    "BlackHoverChassis",
    (0.0, 0.0, 0.29),
    (0.84, 0.84, 0.24),
    MAT_BLACK,
    body_root,
    collection,
    bevel_width=0.055
)

# Orange upper shell. Visibly attached to the black chassis.
cube(
    "OrangeUpperShell",
    (0.0, 0.0, 0.45),
    (0.70, 0.70, 0.16),
    MAT_ORANGE,
    body_root,
    collection,
    bevel_width=0.050
)

# Four compact lower bumper plates; attached directly to the chassis,
# not separate hover engines. These make the silhouette read as machinery.
for index, (x, y) in enumerate([
    (-0.33, -0.33), (0.33, -0.33), (-0.33, 0.33), (0.33, 0.33)
]):
    cube(
        f"CornerBumper_{index+1}",
        (x, y, 0.22),
        (0.16, 0.16, 0.12),
        MAT_DARK_GRAY,
        body_root,
        collection,
        bevel_width=0.025
    )

# Front status strip: forward is -Y.
cube(
    "FrontStatusHousing",
    (0.0, -0.438, 0.34),
    (0.34, 0.040, 0.10),
    MAT_DARK_GRAY,
    body_root,
    collection,
    bevel_width=0.012
)
sphere(
    "FrontStatusLens",
    (0.0, -0.463, 0.34),
    (0.052, 0.020, 0.040),
    MAT_GREEN,
    body_root,
    collection,
    segments=10,
    rings=6
)

# ---------------------------------------------------------------------
# SINGLE CENTRAL BLACK INTAKE / EXHAUST / SEED-WORK MODULE
# ---------------------------------------------------------------------

# This is intentionally the ONLY underslung air / work component.
# It is mounted directly to the underside of the chassis.
cone(
    "CentralBlackAirSeedModule",
    (0.0, 0.0, 0.145),
    radius_bottom=0.245,
    radius_top=0.165,
    depth=0.22,
    material=MAT_BLACK,
    parent=work_root,
    collection=collection,
    vertices=12,
    bevel_width=0.020
)

# Opening disk visual: embedded into the bottom of the same module.
cylinder(
    "CentralIntakeExhaustOpening",
    (0.0, 0.0, 0.035),
    radius=0.175,
    depth=0.035,
    material=MAT_DARK_GRAY,
    parent=work_root,
    collection=collection,
    vertices=12,
    bevel_width=0.010
)

# Inner seed/air guide cone is recessed into the opening, not floating.
cone(
    "CentralSeedGuide",
    (0.0, 0.0, 0.015),
    radius_bottom=0.105,
    radius_top=0.045,
    depth=0.055,
    material=MAT_BLACK,
    parent=work_root,
    collection=collection,
    vertices=10,
    bevel_width=0.006
)

# Four short orange braces make the work module visibly load-bearing.
for index, (x, y) in enumerate([
    (-0.17, -0.17), (0.17, -0.17), (-0.17, 0.17), (0.17, 0.17)
]):
    beam_between(
        f"WorkModuleBrace_{index+1}",
        (x, y, 0.235),
        (x * 0.72, y * 0.72, 0.36),
        0.026,
        MAT_ORANGE,
        work_root,
        collection,
        vertices=8
    )

# ---------------------------------------------------------------------
# TOP SEED STORAGE COMPARTMENT
# ---------------------------------------------------------------------

# Black lower storage frame attached to upper shell.
cube(
    "StorageBaseFrame",
    (0.0, 0.0, 0.57),
    (0.46, 0.46, 0.08),
    MAT_BLACK,
    storage_root,
    collection,
    bevel_width=0.028
)

# Semi-transparent rounded storage bin, resting on the lower storage frame.
# It is deliberately simple and chunky, not a floating glass ornament.
cube(
    "TranslucentSeedBin",
    (0.0, 0.0, 0.70),
    (0.40, 0.40, 0.22),
    MAT_GLASS,
    storage_root,
    collection,
    bevel_width=0.055
)

# Solid black lid directly touching the transparent bin.
cube(
    "SeedBinLid",
    (0.0, 0.0, 0.835),
    (0.43, 0.43, 0.055),
    MAT_BLACK,
    storage_root,
    collection,
    bevel_width=0.025
)

# Visible seed pellets inside the chamber. Each rests on the storage base.
seed_positions = [
    (-0.095, -0.070, 0.615),
    (0.080, -0.060, 0.615),
    (-0.050, 0.080, 0.615),
    (0.095, 0.085, 0.615),
]
for index, position in enumerate(seed_positions):
    sphere(
        f"SeedPellet_{index+1}",
        position,
        (0.052, 0.052, 0.052),
        MAT_SEED,
        storage_root,
        collection,
        segments=8,
        rings=5
    )

# ---------------------------------------------------------------------
# SIDE FARM TOOL IDENTITY
# ---------------------------------------------------------------------

# Two small orange side rails; they are attached, not dangling.
for side, label in [(-1.0, "Left"), (1.0, "Right")]:
    cube(
        f"SideRail_{label}",
        (side * 0.40, 0.0, 0.43),
        (0.055, 0.44, 0.09),
        MAT_ORANGE,
        body_root,
        collection,
        bevel_width=0.020
    )

# ---------------------------------------------------------------------
# EXPORT
# ---------------------------------------------------------------------

def merge_static_meshes_for_export():
    meshes = [obj for obj in collection.objects if obj.type == "MESH"]
    if len(meshes) <= 1:
        return meshes[0] if meshes else None

    # Apply modifiers first so all beveled geometry survives joining.
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = "FarmRunner_Mesh"
    merged.parent = root
    return merged


if JOIN_STATIC_MESHES_FOR_EXPORT:
    merge_static_meshes_for_export()

bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for child in root.children_recursive:
    child.select_set(True)
bpy.context.view_layer.objects.active = root

output_dir = os.path.dirname(EXPORT_GLB_PATH)
if output_dir:
    os.makedirs(output_dir, exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=EXPORT_GLB_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT"
)

print(f"[FarmRunner] GLB exported: {EXPORT_GLB_PATH}")
print("[FarmRunner] Generated: orange/black low-hover seeding device with one central black intake/exhaust work module.")
