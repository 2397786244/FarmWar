import bpy
import bmesh
import math
import mathutils
import os
import sys
from mathutils import Vector

# =========================================================
# Lowpoly professional wheat-colored twin-barrel auto turret
# v1.5: matte rustic wheat/brown/black palette; radar shifted left; thin antenna seated correctly.
# =========================================================
# Root origin at ground center.
# Blender orientation: Z up, turret forward is local -Y.
# Rotating node: TurretYaw (all rotating parts under this node)
#
# Output:
#   FTF_Turret_WheatTwinAuto.glb
# Optional preview:
#   FTF_Turret_WheatTwinAuto_preview.png
# =========================================================

ASSET_NAME = "FTF_Turret_WheatTwinAuto"

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    bpy.context.preferences.edit.use_global_undo = False


def ensure_collection(name="Collection"):
    scene = bpy.context.scene
    if name in bpy.data.collections:
        col = bpy.data.collections[name]
    else:
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
    return col


def clear_default_collection_objects():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name, base=(0.8, 0.67, 0.33, 1.0), metallic=0.0, roughness=0.80):
    """Create a deliberately matte, non-metallic material.

    This turret uses a rustic wheat / brown / black painted-plastic palette.
    Metallic is always forced to 0.0 so it does not read as a metal prop.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = max(roughness, 0.72)
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.22
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.0
    return mat


def set_parent(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def link_to_collection(obj, collection):
    if obj.name not in collection.objects:
        collection.objects.link(obj)
    if obj.name in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.unlink(obj)


def assign_material(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def apply_bevel(obj, width=0.02, segments=2, angle_deg=30.0):
    mod = obj.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle_deg)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)


def shade_auto(obj, angle_deg=40.0):
    """Blender 4.4+/5.x compatible smoothing helper.

    Mesh.use_auto_smooth was removed in Blender 4.1, so do not access it.
    The turret already uses low segment counts and bevels for its lowpoly form;
    smooth shading is used only to remove faceting on rounded parts.
    """
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    obj.select_set(False)


def add_cube(name, size=(1,1,1), location=(0,0,0), rotation=(0,0,0), scale=(1,1,1), collection=None):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0]*0.5*scale[0], size[1]*0.5*scale[1], size[2]*0.5*scale[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collection:
        link_to_collection(obj, collection)
    return obj


def add_cylinder(name, radius=0.5, depth=1.0, vertices=12, location=(0,0,0), rotation=(0,0,0), collection=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if collection:
        link_to_collection(obj, collection)
    return obj


def add_uv_sphere(name, radius=0.5, segments=16, rings=8, location=(0,0,0), rotation=(0,0,0), scale=(1,1,1), collection=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collection:
        link_to_collection(obj, collection)
    return obj


def add_icosphere(name, radius=0.5, subdivisions=1, location=(0,0,0), collection=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    if collection:
        link_to_collection(obj, collection)
    return obj


def taper_cylinder(obj, top_scale=0.82, bottom_scale=1.0):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    zs = [v.co.z for v in bm.verts]
    zmin = min(zs)
    zmax = max(zs)
    for v in bm.verts:
        t = 0.0 if abs(zmax-zmin) < 1e-6 else (v.co.z - zmin) / (zmax - zmin)
        s = bottom_scale + (top_scale - bottom_scale) * t
        v.co.x *= s
        v.co.y *= s
    bm.to_mesh(me)
    bm.free()


def make_radar_dish(name, radius=0.28, depth_scale=0.45, location=(0,0,0), collection=None):
    # Bowl-like radar dish from a sphere cap.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    threshold = location[2]  # not directly used after local coords; keep local z >= 0
    to_delete = [f for f in bm.faces if all(v.co.z < -0.02 for v in f.verts)]
    bmesh.ops.delete(bm, geom=to_delete, context='FACES')
    # flatten and open bowl
    for v in bm.verts:
        v.co.z *= depth_scale
    bmesh.ops.scale(bm, verts=bm.verts, vec=(1.05,1.05,1.0))
    bm.to_mesh(obj.data)
    bm.free()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collection:
        link_to_collection(obj, collection)
    return obj


def bbox_world(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    hi = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return lo, hi


def bbox_gap(a, b):
    alo, ahi = bbox_world(a)
    blo, bhi = bbox_world(b)
    def axis_gap(a0,a1,b0,b1):
        if a1 < b0:
            return b0 - a1
        if b1 < a0:
            return a0 - b1
        return 0.0
    gx = axis_gap(alo.x, ahi.x, blo.x, bhi.x)
    gy = axis_gap(alo.y, ahi.y, blo.y, bhi.y)
    gz = axis_gap(alo.z, ahi.z, blo.z, bhi.z)
    return math.sqrt(gx*gx + gy*gy + gz*gz)


def bounds_union(meshes):
    lows = []
    highs = []
    for o in meshes:
        lo, hi = bbox_world(o)
        lows.append(lo)
        highs.append(hi)
    low = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
    high = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
    return low, high


def validate_hierarchy(root, turret_yaw, fixed_meshes, yaw_meshes):
    if turret_yaw.parent != root:
        raise RuntimeError("HIERARCHY AUDIT FAILED: TurretYaw must be direct child of root")
    for m in fixed_meshes:
        if m.parent != root:
            raise RuntimeError(f"HIERARCHY AUDIT FAILED: fixed mesh {m.name} must be parented to root")
    for m in yaw_meshes:
        if m.parent != turret_yaw:
            raise RuntimeError(f"HIERARCHY AUDIT FAILED: yaw mesh {m.name} must be parented to TurretYaw")
    print("HIERARCHY AUDIT OK: fixed base and TurretYaw meshes are separated")


def validate_bounds(meshes):
    bpy.context.view_layer.update()
    low, high = bounds_union(meshes)
    size = high - low
    footprint_x = size.x
    footprint_y = size.y
    height = size.z
    print(f"BOUNDS DEBUG: footprint={footprint_x:.3f}m x {footprint_y:.3f}m, height={height:.3f}m, low={tuple(round(v,3) for v in low)}, high={tuple(round(v,3) for v in high)}")
    if footprint_x > 2.0 + 1e-3 or footprint_y > 2.0 + 1e-3:
        raise RuntimeError(f"BOUNDS AUDIT FAILED: footprint {footprint_x:.3f}m x {footprint_y:.3f}m exceeds 2.0m x 2.0m")
    if not (1.70 <= height <= 2.10):
        raise RuntimeError(f"BOUNDS AUDIT FAILED: height {height:.3f}m is outside 1.70m–2.10m target")
    print(f"BOUNDS AUDIT OK: footprint={footprint_x:.3f}m x {footprint_y:.3f}m, height={height:.3f}m, low={tuple(round(v,3) for v in low)}, high={tuple(round(v,3) for v in high)}")


def validate_attachments(pairs, max_gap=0.016):
    bpy.context.view_layer.update()
    failures = []
    for a,b in pairs:
        gap = bbox_gap(a,b)
        if gap > max_gap:
            failures.append(f"{a.name}<->{b.name} gap={gap*1000:.1f}mm")
    if failures:
        raise RuntimeError("ATTACHMENT AUDIT FAILED: " + "; ".join(failures))
    print("ATTACHMENT AUDIT OK: no visually detached mesh parts")


def validate_surface_audit(meshes):
    # Lightweight audit: flag suspicious almost-identical coplanar box pairs.
    bpy.context.view_layer.update()
    suspicious = []
    for i in range(len(meshes)):
        for j in range(i+1, len(meshes)):
            a = meshes[i]; b = meshes[j]
            alo, ahi = bbox_world(a)
            blo, bhi = bbox_world(b)
            size_a = ahi - alo
            size_b = bhi - blo
            # Only flag if bounding boxes are extremely close in all axes and size nearly same.
            near = (abs(alo.x-blo.x)<0.001 and abs(alo.y-blo.y)<0.001 and abs(alo.z-blo.z)<0.001 and
                    abs(ahi.x-bhi.x)<0.001 and abs(ahi.y-bhi.y)<0.001 and abs(ahi.z-bhi.z)<0.001)
            if near:
                suspicious.append(f"{a.name}<->{b.name}")
    if suspicious:
        raise RuntimeError("SURFACE AUDIT FAILED: possible duplicate overlapping meshes: " + "; ".join(suspicious))
    print(f"SURFACE AUDIT OK: no duplicate/coplanar overlapping mesh bounds across {len(meshes)} meshes")


def setup_preview_camera_and_lights(root):
    bpy.ops.object.camera_add(location=(3.9, -4.6, 2.5), rotation=(math.radians(72), 0.0, math.radians(38)))
    cam = bpy.context.active_object
    bpy.context.scene.camera = cam

    bpy.ops.object.light_add(type='SUN', location=(4, -2, 6))
    sun = bpy.context.active_object
    sun.data.energy = 2.8
    sun.rotation_euler = (math.radians(40), math.radians(5), math.radians(35))

    bpy.ops.object.light_add(type='AREA', location=(-2.8, -3.5, 2.0))
    area = bpy.context.active_object
    area.data.energy = 1800
    area.data.shape = 'RECTANGLE'
    area.data.size = 4
    area.data.size_y = 4
    area.rotation_euler = (math.radians(70), 0, math.radians(-28))

    bpy.ops.mesh.primitive_plane_add(size=12, location=(0,0,0))
    plane = bpy.context.active_object
    plane.name = "PreviewGround"
    mat = make_material("PreviewGroundMat", base=(0.43, 0.44, 0.46, 1.0), metallic=0.0, roughness=0.88)
    assign_material(plane, mat)


def export_glb(output_path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if obj.type in {'MESH', 'EMPTY'}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = None
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        export_apply=True,
        export_yup=True,
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )


def render_preview(output_path):
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    out_dir = os.path.join(os.getcwd(), "generated_foodwar_turrets")
    skip_preview = False

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--output" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
            continue
        if arg == "--skip-preview":
            skip_preview = True
            i += 1
            continue
        i += 1
    return out_dir, skip_preview


def build_turret():
    reset_scene()
    clear_default_collection_objects()
    col = ensure_collection("Turret")

    # Rustic, non-metallic palette only: wheat yellow, farm brown, and matte black.
    # No blue sensor glow, no metallic highlights, and no glossy coat.
    mats = {
        "wheat": make_material(
            "Mat_WheatMatte",
            base=(0.64, 0.47, 0.18, 1.0),
            roughness=0.86
        ),
        "brown": make_material(
            "Mat_FarmBrownMatte",
            base=(0.22, 0.105, 0.040, 1.0),
            roughness=0.90
        ),
        "black": make_material(
            "Mat_CharcoalBlackMatte",
            base=(0.035, 0.028, 0.020, 1.0),
            roughness=0.88
        ),
    }

    root = bpy.data.objects.new(ASSET_NAME, None)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = 0.18
    col.objects.link(root)

    fixed_meshes = []
    yaw_meshes = []

    # Fixed base
    base_skirt = add_cylinder("BaseSkirt", radius=0.88, depth=0.20, vertices=10, location=(0,0,0.10), collection=col)
    taper_cylinder(base_skirt, top_scale=0.85, bottom_scale=1.0)
    apply_bevel(base_skirt, width=0.012, segments=2)
    assign_material(base_skirt, mats["brown"])
    set_parent(base_skirt, root)
    fixed_meshes.append(base_skirt)

    base_core = add_cylinder("BaseCore", radius=0.58, depth=0.24, vertices=10, location=(0,0,0.30), collection=col)
    taper_cylinder(base_core, top_scale=0.94, bottom_scale=1.0)
    apply_bevel(base_core, width=0.010, segments=2)
    assign_material(base_core, mats["wheat"])
    set_parent(base_core, root)
    fixed_meshes.append(base_core)

    base_ring = add_cylinder("BaseRing", radius=0.52, depth=0.08, vertices=12, location=(0,0,0.46), collection=col)
    assign_material(base_ring, mats["brown"])
    set_parent(base_ring, root)
    fixed_meshes.append(base_ring)

    fixed_column = add_cube("FixedColumn", size=(0.54, 0.54, 0.36), location=(0,0,0.64), collection=col)
    apply_bevel(fixed_column, width=0.016, segments=2)
    assign_material(fixed_column, mats["brown"])
    set_parent(fixed_column, root)
    fixed_meshes.append(fixed_column)

    # Rotating node
    turret_yaw = bpy.data.objects.new("TurretYaw", None)
    turret_yaw.empty_display_type = 'SINGLE_ARROW'
    turret_yaw.empty_display_size = 0.22
    turret_yaw.location = (0,0,0.82)
    col.objects.link(turret_yaw)
    set_parent(turret_yaw, root)

    yaw_ring = add_cylinder("YawRing", radius=0.40, depth=0.08, vertices=12, location=(0,0,0.82), collection=col)
    assign_material(yaw_ring, mats["brown"])
    set_parent(yaw_ring, turret_yaw)
    yaw_meshes.append(yaw_ring)

    turret_hull = add_cube("TurretHull", size=(0.72, 0.80, 0.34), location=(0,0.02,1.02), collection=col)
    apply_bevel(turret_hull, width=0.018, segments=2)
    assign_material(turret_hull, mats["wheat"])
    set_parent(turret_hull, turret_yaw)
    yaw_meshes.append(turret_hull)

    cheek_l = add_cube("HullCheekL", size=(0.16, 0.56, 0.22), location=(-0.32,0.03,1.00), collection=col)
    apply_bevel(cheek_l, width=0.010, segments=2)
    assign_material(cheek_l, mats["brown"])
    set_parent(cheek_l, turret_yaw)
    yaw_meshes.append(cheek_l)

    cheek_r = add_cube("HullCheekR", size=(0.16, 0.56, 0.22), location=(0.32,0.03,1.00), collection=col)
    apply_bevel(cheek_r, width=0.010, segments=2)
    assign_material(cheek_r, mats["brown"])
    set_parent(cheek_r, turret_yaw)
    yaw_meshes.append(cheek_r)

    rear_counter = add_cube("RearCounterweight", size=(0.40, 0.22, 0.18), location=(0,0.42,1.01), collection=col)
    apply_bevel(rear_counter, width=0.010, segments=2)
    assign_material(rear_counter, mats["brown"])
    set_parent(rear_counter, turret_yaw)
    yaw_meshes.append(rear_counter)

    barrel_block = add_cube("BarrelBlock", size=(0.50, 0.22, 0.16), location=(0,-0.42,1.00), collection=col)
    apply_bevel(barrel_block, width=0.010, segments=2)
    assign_material(barrel_block, mats["black"])
    set_parent(barrel_block, turret_yaw)
    yaw_meshes.append(barrel_block)

    # Twin barrels
    for side, x in (("L", -0.15), ("R", 0.15)):
        # Shortened and pulled back so the full turret remains inside a 2m x 2m footprint.
        shroud = add_cylinder(f"BarrelShroud_{side}", radius=0.070, depth=0.58, vertices=10, location=(x,-0.67,1.00), rotation=(math.radians(90),0,0), collection=col)
        assign_material(shroud, mats["wheat"])
        set_parent(shroud, turret_yaw)
        yaw_meshes.append(shroud)

        barrel = add_cylinder(f"BarrelInner_{side}", radius=0.038, depth=0.70, vertices=10, location=(x,-0.72,1.00), rotation=(math.radians(90),0,0), collection=col)
        assign_material(barrel, mats["black"])
        set_parent(barrel, turret_yaw)
        yaw_meshes.append(barrel)

        muzzle = add_cylinder(f"MuzzleRing_{side}", radius=0.055, depth=0.06, vertices=10, location=(x,-1.07,1.00), rotation=(math.radians(90),0,0), collection=col)
        assign_material(muzzle, mats["brown"])
        set_parent(muzzle, turret_yaw)
        yaw_meshes.append(muzzle)

    bridge = add_cube("BarrelBridge", size=(0.40,0.10,0.10), location=(0,-0.70,1.08), collection=col)
    apply_bevel(bridge, width=0.008, segments=2)
    assign_material(bridge, mats["black"])
    set_parent(bridge, turret_yaw)
    yaw_meshes.append(bridge)

    # Sensor stack
    # Radar is deliberately offset to the left side of the turret roof.
    # This leaves a clean silhouette gap to the thinner right-side antenna.
    radar_stem = add_cylinder(
        "RadarStem", radius=0.050, depth=0.18, vertices=10,
        location=(-0.16, 0.08, 1.26), collection=col
    )
    assign_material(radar_stem, mats["brown"])
    set_parent(radar_stem, turret_yaw)
    yaw_meshes.append(radar_stem)

    radar_base = add_cylinder(
        "RadarBase", radius=0.12, depth=0.05, vertices=12,
        location=(-0.16, 0.08, 1.36), collection=col
    )
    assign_material(radar_base, mats["brown"])
    set_parent(radar_base, turret_yaw)
    yaw_meshes.append(radar_base)

    # The dish is seated into its base, rather than floating above it.
    radar_dish = make_radar_dish(
        "RadarDish", radius=0.26, depth_scale=0.42,
        location=(-0.16, 0.08, 1.425), collection=col
    )
    assign_material(radar_dish, mats["wheat"])
    set_parent(radar_dish, turret_yaw)
    radar_dish.rotation_euler = (math.radians(-12), 0.0, math.radians(8))
    yaw_meshes.append(radar_dish)

    radar_sensor = add_icosphere(
        "RadarSensorCore", radius=0.040, subdivisions=1,
        location=(-0.16, 0.08, 1.43), collection=col
    )
    assign_material(radar_sensor, mats["black"])
    set_parent(radar_sensor, turret_yaw)
    yaw_meshes.append(radar_sensor)

    # Thin right-rear communication antenna.  The rod slightly overlaps its base
    # and tip so the audit catches no floating parts, but the overlap is hidden.
    antenna_base = add_cube(
        "AntennaBase", size=(0.055, 0.055, 0.055),
        location=(0.24, 0.18, 1.18), collection=col
    )
    apply_bevel(antenna_base, width=0.004, segments=1)
    assign_material(antenna_base, mats["black"])
    set_parent(antenna_base, turret_yaw)
    yaw_meshes.append(antenna_base)

    antenna_rod = add_cylinder(
        "AntennaRod", radius=0.010, depth=0.54, vertices=8,
        location=(0.24, 0.18, 1.476), collection=col
    )
    assign_material(antenna_rod, mats["black"])
    set_parent(antenna_rod, turret_yaw)
    yaw_meshes.append(antenna_rod)

    antenna_tip = add_icosphere(
        "AntennaTip", radius=0.022, subdivisions=1,
        location=(0.24, 0.18, 1.766), collection=col
    )
    assign_material(antenna_tip, mats["black"])
    set_parent(antenna_tip, turret_yaw)
    yaw_meshes.append(antenna_tip)

    # cosmetic smoothing
    for obj in fixed_meshes + yaw_meshes:
        if obj.type == 'MESH':
            shade_auto(obj)

    meshes = fixed_meshes + yaw_meshes

    # Audits
    validate_hierarchy(root, turret_yaw, fixed_meshes, yaw_meshes)
    validate_bounds(meshes)
    validate_attachments([
        (base_core, base_skirt),
        (base_ring, base_core),
        (fixed_column, base_ring),
        (yaw_ring, fixed_column),
        (turret_hull, yaw_ring),
        (cheek_l, turret_hull),
        (cheek_r, turret_hull),
        (rear_counter, turret_hull),
        (barrel_block, turret_hull),
        # BarrelBridge is a cross-brace mounted on the two barrel shrouds.
        # It is intentionally forward of BarrelBlock, so do not audit it against BarrelBlock.
        (bridge, yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_L')]),
        (bridge, yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_R')]),
        (yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_L')], barrel_block),
        (yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_R')], barrel_block),
        (yaw_meshes[[o.name for o in yaw_meshes].index('BarrelInner_L')], yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_L')]),
        (yaw_meshes[[o.name for o in yaw_meshes].index('BarrelInner_R')], yaw_meshes[[o.name for o in yaw_meshes].index('BarrelShroud_R')]),
        (yaw_meshes[[o.name for o in yaw_meshes].index('MuzzleRing_L')], yaw_meshes[[o.name for o in yaw_meshes].index('BarrelInner_L')]),
        (yaw_meshes[[o.name for o in yaw_meshes].index('MuzzleRing_R')], yaw_meshes[[o.name for o in yaw_meshes].index('BarrelInner_R')]),
        (radar_stem, turret_hull),
        (radar_base, radar_stem),
        (radar_dish, radar_base),
        (radar_sensor, radar_dish),
        (antenna_base, turret_hull),
        (antenna_rod, antenna_base),
        (antenna_tip, antenna_rod),
    ])
    validate_surface_audit(meshes)

    return root, meshes


def main():
    out_dir, skip_preview = parse_args()
    os.makedirs(out_dir, exist_ok=True)

    root, meshes = build_turret()

    glb_path = os.path.join(out_dir, f"{ASSET_NAME}.glb")
    export_glb(glb_path)
    print(f"GENERATED: {glb_path}")

    if not skip_preview:
        setup_preview_camera_and_lights(root)
        preview_path = os.path.join(out_dir, f"{ASSET_NAME}_preview.png")
        render_preview(preview_path)
        print(f"PREVIEW: {preview_path}")


if __name__ == "__main__":
    main()
