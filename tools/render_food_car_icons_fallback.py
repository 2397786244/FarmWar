"""Render the food-car GLBs into transparent square PNG placeholders.

This uses the same dependency-free GLB rasterizer as the Range Ledger fallback.
It is intentionally separate from the Range Ledger job list so running it does
not change or overwrite any weapon reference images.
"""

import argparse
from pathlib import Path

from render_rangeledger_assets_fallback import load_triangles, rasterize, write_png


JOBS = [
    ("food_truck", "assets/vehicles/FTF_Vehicle_FoodTruck_Pink_BurgerSign_5_5m.glb"),
    ("burger", "assets/food/fast_food/Burger.glb"),
    ("fries", "assets/food/fast_food/Fries.glb"),
    ("taco", "assets/food/fast_food/Taco.glb"),
    ("soda", "assets/food/fast_food/Soda.glb"),
    ("ice_cream", "assets/food/fast_food/IceCream.glb"),
    ("egg_tart", "assets/food/fast_food/Eggtart.glb"),
    ("fried_chicken_nuggets", "assets/food/fast_food/FriedChickenNuggets.glb"),
]


def parse_args():
    parser = argparse.ArgumentParser(description="Render food-car icons without external Python packages.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", default="assets/icons/food_car")
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--only", default="")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output = (project / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    only = {value.strip() for value in args.only.split(",") if value.strip()}
    jobs = [(image_id, model) for image_id, model in JOBS if not only or image_id in only]
    counts = {"rendered": 0, "skipped": 0, "failed": 0}
    for image_id, relative_model in jobs:
        destination = output / f"{image_id}.png"
        if destination.is_file() and not args.overwrite:
            print(f"[FoodCarFallback] SKIP {image_id}")
            counts["skipped"] += 1
            continue
        try:
            triangles = load_triangles(project / relative_model)
            if not triangles:
                raise ValueError("model contains no triangles")
            write_png(destination, rasterize(triangles, args.size), args.size)
            print(f"[FoodCarFallback] RENDER {image_id}: {destination} ({len(triangles)} triangles)")
            counts["rendered"] += 1
        except Exception as exc:
            print(f"[FoodCarFallback] FAILED {image_id}: {exc}")
            counts["failed"] += 1
    print(f"[FoodCarFallback] Done: {counts}")
    if counts["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
