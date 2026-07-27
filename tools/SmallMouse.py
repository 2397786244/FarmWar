# Food-War SmallMouse
# Compact robotic mouse / Engineer exclusive tool - Blender 4.4+ generator
#
# OUTPUT:
#   small_mouse.glb  (saved beside this script)
#
# ASSET CONTRACT
# - Godot-ready GLB, stylized low-poly game asset.
# - Root origin: ground center (0, 0, 0).
# - Blender visual front: local -Y.
# - Intended Godot forward after glTF import: +Z.
# - Compact size:
#       body footprint about 0.30m wide x 0.55m long,
#       total height about 0.50m including vertical tail antenna.
# - Dark black / charcoal body. Two red emissive front camera apertures; black micro-laser aperture.
# - Blue camera and micro-laser are visual parts of the merged static mesh.
# - All visible geometry is mechanically attached. No decorative floating meshes.
# - All static meshes are merged to one mesh before GLB export.
#
# OUTPUT NODE HIERARCHY
# SmallMouse
# └── SmallMouse_StaticMesh
#
# This model has no separate wheel nodes: it is a small four-paw crawler.

import bpy
import os
from math import radians


# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------

CLEAR_SCENE = True
JOIN_STATIC_MESHES_FOR_EXPORT = True

ROOT_NAME = "SmallMouse"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
EXPORT_PATH = os.path.join(SCRIPT_DIR, "small_mouse_v5_binocular_red_eyes.glb")


# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_material(
    name,
    color,
    metallic=0.0,
    roughness=0.5,
    emission_color=None,
    emission_strength=0.0,
):
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)

    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    bsdf.inputs["Base Color"].default_value = (
        color[0],
        color[1],
        color[2],
        1.0,
    )
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if emission_color is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (
                emission_color[0],
                emission_color[1],
                emission_color[2],
                1.0,
            )
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (
                emission_color[0],
                emission_color[1],
                emission_color[2],
                1.0,
            )

        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


MAT_BLACK = make_material(
    "MAT_SmallMouse_Black",
    (0.012, 0.015, 0.020),
    metallic=0.34,
    roughness=0.34,
)

MAT_CHARCOAL = make_material(
    "MAT_SmallMouse_Charcoal",
    (0.055, 0.065, 0.078),
    metallic=0.46,
    roughness=0.40,
)

MAT_RUBBER = make_material(
    "MAT_SmallMouse_Rubber",
    (0.004, 0.006, 0.008),
    metallic=0.01,
    roughness=0.74,
)

MAT_RED_CAMERA = make_material(
    "MAT_SmallMouse_CameraRed",
    (0.52, 0.006, 0.008),
    metallic=0.10,
    roughness=0.20,
    emission_color=(1.0, 0.0, 0.0),
    emission_strength=4.2,
)


# ---------------------------------------------------------------------
# BLENDER HELPERS
# ---------------------------------------------------------------------

def get_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def add_empty(name, parent, collection, location=(0.0, 0.0, 0.0)):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    return obj


def set_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_bevel(obj, width=0.01):
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"


def cube_local(
    name,
    parent,
    collection,
    location,
    dimensions,
    material,
    rotation=(0.0, 0.0, 0.0),
    bevel=0.01,
):
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = rotation
    obj.dimensions = dimensions

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)

    set_material(obj, material)
    add_bevel(obj, bevel)
    return obj


def cylinder_local(
    name,
    parent,
    collection,
    location,
    radius,
    depth,
    material,
    rotation=(0.0, 0.0, 0.0),
    vertices=12,
    bevel=0.006,
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = rotation
    set_material(obj, material)
    add_bevel(obj, bevel)
    return obj


def low_poly_ellipsoid_local(
    name,
    parent,
    collection,
    location,
    dimensions,
    material,
    segments=12,
    rings=6,
):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    obj.dimensions = dimensions

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)

    set_material(obj, material)
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def descendant_meshes(parent):
    return [obj for obj in parent.children_recursive if obj.type == "MESH"]


def join_meshes(meshes, target_name, parent):
    valid_meshes = [obj for obj in meshes if obj is not None and obj.type == "MESH"]
    if not valid_meshes:
        return None

    for obj in valid_meshes:
        apply_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in valid_meshes:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = valid_meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = target_name
    merged.parent = parent
    return merged


# ---------------------------------------------------------------------
# ROOT / COLLECTION
# ---------------------------------------------------------------------

if CLEAR_SCENE:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

collection = get_collection(ROOT_NAME)

root = add_empty(ROOT_NAME, None, collection)
root["asset_role"] = "FoodWar_Engineer_SmallMouse"
root["root_origin"] = "ground_center_0_0_0"
root["blender_visual_front"] = "-Y"
root["godot_intended_forward"] = "+Z"
root["max_body_footprint_m"] = "0.30 x 0.55"
root["total_height_including_tail_m"] = "about 0.50"
root["static_meshes_merged"] = True
root["no_floating_decorative_meshes"] = True

static_root = add_empty("StaticBody", root, collection)

# ---------------------------------------------------------------------
# MOUSE BODY
# Front is -Y. Body parts intentionally overlap / connect, eliminating
# visually floating panels.
# ---------------------------------------------------------------------

# Low belly plate. Bottom reaches ground-near level; all paws connect to it.
cube_local(
    "BellyFrame",
    static_root,
    collection,
    location=(0.0, 0.025, 0.065),
    dimensions=(0.225, 0.390, 0.070),
    material=MAT_BLACK,
    bevel=0.022,
)

# Main low rounded body: stylized robotic mouse shell.
low_poly_ellipsoid_local(
    "MouseBodyShell",
    static_root,
    collection,
    location=(0.0, 0.040, 0.152),
    dimensions=(0.270, 0.455, 0.205),
    material=MAT_CHARCOAL,
    segments=12,
    rings=6,
)

# Head overlaps the body and creates an unmistakably mouse-like front.
low_poly_ellipsoid_local(
    "MouseHeadShell",
    static_root,
    collection,
    location=(0.0, -0.188, 0.137),
    dimensions=(0.245, 0.205, 0.165),
    material=MAT_BLACK,
    segments=12,
    rings=6,
)

# Armored top plate is embedded over the shell and mechanically readable.
cube_local(
    "TopArmorPlate",
    static_root,
    collection,
    location=(0.0, 0.015, 0.263),
    dimensions=(0.165, 0.245, 0.040),
    material=MAT_BLACK,
    bevel=0.014,
)

# Larger attached mouse ears.
# Their inner halves deliberately overlap the head/body shell by about 2cm,
# eliminating the earlier floating gap.
for side_name, x in [("Left", -0.103), ("Right", 0.103)]:
    cylinder_local(
        f"MouseEar_{side_name}",
        static_root,
        collection,
        location=(x, -0.078, 0.202),
        radius=0.056,
        depth=0.042,
        material=MAT_CHARCOAL,
        rotation=(0.0, radians(90.0), 0.0),
        vertices=12,
        bevel=0.006,
    )

# Four compact crawler paws: each intersects the belly frame and rests close
# to ground, giving the mouse a small four-foot robot silhouette.
for paw_name, x, y in [
    ("FrontLeft", -0.095, -0.135),
    ("FrontRight", 0.095, -0.135),
    ("RearLeft", -0.095, 0.145),
    ("RearRight", 0.095, 0.145),
]:
    cube_local(
        f"Paw_{paw_name}",
        static_root,
        collection,
        location=(x, y, 0.030),
        dimensions=(0.072, 0.102, 0.060),
        material=MAT_RUBBER,
        bevel=0.018,
    )

# Small side rails connect visual paw positions with the body frame.
for side_name, x in [("Left", -0.115), ("Right", 0.115)]:
    cube_local(
        f"SideBodyRail_{side_name}",
        static_root,
        collection,
        location=(x, 0.020, 0.104),
        dimensions=(0.020, 0.355, 0.042),
        material=MAT_BLACK,
        bevel=0.007,
    )

# ---------------------------------------------------------------------
# FRONT CAMERA + MICRO LASER
# Both are inset into attached front housings.
# ---------------------------------------------------------------------

cube_local(
    "BinocularCameraHousing",
    static_root,
    collection,
    location=(0.0, -0.286, 0.157),
    dimensions=(0.158, 0.072, 0.078),
    material=MAT_BLACK,
    bevel=0.016,
)

# Twin red camera bezels and lenses. Together they form a small binocular
# camera, making the robot read more clearly as a mouse with two red eyes.
# Both camera modules are recessed into the same connected front housing.
for side_name, x in [("Left", -0.040), ("Right", 0.040)]:
    cylinder_local(
        f"CameraBezel_{side_name}",
        static_root,
        collection,
        location=(x, -0.327, 0.157),
        radius=0.026,
        depth=0.018,
        material=MAT_CHARCOAL,
        rotation=(radians(90.0), 0.0, 0.0),
        vertices=12,
        bevel=0.003,
    )

    cylinder_local(
        f"RedCameraEye_{side_name}",
        static_root,
        collection,
        location=(x, -0.340, 0.157),
        radius=0.016,
        depth=0.012,
        material=MAT_RED_CAMERA,
        rotation=(radians(90.0), 0.0, 0.0),
        vertices=12,
        bevel=0.002,
    )

# Compact laser housing sits under the camera and overlaps the head shell.
cube_local(
    "LaserHousing",
    static_root,
    collection,
    location=(0.0, -0.286, 0.092),
    dimensions=(0.072, 0.068, 0.050),
    material=MAT_BLACK,
    bevel=0.012,
)

cylinder_local(
    "LaserEmitterBezel",
    static_root,
    collection,
    location=(0.0, -0.327, 0.092),
    radius=0.019,
    depth=0.017,
    material=MAT_CHARCOAL,
    rotation=(radians(90.0), 0.0, 0.0),
    vertices=10,
    bevel=0.002,
)

cylinder_local(
    "LaserEmitterAperture",
    static_root,
    collection,
    location=(0.0, -0.339, 0.092),
    radius=0.010,
    depth=0.010,
    material=MAT_BLACK,
    rotation=(radians(90.0), 0.0, 0.0),
    vertices=10,
    bevel=0.001,
)

# ---------------------------------------------------------------------
# VERTICAL TAIL / ANTENNA
# Tail is intentionally vertical as requested. The bottom is embedded into
# the rear body shell, then the mast and tip are directly stacked.
# ---------------------------------------------------------------------

cylinder_local(
    "TailAntennaBase",
    static_root,
    collection,
    location=(0.0, 0.228, 0.245),
    radius=0.035,
    depth=0.060,
    material=MAT_BLACK,
    vertices=10,
    bevel=0.005,
)

cylinder_local(
    "TailAntennaMast",
    static_root,
    collection,
    location=(0.0, 0.228, 0.365),
    radius=0.012,
    depth=0.220,
    material=MAT_BLACK,
    vertices=8,
    bevel=0.003,
)

cylinder_local(
    "TailAntennaTip",
    static_root,
    collection,
    location=(0.0, 0.228, 0.485),
    radius=0.020,
    depth=0.030,
    material=MAT_CHARCOAL,
    vertices=8,
    bevel=0.004,
)

# Rear antenna brace: a visible short mounting block joining tail base
# to the body rather than a free-standing rod.
cube_local(
    "TailMountBrace",
    static_root,
    collection,
    location=(0.0, 0.202, 0.215),
    dimensions=(0.090, 0.090, 0.065),
    material=MAT_CHARCOAL,
    bevel=0.012,
)

# ---------------------------------------------------------------------
# LOW-POLY STRUCTURAL DETAILS
# Small embedded fasteners keep the asset readable without adding textures.
# ---------------------------------------------------------------------

for index, x in enumerate([-0.065, 0.065]):
    cylinder_local(
        f"TopFastener_{index+1}",
        static_root,
        collection,
        location=(x, 0.015, 0.287),
        radius=0.010,
        depth=0.009,
        material=MAT_CHARCOAL,
        vertices=8,
        bevel=0.001,
    )

# ---------------------------------------------------------------------
# MERGE STATIC MESHES
# All visible static geometry becomes one efficient mesh with preserved
# material slots for the twin red camera apertures and black laser aperture.
# ---------------------------------------------------------------------

if JOIN_STATIC_MESHES_FOR_EXPORT:
    join_meshes(
        descendant_meshes(static_root),
        "SmallMouse_StaticMesh",
        static_root,
    )

# ---------------------------------------------------------------------
# EXPORT GLB
# ---------------------------------------------------------------------

bpy.context.view_layer.update()

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for child in root.children_recursive:
    child.select_set(True)
bpy.context.view_layer.objects.active = root

output_dir = os.path.dirname(EXPORT_PATH)
if output_dir:
    os.makedirs(output_dir, exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=EXPORT_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT",
)

print(f"[SmallMouse] Exported GLB: {EXPORT_PATH}")
print("[SmallMouse] All visible geometry, including attached ears, twin red camera eyes and black laser aperture, merged into one static mesh.")
