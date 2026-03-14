#-----------------------------------
# UI Manager - Handles editor UI, syntax, functions
#-----------------------------------
class_name UIManager
extends RefCounted

var main: Panel
var compiled_funcs = []

func _init(main_node: Panel):
	main = main_node

func setup_editor():
	main.editor.draw_tabs = true
	main.editor.draw_spaces = true
	
	main.editor.add_theme_color_override("guides_color", Color(1, 1, 1, 0.1))
	main.editor.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.1))
	
	var fnt = ThemeDB.fallback_font
	main.editor.add_theme_font_override("font", fnt)
	main.editor.add_theme_font_size_override("font_size", 14)
	
	main.editor.highlight_current_line = true
	main.editor.add_theme_color_override("current_line_color", Color(1, 1, 1, 0.05))
	
	setup_syntax()
	
	main.editor.gutters_draw_line_numbers = true
	main.editor.line_folding = true
	main.editor.gutters_draw_fold_gutter = true
	main.editor.set_gutter_draw(0, true)
	main.editor.set_gutter_draw(1, true)
	
	main.editor.code_completion_prefixes = [" ", " ", "(", "[", "{", ",", "=", ">", "<", "!"]
	main.editor.auto_brace_completion_enabled = true
	main.editor.auto_brace_completion_pairs = {
		"{": "}", "(": ")", "[": "]", "\"": "\"", "'": "'"
	}
	
	main.editor.add_string_delimiter("\"", "\"")
	main.editor.add_string_delimiter("'", "'")
	main.editor.add_comment_delimiter("//", "")
	main.editor.add_comment_delimiter("/*", "*/")
	
	main.editor.line_length_guidelines = [80, 120]
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#3d3d3d")
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	
	main.editor.add_theme_stylebox_override("normal", style)
	main.editor.add_theme_stylebox_override("focus", style)

func setup_syntax():
	var high = CodeHighlighter.new()
	var kw_color = Color("#ff79c6")
	var type_color = Color("#8be9fd")
	var ctrl_color = Color("#bd93f9")
	var str_color = Color("#f1fa8c")
	var cmt_color = Color("#6272a4")
	var num_color = Color("#bd93f9")
	var func_color = Color("#50fa7b")
	
	var keywords = ["break", "case", "continue", "default", "do", "else", "for", "goto",
		"if", "return", "switch", "while", "sizeof", "typedef", "struct", "union"]
	for k in keywords:
		high.add_keyword_color(k, kw_color)
	
	var types = ["int", "long", "short", "char", "float", "double", "void",
		"signed", "unsigned", "static", "const", "volatile", "extern"]
	for t in types:
		high.add_keyword_color(t, type_color)
	
	var preproc = ["#include", "#define", "#ifdef", "#ifndef", "#endif", "#pragma", "#else"]
	for p in preproc:
		high.add_keyword_color(p, ctrl_color)
	
	high.number_color = num_color
	high.symbol_color = Color("#ffb86c")
	
	var common = ["printf", "scanf", "malloc", "free", "main", "exit", "fopen", "fclose"]
	for f in common:
		high.add_keyword_color(f, func_color)
	
	high.add_color_region("\"", "\"", str_color)
	high.add_color_region("'", "'", str_color)
	high.add_color_region("//", "", cmt_color)
	high.add_color_region("/*", "*/", cmt_color)
	
	main.editor.syntax_highlighter = high

func scan_functions():
	compiled_funcs.clear()
	main.func_list.clear()
	
	if main.func_panel:
		main.func_panel.visible = true
	
	var txt = main.editor.text
	var lines = txt.split("\n")
	
	var func_regex = RegEx.new()
	func_regex.compile("[a-zA-Z_][a-zA-Z0-9_]*\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")
	
	var in_func = false
	var cur_func = ""
	var brace_cnt = 0
	var start_line = -1
	
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		
		if line.is_empty() or line.begins_with("//") or line.begins_with("/*"):
			continue
		
		var res = func_regex.search(line)
		if res and not in_func:
			if "(" in line and ")" in line:
				var next = ""
				if i + 1 < lines.size():
					next = lines[i + 1].strip_edges()
				if "{" in line or next.begins_with("{"):
					var name = res.get_string(1)
					cur_func = name
					start_line = i
					in_func = true
					if "{" in line:
						brace_cnt = line.count("{")
					else:
						brace_cnt = 1

		elif in_func:
			brace_cnt += line.count("{") - line.count("}")
			if brace_cnt <= 0:
				in_func = false
				compiled_funcs.append({
					"name": cur_func,
					"line": start_line
				})
				main.func_list.add_item(cur_func)

	if main.func_list.is_connected("item_selected", _on_func_selected):
		main.func_list.disconnect("item_selected", _on_func_selected)

	main.func_list.item_selected.connect(_on_func_selected)

	if compiled_funcs.size() == 0:
		main.func_list.add_item("(no functions)")

func _on_func_selected(idx):
	if idx >= 0 and idx < compiled_funcs.size():
		var data = compiled_funcs[idx]
		var ln = data["line"]

		main.editor.set_caret_line(ln)
		main.editor.set_caret_line(ln, true)
		main.editor.set_line_as_center_visible(max(0, ln - 3))
		
		highlight_line(ln)

func highlight_line(ln: int):
	var old_color = null
	if ln < main.editor.get_line_count():
		old_color = main.editor.get_line_background_color(ln)

	main.editor.set_line_background_color(ln, Color(0.3, 0.5, 0.8, 0.3))

	await main.get_tree().create_timer(0.5).timeout
	if ln < main.editor.get_line_count():
		main.editor.set_line_background_color(ln, old_color if old_color else Color(0,0,0,0))

func show_panel_photo_menu():
	var menu = PopupMenu.new()
	main.add_child(menu)

	menu.add_icon_item(main.get_theme_icon("Panel", "EditorIcons"), "Code Panel", 0)
	menu.add_icon_item(main.get_theme_icon("Panel", "EditorIcons"), "AI Panel", 1)
	menu.add_icon_item(main.get_theme_icon("Panel", "EditorIcons"), "Output Panel", 2)
	menu.add_icon_item(main.get_theme_icon("Panel", "EditorIcons"), "Output2 Panel", 4)
	menu.add_separator()
	menu.add_icon_item(main.get_theme_icon("Panel", "EditorIcons"), "All Panels", 3)
	menu.add_separator()
	menu.add_icon_item(main.get_theme_icon("Cancel", "EditorIcons"), "Cancel", 5)

	menu.id_pressed.connect(func(id):
		match id:
			0, 1, 2, 3, 4:
				show_image_dialog_for_panel(id)
			5:
				main.log_box.text = "Operation cancelled\n"
				menu.queue_free()
	)
	@warning_ignore("narrowing_conversion")
	menu.popup(Rect2i(main.get_global_mouse_position().x, main.get_global_mouse_position().y, 0, 0))

func show_image_dialog_for_panel(panel_choice: int):
	var file_dialog = FileDialog.new()
	main.add_child(file_dialog)
	
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	
	# Для Code Panel (panel_choice = 0) - только изображения
	if panel_choice == 0:
		file_dialog.filters = ["*.png ; PNG Images", "*.jpg ; JPEG Images", "*.jpeg ; JPEG Images"]
		file_dialog.title = "Select an image background for Code Panel"
	else:
		# Для остальных панелей - изображения и видео
		file_dialog.filters = ["*.ogv ; Ogg Video", "*.png ; PNG Images", "*.jpg ; JPEG Images", "*.jpeg ; JPEG Images"]
		file_dialog.title = "Select an image or video background"
	
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	
	file_dialog.file_selected.connect(_on_photo_selected.bind(panel_choice, file_dialog))
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_photo_selected(path: String, panel_choice: int, dlg: FileDialog):
	var file_ext = path.get_extension().to_lower()
	
	# Для Code Panel (panel_choice = 0) - запрещаем видео
	if panel_choice == 0:
		if file_ext in ["ogv"]:
			main.log_box.text = ">>> Videos are not allowed on Code Panel. Please use images only.\n"
			main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
			dlg.queue_free()
			return
	
	if file_ext == "ogv":
		if not FileAccess.file_exists(path):
			main.log_box.text = ">>> Video file not found: " + path + "\n"
			main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
			dlg.queue_free()
			return
		
		apply_video_background(path, panel_choice)
		main.log_box.text = "Video background applied!\n"
		main.log_box.add_theme_color_override("font_color", Color.PALE_GREEN)
		dlg.queue_free()
		return
	
	if file_ext in ["png", "jpg", "jpeg"]:
		var img = Image.new()
		if img.load(path) == OK:
			var style = StyleBoxTexture.new()
			style.texture = ImageTexture.create_from_image(img)
			apply_background_style(style, panel_choice)
			main.log_box.text = "Image background applied!\n"
			main.log_box.add_theme_color_override("font_color", Color.PALE_GREEN)
		else:
			main.log_box.text = ">>> Can't load image file.\n"
			main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		dlg.queue_free()
		return
	
	main.log_box.text = ">>> Unsupported format.\n"
	main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
	dlg.queue_free()

func apply_background_style(style: StyleBoxTexture, panel_choice: int):
	match panel_choice:
		0: 
			main.editor.add_theme_stylebox_override("normal", style)
			main.editor.add_theme_stylebox_override("focus", style)
		1: 
			var ai_panel = get_ai_panel()
			ai_panel.add_theme_stylebox_override("panel", style)
		2: 
			get_output_panel().add_theme_stylebox_override("panel", style)
		4: 
			get_output2_panel().add_theme_stylebox_override("panel", style)
		3:
			apply_background_style(style, 0)
			apply_background_style(style, 1)
			apply_background_style(style, 2)
			apply_background_style(style, 4)

func apply_video_background(video_path: String, panel_choice: int):
	var file_ext = video_path.get_extension().to_lower()

	if file_ext != "ogv":
		main.log_box.text = ">>> Godot 4.6 supports only OGV.\n"
		main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		return

	if not FileAccess.file_exists(video_path):
		main.log_box.text = ">>> Video file not found: " + video_path + "\n"
		main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		return

	var video_player = VideoStreamPlayer.new()

	var stream = VideoStreamTheora.new()
	stream.file = video_path
	video_player.stream = stream

	video_player.autoplay = true
	video_player.expand = true
	video_player.volume_db = 0
	video_player.name = "BackgroundVideo"
	video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE

	video_player.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel = get_panel_by_choice(panel_choice, video_path)
	if not panel:
		main.log_box.text = ">>> Panel not found\n"
		return

	var old = panel.get_node_or_null("BackgroundVideo")
	if old:
		old.queue_free()

	panel.add_child(video_player)
	panel.move_child(video_player, 0)

	if panel == main.editor:
		var transparent_bg = StyleBoxFlat.new()
		transparent_bg.bg_color = Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("normal", transparent_bg)
		panel.add_theme_stylebox_override("focus", transparent_bg)
	else:
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("panel", panel_style)

	main.log_box.text = ">>> Video background applied successfully!\n"
	main.log_box.add_theme_color_override("font_color", Color.PALE_GREEN)

func get_panel_by_choice(choice: int, video_path: String = ""):
	match choice:
		0: return main.editor
		1: return get_ai_panel()
		2: return get_output_panel()
		4: return get_output2_panel()
		3:
			apply_video_background(video_path, 0)
			apply_video_background(video_path, 1)
			apply_video_background(video_path, 2)
			apply_video_background(video_path, 4)
			return null
	return null

func get_ai_panel():
	return main.get_node("../../CanvasLayer/AI2")

func get_output_panel():
	return main.get_node("../Output")

func get_output2_panel():
	return main.get_node("../Output2")

func setup_video_anchors(video: VideoStreamPlayer):
	video.anchor_left = 0.0
	video.anchor_top = 0.0
	video.anchor_right = 1.0
	video.anchor_bottom = 1.0
	video.set_deferred("size", Vector2.ZERO)

	video.set_deferred("offset_left", 0)
	video.set_deferred("offset_top", 0)
	video.set_deferred("offset_right", 0)
	video.set_deferred("offset_bottom", 0)

func remove_old_video(panel: Control):
	var old = panel.get_node_or_null("BackgroundVideo")
	if old:
		old.queue_free()

func add_video_overlay(panel: Control):
	var overlay = ColorRect.new()
	overlay.name = "VideoOverlay"
	overlay.color = Color(0, 0, 0, 0.2)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0

	var old_overlay = panel.get_node_or_null("VideoOverlay")
	if old_overlay:
		old_overlay.queue_free()

	panel.add_child(overlay)
	panel.move_child(overlay, panel.get_child_count() - 1)
