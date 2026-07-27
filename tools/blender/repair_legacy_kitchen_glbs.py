import bpy
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
KITCHEN_DIR = os.path.join(PROJECT_ROOT, "assets", "kitchen")

FILES = [
    f"FTF_Kitchen_{asset}_{color}.glb"
    for asset in ("Chopping_Station", "Oven", "Pot")
    for color in ("Red", "Blue", "Green", "Yellow")
]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def is_collision_mesh(obj):
    upper_name = obj.name.upper()
    return (
        obj.type == "MESH"
        and (
            upper_name.startswith(("UCX_", "MESH_UCX_"))
            or obj.get("ftf_role") == "collision"
        )
    )


def repair(path):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)

    removed = []
    for obj in list(bpy.context.scene.objects):
        if is_collision_mesh(obj):
            removed.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)

    remaining = [
        obj.name
        for obj in bpy.context.scene.objects
        if is_collision_mesh(obj)
    ]
    if remaining:
        raise RuntimeError(f"Collision meshes remain in {path}: {remaining}")

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print(f"REPAIRED {os.path.basename(path)} removed={removed}")


for filename in FILES:
    repair(os.path.join(KITCHEN_DIR, filename))
