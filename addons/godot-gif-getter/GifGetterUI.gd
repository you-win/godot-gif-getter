extends CanvasLayer

const GIF_EXPORTER = preload("res://addons/gdgifexporter/gifexporter.gd")
const MEDIAN_CUT = preload("res://addons/gdgifexporter/quantization/median_cut.gd")
const EUQ = preload("res://addons/gdgifexporter/quantization/enhanced_uniform_quantization.gd")

const MAX_CONSOLE_MESSAGE_COUNT: int = 20

onready var control: Control = $Control

onready var capture_now_button: Button = $Control/Options/VBoxContainer/ButtonContainer/CaptureNowButton
onready var capture_in_five_seconds_button: Button = $Control/Options/VBoxContainer/ButtonContainer/CaptureInFiveSecondsButton
onready var save_location_line_edit: LineEdit = $Control/Options/VBoxContainer/SaveLocationContainer/LineEdit
onready var frames_line_edit: LineEdit = $Control/Options/VBoxContainer/FramesContainer/LineEdit
onready var frame_skip_line_edit: LineEdit = $Control/Options/VBoxContainer/FrameSkipContainer/LineEdit
onready var frame_delay_line_edit: LineEdit = $Control/Options/VBoxContainer/FrameDelayContainer/LineEdit
onready var threads_line_edit: LineEdit = $Control/Options/VBoxContainer/ThreadsContainer/LineEdit

onready var console: VBoxContainer = $Control/Console/ScrollContainer/VBoxContainer

onready var _viewport: Viewport = get_viewport()

# Main exporter, coalesces all buffers into one and saves to file
var _gif_exporter: GifExporter

# Determines if viewport texture data should be stored for processing
var _should_capture: bool = false
# Holds viewport texture data
var _images: Array = []

# Delay between storing viewport texture data
var _frame_skip: int = 3
# Count ticks between each frame skip
var _frame_skip_counter: int = 0

# Delay between each frame in the gif
var _gif_frame_delay: float = 0.1

# Total number of frames in the gif
var _max_frames: int = 20
# Count frames stored
var _current_frame: int = 1

# Main coalescing thread
var _render_thread: Thread = Thread.new()

# Number of render threads
var _max_threads: int = 4
# Render thread storage
var _render_threads: Array = []

# Path to intended save location
var _save_location: String = "user://result.gif"

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	_gif_exporter = GIF_EXPORTER.new(_viewport.size.x, _viewport.size.y)
	
	capture_now_button.connect("pressed", self, "_on_capture_now")
	capture_in_five_seconds_button.connect("pressed", self, "_on_capture_in_five_seconds")
	$Control/Options/VBoxContainer/SaveLocationContainer/Button.connect("pressed", self, "_on_select_path_button_pressed")

func _physics_process(_delta: float) -> void:
	if _should_capture:
		_frame_skip_counter += 1
		if (_frame_skip_counter > _frame_skip and _current_frame <= _max_frames):
			var image: Image = _viewport.get_texture().get_data()
			image.convert(Image.FORMAT_RGBA8)
			image.flip_y() # Images from the viewport are upside down
			
			_images.append(image)
			
			_frame_skip_counter = 0
			_current_frame += 1
		elif (_current_frame > _max_frames):
			_should_capture = false
			_current_frame = 1
			control.visible = true
			
			# Single thread
			# _render_thread.start(self, "_render_gif")
			
			# Multi thread
			var data: Array = []
			for i in range(_max_threads):
				_render_threads.append(Thread.new())
				data.append([])
			
			# Divide up image data
			# Will need to reconstruct this order later
			var c: int = 0
			for image in _images:
				data[c].append(image)
				if c < _max_threads - 1:
					c += 1
				else:
					c = 0
			
			for t in _render_threads.size():
				_render_threads[t].start(self, "_write_frame_buffer_threaded", data[t])
			
			_render_thread.start(self, "_render_gif_threaded", _render_threads)

###############################################################################
# Connections                                                                 #
###############################################################################

func _on_capture_now() -> void:
	# Validate input
	var dir: Directory = Directory.new()
	if not dir.dir_exists(save_location_line_edit.text.get_base_dir()):
		_log_message("Directory does not exist.", true)
		return
	if not frames_line_edit.text.is_valid_integer():
		_log_message("Frames input is not a valid integer.", true)
		return
	if not frame_skip_line_edit.text.is_valid_integer():
		_log_message("Frame skip input is not a valid integer.", true)
		return
	if not frame_delay_line_edit.text.is_valid_float():
		_log_message("Frame delay input is not a valid float.", true)
		return
	if not threads_line_edit.text.is_valid_integer():
		_log_message("Threads input is not a valid integer.", true)
		return
	
	_save_location = save_location_line_edit.text
	_max_frames = frames_line_edit.text.to_int()
	_frame_skip = frame_skip_line_edit.text.to_int()
	_gif_frame_delay = frame_delay_line_edit.text.to_float()
	_max_threads = threads_line_edit.text.to_int()
	
	_should_capture = true
	control.visible = false

func _on_capture_in_five_seconds() -> void:
	yield(get_tree().create_timer(5.0), "timeout")
	_on_capture_now()

func _on_select_path_button_pressed() -> void:
	var fd: FileDialog = FileDialog.new()
	fd.name = "fd"
	fd.mode = FileDialog.MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.current_dir = OS.get_executable_path().get_base_dir()
	fd.current_path = fd.current_dir
	fd.current_file = "result.gif"
	fd.add_filter("*.gif ; gif files")
	fd.connect("file_selected", self, "_on_system_path_selected")
	fd.connect("popup_hide", self, "_on_popup_hide")
	
	var screen_middle: Vector2 = Vector2(get_viewport().size.x / 2, get_viewport().size.y / 2)
	fd.set_global_position(screen_middle)
	fd.rect_size = screen_middle
	
	control.add_child(fd)
	fd.popup_centered_clamped(screen_middle)
	
	yield(fd, "file_selected")
	fd.queue_free()

func _on_system_path_selected(path: String) -> void:
	var path_tokens = path.split("/")
	path_tokens.invert()
	# If you don't select anything, path will auto-populate .gif as the filename
	if (path_tokens[0] == ".gif"):
		path_tokens[0] = "result.gif"
	path_tokens.invert()
	
	save_location_line_edit.text = path_tokens.join("/")

func _on_popup_hide() -> void:
	var fd: FileDialog = get_node_or_null("fd")
	if fd:
		fd.queue_free()

###############################################################################
# Private functions                                                           #
###############################################################################

func _render_gif(_x) -> void:
	"""
	_render_gif
	
	Single-threaded render and writing. Extremely slow.
	An empty parameter is required when running on a thread.
	"""
	var file: File = File.new()
	file.open(_save_location, File.WRITE)

	for i in _images.size():
		_log_message("Processing image %s of %s" % [i + 1, _images.size()])
		
		# TODO This has a memory leak
#		var median_cut: MedianCut = MEDIAN_CUT.new()
#		_gif_exporter.write_frame(_images[i], 1, median_cut)
		
		var euq = EUQ.new()
		_gif_exporter.write_frame(_images[i], _gif_frame_delay, euq)

	file.store_buffer(_gif_exporter.export_file_data())
	file.close()
	
	_log_message("Gif saved")
	
	_render_thread.call_deferred("wait_to_finish")

func _render_gif_threaded(data: Array) -> void:
	"""
	_render_gif_threaded
	
	data is an array containing the Threads used
	"""
	var buffer_data: Array = []
	for t in data.size():
		buffer_data.append(data[t].wait_to_finish())
	
	var reconstructed_buffer: PoolByteArray = PoolByteArray()
	var c: int = 0
	for i in range(_max_frames):
		_log_message("Processing frame %s of %s" % [i + 1, _max_frames])
		var buffer: PoolByteArray = buffer_data[c].pop_front()
		if buffer:
			reconstructed_buffer.append_array(buffer)
		if c < data.size() - 1:
			c += 1
		else:
			c = 0
	
	var file: File = File.new()
	file.open(_save_location, File.WRITE)
	
	# Wait for the file to actually be open
	while true:
		if file.is_open():
			break
	
	file.store_buffer(_gif_exporter.export_file_data_threaded(reconstructed_buffer))
	file.close()
	
	_log_message("Gif saved")
	
	_render_thread.call_deferred("wait_to_finish")

func _write_frame_buffer_threaded(images: Array) -> Array:
	"""
	_write_frame_threaded
	
	images is an array containing the specific subset of images to convert
	
	return a regular Array instead of a PoolByteArray since the data is out of order
	"""
	var result: Array = []
	var converted_images: Array = []
	
	var exporter: GifExporter = GIF_EXPORTER.new(_viewport.size.x, _viewport.size.y)
	var euq = EUQ.new()
	for i in images.size():
		_log_message("Converting image %s of %s" % [i + 1, images.size()])
		
		var converted_image = exporter.convert_image(images[i], euq)
		if converted_image.error == GifExporter.Error.OK:
			# converted_images.append(converted_image)
			result.append(exporter.write_frame_buffer_from_conv_image(converted_image.converted_image, _gif_frame_delay))
		else:
			_log_message("Error: %d" % converted_image.error, true)
	
	# converted_images
	return result

func _log_message(message: String, is_error: bool = false) -> void:
	var label: Label = Label.new()
	if is_error:
		label.text += "[ERROR] "
	label.text += message
#	console.add_child(label)
	console.call_deferred("add_child", label)
	yield(label, "ready")
	console.move_child(label, 0)
	print(message)
	
	while console.get_child_count() > MAX_CONSOLE_MESSAGE_COUNT:
		console.get_child(console.get_child_count() - 1).free()

###############################################################################
# Public functions                                                            #
###############################################################################


