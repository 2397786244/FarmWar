# Blender 4.x / 5.x
# V3.9: FlavorTrickster vest / belt coplanar-surface fixes
# Self-contained FarmWar character generator.
# Builds Rider (male, sunglasses) and Engineer (female, light-blue long hair)
# stylized low-poly roles, each in Red and Blue variants. Includes rigid humanoid
# rig, the same ten
# animation clip names/poses as the existing FarmWar pipeline, GLB export,
# re-import validation, and rendered pose checks.
#
# Run (macOS example):
# "/Applications/Blender.app/Contents/MacOS/Blender" --background --factory-startup \
#   --python generate_farmwar_female_roles_rigged.py -- --output /path/to/output
#
# WARNING: Script runs in factory startup scenes and clears its own scene.

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


def r(x=0.0, y=0.0, z=0.0):
    return (math.radians(x), math.radians(y), math.radians(z))


ANIMATIONS = {
    "Idle": {
        "end": 60,
        "loop": True,
        "keys": [
            (1,  {"Hips": {"loc": (0, 0, 0)}, "Chest": {"rot": r(0, 0, 0)}, "Head": {"rot": r(0, 0, 0)}}),
            (30, {"Hips": {"loc": (0, 0, 0.018)}, "Chest": {"rot": r(1.2, 0, 0.8)}, "Head": {"rot": r(-0.8, 0, -1.0)}}),
            (60, {"Hips": {"loc": (0, 0, 0)}, "Chest": {"rot": r(0, 0, 0)}, "Head": {"rot": r(0, 0, 0)}}),
        ],
    },
    "IdleTool": {
        "end": 60,
        "loop": True,
        "keys": [
            (1, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)}, "Chest": {"rot": r(0, 0, 0)},
            }),
            (30, {
                "__right_arm_ik": {"target": (-0.47, -0.21, 1.09), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 2)}, "Chest": {"rot": r(0.8, 0, 0.5)},
                "Hips": {"loc": (0, 0, 0.012)},
            }),
            (60, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)}, "Chest": {"rot": r(0, 0, 0)},
            }),
        ],
    },
    "IdleAim": {
        "end": 30,
        "loop": True,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(0, 0, 4)},
            }),
            (15, {
                "Chest": {"rot": r(0.5, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.495, 1.425), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(-0.4, 0, 4)},
            }),
            (30, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(0, 0, 4)},
            }),
        ],
    },
    "Walk": {
        "end": 24,
        "loop": True,
        "keys": [
            (1, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, 2)},
                "Thigh.L": {"rot": r(-24, 0, 0)}, "Thigh.R": {"rot": r(24, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(-18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
            (7, {
                "Hips": {"loc": (0, 0, 0.0), "rot": r(0, 0, 0)},
                "Thigh.L": {"rot": r(0, 0, 0)}, "Thigh.R": {"rot": r(0, 0, 0)},
                "UpperArm.L": {"rot": r(0, 0, 0)}, "UpperArm.R": {"rot": r(0, 0, 0)},
            }),
            (13, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, -2)},
                "Thigh.L": {"rot": r(24, 0, 0)}, "Thigh.R": {"rot": r(-24, 0, 0)},
                "UpperArm.L": {"rot": r(-18, 0, 0)}, "UpperArm.R": {"rot": r(18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
            (19, {
                "Hips": {"loc": (0, 0, 0.0), "rot": r(0, 0, 0)},
                "Thigh.L": {"rot": r(0, 0, 0)}, "Thigh.R": {"rot": r(0, 0, 0)},
                "UpperArm.L": {"rot": r(0, 0, 0)}, "UpperArm.R": {"rot": r(0, 0, 0)},
            }),
            (24, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, 2)},
                "Thigh.L": {"rot": r(-24, 0, 0)}, "Thigh.R": {"rot": r(24, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(-18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
        ],
    },
    "JumpStart": {
        "end": 10,
        "loop": False,
        "keys": [
            (1, {}),
            (6, {
                "Hips": {"loc": (0, 0, -0.10)}, "Chest": {"rot": r(8, 0, 0)},
                "Thigh.L": {"rot": r(15, 0, 0)}, "Thigh.R": {"rot": r(15, 0, 0)},
                "UpperArm.L": {"rot": r(-12, 0, 0)}, "UpperArm.R": {"rot": r(-12, 0, 0)},
            }),
            (10, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-4, 0, 0)},
                "Thigh.L": {"rot": r(-8, 0, 0)}, "Thigh.R": {"rot": r(-8, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(18, 0, 0)},
            }),
        ],
    },
    "JumpLoop": {
        "end": 20,
        "loop": True,
        "keys": [
            (1, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-3, 0, 0)},
                "Thigh.L": {"rot": r(-10, 0, 0)}, "Thigh.R": {"rot": r(8, 0, 0)},
                "UpperArm.L": {"rot": r(20, 0, 0)}, "UpperArm.R": {"rot": r(20, 0, 0)},
            }),
            (10, {
                "Hips": {"loc": (0, 0, 0.055)}, "Chest": {"rot": r(-2, 0, 0)},
                "Thigh.L": {"rot": r(-8, 0, 0)}, "Thigh.R": {"rot": r(6, 0, 0)},
                "UpperArm.L": {"rot": r(22, 0, 0)}, "UpperArm.R": {"rot": r(22, 0, 0)},
            }),
            (20, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-3, 0, 0)},
                "Thigh.L": {"rot": r(-10, 0, 0)}, "Thigh.R": {"rot": r(8, 0, 0)},
                "UpperArm.L": {"rot": r(20, 0, 0)}, "UpperArm.R": {"rot": r(20, 0, 0)},
            }),
        ],
    },
    "JumpLand": {
        "end": 12,
        "loop": False,
        "keys": [
            (1, {"Hips": {"loc": (0, 0, 0.03)}, "Chest": {"rot": r(-3, 0, 0)}}),
            (6, {
                "Hips": {"loc": (0, 0, -0.12)}, "Chest": {"rot": r(9, 0, 0)},
                "Thigh.L": {"rot": r(16, 0, 0)}, "Thigh.R": {"rot": r(16, 0, 0)},
                "UpperArm.L": {"rot": r(-8, 0, 0)}, "UpperArm.R": {"rot": r(-8, 0, 0)},
            }),
            (12, {}),
        ],
    },
    "ShootOneHand": {
        "end": 10,
        "loop": False,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
            (3, {
                "Chest": {"rot": r(-2, 0, -4)},
                "__right_arm_ik": {"target": (-0.35, -0.40, 1.44), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(-7, -4, 2)},
            }),
            (6, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
            (10, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
        ],
    },
    "PunchRight": {
        "end": 16,
        "loop": False,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -4)},
                "__right_arm_ik": {"target": (-0.43, -0.22, 1.32), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 8)},
            }),
            (5, {
                "Chest": {"rot": r(1, 0, 9)},
                "__right_arm_ik": {"target": (-0.48, -0.10, 1.24), "bend": (-1.0, 0.0, -0.15)},
                "Hand.R": {"rot": r(0, 0, 10)},
            }),
            (8, {
                "Chest": {"rot": r(-2, 0, -10)},
                "__right_arm_ik": {"target": (-0.30, -0.50, 1.40), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 0)},
            }),
            (11, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.42, -0.24, 1.32), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 8)},
            }),
            (16, {}),
        ],
    },
    "ToolUseRight": {
        "end": 20,
        "loop": False,
        "keys": [
            (1, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)},
            }),
            (7, {
                "Chest": {"rot": r(-2, 0, -4)},
                "__right_arm_ik": {"target": (-0.39, -0.40, 1.15), "bend": (-1.0, 0.0, -0.30)},
                "Hand.R": {"rot": r(0, -3, 2)},
            }),
            (12, {
                "Chest": {"rot": r(-3, 0, -6)},
                "__right_arm_ik": {"target": (-0.35, -0.50, 1.19), "bend": (-1.0, 0.0, -0.28)},
                "Hand.R": {"rot": r(0, -4, 1)},
            }),
            (20, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)},
            }),
        ],
    },
}


# =============================================================================
# PROJECT / OUTPUT
# =============================================================================

try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = os.getcwd()

DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "generated_farmwar_characters_v2")
FPS = 30
RENDER_POSE_CHECKS = True
POSE_CHECKS = {
    "Idle": 1,
    "Walk": 1,
    "IdleAim": 15,
    "ShootOneHand": 3,
    "PunchRight": 8,
    "ToolUseRight": 12,
    "JumpStart": 6,
}

TEAM_COLORS = {
    "Red": "#F23838",
    "Blue": "#1687F8",
}

EXPRESSIONS = ("Calm", "Fierce", "Funny", "Happy", "Worried")

# =============================================================================
# GENERAL HELPERS
# =============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate rigged FarmWar Mage, Apothecary, Assistant, Rider and Engineer character role variants."
    )
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--skip-pose-renders",
        action="store_true",
        help="Export and validate GLBs but do not render pose-check PNGs.",
    )
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index:index + 2], 16) / 255.0 for index in range(0, 8, 2))


def clear_scene(remove_actions=False):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.armatures):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)

    if remove_actions:
        for action in list(bpy.data.actions):
            if action.users == 0:
                bpy.data.actions.remove(action)


def ensure_metric_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS


def make_material(name, color, metallic=0.0, roughness=0.72):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return material


def create_role_materials(role_name, team_name):
    """Exactly six visible material families per role/team variant."""
    team = TEAM_COLORS[team_name]
    common = {
        "skin": ("#E5A076", 0.0, 0.76),
        "dark": ("#303B43", 0.0, 0.72),
        "team": (team, 0.0, 0.58),
    }
    role_palettes = {
        "Mage": {
            "hair": ("#E7B73C", 0.0, 0.58),
            "primary": ("#5A4A9C", 0.0, 0.70),
            "accent": ("#E9DFC9", 0.0, 0.68),
        },
        "Apothecary": {
            "hair": ("#E978AE", 0.0, 0.58),
            "primary": ("#F3D7D8", 0.0, 0.72),
            "accent": ("#57B7A7", 0.0, 0.65),
        },
        "Assistant": {
            "hair": ("#25242C", 0.0, 0.66),
            "primary": ("#F2EEE3", 0.0, 0.74),
            "accent": ("#3188C6", 0.0, 0.72),
        },
        "Rider": {
            # Warm dark hair, cream racing jacket, and steel-blue trim.
            "hair": ("#513528", 0.0, 0.64),
            "primary": ("#E9DFC9", 0.0, 0.70),
            "accent": ("#6F8793", 0.20, 0.52),
        },
        "Engineer": {
            # Light-blue hair, navy work jacket, and blue denim shorts.
            "hair": ("#8ED7F5", 0.0, 0.56),
            "primary": ("#1D3044", 0.0, 0.64),
            "accent": ("#3188C6", 0.0, 0.70),
        },
        "Prospector": {
            # Deep brown skin, dark curly hair, warm ochre field jacket and copper accents.
            "skin": ("#7B4A33", 0.0, 0.76),
            "hair": ("#2C211D", 0.0, 0.68),
            "primary": ("#C88C3A", 0.0, 0.66),
            "accent": ("#66B7B0", 0.0, 0.64),
        },
        "FlavorTrickster": {
            # Wheat-toned skin, dark hair, playful purple outfit with spice-orange accents.
            "skin": ("#C99561", 0.0, 0.76),
            "hair": ("#312620", 0.0, 0.66),
            "primary": ("#64408B", 0.0, 0.66),
            "accent": ("#E08E2E", 0.0, 0.62),
        },
    }
    colors = dict(common)
    colors.update(role_palettes[role_name])
    return {
        key: make_material(
            f"MAT_{role_name}_{team_name}_{key.title()}",
            color,
            metallic=metallic,
            roughness=roughness,
        )
        for key, (color, metallic, roughness) in colors.items()
    }


def create_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root["asset_type"] = "rigged_low_poly_character"
    root["front_axis"] = "-Y"
    return root


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_bevel(obj, width):
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1


def finish_object(obj, name, material, root, bind_bone):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.parent = root
    obj["bind_bone"] = bind_bone
    if material is not None:
        obj.data.materials.append(material)
    return obj


def add_cube(name, location, dimensions, material, root, bind_bone, bevel=0.02, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_cylinder(name, location, radius, depth, material, root, bind_bone, vertices=8, rotation=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_cone(name, location, radius_bottom, radius_top, depth, material, root, bind_bone, vertices=8, bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    obj = bpy.context.object
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_ico(name, location, dimensions, material, root, bind_bone, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=0.5, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    return finish_object(obj, name, material, root, bind_bone)



def add_open_frustum_shell(
    name,
    center_z,
    radius_x_bottom,
    radius_y_bottom,
    radius_x_top,
    radius_y_top,
    height,
    material,
    root,
    bind_bone,
    segments=10,
    angular_offset=0.0,
):
    """Create a one-surface outer garment shell with no caps or internal planes.

    This is intentionally used for skirts, robe hems and belt bands. Compared
    with a closed cone/cube intersecting an underlying body mesh, an open shell
    keeps the only visible surface outside the character and avoids the nearly
    coplanar intersections that can flicker in Godot.
    """
    bottom_z = center_z - height * 0.5
    top_z = center_z + height * 0.5
    vertices = []
    faces = []
    for index in range(segments):
        angle = angular_offset + math.tau * index / segments
        c = math.cos(angle)
        s = math.sin(angle)
        vertices.append((radius_x_bottom * c, radius_y_bottom * s, bottom_z))
        vertices.append((radius_x_top * c, radius_y_top * s, top_z))

    for index in range(segments):
        next_index = (index + 1) % segments
        bottom_a = index * 2
        top_a = bottom_a + 1
        bottom_b = next_index * 2
        top_b = bottom_b + 1
        # Winding faces outward. There are deliberately no top/bottom caps.
        faces.append((bottom_a, bottom_b, top_b, top_a))

    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    obj["bind_bone"] = bind_bone
    mesh.materials.append(material)
    return obj


def add_open_box_band_shell(
    name,
    center_z,
    half_x,
    half_y,
    height,
    material,
    root,
    bind_bone,
    center_x=0.0,
    center_y=0.0,
):
    """Four-sided outer band with no caps or internal faces.

    Use it for waistbands and cuffs around cube-shaped body parts. The shell is
    placed just outside the garment (typically 2–4 mm), so it looks sewn on but
    cannot share a front/back plane with the underlying mesh.
    """
    bottom_z = center_z - height * 0.5
    top_z = center_z + height * 0.5
    # center_x / center_y are important for limb cuffs. Without them, a left
    # and right cuff would both be authored at the origin, perfectly overlap,
    # and correctly trigger the z-fighting audit.
    vertices = [
        (center_x - half_x, center_y - half_y, bottom_z),
        (center_x + half_x, center_y - half_y, bottom_z),
        (center_x + half_x, center_y + half_y, bottom_z),
        (center_x - half_x, center_y + half_y, bottom_z),
        (center_x - half_x, center_y - half_y, top_z),
        (center_x + half_x, center_y - half_y, top_z),
        (center_x + half_x, center_y + half_y, top_z),
        (center_x - half_x, center_y + half_y, top_z),
    ]
    faces = [
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    obj["bind_bone"] = bind_bone
    mesh.materials.append(material)
    return obj


def add_front_robe_panel(name, material, root, bind_bone):
    """A front trim panel held 5–6 mm outside the robe shell.

    The old coordinates were 44–46 mm in front of the robe, which removed
    coplanar overlap but made the panel visibly float. These coordinates follow
    the revised robe slope closely and remain non-coplanar.
    """
    vertices = [
        (-0.145, -0.373, 0.29),
        (0.145, -0.373, 0.29),
        (0.105, -0.208, 0.95),
        (-0.105, -0.208, 0.95),
    ]
    # The panel normal faces local -Y toward the character front.
    faces = [(0, 1, 2, 3)]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    obj["bind_bone"] = bind_bone
    mesh.materials.append(material)
    return obj


def add_cylinder_between(name, start, end, radius, material, root, bind_bone, vertices=8, bevel=0.0):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    midpoint = (start + end) * 0.5
    obj = add_cylinder(
        name,
        midpoint,
        radius,
        direction.length,
        material,
        root,
        bind_bone,
        vertices=vertices,
        bevel=bevel,
    )
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


# =============================================================================
# FACIAL BLEND SHAPES
# =============================================================================

def add_expression_shape_keys(obj, transforms):
    basis = obj.shape_key_add(name="Basis")
    original_positions = [point.co.copy() for point in basis.data]

    for expression in EXPRESSIONS:
        settings = transforms.get(expression, {})
        scale = Vector(settings.get("scale", (1.0, 1.0, 1.0)))
        offset = Vector(settings.get("offset", (0.0, 0.0, 0.0)))
        rotation_y = math.radians(float(settings.get("rotation_y", 0.0)))
        rotation = Matrix.Rotation(rotation_y, 4, "Y")
        shape = obj.shape_key_add(name=expression)
        for index, position in enumerate(original_positions):
            scaled = Vector((position.x * scale.x, position.y * scale.y, position.z * scale.z))
            shape.data[index].co = rotation @ scaled + offset


def add_eye_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_scale = (1.30, 1.0, 1.30) if side == "Left" else (0.95, 1.0, 0.38)
    funny_offset = (0.0, 0.0, 0.018) if side == "Left" else (0.0, 0.0, -0.012)
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"scale": (1.10, 1.0, 0.55), "rotation_y": 14.0 * sign, "offset": (0.0, 0.0, -0.010)},
        "Funny": {"scale": funny_scale, "rotation_y": -10.0 * sign, "offset": funny_offset},
        "Happy": {"scale": (1.18, 1.0, 0.35), "rotation_y": -5.0 * sign, "offset": (0.0, 0.0, -0.015)},
        "Worried": {"scale": (0.92, 1.0, 1.15), "rotation_y": -8.0 * sign, "offset": (0.0, 0.0, 0.005)},
    })


def add_brow_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_height = 0.045 if side == "Left" else -0.025
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"rotation_y": -22.0 * sign, "offset": (0.0, 0.0, -0.025)},
        "Funny": {"rotation_y": 18.0 * sign, "offset": (0.0, 0.0, funny_height)},
        "Happy": {"rotation_y": 7.0 * sign, "offset": (0.0, 0.0, 0.020)},
        "Worried": {"rotation_y": 22.0 * sign, "offset": (0.0, 0.0, 0.030)},
    })


def add_mouth_expression_shapes(obj, segment):
    if segment == "Left":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, 0.025)
        happy_rotation = -18.0
        worried_rotation = 20.0
    elif segment == "Right":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, -0.025)
        happy_rotation = 18.0
        worried_rotation = -20.0
    else:
        happy_offset = (0.0, 0.0, -0.012)
        worried_offset = (0.0, 0.0, 0.018)
        funny_offset = (0.0, 0.0, 0.0)
        happy_rotation = 0.0
        worried_rotation = 0.0

    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"scale": (1.05, 1.0, 0.72), "offset": worried_offset, "rotation_y": worried_rotation},
        "Funny": {"scale": (1.0, 1.0, 1.25 if segment == "Center" else 0.85), "offset": funny_offset, "rotation_y": 12.0 if segment != "Center" else 0.0},
        "Happy": {"offset": happy_offset, "rotation_y": happy_rotation},
        "Worried": {"scale": (0.92, 1.0, 0.9), "offset": worried_offset, "rotation_y": worried_rotation},
    })


def add_face(root, mats, cute=False):
    add_cube("Head", (0.0, 0.0, 1.72), (0.45, 0.38, 0.43), mats["skin"], root, "Head", bevel=0.028)

    eye_scale = (0.068, 0.035, 0.086) if cute else (0.058, 0.035, 0.073)
    left_eye = add_ico("LeftEye", (-0.092, -0.202, 1.755), eye_scale, mats["dark"], root, "Head")
    right_eye = add_ico("RightEye", (0.092, -0.202, 1.755), eye_scale, mats["dark"], root, "Head")
    add_eye_expression_shapes(left_eye, "Left")
    add_eye_expression_shapes(right_eye, "Right")

    left_brow = add_cube("LeftBrow", (-0.102, -0.214, 1.852), (0.142, 0.024, 0.030), mats["hair"], root, "Head", bevel=0.006)
    right_brow = add_cube("RightBrow", (0.102, -0.214, 1.852), (0.142, 0.024, 0.030), mats["hair"], root, "Head", bevel=0.006)
    add_brow_expression_shapes(left_brow, "Left")
    add_brow_expression_shapes(right_brow, "Right")

    add_cube("Nose", (0.0, -0.219, 1.676), (0.065, 0.045, 0.064), mats["skin"], root, "Head", bevel=0.012)

    # The Assistant gets an upward mouth line at rest for a cute, friendly pose.
    base_z = {"Left": 1.592, "Center": 1.580, "Right": 1.592} if cute else {"Left": 1.585, "Center": 1.585, "Right": 1.585}
    for segment, x in (("Left", -0.060), ("Center", 0.0), ("Right", 0.060)):
        mouth = add_cube("Mouth" + segment, (x, -0.213, base_z[segment]), (0.068, 0.020, 0.026), mats["dark"], root, "Head", bevel=0.004)
        add_mouth_expression_shapes(mouth, segment)

    tongue = add_cube("FunnyTongue", (0.0, -0.010, 1.550), (0.095, 0.022, 0.070), mats["team"], root, "Head", bevel=0.006)
    add_expression_shape_keys(tongue, {
        "Calm": {}, "Fierce": {}, "Funny": {"offset": (0.0, -0.218, -0.014)}, "Happy": {}, "Worried": {},
    })

    if cute:
        add_ico("LeftCheek", (-0.158, -0.207, 1.652), (0.090, 0.010, 0.045), mats["team"], root, "Head")
        add_ico("RightCheek", (0.158, -0.207, 1.652), (0.090, 0.010, 0.045), mats["team"], root, "Head")


def tune_prospector_face():
    """Give the Prospector's face enough clearance for every expression.

    The shared face has a deliberately compact cartoon layout.  With the
    Prospector helmet, the Fierce eyebrow shape could visually touch an eye.
    Lowering the eyes leaves a clean visible gap for all five expressions,
    including the downward-slanted Fierce brows, without pushing the brows
    into the headlamp mount.
    """
    for name in ("LeftEye", "RightEye"):
        bpy.data.objects[name].location.z -= 0.015


# =============================================================================
# FEMALE LOW-POLY BODY
# =============================================================================

def add_female_body(
    root,
    mats,
    top_material,
    pants_material,
    boot_material,
    sleeve_material=None,
    cute=False,
    leg_dimensions=(0.20, 0.25, 0.56),
    leg_center_z=0.57,
    boot_dimensions=(0.22, 0.34, 0.23),
):
    sleeve_material = sleeve_material or top_material

    add_cube("Torso", (0.0, 0.0, 1.19), (0.54, 0.32, 0.62), top_material, root, "Chest", bevel=0.055)
    add_cube("Waist", (0.0, 0.0, 0.91), (0.45, 0.30, 0.16), top_material, root, "Hips", bevel=0.040)

    for side, sign, bone_side in (("Left", -1.0, "R"), ("Right", 1.0, "L")):
        leg_x = 0.145 * sign
        add_cube(side + "Leg", (leg_x, 0.015, leg_center_z), leg_dimensions, pants_material, root, "Thigh." + bone_side, bevel=0.033)
        add_cube(side + "Boot", (leg_x, -0.070, 0.165), boot_dimensions, boot_material, root, "Foot." + bone_side, bevel=0.038)

        shoulder = (0.300 * sign, 0.0, 1.41)
        elbow = (0.465 * sign, 0.0, 1.16)
        wrist = (0.565 * sign, -0.018, 0.97)
        add_cylinder_between(side + "UpperArm", shoulder, elbow, 0.094, sleeve_material, root, "UpperArm." + bone_side, vertices=8)
        add_cylinder_between(side + "Forearm", elbow, wrist, 0.078, mats["skin"], root, "Forearm." + bone_side, vertices=8)
        add_ico(side + "Hand", wrist, (0.150, 0.128, 0.170), mats["skin"], root, "Hand." + bone_side)

    add_face(root, mats, cute=cute)


def add_team_badge(root, mats, y=-0.160, z=1.28):
    """Attach a two-layer badge directly to the supplied cloth surface.

    The frame overlaps the cloth by 1 mm and the colored insert overlaps the
    frame by 2 mm. That keeps the badge visually sewn onto the costume without
    creating coplanar triangles or a visibly floating badge stack.
    """
    frame_center_y = y - 0.013
    insert_center_y = y - 0.032
    add_cube("TeamBadgeFrame", (0.0, frame_center_y, z), (0.245, 0.024, 0.18), mats["dark"], root, "Chest", bevel=0.020)
    add_cube("TeamBadge", (0.0, insert_center_y, z), (0.185, 0.016, 0.115), mats["team"], root, "Chest", bevel=0.014)


def add_hair_cap(root, mats, style="long"):
    if style == "short_bob":
        # Full upper-head cap for the Apothecary. Its enlarged closed low-poly
        # volume envelopes the whole crown, temples and upper back of the head;
        # it is not a thin strip, so there is no exposed bald top in 3/4 views.
        # It intersects the head volume slightly but has no coplanar face with it.
        add_ico("HairFullTopCap", (0.0, 0.018, 1.925), (0.54, 0.46, 0.40), mats["hair"], root, "Head")
        add_cube("HairBobBack", (0.0, 0.170, 1.715), (0.44, 0.14, 0.40), mats["hair"], root, "Head", bevel=0.060)
        add_ico("HairBobLeft", (-0.225, -0.025, 1.735), (0.145, 0.15, 0.31), mats["hair"], root, "Head")
        add_ico("HairBobRight", (0.225, -0.025, 1.735), (0.145, 0.15, 0.31), mats["hair"], root, "Head")
        # Fringe and bangs physically overlap the top cap by a few millimetres.
        add_cube("HairBobFringe", (0.0, -0.198, 1.885), (0.35, 0.024, 0.115), mats["hair"], root, "Head", bevel=0.014)
        add_cube("HairBobBangLeft", (-0.135, -0.202, 1.805), (0.110, 0.022, 0.17), mats["hair"], root, "Head", bevel=0.014, rotation=(0.0, 0.0, math.radians(-10)))
        add_cube("HairBobBangRight", (0.135, -0.202, 1.805), (0.110, 0.022, 0.17), mats["hair"], root, "Head", bevel=0.014, rotation=(0.0, 0.0, math.radians(10)))
        return

    # Long and ponytail versions retain a compact crown volume but overlap the
    # head rather than hovering above it.
    add_ico("HairCap", (0.0, 0.025, 1.900), (0.51, 0.43, 0.34), mats["hair"], root, "Head")
    if style == "long":
        add_cube("HairBack", (0.0, 0.175, 1.64), (0.41, 0.12, 0.52), mats["hair"], root, "Head", bevel=0.050)
        add_cylinder_between("HairLockLeft", (-0.195, -0.165, 1.86), (-0.225, -0.175, 1.50), 0.047, mats["hair"], root, "Head", vertices=6)
        add_cylinder_between("HairLockRight", (0.195, -0.165, 1.86), (0.225, -0.175, 1.50), 0.047, mats["hair"], root, "Head", vertices=6)
    elif style == "ponytail":
        add_ico("Ponytail", (0.0, 0.275, 1.77), (0.28, 0.18, 0.38), mats["hair"], root, "Head")
        add_cylinder("PonytailTie", (0.0, 0.195, 1.80), 0.052, 0.12, mats["team"], root, "Head", vertices=8, rotation=(math.radians(90), 0, 0))
        add_cylinder_between("FrontBangLeft", (-0.10, -0.192, 1.92), (-0.15, -0.204, 1.76), 0.032, mats["hair"], root, "Head", vertices=6)
        add_cylinder_between("FrontBangRight", (0.10, -0.192, 1.92), (0.15, -0.204, 1.76), 0.032, mats["hair"], root, "Head", vertices=6)


# =============================================================================
# ROLE BUILDERS
# =============================================================================

def build_mage(team_name):
    root = create_root("FTF_Character_Mage_" + team_name)
    mats = create_role_materials("Mage", team_name)

    # Narrow opaque leggings are fully enclosed by the robe shell. This avoids
    # the former blue/team-colored body piece becoming visible through the skirt.
    add_female_body(
        root,
        mats,
        mats["primary"],
        mats["dark"],
        mats["dark"],
        sleeve_material=mats["primary"],
        cute=False,
        leg_dimensions=(0.14, 0.16, 0.50),
        leg_center_z=0.53,
        boot_dimensions=(0.18, 0.28, 0.20),
    )

    # Outer-only robe shell: no closed cone cap crosses the body or colored trims.
    add_open_frustum_shell(
        "RobeLowerShell", 0.59, 0.445, 0.405, 0.238, 0.180, 0.90,
        mats["primary"], root, "Hips", segments=10, angular_offset=math.pi / 10.0,
    )
    # Team belt is a separate outward shell. It cannot protrude through the robe.
    add_open_frustum_shell(
        "RobeTeamBeltBand", 0.945, 0.286, 0.228, 0.260, 0.204, 0.095,
        mats["team"], root, "Hips", segments=10, angular_offset=math.pi / 10.0,
    )
    add_front_robe_panel("RobeFrontPanel", mats["accent"], root, "Hips")
    add_cube("RobeCollar", (0.0, -0.174, 1.47), (0.31, 0.026, 0.11), mats["accent"], root, "Chest", bevel=0.018)

    add_cylinder_between("LeftRobeSleeve", (-0.30, 0.0, 1.40), (-0.465, 0.0, 1.15), 0.118, mats["primary"], root, "UpperArm.R", vertices=8)
    add_cylinder_between("RightRobeSleeve", (0.30, 0.0, 1.40), (0.465, 0.0, 1.15), 0.118, mats["primary"], root, "UpperArm.L", vertices=8)
    add_cylinder("LeftCuff", (-0.505, -0.010, 1.08), 0.112, 0.12, mats["accent"], root, "Forearm.R", vertices=8, rotation=(math.radians(38), 0, math.radians(-28)))
    add_cylinder("RightCuff", (0.505, -0.010, 1.08), 0.112, 0.12, mats["accent"], root, "Forearm.L", vertices=8, rotation=(math.radians(38), 0, math.radians(28)))

    add_hair_cap(root, mats, style="long")
    # IMPORTANT: use an open cone shell instead of a capped Blender cone.
    # The old cone bottom cap sat exactly on the Head top plane (Z=1.935),
    # which is a real coplanar overlap and was correctly rejected by the
    # z-fighting audit. The shell starts 5 mm above the brim and has no cap,
    # so it cannot share a visible plane with the head or brim.
    add_open_frustum_shell(
        "WizardHatConeShell", 2.270, 0.240, 0.240, 0.012, 0.012, 0.55,
        mats["primary"], root, "Head", segments=8, angular_offset=math.pi / 8.0,
    )
    add_cylinder("WizardHatBrim", (0.0, 0.0, 1.965), 0.34, 0.050, mats["accent"], root, "Head", vertices=10)
    # Continuous cone-following team band instead of a detached front cube.
    add_open_frustum_shell(
        "WizardHatTeamBand", 2.085, 0.231, 0.231, 0.194, 0.194, 0.090,
        mats["team"], root, "Head", segments=8, angular_offset=math.pi / 8.0,
    )
    add_ico("MagicCharm", (0.0, -0.176, 1.31), (0.11, 0.024, 0.11), mats["team"], root, "Chest")
    add_team_badge(root, mats, y=-0.160, z=1.22)
    return root


def build_apothecary(team_name):
    root = create_root("FTF_Character_Apothecary_" + team_name)
    mats = create_role_materials("Apothecary", team_name)
    add_female_body(root, mats, mats["primary"], mats["skin"], mats["dark"], sleeve_material=mats["primary"], cute=True)

    # The former skirt used a closed cone plus a cube hem that intersected it.
    # Both are now outward-only frustum shells with an explicit 18mm gap.
    add_open_frustum_shell(
        "ShortSkirtShell", 0.80, 0.370, 0.310, 0.235, 0.180, 0.36,
        mats["primary"], root, "Hips", segments=10, angular_offset=math.pi / 10.0,
    )
    add_open_frustum_shell(
        "SkirtTeamHemBand", 0.655, 0.386, 0.322, 0.360, 0.298, 0.072,
        mats["team"], root, "Hips", segments=10, angular_offset=math.pi / 10.0,
    )
    # Apron layers use 10mm+ physical clearance; no plane shares a depth.
    add_cube("ApronBib", (0.0, -0.190, 1.16), (0.35, 0.035, 0.37), mats["accent"], root, "Chest", bevel=0.030)
    add_cube("ApronPocket", (0.0, -0.204, 1.05), (0.20, 0.020, 0.105), mats["team"], root, "Chest", bevel=0.012)
    add_cube("LeftApronStrap", (-0.145, -0.171, 1.40), (0.055, 0.024, 0.26), mats["accent"], root, "Chest", bevel=0.012)
    add_cube("RightApronStrap", (0.145, -0.171, 1.40), (0.055, 0.024, 0.26), mats["accent"], root, "Chest", bevel=0.012)

    # Open cuffs hug each boot exterior by 2 mm instead of being cuboids buried
    # inside the boot volume.
    # The two cuff shells must be centered on their own boot, not at the origin.
    # Boot centers are x=±0.145 and y=-0.070; the shell extends 2 mm outside.
    add_open_box_band_shell(
        "LeftBootCuff", 0.275, 0.112, 0.172, 0.085, mats["team"], root, "Foot.R",
        center_x=-0.145, center_y=-0.070,
    )
    add_open_box_band_shell(
        "RightBootCuff", 0.275, 0.112, 0.172, 0.085, mats["team"], root, "Foot.L",
        center_x=0.145, center_y=-0.070,
    )

    for name, x, color in (("Left", -0.26, mats["team"]), ("Right", 0.26, mats["accent"])):
        add_cylinder(name + "Bottle", (x, -0.190, 0.94), 0.060, 0.16, color, root, "Hips", vertices=6, bevel=0.008)
        add_cylinder(name + "Stopper", (x, -0.190, 1.045), 0.028, 0.052, mats["dark"], root, "Hips", vertices=6)

    add_hair_cap(root, mats, style="short_bob")
    add_ico("HairClip", (0.160, -0.218, 1.87), (0.10, 0.016, 0.055), mats["team"], root, "Head")
    add_team_badge(root, mats, y=-0.208, z=1.29)
    return root


def build_assistant(team_name):
    root = create_root("FTF_Character_Assistant_" + team_name)
    mats = create_role_materials("Assistant", team_name)
    add_female_body(root, mats, mats["primary"], mats["accent"], mats["dark"], sleeve_material=mats["primary"], cute=True)

    # Casual practical outfit: cream top, denim jeans, large team-color scarf.
    add_open_box_band_shell("DenimWaistband", 0.89, 0.227, 0.152, 0.08, mats["accent"], root, "Hips")
    add_cube("LeftJeanPatch", (-0.145, -0.125, 0.58), (0.145, 0.024, 0.13), mats["team"], root, "Thigh.R", bevel=0.012)
    add_cube("RightJeanPatch", (0.145, -0.125, 0.58), (0.145, 0.024, 0.13), mats["team"], root, "Thigh.L", bevel=0.012)
    add_cube("ScarfFront", (0.0, -0.182, 1.42), (0.30, 0.040, 0.11), mats["team"], root, "Chest", bevel=0.025)
    add_cube("ScarfTail", (0.205, 0.145, 1.20), (0.10, 0.055, 0.37), mats["team"], root, "Chest", bevel=0.025)
    add_cube("UtilityPouch", (-0.23, -0.175, 0.88), (0.17, 0.10, 0.17), mats["dark"], root, "Hips", bevel=0.025)
    add_ico("PouchButton", (-0.23, -0.233, 0.89), (0.050, 0.018, 0.050), mats["team"], root, "Hips")

    add_hair_cap(root, mats, style="ponytail")
    add_ico("HairBow", (0.0, 0.210, 1.82), (0.22, 0.050, 0.10), mats["team"], root, "Head")
    add_team_badge(root, mats, y=-0.160, z=1.27)
    return root



# =============================================================================
# RIDER / ENGINEER ROLE BUILDERS
# =============================================================================

def add_male_body(root, mats, top_material, pants_material, boot_material, sleeve_material=None):
    """Chunkier adult male body; shares the exact same skeleton proportions."""
    sleeve_material = sleeve_material or top_material

    add_cube("Torso", (0.0, 0.0, 1.20), (0.63, 0.36, 0.64), top_material, root, "Chest", bevel=0.055)
    add_cube("Waist", (0.0, 0.0, 0.91), (0.53, 0.32, 0.16), top_material, root, "Hips", bevel=0.040)

    for side, sign, bone_side in (("Left", -1.0, "R"), ("Right", 1.0, "L")):
        leg_x = 0.17 * sign
        # Keep the leg top 6 mm below the torso bottom. In the old build both
        # planes were exactly Z=0.880; after glTF re-import the two opaque,
        # otherwise hidden internal faces were reported as coplanar. The Waist
        # still overlaps this seam generously, so this tiny clearance is never
        # visible but prevents an exact internal face stack in exported GLB.
        add_cube(side + "Leg", (leg_x, 0.015, 0.584), (0.25, 0.28, 0.58), pants_material, root, "Thigh." + bone_side, bevel=0.035)
        add_cube(side + "Boot", (leg_x, -0.065, 0.18), (0.27, 0.39, 0.25), boot_material, root, "Foot." + bone_side, bevel=0.042)

        shoulder = (0.355 * sign, 0.0, 1.40)
        elbow = (0.515 * sign, 0.0, 1.15)
        wrist = (0.615 * sign, -0.018, 0.96)
        add_cylinder_between(side + "UpperArm", shoulder, elbow, 0.106, sleeve_material, root, "UpperArm." + bone_side, vertices=8)
        add_cylinder_between(side + "Forearm", elbow, wrist, 0.087, mats["skin"], root, "Forearm." + bone_side, vertices=8)
        add_ico(side + "Hand", wrist, (0.175, 0.145, 0.190), mats["skin"], root, "Hand." + bone_side)

    add_face(root, mats, cute=False)


def add_short_male_hair(root, mats):
    """Compact short hair shape with an intentional, readable front fringe."""
    add_ico("HairCap", (0.0, 0.040, 1.900), (0.49, 0.42, 0.26), mats["hair"], root, "Head")
    add_cube("HairBackShort", (0.0, 0.155, 1.795), (0.40, 0.12, 0.20), mats["hair"], root, "Head", bevel=0.040)
    add_cube("HairFringeLeft", (-0.11, -0.188, 1.930), (0.16, 0.042, 0.10), mats["hair"], root, "Head", bevel=0.018, rotation=(0.0, 0.0, math.radians(-9)))
    add_cube("HairFringeRight", (0.08, -0.190, 1.928), (0.19, 0.042, 0.10), mats["hair"], root, "Head", bevel=0.018, rotation=(0.0, 0.0, math.radians(7)))


def add_sunglasses(root, mats):
    """Opaque stylized sunglasses: no transparency sorting issues in Godot."""
    # Lenses sit forward of both eyes and the frame, avoiding coplanar faces.
    add_ico("LeftSunglassLens", (-0.105, -0.235, 1.765), (0.165, 0.028, 0.105), mats["dark"], root, "Head")
    add_ico("RightSunglassLens", (0.105, -0.235, 1.765), (0.165, 0.028, 0.105), mats["dark"], root, "Head")
    add_cube("SunglassesBridge", (0.0, -0.236, 1.766), (0.080, 0.022, 0.030), mats["accent"], root, "Head", bevel=0.006)
    add_cube("SunglassesTopFrame", (0.0, -0.238, 1.818), (0.370, 0.022, 0.025), mats["accent"], root, "Head", bevel=0.006)
    add_cube("LeftSunglassesArm", (-0.245, -0.075, 1.780), (0.030, 0.245, 0.030), mats["accent"], root, "Head", bevel=0.005)
    add_cube("RightSunglassesArm", (0.245, -0.075, 1.780), (0.030, 0.245, 0.030), mats["accent"], root, "Head", bevel=0.005)


def build_rider(team_name):
    root = create_root("FTF_Character_Rider_" + team_name)
    mats = create_role_materials("Rider", team_name)
    add_male_body(root, mats, mats["primary"], mats["dark"], mats["dark"], sleeve_material=mats["primary"])

    # Toy-like racing jacket: cream base, dark panels, and only a controlled
    # amount of red/blue team color on stripes, collar and badge.
    # Torso's front face is Y=-0.180. Keep the jacket's rear face 3 mm forward
    # at Y=-0.183: close enough to read as worn clothing, but never coplanar.
    # Earlier revisions used center=-0.201 and depth=0.042, whose rear face was
    # exactly Y=-0.180 and therefore overlapped the torso's front polygons.
    add_cube("RacingJacketFront", (0.0, -0.203, 1.20), (0.54, 0.040, 0.47), mats["primary"], root, "Chest", bevel=0.035)
    add_cube("JacketCenterZip", (0.0, -0.232, 1.20), (0.030, 0.010, 0.43), mats["accent"], root, "Chest", bevel=0.005)
    add_cube("JacketLeftPanel", (-0.235, -0.239, 1.22), (0.115, 0.012, 0.40), mats["dark"], root, "Chest", bevel=0.012)
    add_cube("JacketRightPanel", (0.235, -0.239, 1.22), (0.115, 0.012, 0.40), mats["dark"], root, "Chest", bevel=0.012)
    add_cube("JacketCollar", (0.0, -0.185, 1.49), (0.38, 0.045, 0.10), mats["team"], root, "Chest", bevel=0.020)
    add_cube("LeftSleeveTeamStripe", (-0.455, -0.005, 1.25), (0.065, 0.26, 0.075), mats["team"], root, "UpperArm.R", bevel=0.012, rotation=(math.radians(34), 0.0, math.radians(-28)))
    add_cube("RightSleeveTeamStripe", (0.455, -0.005, 1.25), (0.065, 0.26, 0.075), mats["team"], root, "UpperArm.L", bevel=0.012, rotation=(math.radians(34), 0.0, math.radians(28)))
    # Use an uncapped belt shell instead of a solid cuboid enclosing Waist.
    # That retains close contact but removes interior faces and coplanar risks.
    add_open_box_band_shell(
        "RacingBelt", 0.90, 0.273, 0.163, 0.10, mats["accent"], root, "Hips"
    )
    add_cube("BeltBuckle", (0.0, -0.175, 0.90), (0.13, 0.018, 0.09), mats["team"], root, "Hips", bevel=0.015)
    add_cube("LeftDrivingGlove", (-0.615, -0.020, 0.96), (0.18, 0.15, 0.13), mats["dark"], root, "Hand.R", bevel=0.025)
    add_cube("RightDrivingGlove", (0.615, -0.020, 0.96), (0.18, 0.15, 0.13), mats["dark"], root, "Hand.L", bevel=0.025)

    add_short_male_hair(root, mats)
    add_sunglasses(root, mats)
    add_team_badge(root, mats, y=-0.220, z=1.34)
    return root


def build_engineer(team_name):
    root = create_root("FTF_Character_Engineer_" + team_name)
    mats = create_role_materials("Engineer", team_name)

    # Skin-colored leg pieces are deliberately exposed below the denim shorts;
    # all clothing volumes are offset from the body, not coplanar overlays.
    add_female_body(root, mats, mats["primary"], mats["skin"], mats["dark"], sleeve_material=mats["primary"], cute=False)

    # Cool cropped work jacket and blue denim shorts.
    add_cube("EngineerJacketFront", (0.0, -0.184, 1.22), (0.48, 0.046, 0.39), mats["primary"], root, "Chest", bevel=0.035)
    add_cube("EngineerJacketZip", (0.0, -0.216, 1.22), (0.024, 0.014, 0.34), mats["accent"], root, "Chest", bevel=0.004)
    add_cube("EngineerLeftPocket", (-0.135, -0.216, 1.13), (0.13, 0.014, 0.10), mats["accent"], root, "Chest", bevel=0.010)
    add_cube("EngineerRightPocket", (0.135, -0.216, 1.13), (0.13, 0.014, 0.10), mats["accent"], root, "Chest", bevel=0.010)
    add_cube("EngineerCollar", (0.0, -0.180, 1.48), (0.31, 0.040, 0.10), mats["team"], root, "Chest", bevel=0.018)

    # Separate shorts for each thigh so the rigid walk animation remains clean.
    add_cube("LeftDenimShorts", (-0.145, 0.005, 0.72), (0.235, 0.275, 0.31), mats["accent"], root, "Thigh.R", bevel=0.032)
    add_cube("RightDenimShorts", (0.145, 0.005, 0.72), (0.235, 0.275, 0.31), mats["accent"], root, "Thigh.L", bevel=0.032)
    add_open_box_band_shell("ShortsWaistband", 0.875, 0.227, 0.152, 0.075, mats["dark"], root, "Hips")
    add_cube("LeftShortsPatch", (-0.145, -0.143, 0.70), (0.13, 0.020, 0.09), mats["team"], root, "Thigh.R", bevel=0.010)
    add_cube("RightShortsPatch", (0.145, -0.143, 0.70), (0.13, 0.020, 0.09), mats["team"], root, "Thigh.L", bevel=0.010)

    # Tool belt with two large pouches and a stylized wrench-like symbol.
    add_cube("ToolBelt", (0.0, -0.005, 0.93), (0.51, 0.32, 0.095), mats["dark"], root, "Hips", bevel=0.020)
    add_cube("LeftToolPouch", (-0.255, -0.155, 0.87), (0.16, 0.12, 0.18), mats["primary"], root, "Hips", bevel=0.025)
    add_cube("RightToolPouch", (0.255, -0.155, 0.87), (0.16, 0.12, 0.18), mats["primary"], root, "Hips", bevel=0.025)
    add_cylinder("ToolBeltBolt", (0.0, -0.190, 0.93), 0.045, 0.035, mats["team"], root, "Hips", vertices=6, rotation=(math.radians(90), 0.0, 0.0))
    add_cube("LeftArmBand", (-0.415, -0.008, 1.28), (0.058, 0.20, 0.085), mats["team"], root, "UpperArm.R", bevel=0.012, rotation=(math.radians(34), 0.0, math.radians(-28)))
    add_cube("RightArmBand", (0.415, -0.008, 1.28), (0.058, 0.20, 0.085), mats["team"], root, "UpperArm.L", bevel=0.012, rotation=(math.radians(34), 0.0, math.radians(28)))

    # Light-blue long hair and a compact one-piece engineering visor/headset.
    add_hair_cap(root, mats, style="long")
    add_cube("EngineerVisorBand", (0.0, -0.207, 1.865), (0.40, 0.030, 0.055), mats["dark"], root, "Head", bevel=0.008)
    add_ico("EngineerVisorLens", (0.0, -0.226, 1.850), (0.25, 0.018, 0.090), mats["accent"], root, "Head")
    add_ico("HeadsetLeftCup", (-0.245, 0.005, 1.81), (0.085, 0.065, 0.12), mats["team"], root, "Head")
    add_ico("HeadsetRightCup", (0.245, 0.005, 1.81), (0.085, 0.065, 0.12), mats["team"], root, "Head")
    add_cylinder_between("HairBraid", (0.20, 0.145, 1.72), (0.25, 0.180, 1.38), 0.040, mats["hair"], root, "Head", vertices=6)
    add_team_badge(root, mats, y=-0.209, z=1.33)
    return root




def add_short_curly_hair(root, mats):
    """Compact curly hairstyle for the Prospector: readable silhouette, no flat cards."""
    add_ico("HairCap", (0.0, 0.045, 1.890), (0.48, 0.40, 0.28), mats["hair"], root, "Head")
    curls = [
        ("CurlBack", (0.0, 0.165, 1.83), (0.34, 0.12, 0.18)),
        ("CurlLeft", (-0.205, -0.030, 1.79), (0.13, 0.15, 0.18)),
        ("CurlRight", (0.205, -0.030, 1.79), (0.13, 0.15, 0.18)),
        ("CurlFrontLeft", (-0.120, -0.205, 1.86), (0.11, 0.05, 0.10)),
        ("CurlFrontRight", (0.120, -0.205, 1.86), (0.11, 0.05, 0.10)),
    ]
    for name, loc, dims in curls:
        add_ico(name, loc, dims, mats["hair"], root, "Head")


def build_prospector(team_name):
    root = create_root("FTF_Character_Prospector_" + team_name)
    mats = create_role_materials("Prospector", team_name)
    add_female_body(root, mats, mats["primary"], mats["accent"], mats["dark"], sleeve_material=mats["primary"], cute=False)
    tune_prospector_face()

    # Practical field jacket and cargo gear, all offset from the body to avoid flicker.
    add_cube("ProspectorJacketFront", (0.0, -0.184, 1.21), (0.50, 0.046, 0.42), mats["primary"], root, "Chest", bevel=0.032)
    add_cube("ProspectorJacketZip", (0.0, -0.216, 1.21), (0.024, 0.014, 0.36), mats["dark"], root, "Chest", bevel=0.004)
    add_cube("ProspectorCollar", (0.0, -0.180, 1.48), (0.32, 0.038, 0.11), mats["team"], root, "Chest", bevel=0.018)
    add_cube("LeftCargoPant", (-0.145, 0.005, 0.70), (0.225, 0.265, 0.35), mats["accent"], root, "Thigh.R", bevel=0.028)
    add_cube("RightCargoPant", (0.145, 0.005, 0.70), (0.225, 0.265, 0.35), mats["accent"], root, "Thigh.L", bevel=0.028)
    # A four-sided outer belt shell replaces the old closed cube. The old cube
    # had its rear face exactly on Waist.y = +0.150, which produced a real
    # coplanar overlap after GLB re-import. This shell sits 4 mm outside the
    # waist on every side, has no top/bottom caps, and still reads as a fitted belt.
    add_open_box_band_shell(
        "ProspectorWaistBelt", 0.91, 0.229, 0.154, 0.090,
        mats["dark"], root, "Hips"
    )
    add_cube("LeftKneePad", (-0.145, -0.150, 0.47), (0.14, 0.030, 0.12), mats["dark"], root, "Shin.R", bevel=0.010)
    add_cube("RightKneePad", (0.145, -0.150, 0.47), (0.14, 0.030, 0.12), mats["dark"], root, "Shin.L", bevel=0.010)

    # Distinctive mining/scan equipment.
    add_cube("ProspectorBackpack", (0.0, 0.175, 1.17), (0.33, 0.14, 0.43), mats["dark"], root, "Chest", bevel=0.032)
    add_cube("BackpackRollTop", (0.0, 0.212, 1.38), (0.29, 0.10, 0.10), mats["primary"], root, "Chest", bevel=0.018)
    add_cube("LeftBackpackStrap", (-0.125, -0.120, 1.26), (0.060, 0.028, 0.33), mats["dark"], root, "Chest", bevel=0.010)
    add_cube("RightBackpackStrap", (0.125, -0.120, 1.26), (0.060, 0.028, 0.33), mats["dark"], root, "Chest", bevel=0.010)
    add_cube("ScannerPad", (0.22, -0.170, 1.08), (0.13, 0.040, 0.18), mats["accent"], root, "Hips", bevel=0.016)
    add_ico("ScannerLens", (0.22, -0.199, 1.10), (0.060, 0.018, 0.060), mats["team"], root, "Hips")
    # A compact, front-mounted headlamp replaces the old full circular disc,
    # which looked like a grey reflective plate from the front.
    add_cube("ProspectorHeadlampMount", (0.0, -0.190, 1.920), (0.250, 0.026, 0.052), mats["dark"], root, "Head", bevel=0.006)
    add_cube("ProspectorHeadlampHousing", (0.0, -0.231, 1.920), (0.168, 0.060, 0.104), mats["dark"], root, "Head", bevel=0.012)
    add_cube("ProspectorHeadlampRim", (0.0, -0.264, 1.920), (0.128, 0.012, 0.078), mats["team"], root, "Head", bevel=0.004)
    add_ico("ProspectorHeadlampLens", (0.0, -0.274, 1.920), (0.094, 0.014, 0.054), mats["accent"], root, "Head")
    add_short_curly_hair(root, mats)
    add_team_badge(root, mats, y=-0.209, z=1.31)
    return root


def build_flavor_trickster(team_name):
    root = create_root("FTF_Character_FlavorTrickster_" + team_name)
    mats = create_role_materials("FlavorTrickster", team_name)
    add_male_body(root, mats, mats["primary"], mats["dark"], mats["dark"], sleeve_material=mats["primary"])

    # Sturdy silhouette with playful disruptive-spice equipment. Every front layer
    # is pulled forward from the torso to avoid coplanar z-fighting.
    # Keep a 4 mm air gap from Torso.front (Y=-0.180). The old panel back face
    # was exactly Y=-0.180 after export, which is a real z-fighting risk.
    add_cube("TricksterVestFront", (0.0, -0.205, 1.20), (0.55, 0.042, 0.45), mats["primary"], root, "Chest", bevel=0.034)
    add_cube("TricksterApronPanel", (0.0, -0.225, 1.02), (0.30, 0.020, 0.40), mats["accent"], root, "Chest", bevel=0.012)
    add_cube("TricksterScarf", (0.0, -0.188, 1.43), (0.33, 0.040, 0.10), mats["team"], root, "Chest", bevel=0.018)
    # A closed cube belt creates hidden coplanar/near-coplanar faces with Waist.
    # Use an open sewn-on shell: 4 mm outside the Waist on every side, no caps.
    add_open_box_band_shell(
        "TricksterBelt", 0.90, 0.269, 0.164, 0.10,
        mats["accent"], root, "Hips", center_y=0.0,
    )
    add_cube("LeftWristWrap", (-0.60, -0.012, 0.98), (0.13, 0.12, 0.08), mats["team"], root, "Hand.R", bevel=0.014)
    add_cube("RightWristWrap", (0.60, -0.012, 0.98), (0.13, 0.12, 0.08), mats["team"], root, "Hand.L", bevel=0.014)

    # Spice canisters and a compact back rig.
    add_cube("SpiceRig", (0.0, 0.175, 1.10), (0.32, 0.12, 0.36), mats["dark"], root, "Chest", bevel=0.028)
    for name, x in (("Left", -0.12), ("Center", 0.0), ("Right", 0.12)):
        add_cylinder(name + "SpiceCanister", (x, 0.225, 1.11), 0.052, 0.18, mats["accent"], root, "Chest", vertices=6, bevel=0.006)
        add_cylinder(name + "CanisterCap", (x, 0.225, 1.22), 0.026, 0.045, mats["team"], root, "Chest", vertices=6)

    add_short_male_hair(root, mats)
    # Tilted chefish cap / bandana hybrid for a playful disruptive silhouette.
    add_cube("TricksterCapBase", (0.0, 0.030, 2.005), (0.34, 0.23, 0.10), mats["accent"], root, "Head", bevel=0.020, rotation=(0.0, 0.0, math.radians(14)))
    add_cube("TricksterCapTail", (0.16, 0.145, 1.985), (0.18, 0.08, 0.07), mats["team"], root, "Head", bevel=0.016, rotation=(0.0, 0.0, math.radians(22)))
    add_cube("TricksterMonocle", (0.095, -0.235, 1.765), (0.115, 0.016, 0.115), mats["accent"], root, "Head", bevel=0.006)
    add_cube("TricksterMonocleStrap", (0.0, -0.214, 1.820), (0.35, 0.010, 0.028), mats["dark"], root, "Head", bevel=0.003)
    add_team_badge(root, mats, y=-0.219, z=1.32)
    return root


ROLE_BUILDERS = {
    "Mage": build_mage,
    "Apothecary": build_apothecary,
    "Assistant": build_assistant,
    "Rider": build_rider,
    "Engineer": build_engineer,
    "Prospector": build_prospector,
    "FlavorTrickster": build_flavor_trickster,
}


# =============================================================================
# RIGGING
# =============================================================================

BONES = {
    "Root": ((0.0, 0.0, 0.02), (0.0, 0.0, 0.25), None, False),
    "Hips": ((0.0, 0.0, 0.25), (0.0, 0.0, 0.76), "Root", False),
    "Spine": ((0.0, 0.0, 0.76), (0.0, 0.0, 1.10), "Hips", True),
    "Chest": ((0.0, 0.0, 1.10), (0.0, 0.0, 1.50), "Spine", True),
    "Neck": ((0.0, 0.0, 1.50), (0.0, 0.0, 1.59), "Chest", True),
    "Head": ((0.0, 0.0, 1.59), (0.0, 0.0, 1.96), "Neck", True),
    # Character faces -Y. Anatomical right is the -X side.
    "UpperArm.R": ((-0.25, 0.0, 1.43), (-0.49, 0.0, 1.15), "Chest", False),
    "Forearm.R": ((-0.49, 0.0, 1.15), (-0.60, 0.0, 0.98), "UpperArm.R", True),
    "Hand.R": ((-0.60, 0.0, 0.98), (-0.62, 0.0, 0.84), "Forearm.R", True),
    "UpperArm.L": ((0.25, 0.0, 1.43), (0.49, 0.0, 1.15), "Chest", False),
    "Forearm.L": ((0.49, 0.0, 1.15), (0.60, 0.0, 0.98), "UpperArm.L", True),
    "Hand.L": ((0.60, 0.0, 0.98), (0.62, 0.0, 0.84), "Forearm.L", True),
    "Thigh.R": ((-0.13, 0.0, 0.76), (-0.17, 0.0, 0.42), "Hips", False),
    "Shin.R": ((-0.17, 0.0, 0.42), (-0.17, 0.0, 0.16), "Thigh.R", True),
    "Foot.R": ((-0.17, 0.0, 0.16), (-0.17, -0.24, 0.11), "Shin.R", False),
    "Thigh.L": ((0.13, 0.0, 0.76), (0.17, 0.0, 0.42), "Hips", False),
    "Shin.L": ((0.17, 0.0, 0.42), (0.17, 0.0, 0.16), "Thigh.L", True),
    "Foot.L": ((0.17, 0.0, 0.16), (0.17, -0.24, 0.11), "Shin.L", False),
}


def create_armature(root):
    armature_data = bpy.data.armatures.new("CharacterSkeleton")
    armature = bpy.data.objects.new("CharacterSkeleton", armature_data)
    bpy.context.collection.objects.link(armature)
    armature.parent = root
    armature.show_in_front = True
    armature.data.display_type = "OCTAHEDRAL"

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = {}
    for name, (head, tail, parent_name, connected) in BONES.items():
        bone = armature.data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = name != "Root"
        edit_bones[name] = bone
        if parent_name:
            bone.parent = edit_bones[parent_name]
            bone.use_connect = connected
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def bind_mesh_rigid(mesh, armature):
    world_matrix = mesh.matrix_world.copy()
    mesh.parent = None
    mesh.matrix_world = world_matrix
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            mesh.modifiers.remove(modifier)
    mesh.vertex_groups.clear()

    bone_name = mesh.get("bind_bone", "Chest")
    if bone_name not in armature.data.bones:
        raise RuntimeError(f"Unknown bind bone {bone_name} for {mesh.name}")
    group = mesh.vertex_groups.new(name=bone_name)
    group.add(list(range(len(mesh.data.vertices))), 1.0, "REPLACE")
    modifier = mesh.modifiers.new(name="CharacterSkeleton", type="ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    mesh.parent = armature
    mesh["bound_bone"] = bone_name


def rig_character(root):
    armature = create_armature(root)
    meshes = [child for child in root.children if child.type == "MESH"]
    for mesh in meshes:
        bind_mesh_rigid(mesh, armature)
    root["rig_type"] = "rigid_low_poly_humanoid"
    root["skeleton_bones"] = len(BONES)
    root["animation_ready"] = True
    return armature, meshes


# =============================================================================
# ANIMATION CREATION
# =============================================================================

def reset_pose(armature):
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def point_bone_between(bone, start, end):
    direction = Vector(end) - Vector(start)
    if direction.length_squared < 0.000001:
        return
    rotation = direction.normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()
    bone.matrix = Matrix.Translation(Vector(start)) @ rotation


def solve_right_arm(armature, target, bend_hint):
    bpy.context.view_layer.update()
    upper = armature.pose.bones["UpperArm.R"]
    forearm = armature.pose.bones["Forearm.R"]
    shoulder = upper.head.copy()
    wrist = Vector(target)
    to_target = wrist - shoulder
    distance = max(0.0001, to_target.length)
    length_upper = upper.bone.length
    length_forearm = forearm.bone.length
    max_reach = (length_upper + length_forearm) * 0.985
    if distance > max_reach:
        wrist = shoulder + to_target.normalized() * max_reach
        to_target = wrist - shoulder
        distance = max_reach

    axis = to_target.normalized()
    along = (length_upper * length_upper - length_forearm * length_forearm + distance * distance) / (2.0 * distance)
    height = math.sqrt(max(0.0, length_upper * length_upper - along * along))
    bend = Vector(bend_hint)
    perpendicular = bend - axis * bend.dot(axis)
    if perpendicular.length_squared < 0.000001:
        perpendicular = Vector((1.0, 0.0, 0.0))
    perpendicular.normalize()
    elbow = shoulder + axis * along + perpendicular * height

    point_bone_between(upper, shoulder, elbow)
    bpy.context.view_layer.update()
    point_bone_between(forearm, elbow, wrist)
    bpy.context.view_layer.update()


def insert_full_pose(armature, frame, transforms):
    reset_pose(armature)
    for bone_name, transform in transforms.items():
        if bone_name.startswith("__"):
            continue
        bone = armature.pose.bones.get(bone_name)
        if bone is None:
            continue
        if "rot" in transform:
            bone.rotation_euler = transform["rot"]
        if "loc" in transform:
            bone.location = transform["loc"]
    if "__right_arm_ik" in transforms:
        ik = transforms["__right_arm_ik"]
        solve_right_arm(armature, ik["target"], ik["bend"])
    for bone in armature.pose.bones:
        if bone.name == "Root":
            continue
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)


def create_actions(armature):
    armature.animation_data_create()
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)

    for old_action in list(bpy.data.actions):
        bpy.data.actions.remove(old_action)

    for name, spec in ANIMATIONS.items():
        action = bpy.data.actions.new(name=name)
        armature.animation_data.action = action
        for frame, transforms in spec["keys"]:
            insert_full_pose(armature, frame, transforms)
        action["loop"] = spec["loop"]
        action["fps"] = FPS
        action.use_fake_user = True

        for fcurve in action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "BEZIER"

        # Separate NLA track per action. Matches the prior pipeline's GLB export mode.
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.action_frame_start = 1.0
        strip.action_frame_end = float(spec["end"])

    armature.animation_data.action = None
    reset_pose(armature)


# =============================================================================
# VALIDATION / EXPORT
# =============================================================================

# z-fighting prevention audit --------------------------------------------------
# A close visual overlap may be intentional if one mesh sits in front of another,
# but coplanar, overlapping triangles from distinct visual objects are never
# allowed. The audit is run before export and again after GLB re-import.
COPLANAR_PLANE_EPS = 0.00020
COPLANAR_NORMAL_EPS = 0.00050
COPLANAR_AREA_EPS = 0.000001


def _canonical_plane(a, b, c):
    normal = (b - a).cross(c - a)
    if normal.length_squared < 1e-14:
        return None
    normal.normalize()
    # Canonicalize +/- normal so reverse-wound coincident faces share a key.
    for component in (normal.x, normal.y, normal.z):
        if abs(component) > 1e-8:
            if component < 0.0:
                normal = -normal
            break
    distance = normal.dot(a)
    return normal, distance


def _project_2d(point, normal):
    ax = abs(normal.x)
    ay = abs(normal.y)
    az = abs(normal.z)
    # Drop the axis most parallel to the triangle normal.
    if ax >= ay and ax >= az:
        return (point.y, point.z)
    if ay >= az:
        return (point.x, point.z)
    return (point.x, point.y)


def _polygon_area(points):
    area = 0.0
    for index, point in enumerate(points):
        next_point = points[(index + 1) % len(points)]
        area += point[0] * next_point[1] - point[1] * next_point[0]
    return area * 0.5


def _ensure_ccw(points):
    return points if _polygon_area(points) >= 0.0 else list(reversed(points))


def _line_intersection(a, b, c, d):
    r = (b[0] - a[0], b[1] - a[1])
    s = (d[0] - c[0], d[1] - c[1])
    denominator = r[0] * s[1] - r[1] * s[0]
    if abs(denominator) < 1e-12:
        return b
    t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / denominator
    return (a[0] + t * r[0], a[1] + t * r[1])


def _clip_polygon(subject, clip_polygon):
    clip_polygon = _ensure_ccw(clip_polygon)
    output = subject
    for index, edge_start in enumerate(clip_polygon):
        edge_end = clip_polygon[(index + 1) % len(clip_polygon)]
        if not output:
            break
        input_points = output
        output = []
        previous = input_points[-1]
        for current in input_points:
            cross_current = (
                (edge_end[0] - edge_start[0]) * (current[1] - edge_start[1])
                - (edge_end[1] - edge_start[1]) * (current[0] - edge_start[0])
            )
            cross_previous = (
                (edge_end[0] - edge_start[0]) * (previous[1] - edge_start[1])
                - (edge_end[1] - edge_start[1]) * (previous[0] - edge_start[0])
            )
            current_inside = cross_current >= -1e-10
            previous_inside = cross_previous >= -1e-10
            if current_inside:
                if not previous_inside:
                    output.append(_line_intersection(previous, current, edge_start, edge_end))
                output.append(current)
            elif previous_inside:
                output.append(_line_intersection(previous, current, edge_start, edge_end))
            previous = current
    return output


def _triangles_for_mesh(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        matrix = evaluated.matrix_world.copy()
        records = []
        for triangle in mesh.loop_triangles:
            a, b, c = (matrix @ mesh.vertices[index].co for index in triangle.vertices)
            plane = _canonical_plane(a, b, c)
            if plane is None:
                continue
            normal, distance = plane
            projected = [_project_2d(point, normal) for point in (a, b, c)]
            min_x = min(point[0] for point in projected)
            max_x = max(point[0] for point in projected)
            min_y = min(point[1] for point in projected)
            max_y = max(point[1] for point in projected)
            key = (
                round(normal.x / COPLANAR_NORMAL_EPS),
                round(normal.y / COPLANAR_NORMAL_EPS),
                round(normal.z / COPLANAR_NORMAL_EPS),
                round(distance / COPLANAR_PLANE_EPS),
            )
            records.append((key, obj.name, projected, (min_x, max_x, min_y, max_y)))
        return records
    finally:
        evaluated.to_mesh_clear()


def validate_no_coplanar_overlaps(meshes, stage):
    grouped = {}
    for mesh in meshes:
        for record in _triangles_for_mesh(mesh):
            grouped.setdefault(record[0], []).append(record)

    offenders = []
    for records in grouped.values():
        # Only compare triangles from different visible Mesh objects.
        for first_index in range(len(records)):
            _, first_name, first_triangle, first_bounds = records[first_index]
            for second_index in range(first_index + 1, len(records)):
                _, second_name, second_triangle, second_bounds = records[second_index]
                if first_name == second_name:
                    continue
                if (
                    first_bounds[1] <= second_bounds[0] + 1e-9
                    or second_bounds[1] <= first_bounds[0] + 1e-9
                    or first_bounds[3] <= second_bounds[2] + 1e-9
                    or second_bounds[3] <= first_bounds[2] + 1e-9
                ):
                    continue
                overlap = _clip_polygon(first_triangle, second_triangle)
                if len(overlap) >= 3 and abs(_polygon_area(overlap)) > COPLANAR_AREA_EPS:
                    offenders.append((first_name, second_name))
                    if len(offenders) >= 12:
                        break
            if len(offenders) >= 12:
                break
        if len(offenders) >= 12:
            break

    if offenders:
        unique = sorted({"%s <-> %s" % pair for pair in offenders})
        raise RuntimeError("Potential z-fighting coplanar overlap at %s: %s" % (stage, "; ".join(unique)))
    print("SURFACE AUDIT OK %s: no coplanar overlapping triangles across %d meshes" % (stage, len(meshes)))


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def validate_character(root, armature, meshes):
    failures = []
    if root.type != "EMPTY":
        failures.append("root must be Empty")
    if len([obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]) != 1:
        failures.append("expected exactly one armature in build scene")
    if len(armature.data.bones) != len(BONES):
        failures.append("unexpected skeleton bone count")

    for obj in meshes:
        upper_name = obj.name.upper()
        if upper_name.startswith(("UCX_", "MESH_UCX_")):
            failures.append("collision mesh: " + obj.name)
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale: " + obj.name)
        if "." in obj.name:
            failures.append("generated non-semantic suffix: " + obj.name)
        if obj.get("bound_bone") not in armature.data.bones:
            failures.append("missing valid rigid bind: " + obj.name)
        for vertex in obj.data.vertices:
            co = obj.matrix_world @ vertex.co
            if not all(math.isfinite(value) for value in co):
                failures.append("non-finite vertex: " + obj.name)
                break

    if failures:
        raise RuntimeError("; ".join(failures))

    validate_no_coplanar_overlaps(meshes, "build")

    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)
    attached_materials = {mat.name for mesh in meshes for mat in mesh.data.materials if mat}
    expression_meshes = [mesh for mesh in meshes if mesh.data.shape_keys]
    if not expression_meshes:
        raise RuntimeError("No blend-shape facial meshes found")
    for mesh in expression_meshes:
        names = {block.name for block in mesh.data.shape_keys.key_blocks}
        if not set(EXPRESSIONS).issubset(names):
            raise RuntimeError(f"Missing facial expressions on {mesh.name}: {sorted(set(EXPRESSIONS) - names)}")

    print(
        f"VALID {root.name}: meshes={len(meshes)}, materials={len(attached_materials)}, "
        f"triangles={triangles}, bones={len(armature.data.bones)}, expression_meshes={len(expression_meshes)}"
    )


def export_character(root, output_path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        # Keep the non-deforming Root bone in the GLB. With export_def_bones=True
        # Blender 4.4 filters it out, because Root.use_deform is False. That leads
        # to a 17-bone import even though the authored rig has 18 bones.
        export_def_bones=False,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )


def action_matches(imported_actions, wanted_name):
    direct = next((action for action in imported_actions if action.name == wanted_name), None)
    if direct:
        return direct
    return next((action for action in imported_actions if action.name.endswith(wanted_name)), None)


def verify_export(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    collision_meshes = [obj.name for obj in meshes if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))]
    zero_scale = [obj.name for obj in meshes if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001]
    negative_scale = [obj.name for obj in meshes if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0]
    actions = list(bpy.data.actions)
    missing_actions = [name for name in ANIMATIONS if action_matches(actions, name) is None]

    expression_meshes = []
    incomplete_expressions = []
    for mesh in meshes:
        if mesh.data.shape_keys is None:
            continue
        names = {block.name for block in mesh.data.shape_keys.key_blocks if block.name != "Basis"}
        if names:
            expression_meshes.append(mesh.name)
            if not set(EXPRESSIONS).issubset(names):
                incomplete_expressions.append(mesh.name)

    # The exported GLB must retain all authored bones, including the non-deforming
    # Root bone. This is why export_character uses export_def_bones=False.
    validate_no_coplanar_overlaps(meshes, "reimport")

    if (
        len(armatures) != 1
        or len(armatures[0].data.bones) != len(BONES)
        or collision_meshes
        or zero_scale
        or negative_scale
        or missing_actions
        or not expression_meshes
        or incomplete_expressions
    ):
        raise RuntimeError(
            f"Invalid GLB {path}: armatures={len(armatures)}, bones="
            f"{len(armatures[0].data.bones) if armatures else 0}, collision={collision_meshes}, "
            f"zero={zero_scale}, negative={negative_scale}, missing_actions={missing_actions}, "
            f"expression_meshes={expression_meshes}, incomplete_expressions={incomplete_expressions}"
        )

    print(
        f"REIMPORT OK {os.path.basename(path)}: meshes={len(meshes)}, bones={len(armatures[0].data.bones)}, "
        f"actions={len(actions)}, expression_meshes={len(expression_meshes)}"
    )


# =============================================================================
# POSE RENDER CHECKS
# =============================================================================

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_lighting_and_camera():
    bpy.ops.mesh.primitive_plane_add(size=7.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_mat = make_material("MAT_PreviewGround", "#19241F", roughness=0.96)
    ground.data.materials.append(ground_mat)

    bpy.ops.object.camera_add(location=(3.45, -5.30, 2.75))
    camera = bpy.context.object
    look_at(camera, (0.0, 0.0, 1.10))
    bpy.context.scene.camera = camera

    for name, location, energy, size in (
        ("Key", (-3.0, -4.0, 5.0), 950.0, 4.0),
        ("Fill", (4.0, -1.0, 3.4), 620.0, 3.0),
        ("Rim", (1.0, 3.2, 4.2), 460.0, 2.5),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, (0.0, 0.0, 1.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.012, 0.018, 0.025)


def render_pose_checks(glb_path, output_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    add_preview_lighting_and_camera()

    role_stem = os.path.splitext(os.path.basename(glb_path))[0]
    pose_dir = os.path.join(output_dir, "pose_checks", role_stem)
    os.makedirs(pose_dir, exist_ok=True)
    imported_actions = list(bpy.data.actions)

    # Disable NLA influence for a deterministic direct action preview.
    armature.animation_data_create()
    for track in armature.animation_data.nla_tracks:
        track.mute = True

    for action_name, frame in POSE_CHECKS.items():
        action = action_matches(imported_actions, action_name)
        if action is None:
            raise RuntimeError(f"Cannot render missing action {action_name} from {glb_path}")
        armature.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        bpy.context.scene.render.filepath = os.path.join(pose_dir, action_name + ".png")
        bpy.ops.render.render(write_still=True)
        print(f"POSECHECK {role_stem} {action_name}: {bpy.context.scene.render.filepath}")

    # A rear three-quarter Idle render is especially useful for checking hair,
    # backpacks, robe shells and skirt hems that a front camera would hide.
    idle_action = action_matches(imported_actions, "Idle")
    if idle_action is not None:
        armature.animation_data.action = idle_action
        bpy.context.scene.frame_set(1)
        camera = bpy.context.scene.camera
        camera.location = (-3.45, 5.30, 2.75)
        look_at(camera, (0.0, 0.0, 1.10))
        bpy.context.scene.render.filepath = os.path.join(pose_dir, "Idle_BackThreeQuarter.png")
        bpy.ops.render.render(write_still=True)
        print(f"POSECHECK {role_stem} Idle_BackThreeQuarter: {bpy.context.scene.render.filepath}")


# =============================================================================
# BUILD / MAIN
# =============================================================================

def build_export_validate_variant(role_name, team_name, output_dir, render_checks):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ensure_metric_scene()
    root = ROLE_BUILDERS[role_name](team_name)
    armature, meshes = rig_character(root)
    create_actions(armature)
    validate_character(root, armature, meshes)

    output_path = os.path.join(output_dir, f"FTF_Character_{role_name}_{team_name}_Rigged_V3_9.glb")
    export_character(root, output_path)
    print("EXPORTED", output_path)

    verify_export(output_path)
    if render_checks:
        render_pose_checks(output_path, output_dir)
    return output_path


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    output_paths = []
    for role_name in ("Mage", "Apothecary", "Assistant", "Rider", "Engineer", "Prospector", "FlavorTrickster"):
        for team_name in ("Red", "Blue"):
            output_paths.append(
                build_export_validate_variant(
                    role_name,
                    team_name,
                    output_dir,
                    render_checks=RENDER_POSE_CHECKS and not args.skip_pose_renders,
                )
            )

    print("DONE: generated %d animated Mage/Apothecary/Assistant/Rider/Engineer/Prospector/FlavorTrickster character GLBs in %s" % (len(output_paths), output_dir))


if __name__ == "__main__":
    main()
