@tool
class_name GrassScatterBakeData
extends Resource

const FORMAT_VERSION := 2

@export var format_version := FORMAT_VERSION
@export var terrain_size := Vector2.ZERO
@export var chunk_size := 32.0
@export var random_seed := 0
@export var small_chunks: Dictionary = {}
@export var tall_chunks: Dictionary = {}
@export var black_eyed_susan_chunks: Dictionary = {}
@export var coneflower_chunks: Dictionary = {}
@export var fern_chunks: Dictionary = {}


func is_compatible(expected_size: Vector2, expected_chunk_size: float, expected_seed: int) -> bool:
	return format_version == FORMAT_VERSION \
		and terrain_size.is_equal_approx(expected_size) \
		and is_equal_approx(chunk_size, expected_chunk_size) \
		and random_seed == expected_seed
