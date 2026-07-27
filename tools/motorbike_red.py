# Blender 4.x / 5.x - standalone Food War asset generator
# This script creates a visual-only GLB and a 1100x700 PNG preview.
# It clears the scene, generates the asset, validates it, exports it, then
# clears the scene again and re-imports the GLB for final validation.

import bpy
import bmesh
import math
import os
from mathutils import Vector

ASSET_NAME = "FTF_Vehicle_Motorbike_Red"
OUTPUT_FOLDER_NAME = "generated_foodwar_assets"
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
        centers.append(base_v + direction * (length * t) + Vector((0.0, 0.0, lift)))
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



# Food War vehicle asset: compact stylized motorbike, 1.5m tall.
EXPECTED_HEIGHT = 1.50
HEIGHT_TOLERANCE = 0.08
TEAM_COLOR_HEX = "#C9433F"
TEAM_HIGHLIGHT_HEX = "#F06A57"


def build_asset():
    root = create_root()

    body_main = make_material("BikeBodyMain", TEAM_COLOR_HEX, roughness=0.60)
    body_highlight = make_material("BikeBodyHighlight", TEAM_HIGHLIGHT_HEX, roughness=0.56)
    warm_cream = make_material("BikeWarmCream", "#E9DFC9", roughness=0.68)
    graphite = make_material("BikeToolGraphite", "#2C343A", roughness=0.70, metallic=0.05)
    steel = make_material("BikeSteelBlueGray", "#6F8793", roughness=0.42, metallic=0.55)
    tire = make_material("BikeTire", "#242A2E", roughness=0.88)
    lamp = make_material("BikeLamp", "#E9B93F", roughness=0.45, metallic=0.08)

    # Front is local -Y, as required by the Food War coordinate convention.
    # Wheels sit exactly on Z=0 and form the main readable silhouette.
    for prefix, y in (("Front", -0.78), ("Rear", 0.78)):
        add_cylinder(
            root, prefix + "Tire", (0.0, y, 0.29), radius=0.29, depth=0.16,
            material=tire, vertices=10, bevel=0.010, rotation=(0.0, math.radians(90.0), 0.0)
        )
        add_cylinder(
            root, prefix + "WheelRim", (0.0, y, 0.29), radius=0.185, depth=0.125,
            material=steel, vertices=10, bevel=0.006, rotation=(0.0, math.radians(90.0), 0.0)
        )
        add_cylinder(
            root, prefix + "WheelHub", (0.0, y, 0.29), radius=0.050, depth=0.175,
            material=graphite, vertices=8, bevel=0.004, rotation=(0.0, math.radians(90.0), 0.0)
        )

    # Lower frame and suspension: chunky, sparse and toy-like rather than mechanical-realistic.
    add_cylinder_between(root, "LowerFrame", (0.0, 0.68, 0.47), (0.0, -0.47, 0.57), 0.065, graphite, vertices=8, bevel=0.006)
    add_cylinder_between(root, "RearSupport", (0.0, 0.72, 0.47), (0.0, 0.44, 0.86), 0.055, graphite, vertices=8, bevel=0.006)
    add_cylinder_between(root, "FrontSteeringStem", (0.0, -0.68, 0.46), (0.0, -0.46, 1.25), 0.050, steel, vertices=8, bevel=0.006)
    add_cylinder_between(root, "LeftFrontFork", (-0.16, -0.75, 0.37), (-0.16, -0.49, 1.12), 0.035, steel, vertices=8, bevel=0.004)
    add_cylinder_between(root, "RightFrontFork", (0.16, -0.75, 0.37), (0.16, -0.49, 1.12), 0.035, steel, vertices=8, bevel=0.004)

    # Main visual body: tank, seat, nose and fenders use clean color blocking.
    add_cube(root, "FuelTank", (0.0, -0.05, 0.88), (0.62, 0.82, 0.38), body_main, bevel=0.060)
    add_cube(root, "TankHighlightPanel", (0.0, -0.16, 1.085), (0.36, 0.42, 0.035), body_highlight, bevel=0.012)
    add_cube(root, "Seat", (0.0, 0.52, 0.98), (0.54, 0.62, 0.19), graphite, bevel=0.045)
    add_cube(root, "RearCargoAccent", (0.0, 0.92, 0.78), (0.50, 0.34, 0.22), body_main, bevel=0.040)
    add_cube(root, "FrontCowling", (0.0, -0.58, 1.03), (0.54, 0.34, 0.43), body_main, bevel=0.055)
    add_cube(root, "HeadlampHousing", (0.0, -0.77, 1.12), (0.32, 0.08, 0.20), warm_cream, bevel=0.020)
    add_cube(root, "HeadlampLens", (0.0, -0.817, 1.12), (0.18, 0.018, 0.105), lamp, bevel=0.006)

    # Fenders sit clearly above tyres, offset so their surfaces never coincide with wheels.
    add_cube(root, "FrontFender", (0.0, -0.78, 0.58), (0.47, 0.48, 0.115), body_highlight, bevel=0.035)
    add_cube(root, "RearFender", (0.0, 0.78, 0.59), (0.47, 0.44, 0.105), body_main, bevel=0.032)

    # Handlebar silhouette reaches the requested total height of 1.5m.
    add_cylinder_between(root, "HandlebarColumn", (0.0, -0.46, 1.16), (0.0, -0.46, 1.38), 0.035, graphite, vertices=8, bevel=0.004)
    add_cylinder(
        root, "Handlebar", (0.0, -0.46, 1.40), radius=0.043, depth=0.82,
        material=graphite, vertices=8, bevel=0.006, rotation=(0.0, math.radians(90.0), 0.0)
    )
    add_cube(root, "LeftGrip", (-0.47, -0.46, 1.40), (0.22, 0.095, 0.095), graphite, bevel=0.018)
    add_cube(root, "RightGrip", (0.47, -0.46, 1.40), (0.22, 0.095, 0.095), graphite, bevel=0.018)
    # The display cap tops at exactly 1.50m.
    add_cube(root, "HandlebarDisplay", (0.0, -0.405, 1.455), (0.23, 0.14, 0.09), warm_cream, bevel=0.018)

    # Functional accents: footrests and a small rear lamp.
    add_cube(root, "LeftFootrest", (-0.34, 0.30, 0.58), (0.24, 0.18, 0.07), steel, bevel=0.012)
    add_cube(root, "RightFootrest", (0.34, 0.30, 0.58), (0.24, 0.18, 0.07), steel, bevel=0.012)
    add_cube(root, "RearLamp", (0.0, 1.115, 0.80), (0.20, 0.026, 0.11), body_highlight, bevel=0.008)

    return root


main()
