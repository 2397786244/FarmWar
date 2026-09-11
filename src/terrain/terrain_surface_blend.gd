@tool
class_name TerrainSurfaceBlend
extends RefCounted

## Shared codec for the four indexed terrain surfaces stored at every authoring
## texel. IDs and weights deliberately live in separate RGBA8 images: IDs must
## never be filtered, while the derived render image can be filtered normally.

const LAYER_COUNT := 4
const WEIGHT_EPSILON := 0.0001


static func make_default_ids(default_surface_id: int) -> Color:
	var encoded := float(clampi(default_surface_id, 0, 255)) / 255.0
	return Color(encoded, encoded, encoded, encoded)


static func make_default_weights() -> Color:
	return Color(1.0, 0.0, 0.0, 0.0)


static func decode_ids(encoded: Color) -> PackedInt32Array:
	return PackedInt32Array([
		clampi(roundi(encoded.r * 255.0), 0, 255),
		clampi(roundi(encoded.g * 255.0), 0, 255),
		clampi(roundi(encoded.b * 255.0), 0, 255),
		clampi(roundi(encoded.a * 255.0), 0, 255),
	])


static func decode_weights(encoded: Color) -> PackedFloat32Array:
	return PackedFloat32Array([
		clampf(encoded.r, 0.0, 1.0),
		clampf(encoded.g, 0.0, 1.0),
		clampf(encoded.b, 0.0, 1.0),
		clampf(encoded.a, 0.0, 1.0),
	])


static func encode_ids(ids: PackedInt32Array, default_surface_id: int) -> Color:
	var fallback := clampi(default_surface_id, 0, 255)
	return Color(
		float(_id_at(ids, 0, fallback)) / 255.0,
		float(_id_at(ids, 1, fallback)) / 255.0,
		float(_id_at(ids, 2, fallback)) / 255.0,
		float(_id_at(ids, 3, fallback)) / 255.0
	)


static func encode_weights(weights: PackedFloat32Array) -> Color:
	return Color(
		_weight_at(weights, 0),
		_weight_at(weights, 1),
		_weight_at(weights, 2),
		_weight_at(weights, 3)
	)


static func normalize_encoded(
	id_color: Color,
	weight_color: Color,
	default_surface_id: int
) -> Dictionary:
	var ids := decode_ids(id_color)
	var weights := decode_weights(weight_color)
	_normalize_layers(ids, weights, default_surface_id)
	return {
		"ids": encode_ids(ids, default_surface_id),
		"weights": encode_weights(weights),
	}


static func paint_encoded(
	id_color: Color,
	weight_color: Color,
	target_surface_id: int,
	amount: float,
	default_surface_id: int
) -> Dictionary:
	var ids := decode_ids(id_color)
	var weights := decode_weights(weight_color)
	_normalize_layers(ids, weights, default_surface_id)

	var target_id := clampi(target_surface_id, 0, 255)
	var target_index := -1
	for index in range(LAYER_COUNT):
		if ids[index] == target_id and weights[index] > WEIGHT_EPSILON:
			target_index = index
			break

	if target_index < 0:
		# A fifth surface deterministically replaces the weakest contribution.
		# Keeping that contribution before blending avoids a sudden loss of total
		# weight and makes a newly introduced surface visible immediately.
		target_index = 0
		for index in range(1, LAYER_COUNT):
			if weights[index] < weights[target_index]:
				target_index = index
		ids[target_index] = target_id

	var blend_amount := clampf(amount, 0.0, 1.0)
	for index in range(LAYER_COUNT):
		weights[index] *= 1.0 - blend_amount
	weights[target_index] += blend_amount
	_normalize_layers(ids, weights, default_surface_id)
	return {
		"ids": encode_ids(ids, default_surface_id),
		"weights": encode_weights(weights),
	}


static func remap_encoded(
	id_color: Color,
	weight_color: Color,
	old_surface_id: int,
	replacement_surface_id: int,
	default_surface_id: int
) -> Dictionary:
	var ids := decode_ids(id_color)
	var weights := decode_weights(weight_color)
	for index in range(LAYER_COUNT):
		if ids[index] == old_surface_id:
			ids[index] = replacement_surface_id
	_normalize_layers(ids, weights, default_surface_id)
	return {
		"ids": encode_ids(ids, default_surface_id),
		"weights": encode_weights(weights),
	}


static func get_surface_weight(
	id_color: Color,
	weight_color: Color,
	surface_id: int
) -> float:
	var ids := decode_ids(id_color)
	var weights := decode_weights(weight_color)
	var result := 0.0
	for index in range(LAYER_COUNT):
		if ids[index] == surface_id:
			result += weights[index]
	return clampf(result, 0.0, 1.0)


static func resolve_color(
	id_color: Color,
	weight_color: Color,
	palette_image: Image,
	default_surface_id: int
) -> Color:
	if palette_image == null or palette_image.is_empty():
		return Color(0.35, 0.65, 0.3, 0.9)
	var palette_width := palette_image.get_width()
	var weights := Color(
		clampf(weight_color.r, 0.0, 1.0),
		clampf(weight_color.g, 0.0, 1.0),
		clampf(weight_color.b, 0.0, 1.0),
		clampf(weight_color.a, 0.0, 1.0)
	)
	var total := weights.r + weights.g + weights.b + weights.a
	if total <= WEIGHT_EPSILON:
		return palette_image.get_pixel(
			clampi(default_surface_id, 0, palette_width - 1), 0
		)
	var result := (
		palette_image.get_pixel(clampi(roundi(id_color.r * 255.0), 0, palette_width - 1), 0) * weights.r
		+ palette_image.get_pixel(clampi(roundi(id_color.g * 255.0), 0, palette_width - 1), 0) * weights.g
		+ palette_image.get_pixel(clampi(roundi(id_color.b * 255.0), 0, palette_width - 1), 0) * weights.b
		+ palette_image.get_pixel(clampi(roundi(id_color.a * 255.0), 0, palette_width - 1), 0) * weights.a
	)
	return result / total


static func _normalize_layers(
	ids: PackedInt32Array,
	weights: PackedFloat32Array,
	default_surface_id: int
) -> void:
	var fallback := clampi(default_surface_id, 0, 255)
	for index in range(LAYER_COUNT):
		ids[index] = clampi(ids[index], 0, 255)
		weights[index] = clampf(weights[index], 0.0, 1.0)

	# Merge duplicate IDs into their first active slot.
	for index in range(LAYER_COUNT):
		if weights[index] <= WEIGHT_EPSILON:
			weights[index] = 0.0
			continue
		for previous in range(index):
			if ids[previous] == ids[index] and weights[previous] > 0.0:
				weights[previous] += weights[index]
				weights[index] = 0.0
				break

	var total := 0.0
	for weight in weights:
		total += weight
	if total <= WEIGHT_EPSILON:
		ids[0] = fallback
		weights[0] = 1.0
		for index in range(1, LAYER_COUNT):
			ids[index] = fallback
			weights[index] = 0.0
		return

	for index in range(LAYER_COUNT):
		weights[index] /= total
		if weights[index] <= WEIGHT_EPSILON:
			weights[index] = 0.0
			ids[index] = fallback


static func _id_at(ids: PackedInt32Array, index: int, fallback: int) -> int:
	return clampi(ids[index], 0, 255) if index < ids.size() else fallback


static func _weight_at(weights: PackedFloat32Array, index: int) -> float:
	return clampf(weights[index], 0.0, 1.0) if index < weights.size() else 0.0
