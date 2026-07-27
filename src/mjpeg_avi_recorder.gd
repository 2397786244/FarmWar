extends RefCounted
class_name MjpegAviRecorder

var _file: FileAccess
var _frame_offsets: PackedInt32Array = PackedInt32Array()
var _frame_sizes: PackedInt32Array = PackedInt32Array()
var _width := 0
var _height := 0
var _fps := 15
var _frame_count := 0
var _riff_size_position := 0
var _total_frames_position := 0
var _stream_length_position := 0
var _movi_size_position := 0
var _movi_data_position := 0
var _output_path := ""


func start(path: String, width: int, height: int, fps: int) -> bool:
	_output_path = path
	_width = maxi(2, width - (width % 2))
	_height = maxi(2, height - (height % 2))
	_fps = maxi(1, fps)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return false
	_file.big_endian = false
	_write_header()
	return true


func is_open() -> bool:
	return _file != null


func add_frame(image: Image, jpeg_quality: float = 0.85) -> bool:
	if _file == null or image == null or image.is_empty():
		return false
	if image.get_width() != _width or image.get_height() != _height:
		image.resize(_width, _height, Image.INTERPOLATE_BILINEAR)
	var jpeg := image.save_jpg_to_buffer(clampf(jpeg_quality, 0.1, 1.0))
	if jpeg.is_empty():
		return false
	var chunk_position := _file.get_position()
	_store_fourcc("00dc")
	_file.store_32(jpeg.size())
	_file.store_buffer(jpeg)
	if (jpeg.size() & 1) != 0:
		_file.store_8(0)
	# AVI 1.0 idx1 offsets are relative to the `movi` FOURCC, so the first
	# media chunk begins at offset 4.
	_frame_offsets.append(int(chunk_position - (_movi_data_position - 4)))
	_frame_sizes.append(jpeg.size())
	_frame_count += 1
	return true


func finish() -> String:
	if _file == null:
		return _output_path
	var movi_end := _file.get_position()
	_patch_u32(_movi_size_position, int(movi_end - (_movi_size_position + 4)))
	_store_fourcc("idx1")
	_file.store_32(_frame_count * 16)
	for index in range(_frame_count):
		_store_fourcc("00dc")
		_file.store_32(0x10)
		_file.store_32(_frame_offsets[index])
		_file.store_32(_frame_sizes[index])
	var file_end := _file.get_position()
	_patch_u32(_riff_size_position, int(file_end - 8))
	_patch_u32(_total_frames_position, _frame_count)
	_patch_u32(_stream_length_position, _frame_count)
	_file.close()
	_file = null
	return _output_path


func _write_header() -> void:
	_store_fourcc("RIFF")
	_riff_size_position = _file.get_position()
	_file.store_32(0)
	_store_fourcc("AVI ")

	_store_fourcc("LIST")
	_file.store_32(192)
	_store_fourcc("hdrl")
	_store_fourcc("avih")
	_file.store_32(56)
	_file.store_32(roundi(1000000.0 / float(_fps)))
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0x10)
	_total_frames_position = _file.get_position()
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(1)
	_file.store_32(_width * _height * 3)
	_file.store_32(_width)
	_file.store_32(_height)
	for unused in range(4):
		_file.store_32(0)

	_store_fourcc("LIST")
	_file.store_32(116)
	_store_fourcc("strl")
	_store_fourcc("strh")
	_file.store_32(56)
	_store_fourcc("vids")
	_store_fourcc("MJPG")
	_file.store_32(0)
	_file.store_16(0)
	_file.store_16(0)
	_file.store_32(0)
	_file.store_32(1)
	_file.store_32(_fps)
	_file.store_32(0)
	_stream_length_position = _file.get_position()
	_file.store_32(0)
	_file.store_32(_width * _height * 3)
	_file.store_32(0xFFFFFFFF)
	_file.store_32(0)
	_file.store_16(0)
	_file.store_16(0)
	_file.store_16(_width)
	_file.store_16(_height)

	_store_fourcc("strf")
	_file.store_32(40)
	_file.store_32(40)
	_file.store_32(_width)
	_file.store_32(_height)
	_file.store_16(1)
	_file.store_16(24)
	_store_fourcc("MJPG")
	_file.store_32(_width * _height * 3)
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0)

	_store_fourcc("LIST")
	_movi_size_position = _file.get_position()
	_file.store_32(0)
	_store_fourcc("movi")
	_movi_data_position = _file.get_position()


func _store_fourcc(value: String) -> void:
	_file.store_buffer(value.to_ascii_buffer())


func _patch_u32(position: int, value: int) -> void:
	var return_position := _file.get_position()
	_file.seek(position)
	_file.store_32(value)
	_file.seek(return_position)
