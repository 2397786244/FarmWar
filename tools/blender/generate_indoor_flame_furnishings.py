"""Generate a tabletop candle and a standing indoor torch with named Glow nodes.

Both assets are deliberately self-contained GLBs.  Each root includes a child
empty named ``Glow`` which parents a small emissive glow orb, so game scenes can
find the visual flame reliably and attach a real-time light later if desired.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "facilities", "interior")


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate indoor candle and torch GLBs.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview-dir", default="/tmp")
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def make_material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = (*color, 1.0)
    bsdf = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = (*emission, 1.0)
        emission_strength = bsdf.inputs.get("Emission Strength")
        if emission_strength is not None:
            emission_strength.default_value = strength
    return result


def make_empty(name, location, parent):
    result = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(result)
    result.empty_display_type = "SPHERE"
    result.empty_display_size = 0.04
    result.location = location
    result.parent = parent
    return result


def finish(obj, name, surface, parent, bevel=0.0):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.data.materials.append(surface)
    obj.parent = parent
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    return obj


def cylinder(name, location, radius, depth, surface, parent, bevel=0.0, vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    return finish(bpy.context.object, name, surface, parent, bevel)


def cone(name, location, radius_bottom, radius_top, depth, surface, parent, bevel=0.0, vertices=48):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    return finish(bpy.context.object, name, surface, parent, bevel)


def torus(name, location, major_radius, minor_radius, surface, parent):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=48,
        minor_segments=12,
        location=location,
    )
    return finish(bpy.context.object, name, surface, parent)


def glow_orb(glow_root, radius, surface):
    # A restrained spherical point of light replaces a literal flame.  Bloom
    # in the runtime renderer can enlarge this visually without changing its
    # small physical footprint.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=(0.0, 0.0, 0.0))
    return finish(bpy.context.object, "GlowOrb", surface, glow_root)


def build_candle(materials):
    root = bpy.data.objects.new("TableCandle", None)
    bpy.context.collection.objects.link(root)

    cylinder("Saucer", (0.0, 0.0, 0.018), 0.135, 0.036, materials["brass"], root, bevel=0.009)
    cylinder("WaxBody", (0.0, 0.0, 0.148), 0.076, 0.245, materials["wax"], root, bevel=0.014)
    # A wax rim and slightly recessed top prevent the candle from reading as a plain white tube.
    torus("WaxRim", (0.0, 0.0, 0.270), 0.060, 0.013, materials["wax"], root)
    cylinder("Wick", (0.0, 0.0, 0.292), 0.009, 0.052, materials["wick"], root, bevel=0.002, vertices=16)
    glow_root = make_empty("Glow", (0.0, 0.0, 0.314), root)
    glow_orb(glow_root, 0.018, materials["glow"])
    return root


def build_torch(materials):
    root = bpy.data.objects.new("StandingTorch", None)
    bpy.context.collection.objects.link(root)

    cylinder("Base", (0.0, 0.0, 0.040), 0.285, 0.080, materials["metal"], root, bevel=0.020)
    cylinder("BaseCollar", (0.0, 0.0, 0.098), 0.098, 0.040, materials["metal"], root, bevel=0.009)
    cylinder("Stem", (0.0, 0.0, 0.790), 0.040, 1.320, materials["metal"], root, bevel=0.006)
    cylinder("BowlStemCollar", (0.0, 0.0, 1.470), 0.088, 0.045, materials["metal"], root, bevel=0.008)
    cone("TorchBowl", (0.0, 0.0, 1.545), 0.155, 0.112, 0.140, materials["metal"], root, bevel=0.010)
    torus("BowlRim", (0.0, 0.0, 1.617), 0.130, 0.010, materials["brass"], root)
    # A small three-bar cage makes the flame holder legible while leaving it open and light.
    for index, angle in enumerate((0.0, 2.0944, 4.1888), 1):
        x = 0.118 * math.cos(angle)
        y = 0.118 * math.sin(angle)
        cylinder("CageBar%02d" % index, (x, y, 1.700), 0.010, 0.165, materials["metal"], root, bevel=0.002, vertices=12)
    torus("CageTopRing", (0.0, 0.0, 1.780), 0.120, 0.009, materials["brass"], root)
    glow_root = make_empty("Glow", (0.0, 0.0, 1.630), root)
    glow_orb(glow_root, 0.038, materials["glow"])
    return root


def descendants(root):
    yield root
    for child in root.children:
        yield from descendants(child)


def child_named(root, name):
    return next((node for node in descendants(root) if node.name == name), None)


def bounds(root):
    meshes = [node for node in descendants(root) if node.type == "MESH"]
    points = [node.matrix_world @ Vector(corner) for node in meshes for corner in node.bound_box]
    return min(point.z for point in points), max(point.z for point in points)


def export_root(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for node in descendants(root):
        node.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )


def point_at(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(root, path, camera_location, target):
    existing_objects = list(bpy.context.scene.objects)
    preview_nodes = set(descendants(root))
    previous_hidden = {obj: obj.hide_render for obj in existing_objects}
    # hide_render is not inherited by child meshes, so hide every object that
    # does not belong to the requested model rather than merely hiding its root.
    for obj in existing_objects:
        obj.hide_render = obj not in preview_nodes
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.005))
    ground = bpy.context.object
    ground.data.materials.append(make_material("MAT_PreviewFloor_" + root.name, (0.013, 0.017, 0.024), roughness=0.70))
    bpy.ops.object.camera_add(location=camera_location)
    camera = bpy.context.object
    camera.data.lens = 55
    point_at(camera, Vector(target))
    bpy.context.scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(2.5, -3.0, 3.8))
    key = bpy.context.object
    key.data.energy = 420.0
    key.data.shape = "DISK"
    key.data.size = 3.0
    point_at(key, Vector(target))
    bpy.ops.object.light_add(type="POINT", location=(0.0, -0.18, float(target[2]) + 0.22))
    flame_light = bpy.context.object
    flame_light.data.energy = 34.0
    flame_light.data.color = (1.0, 0.24, 0.03)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.world.color = (0.004, 0.006, 0.010)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    for obj in (ground, camera, key, flame_light):
        bpy.data.objects.remove(obj, do_unlink=True)
    for obj, hidden in previous_hidden.items():
        obj.hide_render = hidden


def main():
    args = parse_args()
    clear_scene()
    materials = {
        "wax": make_material("MAT_Candle_WhiteWax", (0.92, 0.90, 0.82), roughness=0.62),
        "wick": make_material("MAT_Candle_Wick", (0.012, 0.008, 0.005), roughness=0.88),
        "metal": make_material("MAT_Torch_BlackMetal", (0.009, 0.012, 0.017), metallic=0.82, roughness=0.22),
        "brass": make_material("MAT_Torch_AntiqueBrass", (0.25, 0.105, 0.018), metallic=0.78, roughness=0.28),
        "glow": make_material("MAT_Furnishing_WarmGlow", (1.0, 0.52, 0.045), roughness=0.20, emission=(1.0, 0.18, 0.006), strength=5.5),
    }
    candle = build_candle(materials)
    torch = build_torch(materials)
    bpy.context.view_layer.update()
    candle_low, candle_high = bounds(candle)
    torch_low, torch_high = bounds(torch)
    if candle_low < -0.001 or candle_high > 0.48:
        raise RuntimeError("Table candle has unexpected dimensions")
    if torch_low < -0.001 or torch_high > 1.82:
        raise RuntimeError("Standing torch exceeds the intended indoor height")

    output = os.path.abspath(args.output)
    os.makedirs(output, exist_ok=True)
    export_root(candle, os.path.join(output, "TableCandle.glb"))
    # Blender requires globally unique object names.  Free the candle's Glow
    # name after its independent export so the torch's exported node is named
    # exactly Glow instead of Blender's automatic Glow.001 suffix.
    candle_glow = child_named(candle, "Glow")
    torch_glow = child_named(torch, "Glow.001")
    if candle_glow is not None and torch_glow is not None:
        candle_glow.name = "CandleGlowPreview"
        torch_glow.name = "Glow"
    export_root(torch, os.path.join(output, "StandingTorch.glb"))
    preview_dir = os.path.abspath(args.preview_dir)
    os.makedirs(preview_dir, exist_ok=True)
    render_preview(candle, os.path.join(preview_dir, "TableCandle_preview.png"), (1.10, -1.55, 0.92), (0.0, 0.0, 0.20))
    render_preview(torch, os.path.join(preview_dir, "StandingTorch_preview.png"), (3.0, -4.0, 2.5), (0.0, 0.0, 0.90))
    print("Exported TableCandle.glb and StandingTorch.glb to " + output)


if __name__ == "__main__":
    main()
