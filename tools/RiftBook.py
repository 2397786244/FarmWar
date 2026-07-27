# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Riftbook (Mage Tool) [REV3]
#
# Generates:
#   generated_farmtown_tools/
#     FTF_Tool_Riftbook_Open_v3.glb
#
# DESIGN REVISION
# - Open magic book with pages/covers folding inward toward the center.
# - Included open angle about 60 degrees.
# - Purple and gold covers/details, white pages.
# - Red glowing gem attached FLAT onto the outer back cover skin.
# - Gold clasps fixed so they contact the covers.
# - Adds a floating magical rune hovering above the gutter between the pages.
# - Keeps GripPoint and SpellOrigin helper nodes.
# - Strict pre-merge floating-part audit on all structural parts; intentional
#   floating rune is validated separately as an intentional effect object.
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'generated_farmtown_tools')
OUTPUT_GLB = os.path.join(OUTPUT_DIR, 'FTF_Tool_Riftbook_Open_v5.glb')

ROOT_NAME = 'FTF_Tool_Riftbook_Open_v5'
STATIC_NAME = ROOT_NAME + '_Static'
RUNE_ROOT_NAME = 'FloatingRune'
RUNE_MESH_NAME = 'FloatingRuneMesh'
COLLECTION_NAME = 'COL_' + ROOT_NAME
SCRIPT_REVISION = 'REV5_TRUE_LOCAL_COORDS_AND_RUNE_CLEARANCE'

CLEAR_SCENE = True
INCLUDED_ANGLE_DEG = 60.0
HALF_ANGLE_DEG = INCLUDED_ANGLE_DEG * 0.5


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
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
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0


def make_material(name, color, metallic=0.0, roughness=0.6, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = emission_strength
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    mat.diffuse_color = (*color, 1.0)
    return mat


def build_materials():
    return {
        'purple_dark': make_material('MAT_RB3_PurpleDark', (0.23, 0.10, 0.36), metallic=0.20, roughness=0.58),
        'purple': make_material('MAT_RB3_Purple', (0.40, 0.18, 0.62), metallic=0.16, roughness=0.48),
        'gold': make_material('MAT_RB3_Gold', (0.83, 0.68, 0.24), metallic=0.78, roughness=0.26),
        'page_white': make_material('MAT_RB3_PageWhite', (0.92, 0.90, 0.84), metallic=0.02, roughness=0.82),
        'page_edge': make_material('MAT_RB3_PageEdge', (0.86, 0.84, 0.77), metallic=0.01, roughness=0.88),
        'arcane_purple': make_material('MAT_RB3_ArcanePurple', (0.76, 0.60, 1.0), metallic=0.02, roughness=0.18, emission=(0.70, 0.45, 1.0), emission_strength=1.25),
        'gem_red': make_material('MAT_RB3_GemRed', (0.88, 0.16, 0.20), metallic=0.12, roughness=0.22, emission=(0.95, 0.12, 0.16), emission_strength=1.1),
    }


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


def set_flat(obj):
    if obj.type != 'MESH':
        return
    for poly in obj.data.polygons:
        poly.use_smooth = False


def set_smooth(obj):
    if obj.type != 'MESH':
        return
    for poly in obj.data.polygons:
        poly.use_smooth = True


def add_bevel(obj, width=0.0025):
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = 1
    mod.limit_method = 'ANGLE'


def finish_mesh(obj, name, material, collection, bevel=0.0, smooth=False):
    obj.name = name
    assign_material(obj, material)
    if smooth:
        set_smooth(obj)
    else:
        set_flat(obj)
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


def create_empty(name, location, collection, parent=None, display_type='PLAIN_AXES', size=0.04, rotation=(0.0, 0.0, 0.0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.rotation_euler = rotation
    obj.parent = parent
    collection.objects.link(obj)
    return obj


def add_local_cube(parent, name, local_location, dimensions, material, collection, bevel=0.0, local_rotation=(0.0, 0.0, 0.0), smooth=False):
    """Create a mesh using genuine parent-local coordinates.

    Do not set matrix_parent_inverse here: doing so would cancel the parent's
    transform and make the supplied local coordinates behave like world-space
    coordinates.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.parent = parent
    obj.location = local_location
    obj.rotation_euler = local_rotation
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel, smooth)


def add_local_cylinder(parent, name, local_location, radius, depth, material, collection, local_rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0, smooth=True):
    """Create a cylinder using genuine parent-local coordinates."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.parent = parent
    obj.location = local_location
    obj.rotation_euler = local_rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel, smooth)


def set_active(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_transforms_and_modifiers(obj):
    if obj.type != 'MESH':
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for mod in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError:
            pass


def join_meshes(meshes, new_name, parent):
    """Join meshes while preserving their evaluated world-space placement."""
    if not meshes:
        raise RuntimeError('No meshes to join.')

    # Detach each mesh from hinge/effect parents without moving it. This avoids
    # parent transforms being applied twice during Blender's join operation.
    for obj in meshes:
        world_matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world_matrix
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = new_name
    world_matrix = merged.matrix_world.copy()
    merged.parent = parent
    merged.matrix_world = world_matrix
    set_flat(merged)
    return merged


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under(root):
    return [o for o in iter_hierarchy(root) if o.type == 'MESH']


def world_bbox(objects):
    bpy.context.view_layer.update()
    pts = []
    for obj in objects:
        if obj.type != 'MESH':
            continue
        pts.extend(obj.matrix_world @ Vector(c) for c in obj.bound_box)
    if not pts:
        raise RuntimeError('No mesh points available for bounds calculation.')
    low = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    high = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return low, high


def aabb_distance(a, b):
    a_low, a_high = world_bbox([a])
    b_low, b_high = world_bbox([b])
    dx = max(0.0, b_low.x - a_high.x, a_low.x - b_high.x)
    dy = max(0.0, b_low.y - a_high.y, a_low.y - b_high.y)
    dz = max(0.0, b_low.z - a_high.z, a_low.z - b_high.z)
    return (dx * dx + dy * dy + dz * dz) ** 0.5


def build_book(root, collection, mats):
    structural_parts = []
    rune_parts = []

    # Central spine section, relatively low so book can be hand-held comfortably.
    structural_parts.append(add_cube('Spine_Core', (0.0, 0.0, 0.014), (0.038, 0.250, 0.028), mats['purple_dark'], collection, bevel=0.0025))
    structural_parts.append(add_cube('Spine_TopBand', (0.0, 0.0, 0.032), (0.028, 0.244, 0.008), mats['gold'], collection, bevel=0.0015))

    # Hinge empties. Positive/negative Y rotation chosen so OUTER edges rise and pages fold inward.
    left_hinge = create_empty('LeftHinge', (-0.008, 0.0, 0.014), collection, root, 'SINGLE_ARROW', 0.03, rotation=(0.0, math.radians(HALF_ANGLE_DEG), 0.0))
    right_hinge = create_empty('RightHinge', (0.008, 0.0, 0.014), collection, root, 'SINGLE_ARROW', 0.03, rotation=(0.0, math.radians(-HALF_ANGLE_DEG), 0.0))

    # Left half
    structural_parts.append(add_local_cube(left_hinge, 'Cover_Left', (-0.073, 0.0, 0.010), (0.148, 0.252, 0.026), mats['purple'], collection, bevel=0.0025))
    structural_parts.append(add_local_cube(left_hinge, 'Pages_Left_Core', (-0.071, 0.0, 0.030), (0.140, 0.232, 0.028), mats['page_edge'], collection, bevel=0.0018))
    structural_parts.append(add_local_cube(left_hinge, 'Pages_Left_Top', (-0.071, 0.0, 0.045), (0.136, 0.226, 0.006), mats['page_white'], collection, bevel=0.0010))
    structural_parts.append(add_local_cube(left_hinge, 'RunePlate_Left', (-0.071, 0.0, 0.0495), (0.088, 0.128, 0.003), mats['arcane_purple'], collection, bevel=0.0008))
    for suffix, x, y in [('LT', -0.146, 0.104), ('LB', -0.146, -0.104), ('RT', -0.008, 0.104), ('RB', -0.008, -0.104)]:
        structural_parts.append(add_local_cube(left_hinge, f'CornerTrim_{suffix}', (x, y, 0.022), (0.020, 0.024, 0.010), mats['gold'], collection, bevel=0.0008))
    structural_parts.append(add_local_cube(left_hinge, 'Clasp_Left_Outer', (-0.150, 0.0, 0.017), (0.012, 0.060, 0.016), mats['gold'], collection, bevel=0.0008))

    # Flat red gem attached to the OUTER back skin of the left cover.
    structural_parts.append(add_local_cylinder(left_hinge, 'BackGem_Base', (-0.090, 0.0, -0.002), 0.020, 0.006, mats['gold'], collection, local_rotation=(0.0, 0.0, 0.0), vertices=18, bevel=0.0008, smooth=True))
    structural_parts.append(add_local_cylinder(left_hinge, 'BackGem_Red', (-0.090, 0.0, -0.007), 0.013, 0.006, mats['gem_red'], collection, local_rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0008, smooth=True))

    # Right half
    structural_parts.append(add_local_cube(right_hinge, 'Cover_Right', (0.073, 0.0, 0.010), (0.148, 0.252, 0.026), mats['purple'], collection, bevel=0.0025))
    structural_parts.append(add_local_cube(right_hinge, 'Pages_Right_Core', (0.071, 0.0, 0.030), (0.140, 0.232, 0.028), mats['page_edge'], collection, bevel=0.0018))
    structural_parts.append(add_local_cube(right_hinge, 'Pages_Right_Top', (0.071, 0.0, 0.045), (0.136, 0.226, 0.006), mats['page_white'], collection, bevel=0.0010))
    structural_parts.append(add_local_cube(right_hinge, 'RunePlate_Right', (0.071, 0.0, 0.0495), (0.088, 0.128, 0.003), mats['arcane_purple'], collection, bevel=0.0008))
    for suffix, x, y in [('LT2', 0.008, 0.104), ('LB2', 0.008, -0.104), ('RT2', 0.146, 0.104), ('RB2', 0.146, -0.104)]:
        structural_parts.append(add_local_cube(right_hinge, f'CornerTrim_{suffix}', (x, y, 0.022), (0.020, 0.024, 0.010), mats['gold'], collection, bevel=0.0008))
    structural_parts.append(add_local_cube(right_hinge, 'Clasp_Right_Outer', (0.150, 0.0, 0.017), (0.012, 0.060, 0.016), mats['gold'], collection, bevel=0.0008))

    # Intentional hovering magical rune in the middle of the open book.
    rune_root = create_empty(RUNE_ROOT_NAME, (0.0, 0.0, 0.145), collection, root, 'SPHERE', 0.03)
    rune_parts.append(add_local_cylinder(rune_root, 'Rune_Ring', (0.0, 0.0, 0.0), 0.028, 0.004, mats['arcane_purple'], collection, vertices=24, bevel=0.0008, smooth=True))
    rune_parts.append(add_local_cube(rune_root, 'Rune_Bar_X', (0.0, 0.0, 0.0), (0.042, 0.004, 0.004), mats['arcane_purple'], collection, bevel=0.0004))
    rune_parts.append(add_local_cube(rune_root, 'Rune_Bar_Y', (0.0, 0.0, 0.0), (0.004, 0.042, 0.004), mats['arcane_purple'], collection, bevel=0.0004))
    rune_parts.append(add_local_cylinder(rune_root, 'Rune_Core', (0.0, 0.0, 0.001), 0.010, 0.006, mats['gem_red'], collection, vertices=18, bevel=0.0006, smooth=True))

    # Structural pieces remain under their hinge empties until validation/join.
    # Rune pieces remain under rune_root.
    return structural_parts, rune_root, rune_parts, left_hinge, right_hinge


def validate_premerge(structural_parts, rune_root, rune_parts):
    failures = []

    # Every structural part must contact at least one other structural part.
    for p in structural_parts:
        min_dist = min(aabb_distance(p, q) for q in structural_parts if q != p)
        if min_dist > 0.005:
            failures.append(f'{p.name}: nearest-part gap {min_dist:.4f} m > allowed 0.0050 m')

    # Explicit critical attachment checks.
    critical_pairs = [
        ('Spine_Core', 'Cover_Left', 0.005),
        ('Spine_Core', 'Cover_Right', 0.005),
        ('Spine_Core', 'Spine_TopBand', 0.005),
        ('Cover_Left', 'Pages_Left_Core', 0.005),
        ('Cover_Right', 'Pages_Right_Core', 0.005),
        ('Pages_Left_Core', 'Pages_Left_Top', 0.005),
        ('Pages_Right_Core', 'Pages_Right_Top', 0.005),
        ('Pages_Left_Top', 'RunePlate_Left', 0.005),
        ('Pages_Right_Top', 'RunePlate_Right', 0.005),
        ('Cover_Left', 'Clasp_Left_Outer', 0.005),
        ('Cover_Right', 'Clasp_Right_Outer', 0.005),
        ('Cover_Left', 'BackGem_Base', 0.005),
        ('BackGem_Base', 'BackGem_Red', 0.005),
    ]
    for a_name, b_name, allowed in critical_pairs:
        a = bpy.data.objects[a_name]
        b = bpy.data.objects[b_name]
        dist = aabb_distance(a, b)
        if dist > allowed:
            failures.append(f'{a_name} -> {b_name}: gap {dist:.4f} m > allowed {allowed:.4f} m')

    # Intentional floating rune validation. Compare against the actual evaluated
    # page height instead of a fixed magic number, because the page blocks are
    # tilted inward by the hinge transforms.
    rune_low, rune_high = world_bbox(rune_parts)
    rune_center = (rune_low + rune_high) * 0.5
    if abs(rune_center.x) > 0.02 or abs(rune_center.y) > 0.02:
        failures.append('Floating rune is not centered over the middle of the open book.')

    _, left_page_high = world_bbox([bpy.data.objects['Pages_Left_Top']])
    _, right_page_high = world_bbox([bpy.data.objects['Pages_Right_Top']])
    required_rune_low_z = max(left_page_high.z, right_page_high.z) + 0.015
    if rune_low.z < required_rune_low_z:
        failures.append(
            'Floating rune intersects or sits too close to the page area: '
            f'rune_low_z={rune_low.z:.4f}, required>={required_rune_low_z:.4f}'
        )

    if failures:
        raise RuntimeError('FLOATING-PART AUDIT FAILED:\n- ' + '\n- '.join(failures))
    print(f'[VALID] Pre-merge structural audit passed: {len(structural_parts)} structural parts, {len(rune_parts)} intentional-rune parts.')


def build_asset():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    mats = build_materials()
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, None, 'PLAIN_AXES', 0.05)
    root['asset_type'] = 'Tool'
    root['tool_category'] = 'Riftbook'
    root['handheld_orientation'] = 'Open_Up_60Deg_InwardFold'
    root['color_scheme'] = 'Purple_Gold_White_RedGem'
    root['revision'] = SCRIPT_REVISION
    root['included_open_angle_deg'] = INCLUDED_ANGLE_DEG

    structural_parts, rune_root, rune_parts, left_hinge, right_hinge = build_book(root, collection, mats)
    validate_premerge(structural_parts, rune_root, rune_parts)

    join_meshes(structural_parts, STATIC_NAME, root)
    join_meshes(rune_parts, RUNE_MESH_NAME, rune_root)

    # Remove now-unused hinge helper empties.
    bpy.data.objects.remove(left_hinge, do_unlink=True)
    bpy.data.objects.remove(right_hinge, do_unlink=True)

    grip_point = create_empty('GripPoint', (0.0, 0.0, -0.010), collection, root, 'CUBE', 0.025)
    grip_point['attach_role'] = 'PrimaryHandGrip'
    spell_origin = create_empty('SpellOrigin', (0.0, 0.0, 0.115), collection, root, 'SPHERE', 0.03)
    spell_origin['effect_role'] = 'MagicCastOrigin'

    meshes = get_meshes_under(root)
    mesh_names = sorted(m.name for m in meshes)
    required = {STATIC_NAME, RUNE_MESH_NAME}
    if not required.issubset(set(mesh_names)):
        raise RuntimeError('Expected merged static mesh and floating rune mesh to exist.')

    low, high = world_bbox(meshes)
    dims = high - low
    if dims.x > 0.40 or dims.y > 0.32 or dims.z > 0.20:
        raise RuntimeError(f'Riftbook exceeds intended handheld size. Got {tuple(round(v, 3) for v in dims)}')

    forbidden = [o.name for o in bpy.context.scene.objects if o.type in {'CAMERA', 'LIGHT'}]
    if forbidden:
        raise RuntimeError('Cameras/lights must not remain: ' + ', '.join(forbidden))

    return root


def export_root(root):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
    )
    print('[EXPORT] ' + OUTPUT_GLB)


def main():
    print(f'\n=== Generating Riftbook [{SCRIPT_REVISION}] ===\n')
    root = build_asset()
    export_root(root)
    print('\n=== Finished ===')
    print('Godot nodes:')
    print(' - GripPoint: attach to mage hand.')
    print(' - SpellOrigin: spell particle / effect spawn point.')
    print(' - FloatingRune: intentional hovering rune over the open book center.')
    print(' - Book pages fold inward toward the center with an included angle of 60 degrees.')
    print(' - Parent-local coordinates are applied correctly; rune clearance is checked against actual tilted-page height.')


if __name__ == '__main__':
    main()
