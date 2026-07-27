# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Wooden Slat Crates (2m and 3m)
#
# Generates:
#   generated_farmtown_props/
#     FTF_Prop_WoodenCrate_Slat_2m_v1.glb
#     FTF_Prop_WoodenCrate_Slat_3m_v1.glb
#
# Each crate is a separate root with a merged static mesh. All loose parts are
# validated before merge.
# -----------------------------------------------------------------------------

import bpy
import os
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'generated_farmtown_props')
CLEAR_SCENE = True

ASSETS = [
    {"size": 2.0, "root_name": "FTF_Prop_WoodenCrate_Slat_2m_v1", "output": "FTF_Prop_WoodenCrate_Slat_2m_v1.glb", "revision": "REV1_2M"},
    {"size": 3.0, "root_name": "FTF_Prop_WoodenCrate_Slat_3m_v1", "output": "FTF_Prop_WoodenCrate_Slat_3m_v1.glb", "revision": "REV1_3M"},
]


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.images, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def configure_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0


def make_material(name, color, metallic=0.0, roughness=0.7):
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
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    mat.diffuse_color = (*color, 1.0)
    return mat


def build_materials(tag):
    return {
        'wood_dark': make_material(f'MAT_{tag}_WoodDark', (0.34, 0.22, 0.10), 0.02, 0.82),
        'wood_mid': make_material(f'MAT_{tag}_WoodMid', (0.49, 0.33, 0.15), 0.02, 0.78),
        'wood_light': make_material(f'MAT_{tag}_WoodLight', (0.61, 0.43, 0.21), 0.01, 0.76),
        'metal': make_material(f'MAT_{tag}_Metal', (0.38, 0.39, 0.40), 0.55, 0.34),
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


def add_bevel(obj, width=0.01):
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = 1
    mod.limit_method = 'ANGLE'


def finish_mesh(obj, name, mat, collection, bevel=0.0):
    obj.name = name
    assign_material(obj, mat)
    set_flat(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    move_to_collection(obj, collection)
    return obj


def add_cube(name, loc, dims, mat, collection, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, mat, collection, bevel)


def create_empty(name, loc, collection, parent=None, display_type='PLAIN_AXES', size=0.2):
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


def build_crate(asset):
    size = asset['size']
    root_name = asset['root_name']
    collection = get_or_create_collection('COL_' + root_name)
    mats = build_materials(root_name)
    root = create_empty(root_name, (0.0, 0.0, 0.0), collection, None, 'PLAIN_AXES', max(0.20, size * 0.08))
    root['asset_type'] = 'Prop'
    root['prop_category'] = 'WoodenCrate'
    root['size_m'] = (size, size, size)
    root['revision'] = asset['revision']

    half = size * 0.5
    plank_t = max(0.10, size * 0.06)
    slat_t = max(0.07, size * 0.04)
    slat_w = max(0.18, size * 0.14)
    post_w = max(0.16, size * 0.09)
    edge_z = half - plank_t * 0.5
    edge_y = half - plank_t * 0.5
    edge_x = half - plank_t * 0.5

    parts = []

    # Corner posts
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(add_cube(f'CornerPost_{ix}_{iy}', (ix * (half - post_w * 0.5), iy * (half - post_w * 0.5), half), (post_w, post_w, size), mats['wood_dark'], collection, bevel=0.01))

    # Top and bottom outer rails
    for z in (plank_t * 0.5, size - plank_t * 0.5):
        for iy in (-1, 1):
            parts.append(add_cube(f'RailX_{"Top" if z>half else "Bottom"}_{iy}', (0.0, iy * edge_y, z), (size - 2 * post_w, plank_t, plank_t), mats['wood_mid'], collection, bevel=0.008))
        for ix in (-1, 1):
            parts.append(add_cube(f'RailY_{"Top" if z>half else "Bottom"}_{ix}', (ix * edge_x, 0.0, z), (plank_t, size - 2 * post_w, plank_t), mats['wood_mid'], collection, bevel=0.008))

    # Mid rails on four sides
    for iy in (-1, 1):
        parts.append(add_cube(f'MidRailX_{iy}', (0.0, iy * edge_y, half), (size - 2 * post_w, plank_t, plank_t), mats['wood_mid'], collection, bevel=0.008))
    for ix in (-1, 1):
        parts.append(add_cube(f'MidRailY_{ix}', (ix * edge_x, 0.0, half), (plank_t, size - 2 * post_w, plank_t), mats['wood_mid'], collection, bevel=0.008))

    # Slats: front/back
    x_positions = (-size * 0.25, 0.0, size * 0.25)
    z_positions = (size * 0.22, half, size * 0.78)
    for iy in (-1, 1):
        for i, x in enumerate(x_positions):
            parts.append(add_cube(f'FrontBackSlat_{iy}_{i}', (x, iy * edge_y, half), (slat_w, plank_t, size - 2 * plank_t), mats['wood_light'], collection, bevel=0.006))
        for i, z in enumerate(z_positions):
            parts.append(add_cube(f'FrontBackCross_{iy}_{i}', (0.0, iy * edge_y, z), (size - 2 * post_w, plank_t, slat_t), mats['wood_mid'], collection, bevel=0.006))

    # Slats: left/right
    y_positions = (-size * 0.25, 0.0, size * 0.25)
    for ix in (-1, 1):
        for i, y in enumerate(y_positions):
            parts.append(add_cube(f'LeftRightSlat_{ix}_{i}', (ix * edge_x, y, half), (plank_t, slat_w, size - 2 * plank_t), mats['wood_light'], collection, bevel=0.006))
        for i, z in enumerate(z_positions):
            parts.append(add_cube(f'LeftRightCross_{ix}_{i}', (ix * edge_x, 0.0, z), (plank_t, size - 2 * post_w, slat_t), mats['wood_mid'], collection, bevel=0.006))

    # Top slats
    top_z = size - plank_t * 0.5
    for i, y in enumerate(y_positions):
        parts.append(add_cube(f'TopSlat_{i}', (0.0, y, top_z), (size - 2 * post_w, slat_w, plank_t), mats['wood_light'], collection, bevel=0.006))

    # Bottom support slats
    bottom_z = plank_t * 0.5
    for i, y in enumerate((-size * 0.22, size * 0.22)):
        parts.append(add_cube(f'BottomSkid_{i}', (0.0, y, bottom_z), (size - 2 * post_w, slat_w, plank_t), mats['wood_dark'], collection, bevel=0.006))

    # Simple corner metal brackets
    bracket_len = post_w * 1.2
    bracket_t = max(0.04, plank_t * 0.35)
    for ix in (-1, 1):
        for iy in (-1, 1):
            parts.append(add_cube(f'BracketX_{ix}_{iy}', (ix * (half - bracket_len * 0.5), iy * edge_y, size - bracket_t * 0.5), (bracket_len, bracket_t, bracket_t), mats['metal'], collection, bevel=0.002))
            parts.append(add_cube(f'BracketY_{ix}_{iy}', (ix * edge_x, iy * (half - bracket_len * 0.5), size - bracket_t * 0.5), (bracket_t, bracket_len, bracket_t), mats['metal'], collection, bevel=0.002))

    for p in parts:
        p.parent = root

    # Pre-merge floating-part audit.
    failures = []
    for p in parts:
        if p.name.startswith('CornerPost'):
            continue
        # each part should touch at least one other part
        min_dist = min(aabb_distance(p, q) for q in parts if q != p)
        if min_dist > 0.005:
            failures.append(f'{p.name}: nearest-part gap {min_dist:.4f} m > allowed 0.0050 m')
    if failures:
        raise RuntimeError('FLOATING-PART AUDIT FAILED:\n- ' + '\n- '.join(failures))
    print(f'[VALID] Pre-merge attachment audit passed for {root_name}: {len(parts)} parts.')

    join_meshes(parts, root_name + '_Static', root)

    # Post-merge validation
    meshes = get_meshes_under(root)
    if len(meshes) != 1:
        raise RuntimeError(f'Expected one merged mesh for {root_name}.')
    low, high = world_bbox(meshes)
    dims = high - low
    if abs(dims.x - size) > 0.10 or abs(dims.y - size) > 0.10 or abs(dims.z - size) > 0.10:
        raise RuntimeError(f'Crate size drifted from target {size}m. Got {tuple(round(v,3) for v in dims)}')
    return root, os.path.join(OUTPUT_DIR, asset['output'])


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
    print('\n=== Generating Wooden Slat Crates [REV1_MULTI_SIZE] ===\n')
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()
    outputs = []
    for asset in ASSETS:
        root, out = build_crate(asset)
        export_root(root, out)
        outputs.append(out)
    print('\n=== Finished ===')
    for out in outputs:
        print(' - ' + out)


if __name__ == '__main__':
    main()
