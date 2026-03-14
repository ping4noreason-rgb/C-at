#╔═══════════════════════════════════╗
#║           C-at v8.0               ║
#║     The Purrfect C Editor         ║
#║                                   ║
#║      ∧,,,∧                        ║
#║     ( •‿• )                       ║
#║     /  づ♡                        ║
#╚═══════════════════════════════════╝

#-----------------------------------
# C-at: Collaborative C Editor
# MIT License
# This is a solo project for quickly writing C code.
# This version of the editor is very portable, as it's a small, simple window with easy controls.
#-----------------------------------

extends Panel

#-----------------------------------
# Preload
#-----------------------------------
@warning_ignore("shadowed_global_identifier")
const FileManager = preload("res://Redactor/Redactor_C/Scripts/Classes/FileManager.gd")
const Compiler = preload("res://Redactor/Redactor_C/Scripts/Classes/Compilier.gd")
@warning_ignore("shadowed_global_identifier")
const NetworkManager = preload("res://Redactor/Redactor_C/Scripts/Classes/NetworkManager.gd")
@warning_ignore("shadowed_global_identifier")
const UIManager = preload("res://Redactor/Redactor_C/Scripts/Classes/UIManager.gd")
@warning_ignore("shadowed_global_identifier")
const SyntaxChecker = preload("res://Redactor/Redactor_C/Scripts/Classes/SyntaxChecker.gd")

#-----------------------------------
# UI References
#-----------------------------------
@onready var editor = $CodeEdit
@onready var log_box = $"../Output/Label"
@onready var run_btn = $"../../CanvasLayer/AI2/Button"
@onready var user_list = $"../Output2/ItemList"
@onready var compile_status = $"../Output2/Label"
@onready var func_list = $"../../CanvasLayer/AI2/ItemList"
@onready var func_panel = $"../../CanvasLayer/AI2"
@onready var file_browser = $"../../CanvasLayer/Tree"

#-----------------------------------
# Managers
#-----------------------------------
var file_manager: FileManager
var compiler: Compiler
var network_manager: NetworkManager
var ui_manager: UIManager
var syntax_checker: SyntaxChecker
var busy_compiling: bool = false

#-----------------------------------
# Helpers
#-----------------------------------
var completion_enabled: bool = true
var completion_blocked_until: float = 0.0

#-----------------------------------
# RPC state
#-----------------------------------
var ignore_edits = false
var debounce_timer: Timer

#-----------------------------------
# Initialization
#-----------------------------------
func _ready():
	#DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

	file_manager = FileManager.new(self)
	compiler = Compiler.new(self, multiplayer) 
	network_manager = NetworkManager.new(self, multiplayer) 
	syntax_checker = SyntaxChecker.new(self)
	ui_manager = UIManager.new(self)

	ui_manager.setup_editor()
	file_manager.get_real_tcc_path()
	network_manager.init_network()

	debounce_timer = Timer.new()
	debounce_timer.one_shot = true
	debounce_timer.wait_time = 0.8
	debounce_timer.timeout.connect(_check_syntax)
	add_child(debounce_timer)

	editor.code_completion_requested.connect(_show_completions)
	editor.lines_edited_from.connect(_on_lines_changed)
	editor.gutter_clicked.connect(_on_gutter_click)
	run_btn.pressed.connect(_run_code)

	file_manager.load_initial_file()

	file_manager.build_file_tree()
	ui_manager.scan_functions()

	file_browser.gui_input.connect(_on_tree_right_click)
	file_browser.item_activated.connect(_on_tree_item_click)

	var mem_label = Label.new()
	mem_label.name = "MemoryLabel"
	mem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mem_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	mem_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	mem_label.add_theme_font_size_override("font_size", 10)

	mem_label.anchor_right = 1.0
	mem_label.anchor_bottom = 1.0
	mem_label.offset_right = -10
	mem_label.offset_bottom = -10
	mem_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	mem_label.size_flags_vertical = Control.SIZE_SHRINK_END

	func_panel.position = Vector2(805.896, 7.0)
	func_panel.size = Vector2(162.104, 459.0)

#-----------------------------------
# RPC Functions (must be in main script)
#-----------------------------------
@rpc("any_peer", "call_local")
@warning_ignore("shadowed_variable_base_class")
func _register_self(name: String):
	if not multiplayer.is_server():
		return

	var id = multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1

	Global.connected_peers[id] = {"name": name, "cursor": 0, "compiling": false}

	if id != 1:
		_send_full_text.rpc_id(id, editor.text)

	_update_userlist.rpc(Global.connected_peers)

@rpc("authority", "call_local")
func _update_userlist(data):
	if not data.is_empty():
		Global.connected_peers = data
	
	if user_list:
		user_list.clear()
		for id in Global.connected_peers:
			var u = Global.connected_peers[id]
			var stat = " (🔨)" if u.get("compiling", false) else ""
			user_list.add_item(u["name"] + stat)

@rpc("authority")
func _send_full_text(txt):
	ignore_edits = true
	var cur_line = editor.get_caret_line()
	var cur_col = editor.get_caret_column()
	editor.text = txt
	editor.set_caret_line(cur_line)
	editor.set_caret_column(cur_col)
	ignore_edits = false

@rpc("any_peer", "unreliable")
func _send_change(txt, cursor):
	if multiplayer.is_server():
		var sender = multiplayer.get_remote_sender_id()
		_apply_change(txt, cursor, sender)
		_send_to_clients.rpc(txt, cursor, sender)

@rpc("authority", "unreliable")
func _send_to_clients(txt, cursor, exclude):
	if multiplayer.get_unique_id() == exclude:
		return
	_apply_change(txt, cursor, exclude)

@rpc("any_peer", "call_local")
func _update_comp_status(pid: int, comp: bool):
	if multiplayer.is_server():
		if Global.connected_peers.has(pid):
			Global.connected_peers[pid]["compiling"] = comp
			compiler.update_compile_display()
			_update_userlist.rpc(Global.connected_peers)
	else:
		compiler.update_compile_display()

#-----------------------------------
# File Browser Event Handlers
#-----------------------------------
func _on_tree_right_click(event: InputEvent):
	file_manager.handle_tree_right_click(event)

func _on_tree_item_click():
	file_manager.handle_tree_item_click()

#-----------------------------------
# Main Actions
#-----------------------------------
func _run_code():
	compiler.run_code()

func save_current():
	file_manager.save_current()

func set_panel_photo():
	ui_manager.show_panel_photo_menu()

#-----------------------------------
# Editor Event Handlers
#-----------------------------------
func _on_lines_changed(_a, _b):
	debounce_timer.start()

func _on_gutter_click(line: int, gutter: int):
	if gutter == 0:
		editor.toggle_fold_line(line)

func _check_syntax():
	syntax_checker.check_syntax()

func _show_completions():
	var keywords = ["if", "else", "for", "while", "do", "switch", "case", "break", 
		"continue", "return", "goto", "sizeof", "int", "char", "float", "void"]
	var funcs = ["printf", "scanf", "malloc", "free", "fopen", "fclose"]
	
	var ficon = get_theme_icon("Method", "EditorIcons")
	var kicon = get_theme_icon("Keyword", "EditorIcons")
	
	for k in keywords:
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, k, k, Color(0.9, 0.4, 0.7), kicon)
	
	for f in funcs:
		editor.add_code_completion_option(CodeEdit.KIND_FUNCTION, f, f + "(", Color(0.4, 0.9, 1.0), ficon)
	
	editor.update_code_completion_options(true)

func scan_functions():
	ui_manager.scan_functions()

#-----------------------------------
# Input Handling
#-----------------------------------
func _input(ev):
	if ev.is_action_pressed("ui_accept") and ev.ctrl_pressed and ev.shift_pressed:
		set_panel_photo()
		editor.accept_event()

	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_S and ev.ctrl_pressed:
			save_current()
			editor.accept_event()

		elif ev.keycode == KEY_R and ev.ctrl_pressed:
			if multiplayer.multiplayer_peer != null:
				_register_self.rpc_id(1, Global.local_user_name)
				editor.accept_event()

		elif ev.keycode == KEY_SPACE and ev.ctrl_pressed:
			toggle_code_completion()
			editor.accept_event()

#-----------------------------------
# Code Completion Disabling Manager
#-----------------------------------
func toggle_code_completion():
	completion_enabled = !completion_enabled

	if completion_enabled:
		editor.code_completion_enabled = true
		completion_blocked_until = 0.0
		log_box.text = ">>> Code completion enabled\n"
		log_box.add_theme_color_override("font_color", Color.PALE_GREEN)
	else:
		editor.code_completion_enabled = false
		editor.cancel_code_completion()

		completion_blocked_until = INF
		hide_completion_window()

		log_box.text = ">>> Code completion disabled\n"
		log_box.add_theme_color_override("font_color", Color.INDIAN_RED)

	await get_tree().create_timer(1.0).timeout
	log_box.add_theme_color_override("font_color", Color(1, 1, 1))

func hide_completion_window():
	editor.cancel_code_completion()
	editor.accept_event()
	editor.queue_redraw()

#-----------------------------------
# Helper functions for network
#-----------------------------------
func _apply_change(txt, _cursor, peer):
	ignore_edits = true
	var my_line = editor.get_caret_line()
	var my_col = editor.get_caret_column()

	if editor.text != txt:
		editor.text = txt

	if peer != multiplayer.get_unique_id():
		editor.set_caret_line(my_line)
		editor.set_caret_column(my_col)

	ignore_edits = false
	debounce_timer.start()

#-----------------------------------
# Cleanup
#-----------------------------------
func _exit_tree():
	compiler.kill_all_processes()
	compiler.cleanup_temp_files([])

#-----------------------------------
# Main Loop
#-----------------------------------
func _process(delta):
	compiler.last_compile_time += delta

	if completion_enabled and compiler.last_compile_time > 0.1:
		if Time.get_ticks_msec() / 1000.0 > completion_blocked_until:
			editor.request_code_completion()
			compiler.last_compile_time = 0

#-----------------------------------
# Log Cleanup
#-----------------------------------
func _on_button_pressed():
	log_box.text = ""

#   ∧,,,∧
#  ( •‿• )
#  /  づ♡
#  Thank you for reading my code to the end. Bye! (ASCII art was generated by neural network)
