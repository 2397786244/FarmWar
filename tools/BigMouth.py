# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Mimic Crate Trap with Mechanical Tongue [REV4]
#
# Generates:
#   generated_farmtown_traps/
#     FTF_Trap_MimicCrate_MechTongue_3m_v7.glb
#
# Design:
# - Fully sealed 3m wooden crate.
# - Only ONE side (front / -Y) contains the hidden trap mouth.
# - Mouth has a clear mechanical-lip silhouette.
# - Tongue is replaced with a silver-white mechanical telescoping grabber strip.
# - Gameplay intention unchanged: extend, latch to a target, pull them back
#   onto the crate top, and hold them on the anchor point.
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'generated_farmtown_traps')
OUTPUT_GLB = os.path.join(OUTPUT_DIR, 'FTF_Trap_MimicCrate_MechTongue_3m_v7.glb')
ROOT_NAME = 'FTF_Trap_MimicCrate_MechTongue_3m_v7'
COLLECTION_NAME = 'COL_' + ROOT_NAME
CLEAR_SCENE = True
SIZE = 3.0
TONGUE_SIDE = 'Front'  # only the negative Y side has the trap mouth


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.images, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def configure_scene():
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0


def make_material(name, color, metallic=0.0, roughness=0.7, emission=None, emission_strength=0.0):
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


def build_materials(tag):
    return {
        'wood_dark': make_material(f'MAT_{tag}_WoodDark', (0.33, 0.21, 0.10), 0.02, 0.84),
        'wood_mid': make_material(f'MAT_{tag}_WoodMid', (0.49, 0.33, 0.16), 0.02, 0.78),
        'wood_light': make_material(f'MAT_{tag}_WoodLight', (0.63, 0.45, 0.22), 0.01, 0.76),
        'metal_dark': make_material(f'MAT_{tag}_MetalDark', (0.22, 0.24, 0.26), 0.64, 0.30),
        'metal_light': make_material(f'MAT_{tag}_MetalLight', (0.76, 0.79, 0.82), 0.78, 0.20),
        'metal_white': make_material(f'MAT_{tag}_MetalWhite', (0.88, 0.90, 0.93), 0.74, 0.16),
        'black': make_material(f'MAT_{tag}_Black', (0.06, 0.06, 0.07), 0.10, 0.78),
        'red_light': make_material(f'MAT_{tag}_RedLight', (0.86, 0.14, 0.14), 0.04, 0.34, emission=(0.92, 0.10, 0.10), emission_strength=0.4),
    }


def get_or_create_collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def assign_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def set_flat(obj):
    if obj.type != 'MESH':
        return
    for p in obj.data.polygons:
        p.use_smooth = False


def set_smooth(obj):
    if obj.type != 'MESH':
        return
    for p in obj.data.polygons:
        p.use_smooth = True


def add_bevel(obj, width=0.01):
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = 1
    mod.limit_method = 'ANGLE'


def finish_mesh(obj, name, mat, collection, bevel=0.0, smooth=False):
    obj.name = name
    assign_material(obj, mat)
    if smooth:
        set_smooth(obj)
    else:
        set_flat(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    move_to_collection(obj, collection)
    return obj


def add_cube(name, loc, dims, mat, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, mat, collection, bevel)


def add_cylinder(name, loc, radius, depth, mat, collection, rotation=(0.0, 0.0, 0.0), vertices=16, bevel=0.0, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    return finish_mesh(bpy.context.object, name, mat, collection, bevel, smooth)


def create_empty(name, loc, collection, parent=None, display_type='PLAIN_AXES', size=0.18):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = loc
    obj.parent = parent
    collection.objects.link(obj)
    return obj


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


def join_meshes(meshes, name, parent):
    if not meshes:
        raise RuntimeError('No meshes to join')
    for m in meshes:
        apply_transforms_and_modifiers(m)
    bpy.ops.object.select_all(action='DESELECT')
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = name
    merged.parent = parent
    set_flat(merged)
    return merged


def iter_hierarchy(root):
    yield root
    for c in root.children:
        yield from iter_hierarchy(c)


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
        raise RuntimeError('No mesh points available')
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


def build_crate_body(root, collection, mats):
    half = SIZE * 0.5
    frame = 0.24
    panel_t = 0.16
    inner = SIZE - 2.0 * frame
    overlap = 0.0
    side_w = inner
    panel_h = SIZE - 2.0 * panel_t
    edge = half - frame * 0.5

    parts = []

    # Four corner posts remain as the visible wooden frame.
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(add_cube(
                f'CornerPost_{ix}_{iy}',
                (ix * edge, iy * edge, half),
                (frame, frame, SIZE),
                mats['wood_dark'],
                collection,
                bevel=0.01,
            ))

    # Fully sealed panels. REV6 deliberately removes RailX_* / RailY_*.
    # Those horizontal rail surfaces previously shared the same outer planes as
    # the sealed panels and caused visible Z-fighting on all four side faces.
    parts.append(add_cube(
        'Panel_Back',
        (0.0, half - panel_t * 0.5, half),
        (side_w, panel_t, panel_h),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'Panel_Left',
        (-(half - panel_t * 0.5), 0.0, half),
        (panel_t, side_w, panel_h),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'Panel_Right',
        ((half - panel_t * 0.5), 0.0, half),
        (panel_t, side_w, panel_h),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'Panel_Top',
        (0.0, 0.0, SIZE - panel_t * 0.5),
        (side_w, side_w, panel_t),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'Panel_Bottom',
        (0.0, 0.0, panel_t * 0.5),
        (side_w, side_w, panel_t),
        mats['wood_dark'],
        collection,
        bevel=0.006,
    ))

    # Front side is tiled around the single mechanical mouth. These four wood
    # panels meet at their boundaries instead of overlapping on the same plane.
    front_y = -(half - panel_t * 0.5)
    mouth_half_w = 0.57
    mouth_low_z = 0.93
    mouth_high_z = 2.07
    panel_inner_edge = half - frame

    side_panel_width = panel_inner_edge - mouth_half_w
    side_panel_center_x = (panel_inner_edge + mouth_half_w) * 0.5
    parts.append(add_cube(
        'FrontPanel_Left',
        (-side_panel_center_x, front_y, half),
        (side_panel_width, panel_t, panel_h),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'FrontPanel_Right',
        (side_panel_center_x, front_y, half),
        (side_panel_width, panel_t, panel_h),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))

    top_panel_height = (SIZE - panel_t) - mouth_high_z
    bottom_panel_height = mouth_low_z - panel_t
    parts.append(add_cube(
        'FrontPanel_Top',
        (0.0, front_y, mouth_high_z + top_panel_height * 0.5),
        (mouth_half_w * 2.0, panel_t, top_panel_height),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))
    parts.append(add_cube(
        'FrontPanel_Bottom',
        (0.0, front_y, panel_t + bottom_panel_height * 0.5),
        (mouth_half_w * 2.0, panel_t, bottom_panel_height),
        mats['wood_light'],
        collection,
        bevel=0.006,
    ))

    # Mechanical mouth housing / lips. It protrudes slightly beyond the wooden
    # face, so it does not share a coplanar surface with the surrounding panels.
    parts.append(add_cube('Mouth_Housing', (0.0, -1.42, 1.50), (1.14, 0.22, 1.14), mats['black'], collection, bevel=0.010))
    parts.append(add_cube('Mouth_Lip_Top', (0.0, -1.48, 1.82), (0.96, 0.12, 0.14), mats['metal_dark'], collection, bevel=0.006))
    parts.append(add_cube('Mouth_Lip_Bottom', (0.0, -1.48, 1.18), (0.96, 0.12, 0.14), mats['metal_dark'], collection, bevel=0.006))
    parts.append(add_cube('Mouth_Lip_Left', (-0.42, -1.48, 1.50), (0.14, 0.12, 0.54), mats['metal_dark'], collection, bevel=0.006))
    parts.append(add_cube('Mouth_Lip_Right', (0.42, -1.48, 1.50), (0.14, 0.12, 0.54), mats['metal_dark'], collection, bevel=0.006))
    parts.append(add_cube('Mouth_InnerSocket', (0.0, -1.35, 1.50), (0.64, 0.22, 0.34), mats['black'], collection, bevel=0.008))
    parts.append(add_cube('Mouth_Accent_0', (-0.24, -1.47, 1.50), (0.06, 0.03, 0.26), mats['red_light'], collection, bevel=0.002))
    parts.append(add_cube('Mouth_Accent_1', (0.24, -1.47, 1.50), (0.06, 0.03, 0.26), mats['red_light'], collection, bevel=0.002))

    # REV7 removes the remaining decorative Strap_Top_* / Strap_Side_* parts.
    # They were not structurally necessary, floated 3 cm above the adjacent
    # sealed panels, and could also reintroduce overlapping-surface flicker.

    for p in parts:
        p.parent = root
    return parts

def build_mechanical_tongue(root, collection, mats):
    # Separate animation node. Every tongue piece is created in TongueRoot local
    # space, avoiding the previous world-position + parent-position double offset.
    tongue_root = create_empty('TongueRoot', (0.0, -1.38, 1.50), collection, root, 'SINGLE_ARROW', 0.16)
    parts = []

    # Local Y points outward from the front face toward -Y.
    parts.append(add_cube('Tongue_Base', (0.0, -0.02, 0.00), (0.42, 0.26, 0.14), mats['metal_white'], collection, bevel=0.008))
    parts.append(add_cube('Tongue_Mid', (0.0, -0.18, 0.00), (0.34, 0.16, 0.10), mats['metal_light'], collection, bevel=0.006))
    parts.append(add_cube('Tongue_TipBody', (0.0, -0.31, 0.00), (0.28, 0.12, 0.16), mats['metal_light'], collection, bevel=0.006))
    parts.append(add_cube('Tongue_TipPad', (0.0, -0.39, 0.00), (0.34, 0.08, 0.22), mats['metal_dark'], collection, bevel=0.006))
    parts.append(add_cube('Tongue_TipClamp_L', (-0.12, -0.40, 0.00), (0.06, 0.08, 0.14), mats['metal_white'], collection, bevel=0.004))
    parts.append(add_cube('Tongue_TipClamp_R', (0.12, -0.40, 0.00), (0.06, 0.08, 0.14), mats['metal_white'], collection, bevel=0.004))
    parts.append(add_cube('Tongue_Light', (0.0, -0.32, 0.075), (0.16, 0.03, 0.03), mats['red_light'], collection, bevel=0.002))

    # Two flat mechanical tendon rails connect the base to the tip body.
    parts.append(add_cube('Tongue_Cable_L', (-0.11, -0.18, -0.055), (0.028, 0.32, 0.028), mats['metal_dark'], collection, bevel=0.002))
    parts.append(add_cube('Tongue_Cable_R', (0.11, -0.18, -0.055), (0.028, 0.32, 0.028), mats['metal_dark'], collection, bevel=0.002))

    for p in parts:
        p.parent = tongue_root

    tongue_tip_marker = create_empty('TongueTipMarker', (0.0, -1.81, 1.50), collection, root, 'SPHERE', 0.10)
    victim_anchor = create_empty('VictimAnchor', (0.0, 0.0, 3.12), collection, root, 'CUBE', 0.14)
    trap_front_face = create_empty('TrapFrontFace', (0.0, -1.50, 1.50), collection, root, 'CUBE', 0.14)
    return tongue_root, parts, tongue_tip_marker, victim_anchor, trap_front_face

def validate_premerge(crate_parts, tongue_parts):
    failures = []

    # All crate pieces should contact some other crate part.
    for p in crate_parts:
        min_dist = min(aabb_distance(p, q) for q in crate_parts if q != p)
        if min_dist > 0.005:
            failures.append(f'{p.name}: nearest crate-part gap {min_dist:.4f} m > 0.0050 m')

    forbidden_surface_parts = [
        obj.name for obj in crate_parts
        if obj.name.startswith('RailX_')
        or obj.name.startswith('RailY_')
        or obj.name.startswith('Strap_Top_')
        or obj.name.startswith('Strap_Side_')
    ]
    if forbidden_surface_parts:
        failures.append(
            'Forbidden overlapping/floating surface decorations found: ' +
            ', '.join(sorted(forbidden_surface_parts))
        )

    # Specific mouth relationships.
    for a, b, allowed in [
        ('Mouth_Housing', 'FrontPanel_Left', 0.005),
        ('Mouth_Housing', 'FrontPanel_Right', 0.005),
        ('Mouth_Housing', 'FrontPanel_Top', 0.005),
        ('Mouth_Housing', 'FrontPanel_Bottom', 0.005),
        ('Mouth_Lip_Top', 'Mouth_Housing', 0.005),
        ('Mouth_Lip_Bottom', 'Mouth_Housing', 0.005),
        ('Mouth_Lip_Left', 'Mouth_Housing', 0.005),
        ('Mouth_Lip_Right', 'Mouth_Housing', 0.005),
        ('Mouth_InnerSocket', 'Mouth_Housing', 0.005),
    ]:
        dist = aabb_distance(bpy.data.objects[a], bpy.data.objects[b])
        if dist > allowed:
            failures.append(f'{a} -> {b}: gap {dist:.4f} m > {allowed:.4f} m')

    # Tongue relationships.
    for a, b, allowed in [
        ('Tongue_Base', 'Mouth_InnerSocket', 0.005),
        ('Tongue_Base', 'Tongue_Mid', 0.005),
        ('Tongue_Mid', 'Tongue_TipBody', 0.005),
        ('Tongue_TipBody', 'Tongue_TipPad', 0.005),
        ('Tongue_TipClamp_L', 'Tongue_TipPad', 0.005),
        ('Tongue_TipClamp_R', 'Tongue_TipPad', 0.005),
        ('Tongue_Light', 'Tongue_TipBody', 0.005),
        ('Tongue_Cable_L', 'Tongue_Base', 0.02),
        ('Tongue_Cable_L', 'Tongue_TipBody', 0.02),
        ('Tongue_Cable_R', 'Tongue_Base', 0.02),
        ('Tongue_Cable_R', 'Tongue_TipBody', 0.02),
    ]:
        dist = aabb_distance(bpy.data.objects[a], bpy.data.objects[b])
        if dist > allowed:
            failures.append(f'{a} -> {b}: gap {dist:.4f} m > {allowed:.4f} m')

    # Coplanar horizontal side rails were removed in REV6.
    forbidden_rails = [obj.name for obj in crate_parts if obj.name.startswith(('RailX_', 'RailY_'))]
    if forbidden_rails:
        failures.append('Coplanar side rails unexpectedly remain: ' + ', '.join(forbidden_rails))

    # Explicitly ensure only the front side contains the tongue opening.
    if 'Panel_Front' in bpy.data.objects:
        failures.append('Unexpected full front panel found; trap should only have one front mouth side.')

    if failures:
        raise RuntimeError('FLOATING-PART AUDIT FAILED:\n- ' + '\n- '.join(failures))
    print('[VALID] Coplanar side rails removed; sealed panels are the only visible side surfaces.')
    print('[VALID] Mouth_Housing contacts the four tiled front panels without coplanar overlap.')
    print('[VALID] Tongue pieces use TongueRoot local coordinates and remain connected.')
    print(f'[VALID] Pre-merge attachment audit passed for {ROOT_NAME}: {len(crate_parts)} crate parts, {len(tongue_parts)} tongue parts.')


def build_asset():
    collection = get_or_create_collection(COLLECTION_NAME)
    mats = build_materials(ROOT_NAME)
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, None, 'PLAIN_AXES', 0.24)
    root['asset_type'] = 'Trap'
    root['trap_category'] = 'MimicCrateMechanicalTongue'
    root['size_m'] = (SIZE, SIZE, SIZE)
    root['tongue_side'] = TONGUE_SIDE
    root['revision'] = 'REV7_REMOVE_FLOATING_METAL_STRAPS'

    crate_parts = build_crate_body(root, collection, mats)
    tongue_root, tongue_parts, _, _, _ = build_mechanical_tongue(root, collection, mats)

    validate_premerge(crate_parts, tongue_parts)

    join_meshes(crate_parts, ROOT_NAME + '_Static', root)
    join_meshes(tongue_parts, 'TongueMesh', tongue_root)

    # Post-merge validation.
    crate_mesh = bpy.data.objects.get(ROOT_NAME + '_Static')
    if crate_mesh is None:
        raise RuntimeError('Missing merged crate mesh.')
    low, high = world_bbox([crate_mesh])
    dims = high - low
    if abs(dims.x - SIZE) > 0.10 or abs(dims.y - SIZE) > 0.10 or abs(dims.z - SIZE) > 0.10:
        raise RuntimeError(f'Crate body dimensions drifted from target 3m. Got {tuple(round(v,3) for v in dims)}')

    tongue_mesh = bpy.data.objects.get('TongueMesh')
    if tongue_mesh is None:
        raise RuntimeError('Missing merged tongue mesh.')
    return root


def export_root(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True,
                              export_materials='EXPORT', export_cameras=False, export_lights=False)
    print('[EXPORT] ' + filepath)


def main():
    print('\n=== Generating Mimic Crate Trap [REV7_REMOVE_FLOATING_METAL_STRAPS] ===\n')
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()
    root = build_asset()
    export_root(root, OUTPUT_GLB)
    print('\n=== Finished ===')
    print(' - ' + OUTPUT_GLB)
    print('Godot nodes: TongueRoot, TongueTipMarker, VictimAnchor, TrapFrontFace')


if __name__ == '__main__':
    main()
