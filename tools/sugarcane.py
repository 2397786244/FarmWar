# Blender 4.x / 5.x - standalone FarmWar asset generator
# This script creates a visual-only GLB and a 1100x700 PNG preview.
# It clears the scene, generates the asset, validates it, exports it, then
# clears the scene again and re-imports the GLB for final validation.

import bpy
import bmesh
import math
import os
from mathutils import Vector

ASSET_NAME = "FTF_Plant_SugarCane_Purple_4m"
OUTPUT_FOLDER_NAME = "generated_farmwar_assets"
PREVIEW_SIZE = (1100, 700)

try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = bpy.path.abspath("//") if bpy.data.filepath else os.getcwd()

OUTPUT_DIR = os.path.join(SCRIPT_DIR, OUTPUT_FOLDER_NAME)
GLB_PATH = os.path.join(OUTPUT_DIR, ASSET_NAME + ".glb")
PREVIEW_PATH = os.path.join(OUTPUT_DIR, ASSET_NAME + "_preview.png")


def rgba(hex_color):
    """Convert #RRGGBB to Blender RGBA floats."""
    hex_color = hex_color.lstrip("#")
    return (
        int(hex_color[0:2], 16) / 255.0,
        int(hex_color[2:4], 16) / 255.0,
        int(hex_color[4:6], 16) / 255.0,
        1.0,
    )


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def setup_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.unit_settings.scale_length = 1.0
    scene.render.resolution_x = PREVIEW_SIZE[0]
    scene.render.resolution_y = PREVIEW_SIZE[1]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.035, 0.040, 0.050)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        pass


def make_material(name, color_hex, roughness=0.72, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = rgba(color_hex)
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba(color_hex)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return material


def create_root():
    root = bpy.data.objects.new(ASSET_NAME, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    return root


def parent_to_root(obj, root, material=None):
    obj.parent = root
    if material is not None:
        obj.data.materials.append(material)
    return obj


def add_bevel(obj, width=0.02):
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    return obj


def add_cube(root, name, location, dimensions, material, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    parent_to_root(obj, root, material)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    return obj


def add_cylinder(root, name, location, radius, depth, material, vertices=8, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    parent_to_root(obj, root, material)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    return obj


def add_ico(root, name, location, scale, material, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    parent_to_root(obj, root, material)
    return obj


def add_cylinder_between(root, name, start, end, radius, material, vertices=8, bevel=0.0):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    length = direction.length
    if length <= 0.0001:
        raise ValueError("Cylinder endpoints must be different for " + name)

    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        end_fill_type="NGON",
        location=midpoint,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.rotation_mode = "XYZ"
    parent_to_root(obj, root, material)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    return obj


def add_tapered_leaf(root, name, base, direction_xy, length, max_width, arch_height, tip_drop, material, thickness=0.008, segments=3):
    """Create a low-poly solid leaf ribbon that visibly has two sides."""
    base_v = Vector(base)
    direction = Vector((direction_xy[0], direction_xy[1], 0.0))
    if direction.length <= 0.0001:
        raise ValueError("Leaf direction cannot be zero")
    direction.normalize()
    side = Vector((-direction.y, direction.x, 0.0))

    centers = []
    widths = []
    for i in range(segments + 1):
        t = i / segments
        # A simple lifted-and-drooping blade profile.
        lift = arch_height * math.sin(math.pi * t) - tip_drop * (t ** 1.55)
        center = base_v + direction * (length * t) + Vector((0.0, 0.0, lift))
        # Keep every solid leaf vertex above the Z=0 planting plane.
        center.z = max(center.z, thickness * 0.5)
        centers.append(center)
        widths.append(max_width * (math.sin(math.pi * t) ** 0.78))

    vertices = []
    for center, width in zip(centers, widths):
        left = center - side * width * 0.5
        right = center + side * width * 0.5
        vertices.extend([
            (left.x, left.y, left.z + thickness * 0.5),
            (right.x, right.y, right.z + thickness * 0.5),
            (left.x, left.y, left.z - thickness * 0.5),
            (right.x, right.y, right.z - thickness * 0.5),
        ])

    faces = []
    for i in range(segments):
        a = i * 4
        b = (i + 1) * 4
        # top / bottom / left edge / right edge
        faces.append((a, b, b + 1, a + 1))
        faces.append((a + 2, a + 3, b + 3, b + 2))
        faces.append((a, a + 2, b + 2, b))
        faces.append((a + 1, b + 1, b + 3, a + 3))

    # Seal the root and tip so the leaf is a tiny solid mesh rather than a plane.
    faces.append((0, 1, 3, 2))
    last = segments * 4
    faces.append((last, last + 2, last + 3, last + 1))

    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    parent_to_root(obj, root, material)
    return obj


def root_visual_objects(root):
    result = [root]
    result.extend(root.children_recursive)
    return result


def apply_transforms_and_normals(root):
    for obj in root.children_recursive:
        if obj.type != "MESH":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

        bm = bmesh.new()
        bm.from_mesh(obj.data)
        if bm.faces:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()


def asset_bounds(root):
    points = []
    for obj in root.children_recursive:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        raise RuntimeError("Asset has no mesh objects")

    min_v = Vector((min(v.x for v in points), min(v.y for v in points), min(v.z for v in points)))
    max_v = Vector((max(v.x for v in points), max(v.y for v in points), max(v.z for v in points)))
    return min_v, max_v, max_v - min_v


def triangle_count(root):
    total = 0
    for obj in root.children_recursive:
        if obj.type == "MESH":
            total += sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)
    return total


def validate_visual_asset(root, expected_height=None, height_tolerance=0.10):
    visual_objects = root_visual_objects(root)
    mesh_objects = [obj for obj in visual_objects if obj.type == "MESH"]

    if not root.name.startswith("FTF_"):
        raise RuntimeError("Root must use the FTF_ naming prefix")
    if len(mesh_objects) == 0:
        raise RuntimeError("No visible mesh children were created")

    used_names = set()
    for obj in visual_objects:
        upper_name = obj.name.upper()
        if upper_name.startswith(("UCX_", "MESH_UCX_")):
            raise RuntimeError("Collision mesh must not enter visual GLB: " + obj.name)
        if obj.name in used_names:
            raise RuntimeError("Duplicate visual object name: " + obj.name)
        used_names.add(obj.name)
        if obj.type not in {"EMPTY", "MESH"}:
            raise RuntimeError("Visual hierarchy contains forbidden object type: " + obj.type)
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            raise RuntimeError("Zero scale detected: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            raise RuntimeError("Negative scale detected: " + obj.name)
        if obj.type == "MESH" and not obj.data.materials:
            raise RuntimeError("Missing material on mesh: " + obj.name)

    min_v, max_v, dimensions = asset_bounds(root)
    if min_v.z < -0.002:
        raise RuntimeError("Asset extends below Z=0: {:.4f}".format(min_v.z))
    if expected_height is not None and abs(dimensions.z - expected_height) > height_tolerance:
        raise RuntimeError(
            "Asset height {:.3f}m does not meet expected {:.3f}m ± {:.3f}m".format(
                dimensions.z, expected_height, height_tolerance
            )
        )

    return min_v, max_v, dimensions


def report_asset(root, label):
    min_v, max_v, dimensions = asset_bounds(root)
    meshes = [obj for obj in root.children_recursive if obj.type == "MESH"]
    materials = {slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}
    print("[{}] bounds min={} max={} dimensions=({:.3f}, {:.3f}, {:.3f})m".format(
        label, tuple(round(x, 4) for x in min_v), tuple(round(x, 4) for x in max_v),
        dimensions.x, dimensions.y, dimensions.z
    ))
    print("[{}] mesh_count={} material_count={} triangles={}".format(
        label, len(meshes), len(materials), triangle_count(root)
    ))


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def create_preview_scene(root):
    min_v, max_v, dimensions = asset_bounds(root)
    center = (min_v + max_v) * 0.5
    span = max(dimensions.x, dimensions.y, dimensions.z, 1.0)

    ground_material = make_material("PreviewGroundMaterial", "#1B2028", roughness=0.95)
    bpy.ops.mesh.primitive_plane_add(size=span * 3.5, location=(center.x, center.y, min_v.z - 0.012))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    ground.data.materials.append(ground_material)

    bpy.ops.object.camera_add(location=(center.x + span * 1.55, center.y - span * 1.75, min_v.z + span * 1.10))
    camera = bpy.context.active_object
    camera.name = "PreviewCamera"
    camera.data.lens = 52
    look_at(camera, (center.x, center.y, min_v.z + dimensions.z * 0.48))
    bpy.context.scene.camera = camera

    def add_area(name, location, energy, size, color):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.active_object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        look_at(light, (center.x, center.y, min_v.z + dimensions.z * 0.45))
        return light

    add_area("PreviewKey", (center.x + span, center.y - span, min_v.z + span * 1.8), 850.0, span * 0.75, (1.0, 0.84, 0.70))
    add_area("PreviewFill", (center.x - span * 1.1, center.y - span * 0.25, min_v.z + span * 1.15), 500.0, span * 0.65, (0.55, 0.70, 1.0))
    add_area("PreviewRim", (center.x + span * 0.25, center.y + span * 1.1, min_v.z + span * 1.35), 650.0, span * 0.55, (0.85, 0.92, 1.0))


def render_preview():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.context.scene.render.filepath = PREVIEW_PATH
    bpy.ops.render.render(write_still=True)
    print("Preview rendered: " + PREVIEW_PATH)


def select_visual_root(root):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_selected_glb(root):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    select_visual_root(root)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("GLB exported: " + GLB_PATH)


def reimport_and_validate_glb():
    clear_scene()
    setup_scene()
    bpy.ops.import_scene.gltf(filepath=GLB_PATH)

    imported_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not imported_meshes:
        raise RuntimeError("Re-import validation failed: no meshes found")

    collision_meshes = [
        obj.name for obj in imported_meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in imported_meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    negative_scale = [
        obj.name for obj in imported_meshes
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0
    ]
    cameras_or_lights = [
        obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}
    ]

    if collision_meshes:
        raise RuntimeError("Re-import contains collision meshes: " + ", ".join(collision_meshes))
    if zero_scale:
        raise RuntimeError("Re-import contains zero-scale meshes: " + ", ".join(zero_scale))
    if negative_scale:
        raise RuntimeError("Re-import contains negative-scale meshes: " + ", ".join(negative_scale))
    if cameras_or_lights:
        raise RuntimeError("Re-import GLB contains camera/light objects: " + ", ".join(cameras_or_lights))

    points = []
    materials = set()
    triangles = 0
    for obj in imported_meshes:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
        for slot in obj.material_slots:
            if slot.material:
                materials.add(slot.material.name)
        triangles += sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)

    min_v = Vector((min(v.x for v in points), min(v.y for v in points), min(v.z for v in points)))
    max_v = Vector((max(v.x for v in points), max(v.y for v in points), max(v.z for v in points)))
    dimensions = max_v - min_v
    print("[REIMPORT PASS] meshes={} materials={} triangles={} dimensions=({:.3f}, {:.3f}, {:.3f})m".format(
        len(imported_meshes), len(materials), triangles, dimensions.x, dimensions.y, dimensions.z
    ))


def main():
    clear_scene()
    setup_scene()
    root = build_asset()
    apply_transforms_and_normals(root)
    validate_visual_asset(root, expected_height=EXPECTED_HEIGHT, height_tolerance=HEIGHT_TOLERANCE)
    report_asset(root, "EXPORT CHECK")
    create_preview_scene(root)
    render_preview()
    export_selected_glb(root)
    reimport_and_validate_glb()
    print("DONE: {} generated, previewed, exported, and re-import validated.".format(ASSET_NAME))



# FarmWar plant asset: thin purple sugar cane for planting.
# Total height is approximately 4m: the first 3m is a purple segmented stalk,
# and the top metre is reserved for the green leaf crown.
EXPECTED_HEIGHT = 4.0
HEIGHT_TOLERANCE = 0.10


def build_asset():
    root = create_root()

    purple_main = make_material("CanePurpleSkin", "#7B4FA3", roughness=0.82)
    purple_shadow = make_material("CanePurpleShade", "#5A367F", roughness=0.86)
    purple_node = make_material("CanePurpleNode", "#3E235C", roughness=0.90)
    leaf_light = make_material("CaneTopLeafLight", "#78C95B", roughness=0.84)
    leaf_dark = make_material("CaneTopLeafShade", "#35643A", roughness=0.90)

    # A deliberately slender stalk: 3m purple outer skin from Z=0 to Z=3.
    # Each segment touches or slightly overlaps the node bands, avoiding gaps.
    stalk_segments = [
        (0.340, 0.680, purple_main),
        (1.030, 0.650, purple_shadow),
        (1.700, 0.650, purple_main),
        (2.370, 0.650, purple_shadow),
        (2.830, 0.340, purple_main),
    ]
    for index, (z, height, material) in enumerate(stalk_segments, start=1):
        add_cylinder(
            root,
            "PurpleCaneStalkSegment{:02d}".format(index),
            (0.0, 0.0, z),
            radius=0.066,
            depth=height,
            material=material,
            vertices=8,
            bevel=0.007,
        )

    for index, z in enumerate((0.685, 1.365, 2.035, 2.700), start=1):
        add_cylinder(
            root,
            "PurpleCaneNodeBand{:02d}".format(index),
            (0.0, 0.0, z),
            radius=0.076,
            depth=0.055,
            material=purple_node,
            vertices=8,
            bevel=0.004,
        )

    # Green leaves are restricted to the crown. Their tallest blade reaches
    # almost exactly Z=4m, while all bases meet the 3m purple stalk.
    top_leaf_specs = [
        ((0.00, 0.00, 2.94), (1.00, 0.18), 0.54, 0.052, 0.82, 0.18, leaf_dark),
        ((0.00, 0.00, 2.98), (-0.48, 1.00), 0.50, 0.050, 0.90, 0.16, leaf_light),
        ((0.00, 0.00, 3.00), (-1.00, 0.06), 0.47, 0.048, 0.88, 0.16, leaf_dark),
        ((0.00, 0.00, 3.02), (0.26, -1.00), 0.45, 0.046, 0.98, 0.15, leaf_light),
        ((0.00, 0.00, 3.04), (0.75, -0.62), 0.42, 0.044, 1.05, 0.14, leaf_light),
    ]
    for index, spec in enumerate(top_leaf_specs, start=1):
        base, direction, length, width, arch, drop, material = spec
        add_tapered_leaf(
            root,
            "GreenTopLeaf{:02d}".format(index),
            base,
            direction,
            length,
            width,
            arch,
            drop,
            material,
            thickness=0.007,
            segments=3,
        )

    return root


main()
