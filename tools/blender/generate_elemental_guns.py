import bpy
import math
import os


OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def make_material(name, color, metallic=0.0, roughness=0.72):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def add_cube(root, name, location, scale, material, rotation=(0.0, 0.0, 0.0), bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(material)
    obj.parent = root
    return obj


def add_cylinder(
    root,
    name,
    location,
    radius,
    depth,
    material,
    vertices=8,
    rotation=(math.pi / 2.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    obj.parent = root
    return obj


def create_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def export_glb(filename):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    output_path = os.path.join(OUTPUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
    )
    print(f"EXPORTED: {output_path}")


def build_freeze_gun():
    clear_scene()
    navy = make_material("Freeze_Navy", (0.025, 0.07, 0.18), 0.35, 0.42)
    deep_blue = make_material("Freeze_DeepBlue", (0.035, 0.16, 0.46), 0.25, 0.48)
    ice = make_material("Freeze_IceCyan", (0.22, 0.78, 0.95), 0.05, 0.32)
    dark = make_material("Freeze_DarkGrip", (0.018, 0.028, 0.055), 0.1, 0.82)
    steel = make_material("Freeze_Steel", (0.28, 0.38, 0.48), 0.65, 0.3)
    root = create_root("FTF_Tool_Freeze_Gun_DeepBlue")

    # Compact receiver and attached grip.
    add_cube(root, "Receiver", (0.0, -0.08, 0.02), (0.21, 0.36, 0.17), navy)
    add_cube(root, "UpperShell", (0.0, -0.29, 0.12), (0.18, 0.22, 0.065), deep_blue)
    add_cube(
        root,
        "Grip",
        (0.0, 0.20, -0.32),
        (0.145, 0.15, 0.50),
        dark,
        rotation=(math.radians(-10.0), 0.0, 0.0),
        bevel=0.035,
    )
    add_cube(root, "GripCap", (0.0, 0.25, -0.59), (0.16, 0.15, 0.07), deep_blue)

    # Barrel points toward Blender -Y, matching the existing tool convention.
    add_cylinder(root, "ColdBarrel", (0.0, -0.60, 0.09), 0.105, 0.62, steel, 8)
    add_cylinder(root, "IceMuzzleRing", (0.0, -0.92, 0.09), 0.145, 0.085, ice, 8)
    add_cylinder(root, "MuzzleCore", (0.0, -0.97, 0.09), 0.072, 0.035, dark, 8)

    # Three chunky cryogenic focusing prongs.
    add_cube(root, "ProngLeft", (-0.16, -0.91, 0.09), (0.045, 0.14, 0.055), ice, bevel=0.012)
    add_cube(root, "ProngRight", (0.16, -0.91, 0.09), (0.045, 0.14, 0.055), ice, bevel=0.012)
    add_cube(root, "ProngTop", (0.0, -0.91, 0.25), (0.055, 0.14, 0.045), ice, bevel=0.012)

    # Horizontal cold-energy canister attached below the receiver.
    add_cylinder(
        root,
        "CryoCanister",
        (0.0, -0.11, -0.18),
        0.13,
        0.34,
        ice,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cylinder(
        root,
        "CanisterCapLeft",
        (-0.19, -0.11, -0.18),
        0.10,
        0.045,
        deep_blue,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cylinder(
        root,
        "CanisterCapRight",
        (0.19, -0.11, -0.18),
        0.10,
        0.045,
        deep_blue,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cube(root, "RearSight", (0.0, 0.02, 0.23), (0.08, 0.045, 0.03), ice, bevel=0.01)
    add_cube(root, "Trigger", (0.0, 0.11, -0.13), (0.035, 0.055, 0.10), steel, bevel=0.01)

    export_glb("FTF_Tool_Freeze_Gun_DeepBlue.glb")


def build_flame_gun():
    clear_scene()
    red = make_material("Flame_Red", (0.68, 0.035, 0.025), 0.2, 0.5)
    red_dark = make_material("Flame_DarkRed", (0.22, 0.018, 0.012), 0.1, 0.8)
    yellow = make_material("Flame_Yellow", (1.0, 0.68, 0.035), 0.12, 0.45)
    orange = make_material("Flame_Orange", (1.0, 0.22, 0.025), 0.08, 0.5)
    dark = make_material("Flame_NozzleDark", (0.055, 0.045, 0.04), 0.55, 0.35)
    root = create_root("FTF_Tool_Flame_Gun_RedYellow")

    add_cube(root, "Receiver", (0.0, -0.06, 0.02), (0.21, 0.35, 0.17), red)
    add_cube(root, "HeatShield", (0.0, -0.31, 0.12), (0.18, 0.21, 0.065), yellow)
    add_cube(
        root,
        "Grip",
        (0.0, 0.21, -0.32),
        (0.145, 0.15, 0.50),
        red_dark,
        rotation=(math.radians(-10.0), 0.0, 0.0),
        bevel=0.035,
    )
    add_cube(root, "GripCap", (0.0, 0.26, -0.59), (0.16, 0.15, 0.07), yellow)

    add_cylinder(root, "FlameTube", (0.0, -0.58, 0.09), 0.11, 0.58, dark, 8)
    add_cylinder(root, "NozzleBase", (0.0, -0.86, 0.09), 0.15, 0.12, orange, 8)
    add_cylinder(root, "NozzleBell", (0.0, -0.96, 0.09), 0.19, 0.11, yellow, 8)
    add_cylinder(root, "NozzleOpening", (0.0, -1.03, 0.09), 0.105, 0.035, dark, 8)

    # Four visible heat fins make the silhouette readable from a distance.
    add_cube(root, "HeatFinLeft", (-0.145, -0.61, 0.09), (0.035, 0.20, 0.075), yellow, bevel=0.01)
    add_cube(root, "HeatFinRight", (0.145, -0.61, 0.09), (0.035, 0.20, 0.075), yellow, bevel=0.01)
    add_cube(root, "HeatFinTop", (0.0, -0.61, 0.225), (0.07, 0.20, 0.035), orange, bevel=0.01)

    # Yellow fuel cell stays physically connected to the red receiver.
    add_cylinder(
        root,
        "FuelCell",
        (0.0, -0.10, -0.18),
        0.135,
        0.35,
        yellow,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cylinder(
        root,
        "FuelCapLeft",
        (-0.195, -0.10, -0.18),
        0.105,
        0.045,
        red,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cylinder(
        root,
        "FuelCapRight",
        (0.195, -0.10, -0.18),
        0.105,
        0.045,
        red,
        8,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )
    add_cube(root, "PilotLight", (0.0, -0.43, 0.25), (0.055, 0.08, 0.045), orange, bevel=0.012)
    add_cube(root, "Trigger", (0.0, 0.12, -0.13), (0.035, 0.055, 0.10), yellow, bevel=0.01)

    export_glb("FTF_Tool_Flame_Gun_RedYellow.glb")


if __name__ == "__main__":
    build_freeze_gun()
    build_flame_gun()
