# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Farm Town / FarmWar - Giant Red Lying Pepper Crop
#
# Generates one GLB:
#   FTF_Crop_GiantRedPepper_Lying.glb
#
# DESIGN
# - Strange giant crop asset
# - One single huge red chili pepper
# - Lying horizontally on the ground
# - Overall footprint targets about 8m x 8m
# - Overall height targets about 4m
# - Blue pepper body with green stem/calyx and large attached leaves
#
# ASSET STANDARD
# - Root at ground origin (0,0,0)
# - Native Blender Z-up
# - No cameras / lights / text
# - No collision meshes
# - Static visual meshes are merged before export
#
# VALIDATION
# - Root remains at origin
# - No cameras/lights/collision meshes
# - No negative/zero scale
# - Bounding box checked against giant-crop target
# - Attachment audit checks that stem/leaves/calyx/body are not floating
#
# OUTPUT
#   generated_farmtown_crops/FTF_Crop_GiantRedPepper_Lying.glb
#
# Run:
#   blender --background --factory-startup --python generate_giant_red_pepper.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# PATHS / CONSTANTS
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_crops")
OUTPUT_FILE = "FTF_Crop_GiantRedPepper_Lying.glb"

ROOT_NAME = "FTF_Crop_GiantRedPepper_Lying"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True


# Target dimensions. The model is intentionally organic, so the validation allows
# a small tolerance around these values.
TARGET_FOOTPRINT_X = 8.0
TARGET_FOOTPRINT_Y = 8.0
TARGET_HEIGHT_Z = 4.0


# ---------------------------------------------------------------------
# SCENE / MATERIALS
# ---------------------------------------------------------------------

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


def make_material(name, color, roughness=0.72, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    mat.diffuse_color = (*color, 1.0)
    return mat


def build_materials():
    return {
        "pepper_red": make_material("MAT_GiantPepper_RedBody", (0.86, 0.05, 0.025), 0.58, 0.02),
        "pepper_red_dark": make_material("MAT_GiantPepper_DarkRed", (0.40, 0.015, 0.010), 0.72, 0.02),
        "pepper_red_light": make_material("MAT_GiantPepper_SubtleRedHighlight", (1.00, 0.18, 0.08), 0.50, 0.02),
        "stem": make_material("MAT_GiantPepper_Stem", (0.13, 0.38, 0.12), 0.76),
        "leaf": make_material("MAT_GiantPepper_Leaf", (0.20, 0.58, 0.16), 0.78),
        "leaf_light": make_material("MAT_GiantPepper_LeafLight", (0.42, 0.76, 0.25), 0.72),
        "leaf_dark": make_material("MAT_GiantPepper_LeafDark", (0.08, 0.28, 0.09), 0.82),
    }


# ---------------------------------------------------------------------
# COLLECTION / OBJECT HELPERS
# ---------------------------------------------------------------------

def get_or_create_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
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
    for poly in obj.data.polygons:
        poly.use_smooth = False


def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for poly in obj.data.polygons:
        poly.use_smooth = True


def add_bevel(obj, width=0.01, segments=1):
    mod = obj.modifiers.new("LowPolyBevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return mod


def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for mod in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError as exc:
            print(f"[WARN] Could not apply modifier {mod.name} on {obj.name}: {exc}")


def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.55
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "giant_crop"
    root["crop_type"] = "red_pepper"
    root["pose"] = "lying_horizontal"
    root["target_footprint_m"] = "8 x 8"
    root["target_height_m"] = 4.0
    root["has_collision_mesh"] = False
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES

    collection.objects.link(root)
    return root


# ---------------------------------------------------------------------
# GEOMETRY HELPERS
# ---------------------------------------------------------------------

def add_cube(name, location, dimensions, material, parent, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), no_merge=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def add_cylinder_between(name, p0, p1, radius, material, parent, collection, vertices=12, bevel=0.0):
    p0 = Vector(p0)
    p1 = Vector(p1)
    mid = (p0 + p1) * 0.5
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")

    quat = direction.to_track_quat("Z", "Y")
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        location=mid,
        rotation=quat.to_euler(),
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_cone_between(name, p0, p1, radius1, radius2, material, parent, collection, vertices=12, bevel=0.0):
    p0 = Vector(p0)
    p1 = Vector(p1)
    mid = (p0 + p1) * 0.5
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cone: {name}")

    quat = direction.to_track_quat("Z", "Y")
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=length,
        location=mid,
        rotation=quat.to_euler(),
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_lowpoly_sphere(name, location, radius, material, parent, collection, subdivisions=1, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=radius,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def create_pepper_body_mesh(name, material, parent, collection):
    """
    Build the main pepper as one continuous custom mesh.
    This avoids fake body pieces or coplanar overlap.
    """
    rings = 20
    radial = 24

    verts = []
    ring_indices = []

    for i in range(rings):
        t = i / (rings - 1)

        # Horizontal body length about 7.85m, with a mild organic curve in Y.
        x = -3.85 + 7.85 * t
        center_y = 0.55 * math.sin(math.pi * t) - 0.10 * t

        # Taper strongly toward the pointed tip.
        base_radius = 1.75 * ((1.0 - t) ** 0.78) + 0.16 * t
        # Flatten a little in Y but keep a large height so it feels giant.
        ry = base_radius * (0.82 + 0.05 * math.sin(math.pi * t))
        rz = base_radius * 1.03

        # Keep underside very near the ground.
        center_z = rz + 0.035

        ring = []
        for j in range(radial):
            a = math.tau * j / radial

            # Mild lobed surface, like a stylized chili.
            ridge = 1.0 + 0.045 * math.cos(5.0 * a) * (1.0 - t * 0.75)
            y = center_y + math.cos(a) * ry * ridge
            z = center_z + math.sin(a) * rz * ridge
            verts.append((x, y, z))
            ring.append(len(verts) - 1)
        ring_indices.append(ring)

    faces = []
    for i in range(rings - 1):
        for j in range(radial):
            faces.append((
                ring_indices[i][j],
                ring_indices[i][(j + 1) % radial],
                ring_indices[i + 1][(j + 1) % radial],
                ring_indices[i + 1][j],
            ))

    # End caps.
    start_center_index = len(verts)
    verts.append((-3.85, 0.0, 1.82))
    for j in range(radial):
        faces.append((start_center_index, ring_indices[0][j], ring_indices[0][(j + 1) % radial]))

    end_center_index = len(verts)
    verts.append((4.00, -0.10, 0.20))
    for j in range(radial):
        faces.append((end_center_index, ring_indices[-1][(j + 1) % radial], ring_indices[-1][j]))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth_shading(obj)
    obj.parent = parent
    obj["asset_role"] = "render"
    return obj


def add_leaf_mesh(name, base, direction, length, width, curl_height, material, parent, collection, side_bias=0.0):
    """
    Create a single attached large leaf mesh.
    base is the exact attachment point. The mesh includes this base, so the leaf
    is not a floating part.
    """
    base = Vector(base)
    f = Vector(direction).normalized()
    world_up = Vector((0.0, 0.0, 1.0))

    side = world_up.cross(f)
    if side.length < 0.001:
        side = Vector((1.0, 0.0, 0.0))
    else:
        side.normalize()
    up_local = f.cross(side).normalized()

    rows = 7
    cols = 5  # -2, -1, 0, 1, 2 across the leaf

    verts = []
    for i in range(rows):
        s = i / (rows - 1)
        half_w = width * math.sin(math.pi * s) * (0.72 + 0.22 * s)
        center = base + f * (length * s) + up_local * (curl_height * math.sin(math.pi * s))
        # organic bend, slightly biased sideways so leaves do not look perfectly flat
        center += side * (side_bias * math.sin(math.pi * s))

        for c in range(cols):
            u = (c - (cols - 1) * 0.5) / ((cols - 1) * 0.5)
            z_rib = 0.035 * (1.0 - abs(u)) * math.sin(math.pi * s)
            p = center + side * (u * half_w) + up_local * z_rib
            verts.append(tuple(p))

    faces = []
    for i in range(rows - 1):
        for c in range(cols - 1):
            a = i * cols + c
            faces.append((a, a + 1, a + 1 + cols, a + cols))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    obj["asset_role"] = "render"
    return obj


# ---------------------------------------------------------------------
# BUILD CROP
# ---------------------------------------------------------------------

def build_giant_red_pepper():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    # Main giant red chili body: one continuous surface.
    create_pepper_body_mesh(
        "SM_GiantRedPepper_Body",
        mats["pepper_red"],
        root,
        collection,
    )

    # Stem/calyx begins at the large end of the pepper.
    stem_base = Vector((-3.78, 0.02, 1.85))
    stem_points = [
        stem_base,
        Vector((-4.02, 0.06, 2.40)),
        Vector((-3.86, 0.08, 3.02)),
        Vector((-3.38, 0.10, 3.46)),
    ]
    for i in range(len(stem_points) - 1):
        add_cone_between(
            f"SM_GiantRedPepper_Stem_{i:02d}",
            stem_points[i],
            stem_points[i + 1],
            0.19 - 0.035 * i,
            0.16 - 0.035 * i,
            mats["stem"],
            root,
            collection,
            vertices=10,
            bevel=0.003,
        )

    # Calyx star leaves hugging the pepper base.
    calyx_base = Vector((-3.74, 0.02, 1.76))
    calyx_dirs = [
        (-0.35, 0.78, 0.18),
        (-0.35, -0.78, 0.18),
        (-0.55, 0.15, 0.45),
        (-0.20, 0.20, 0.75),
        (-0.20, -0.20, 0.75),
        (-0.65, -0.15, 0.38),
    ]
    for i, direction in enumerate(calyx_dirs):
        add_leaf_mesh(
            f"SM_GiantRedPepper_CalyxLeaf_{i:02d}",
            calyx_base,
            direction,
            1.05,
            0.30,
            0.10,
            mats["leaf_dark"],
            root,
            collection,
            side_bias=0.03 * ((i % 2) * 2 - 1),
        )

    # Large leaves attached to the upper stem. These make the overall footprint
    # approach 8m x 8m while keeping the chili itself a single lying fruit.
    big_leaf_base = Vector((-3.55, 0.08, 3.06))
    add_leaf_mesh(
        "SM_GiantRedPepper_BigLeaf_Left",
        big_leaf_base,
        (-0.10, 0.97, 0.20),
        4.05,
        1.05,
        0.30,
        mats["leaf"],
        root,
        collection,
        side_bias=0.12,
    )
    add_leaf_mesh(
        "SM_GiantRedPepper_BigLeaf_Right",
        big_leaf_base + Vector((0.04, -0.04, -0.05)),
        (-0.08, -0.98, 0.20),
        4.05,
        1.05,
        0.30,
        mats["leaf"],
        root,
        collection,
        side_bias=-0.12,
    )
    add_leaf_mesh(
        "SM_GiantRedPepper_BigLeaf_Upper",
        Vector((-3.42, 0.05, 3.30)),
        (0.25, 0.02, 0.97),
        0.72,
        0.55,
        0.10,
        mats["leaf_light"],
        root,
        collection,
        side_bias=0.0,
    )


    return root


# ---------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def get_static_meshes_for_merge(root):
    return [obj for obj in get_meshes_under_root(root) if not obj.get("no_merge", False)]


def get_mesh_by_name(name):
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Missing expected mesh: {name}")
    return obj


def world_bbox(obj):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def aabb_distance(obj_a, obj_b):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)
    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def bbox_world_all(meshes):
    lows = []
    highs = []
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lows.append(p)
            highs.append(p)
    low = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
    high = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
    return low, high


def validate_attachment_pairs():
    pairs = [
        ("SM_GiantRedPepper_Body", "SM_GiantRedPepper_Stem_00", 0.12),
        ("SM_GiantRedPepper_Stem_00", "SM_GiantRedPepper_Stem_01", 0.06),
        ("SM_GiantRedPepper_Stem_01", "SM_GiantRedPepper_Stem_02", 0.06),
        ("SM_GiantRedPepper_Body", "SM_GiantRedPepper_CalyxLeaf_00", 0.12),
        ("SM_GiantRedPepper_Body", "SM_GiantRedPepper_CalyxLeaf_01", 0.12),
        ("SM_GiantRedPepper_Stem_02", "SM_GiantRedPepper_BigLeaf_Left", 0.16),
        ("SM_GiantRedPepper_Stem_02", "SM_GiantRedPepper_BigLeaf_Right", 0.16),
        ("SM_GiantRedPepper_Stem_02", "SM_GiantRedPepper_BigLeaf_Upper", 0.18),
    ]

    failures = []
    for a_name, b_name, allowed_gap in pairs:
        a = get_mesh_by_name(a_name)
        b = get_mesh_by_name(b_name)
        dist = aabb_distance(a, b)
        if dist > allowed_gap:
            failures.append(f"{a_name} -> {b_name}: gap {dist:.4f}m > allowed {allowed_gap:.4f}m")

    if failures:
        raise RuntimeError("FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures))

    print(f"[VALID] Attachment audit passed: {len(pairs)} checks.")


def detect_suspicious_collision_names():
    bad = []
    for obj in bpy.context.scene.objects:
        n = obj.name.lower()
        if n.startswith("ucx") or "collision" in n or n.startswith("col_"):
            if obj.type == "MESH":
                bad.append(obj.name)
    if bad:
        raise RuntimeError("VALIDATION FAILED: collision-like mesh names found: " + ", ".join(bad))


def validate_asset_before_merge(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root must remain at ground origin (0,0,0).")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(bad_scene))

    detect_suspicious_collision_names()

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root.")

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0 or obj.scale.y < 0 or obj.scale.z < 0:
            failures.append("negative scale: " + obj.name)
    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    validate_attachment_pairs()

    bpy.context.view_layer.update()
    low, high = bbox_world_all(meshes)
    dims = high - low

    # Allow organic tolerance while still enforcing the "giant 8x8m, 4m high" target.
    if not (7.4 <= dims.x <= 8.8):
        raise RuntimeError(f"VALIDATION FAILED: X footprint should be around 8m, got {dims.x:.2f}m.")
    if not (7.2 <= dims.y <= 8.8):
        raise RuntimeError(f"VALIDATION FAILED: Y footprint should be around 8m, got {dims.y:.2f}m.")
    if not (3.75 <= dims.z <= 4.35):
        raise RuntimeError(f"VALIDATION FAILED: height should be around 4m, got {dims.z:.2f}m.")
    if low.z < -0.03:
        raise RuntimeError(f"VALIDATION FAILED: geometry below ground too far: minZ={low.z:.3f}m.")

    tri_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tri_count += len(obj.data.loop_triangles)

    print(
        f"[VALID BEFORE MERGE] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Min Z: {low.z:.3f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {tri_count}\n"
        f"  Pose: lying horizontal giant pepper\n"
    )


def validate_asset_after_merge(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root/origin moved after merge.")

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root after merge.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain after merge: " + ", ".join(bad_scene))

    detect_suspicious_collision_names()

    bpy.context.view_layer.update()
    low, high = bbox_world_all(meshes)
    dims = high - low

    tri_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tri_count += len(obj.data.loop_triangles)

    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {tri_count}\n"
    )


# ---------------------------------------------------------------------
# MERGE / EXPORT
# ---------------------------------------------------------------------

def merge_static_meshes(root):
    meshes = get_static_meshes_for_merge(root)
    if not meshes:
        raise RuntimeError("No static meshes available for merge.")

    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = ROOT_NAME + "_Static"
    merged.parent = root
    merged["no_merge"] = False
    return merged


def select_for_export(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    select_for_export(root)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
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
    print(f"[EXPORT] {filepath}")


# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------

if __name__ == "__main__":
    print("\n=== Generating Giant Red Lying Pepper Crop ===\n")

    root = build_giant_red_pepper()

    validate_asset_before_merge(root)

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset_after_merge(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - One single giant red chili pepper lying horizontally.")
    print(" - No soil/shadow base, no surface tube highlight, no leaf vein tubes.")
    print(" - Target bounds are approximately 8m x 8m x 4m.")
    print(" - Large leaves and stem are attached; attachment audit passed before merge.")
    print(" - No collision meshes, cameras, lights, or text.")
