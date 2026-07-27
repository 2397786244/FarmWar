# Food-War PlantProtector
# Mechanical Scarecrow Plant Protector
# Blender 4.x Python script
#
# FOOD-WAR ASSET CONTRACT APPLIED:
# - Godot 4.x / GLB-ready low-poly prop
# - Root origin at ground-center (0, 0, 0)
# - Native Blender: Z up, visual forward = local -Y
# - Actual maximum footprint: approximately 1.90 m x 1.90 m (below 2 m x 2 m)
# - Approx. height: 2.52 m
# - Single root Empty: PlantProtector
# - No collision shell, no preview lights, no textures
# - No floating visible parts: every visible mesh physically touches or
#   lightly interpenetrates a supporting visible mesh
# - Stylized low-poly / chunky silhouette / restrained large color blocks
# - No realistic military detailing, tiny screws, pipes, engraving, or
#   strong emission materials
#
# USE:
# Blender > Scripting > New > paste > Run Script.
# Set EXPORT_GLB_PATH to an absolute path to export a GLB automatically.

import bpy
import math
import os
from mathutils import Vector

# ---------------------------------------------------------------------
# USER SETTINGS
# ---------------------------------------------------------------------

CLEAR_SCENE = True
ROOT_NAME = "PlantProtector"

# Background execution needs an explicit output path. By default this creates
# "plant_protector.glb" in the same folder as this Python script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
EXPORT_GLB_PATH = os.path.join(SCRIPT_DIR, "plant_protector.glb")

# Keep False while iterating on the model. Once the visual design is approved,
# set True to collapse all static mesh parts into one Godot-friendly mesh node.
# This reduces imported MeshInstance3D count, but makes later per-part editing
# less convenient.
JOIN_STATIC_MESHES_FOR_EXPORT = True

# ---------------------------------------------------------------------
# MATERIALS: six restrained, readable large color blocks
# ---------------------------------------------------------------------

def make_material(name, base_color, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return mat


MAT_WOOD = make_material("MAT_WoodBrown", (0.30, 0.13, 0.055), 0.0, 0.82)
MAT_STRAW = make_material("MAT_HarvestStraw", (0.78, 0.48, 0.13), 0.0, 0.90)
MAT_FARM_GREEN = make_material("MAT_FarmGreen", (0.13, 0.36, 0.16), 0.16, 0.52)
MAT_WARM_METAL = make_material("MAT_WarmMetal", (0.63, 0.34, 0.07), 0.52, 0.40)
MAT_SOFT_STEEL = make_material("MAT_SoftSteel", (0.22, 0.28, 0.29), 0.44, 0.44)
MAT_LENS = make_material("MAT_ProtectionLens", (0.18, 0.58, 0.32), 0.18, 0.28)

# ---------------------------------------------------------------------
# SMALL HELPERS
# ---------------------------------------------------------------------

def get_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def set_mat(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def bevel(obj, width=0.025):
    """One rounded low-poly bevel only; no high-poly smoothing."""
    mod = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    mod.width = width
    mod.segments = 1
    mod.limit_method = "ANGLE"


def cube(name, loc, size, mat, parent, collection, rot=(0.0, 0.0, 0.0), bevel_width=0.025):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_mat(obj, mat)
    if bevel_width > 0:
        bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cylinder(name, loc, radius, depth, mat, parent, collection,
             vertices=12, rot=(0.0, 0.0, 0.0), bevel_width=0.018):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=loc,
        rotation=rot
    )
    obj = bpy.context.object
    obj.name = name
    set_mat(obj, mat)
    if bevel_width > 0:
        bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cone(name, loc, radius_bottom, radius_top, depth, mat, parent, collection,
         vertices=12, rot=(0.0, 0.0, 0.0), bevel_width=0.014):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=loc,
        rotation=rot
    )
    obj = bpy.context.object
    obj.name = name
    set_mat(obj, mat)
    if bevel_width > 0:
        bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def sphere(name, loc, scale, mat, parent, collection, segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=loc
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_mat(obj, mat)
    # Deliberately keep low-poly faceting, no smooth-shading.
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def beam_between(name, start, end, radius, mat, parent, collection, vertices=8):
    """Visible support beam. Local Z spans start -> end."""
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
    set_mat(obj, mat)
    bevel(obj, min(radius * 0.35, 0.018))
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_empty(name, parent, collection, loc=(0.0, 0.0, 0.0)):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def straw_bundle(name, origin, direction, count, length, radius, parent, collection):
    """
    Attached straw silhouette. Every strand starts slightly inside its
    supporting arm / collar, so there are no visually floating straw pieces.
    """
    start_base = Vector(origin)
    forward = Vector(direction).normalized()
    tangent = forward.cross(Vector((0.0, 0.0, 1.0)))
    if tangent.length < 0.001:
        tangent = Vector((1.0, 0.0, 0.0))
    tangent.normalize()
    bitangent = forward.cross(tangent).normalized()

    for i in range(count):
        angle = i * (math.pi * 2.0 / count)
        radial = tangent * math.cos(angle) * 0.055 + bitangent * math.sin(angle) * 0.055
        start = start_base + radial - forward * 0.025
        end = start + forward * length + Vector((0.0, 0.0, 0.018 * ((i % 3) - 1)))
        beam_between(
            f"{name}_{i+1:02d}",
            start,
            end,
            radius,
            MAT_STRAW,
            parent,
            collection,
            vertices=6
        )


# ---------------------------------------------------------------------
# CREATE ROOT AND GROUPS
# ---------------------------------------------------------------------

if CLEAR_SCENE:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

collection = get_collection(ROOT_NAME)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
root = bpy.context.object
root.name = ROOT_NAME
move_to_collection(root, collection)

base_root = add_empty("Base", root, collection)
body_root = add_empty("ScarecrowBody", root, collection)

# Metadata for Godot / production tracking.
root["asset_role"] = "Farmer_Exclusive_PlantProtection_NoProjectileWeapon"
root["forward_axis"] = "-Y"
root["ground_origin"] = "0,0,0"
root["base_footprint_m"] = "1.00 x 1.00"
root["max_silhouette_width_m"] = "approximately 1.90 (arm span)"
root["approx_height_m"] = "2.52"
root["no_floating_visible_parts"] = True
root["no_collision_shell_generated"] = True

# ---------------------------------------------------------------------
# BASE: compact 1.0m x 1.0m footprint
# ---------------------------------------------------------------------

# Metal plinth. Ground origin is its bottom center.
# The outer wooden rim reaches exactly 1.0m x 1.0m.
cube(
    "Base_Platform",
    (0.0, 0.0, 0.10),
    (0.86, 0.86, 0.20),
    MAT_SOFT_STEEL,
    base_root,
    collection,
    bevel_width=0.045
)

# Compact farm-style wooden planter rim, physically touching the platform.
for name, loc, size in [
    ("PlanterRim_Front", (0.0, -0.45, 0.24), (1.00, 0.10, 0.12)),
    ("PlanterRim_Back",  (0.0,  0.45, 0.24), (1.00, 0.10, 0.12)),
    ("PlanterRim_Left",  (-0.45, 0.0, 0.24), (0.10, 0.80, 0.12)),
    ("PlanterRim_Right", (0.45, 0.0, 0.24), (0.10, 0.80, 0.12)),
]:
    cube(name, loc, size, MAT_WOOD, base_root, collection, bevel_width=0.020)

# Four compact stabilizer feet. Their outer edge remains inside the 1.0m base.
for index, (x, y) in enumerate([
    (-0.37, -0.37), (0.37, -0.37), (-0.37, 0.37), (0.37, 0.37)
]):
    cylinder(
        f"StabilizerFoot_{index+1}",
        (x, y, 0.065),
        0.09,
        0.13,
        MAT_WARM_METAL,
        base_root,
        collection,
        vertices=10
    )

# ---------------------------------------------------------------------
# CENTRAL SCARECROW BODY
# ---------------------------------------------------------------------

# The main wooden pole visibly penetrates into the base.
cylinder(
    "Scarecrow_Post",
    (0.0, 0.0, 0.92),
    0.14,
    1.64,
    MAT_WOOD,
    body_root,
    collection,
    vertices=10,
    bevel_width=0.022
)

# Chunky mechanical chest is attached to the central pole.
cube(
    "ProtectionCore_Housing",
    (0.0, -0.02, 1.27),
    (0.47, 0.34, 0.42),
    MAT_FARM_GREEN,
    body_root,
    collection,
    bevel_width=0.055
)

# Large readable front lens. It lightly interpenetrates the chest face.
cylinder(
    "ProtectionCore_Lens",
    (0.0, -0.205, 1.27),
    0.105,
    0.055,
    MAT_LENS,
    body_root,
    collection,
    vertices=12,
    rot=(math.pi * 0.5, 0.0, 0.0),
    bevel_width=0.010
)

# Simple top cap, visibly connected to chest and pole.
cone(
    "ProtectionCore_TopCap",
    (0.0, 0.0, 1.53),
    0.30,
    0.16,
    0.18,
    MAT_WARM_METAL,
    body_root,
    collection,
    vertices=10
)

# Horizontal scarecrow beam, connected through the post.
cube(
    "Scarecrow_ArmBeam",
    (0.0, 0.0, 1.64),
    (1.56, 0.14, 0.14),
    MAT_WOOD,
    body_root,
    collection,
    bevel_width=0.035
)

# Mechanical arm-end bands and attached straw hands.
for side, label in [(-1.0, "Left"), (1.0, "Right")]:
    x = side * 0.66
    cylinder(
        f"ArmBand_{label}",
        (x, 0.0, 1.64),
        0.125,
        0.19,
        MAT_WARM_METAL,
        body_root,
        collection,
        vertices=10,
        rot=(0.0, math.pi * 0.5, 0.0)
    )

    # Each straw bundle begins inside the arm endpoint.
    straw_bundle(
        f"StrawHand_{label}",
        (side * 0.76, 0.0, 1.64),
        (side, 0.0, -0.10),
        count=7,
        length=0.20,
        radius=0.015,
        parent=body_root,
        collection=collection
    )

# Shoulder straw collars connect into the beam and chest.
straw_bundle(
    "StrawCollar_Left",
    (-0.34, 0.0, 1.64),
    (-0.38, 0.0, 0.18),
    count=8,
    length=0.16,
    radius=0.014,
    parent=body_root,
    collection=collection
)
straw_bundle(
    "StrawCollar_Right",
    (0.34, 0.0, 1.64),
    (0.38, 0.0, 0.18),
    count=8,
    length=0.16,
    radius=0.014,
    parent=body_root,
    collection=collection
)

# ---------------------------------------------------------------------
# HEAD + HAT: all visible pieces physically overlap the post / neck
# ---------------------------------------------------------------------

cylinder(
    "Scarecrow_Neck",
    (0.0, 0.0, 1.82),
    0.11,
    0.26,
    MAT_SOFT_STEEL,
    body_root,
    collection,
    vertices=10
)

sphere(
    "Scarecrow_Head",
    (0.0, 0.0, 2.00),
    (0.27, 0.25, 0.28),
    MAT_STRAW,
    body_root,
    collection,
    segments=12,
    rings=8
)

# Face plate is embedded in front (-Y) of the straw head.
cube(
    "FacePlate",
    (0.0, -0.235, 2.00),
    (0.34, 0.050, 0.20),
    MAT_WARM_METAL,
    body_root,
    collection,
    bevel_width=0.025
)

# Two low-poly lenses embedded into face plate, not floating.
for side, label in [(-1.0, "Left"), (1.0, "Right")]:
    sphere(
        f"FaceLens_{label}",
        (side * 0.085, -0.273, 2.045),
        (0.046, 0.022, 0.046),
        MAT_LENS,
        body_root,
        collection,
        segments=10,
        rings=6
    )

# Hat brim intersects the head top.
cylinder(
    "Hat_Brim",
    (0.0, 0.0, 2.23),
    0.36,
    0.065,
    MAT_STRAW,
    body_root,
    collection,
    vertices=12,
    bevel_width=0.010
)

# Hat crown intersects the brim.
cone(
    "Hat_Crown",
    (0.0, 0.0, 2.36),
    0.22,
    0.14,
    0.25,
    MAT_STRAW,
    body_root,
    collection,
    vertices=10,
    bevel_width=0.010
)

# A single visible lightning rod: mechanically fixed into the hat crown.
beam_between(
    "LightningRod",
    (0.0, 0.0, 2.46),
    (0.0, 0.0, 2.56),
    0.025,
    MAT_WARM_METAL,
    body_root,
    collection,
    vertices=8
)

# ---------------------------------------------------------------------
# PLANT-PROTECTION IDENTITY
# ---------------------------------------------------------------------

# This device does NOT fire projectiles or anti-air shells.
# Its protection role is conveyed by:
# - the grounded mechanical scarecrow silhouette,
# - the top lightning rod,
# - the front green protection core,
# - the reinforced farm planter base.
# Gameplay effects such as crop protection are represented in Godot through
# range effects / particles, not by visible projectile emitters.

# ---------------------------------------------------------------------
# SMALL, READABLE FARM DETAILS: intentionally minimal and attached
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# EXPORT
# ---------------------------------------------------------------------

def merge_static_meshes_for_export():
    """
    Optional performance step. All model pieces are static, so they can be
    combined after visual review. Materials remain as material slots.
    """
    meshes = [obj for obj in collection.objects if obj.type == "MESH"]
    if len(meshes) <= 1:
        return meshes[0] if meshes else None

    # Apply bevel modifiers first. Joining without this step would retain only
    # the active object's modifier stack.
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)

    active = meshes[0]
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = "PlantProtector_Mesh"
    merged.parent = root
    return merged


if JOIN_STATIC_MESHES_FOR_EXPORT:
    merge_static_meshes_for_export()

# Apply consistent selection for the GLB export.
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for child in root.children_recursive:
    child.select_set(True)
bpy.context.view_layer.objects.active = root

if EXPORT_GLB_PATH:
    folder = os.path.dirname(EXPORT_GLB_PATH)
    if folder:
        os.makedirs(folder, exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=EXPORT_GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT"
    )
    print(f"[PlantProtector] GLB exported: {EXPORT_GLB_PATH}")
else:
    print("[PlantProtector] No GLB export path was configured.")

print("[PlantProtector] Generated.")
print("Contract: stylized low-poly, ground-centered root, forward -Y, no floating parts.")
print("Approx. footprint: 1.90m x 1.90m | Approx. height: 2.56m")
