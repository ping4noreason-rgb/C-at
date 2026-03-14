#╔═══════════════════════════════════╗
#║           C-at v6.0               ║
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

extends Node2D

#-----------------------------------
# Global variables
#-----------------------------------
var projects = []
var reserved = [
	'CON', 'PRN', 'AUX', 'NUL', 'CLOCK$',
	'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
	'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
	'CON.', 'PRN.', 'AUX.', 'NUL.', 'CLOCK$.',
	'COM1.', 'COM2.', 'COM3.', 'COM4.', 'COM5.', 'COM6.', 'COM7.', 'COM8.', 'COM9.',
	'LPT1.', 'LPT2.', 'LPT3.', 'LPT4.', 'LPT5.', 'LPT6.', 'LPT7.', 'LPT8.', 'LPT9.',
	'System Volume Information', 'Recovery', 'Windows', 'System32', 'System',
	'Config.Msi', '$Recycle.Bin', '$WinREAgent', 'Documents and Settings',
	'Program Files', 'Program Files (x86)', 'ProgramData', 'All Users',
	'Default User', 'Public', 'PerfLogs', 'pagefile.sys', 'hiberfil.sys',
	'swapfile.sys', 'bootmgr', 'BOOTNXT', 'BOOTSECT.BAK', '$Boot', '$Bitmap',
	'$Extend', '$LogFile', '$Mft', '$MftMirr', '$Secure', '$UpCase', '$Volume',
	'$BadClus', 'desktop.ini', 'thumbs.db', 'autorun.inf', 'config.sys',
	'autoexec.bat', 'boot.ini', 'ntldr', 'NTUSER.DAT', 'ntuser.dat.log',
	'ntuser.ini', 'IconCache.db', '.', '..'
]

const DEFAULT_PORT = 8910

#-----------------------------------
# UI References
#-----------------------------------
@onready var file_dialog = $Menu/FileDialog
@onready var project_name = $Menu/Tools/Label/TextEdit
@onready var status_label = $Menu/Tools/Label/Label2
@onready var project_lists = $Menu/Projects/ItemList
@onready var host_btn = $Menu/Tools/Button
@onready var join_btn = $Menu/Tools/Button2
@onready var ip_input = $Menu/Tools/Panel3/TextEdit
@onready var import_btn = $Menu/Tools/ImportButton

#-----------------------------------
# Initialization
#-----------------------------------
func _ready():
	load_projects()
	refresh_list()
	setup_buttons()
	load_user_settings()
	$CheckBox.text = "UPnP"
	$CheckBox.button_pressed = true
	$CheckBox.toggled.connect(func(e): Global.upnp_enabled = e)

func setup_buttons():
	if host_btn.pressed.is_connected(_on_host_pressed):
		host_btn.pressed.disconnect(_on_host_pressed)
	host_btn.pressed.connect(_on_host_pressed)

	if join_btn.pressed.is_connected(_on_join_pressed):
		join_btn.pressed.disconnect(_on_join_pressed)
	join_btn.pressed.connect(_on_join_pressed)

	if import_btn and import_btn.pressed.is_connected(_on_import_button_pressed):
		import_btn.pressed.disconnect(_on_import_button_pressed)
	import_btn.pressed.connect(_on_import_button_pressed)

func load_user_settings():
	if FileAccess.file_exists("user://settings.cfg"):
		var config = ConfigFile.new()
		config.load("user://settings.cfg")
		Global.local_user_name = config.get_value("user", "name", Global.local_user_name)

func _save_user_name():
	var config = ConfigFile.new()
	config.set_value("user", "name", Global.local_user_name)
	config.save("user://settings.cfg")

#-----------------------------------
# Project Hosting
#-----------------------------------
func _on_host_pressed():
	var folder_name = project_name.text.strip_edges()
	
	if folder_name.is_empty():
		var selected = project_lists.get_selected_items()
		if selected.size() > 0:
			var project = projects[selected[0]]
			Global.current_project_path = project["path"]
		else:
			status_label.text = "Enter project name or select one"
			return
	else:
		if not create_folder():
			return 
		Global.current_project_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects").path_join(folder_name)

	var peer = ENetMultiplayerPeer.new()
	var err = OK
	var current_port = DEFAULT_PORT
	var attempts = 0

	while attempts < 10:
		err = peer.create_server(current_port)
		if err == OK:
			break
		attempts += 1
		current_port = DEFAULT_PORT + attempts
		print("Port ", DEFAULT_PORT + attempts - 1, " busy, trying ", current_port)

	if err != OK:
		status_label.text = "Can't find free port after " + str(attempts) + " attempts"
		return

	status_label.text = "Hosting on port: " + str(current_port)
	multiplayer.multiplayer_peer = peer
	Global.is_host = true
	Global.local_user_name = "Host_" + str(randi() % 1000)

	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

#-----------------------------------
# Project Joining
#-----------------------------------
func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "localhost"
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		status_label.text = "Failed to connect: " + str(err)
		return
	
	multiplayer.multiplayer_peer = peer
	Global.is_host = false
	Global.local_user_name = "User_" + str(randi() % 1000)
	
	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

#-----------------------------------
# Project Creation
#-----------------------------------
func create_project_metadata(project_path):
	var metadata = {
		"last_open_file": "main.c",
		"project_name": project_path.get_file()
	}
	
	var config = ConfigFile.new()
	for key in metadata:
		config.set_value("project", key, metadata[key])
	
	config.save(project_path.path_join(".godot_project"))

func create_folder() -> bool:
	var folder_name = project_name.text.strip_edges()
	var base_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects")

	if not DirAccess.dir_exists_absolute(base_path):
		DirAccess.make_dir_absolute(base_path)

	if folder_name.is_empty():
		status_label.text = "Project name cant be empty"
		return false

	if folder_name.to_lower() == "lol":
		status_label.text = "I hate lol."
		return false

	for a in reserved:
		if folder_name.to_upper() == a.to_upper():
			status_label.text = "Reserved Windows name!"
			return false

	var invalid_chars = ['\\', '/', ':', '*', '?', '"', '<', '>', '|']
	for c in invalid_chars:
		if c in folder_name:
			status_label.text = "Invalid characters!"
			return false

	var dir = DirAccess.open(base_path)
	if dir.make_dir(folder_name) == OK:
		status_label.text = "Created"
		load_projects() 
		return true 
	else:
		status_label.text = "Cant create project"
		return false

#-----------------------------------
# Project Selection & Navigation
#-----------------------------------
func _on_button_pressed() -> void:
	var folder_name = project_name.text.strip_edges()

	var selected_indices = project_lists.get_selected_items()
	if selected_indices.size() > 0:
		var selected_project = projects[selected_indices[0]]
		Global.current_project_path = selected_project["path"]
		enter_project(selected_project)
		return 

	if create_folder():
		Global.current_project_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects").path_join(folder_name)
		get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

func enter_project(project: Dictionary) -> void:
	Global.current_project_path = project["path"]
	Global.current_file = project["path"].path_join("main.c")
	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

func _on_item_list_item_activated(index: int) -> void:
	if projects.is_empty() or project_lists.get_item_text(index) == "Nothing here":
		return

	var selected_path = projects[index]["path"]
	Global.current_project_path = selected_path
	Global.current_file = selected_path.path_join("main.c")  
	
	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

#-----------------------------------
# Project Loading & Refresh
#-----------------------------------
func load_projects():
	projects.clear() 
	var projects_folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects")
	
	if not DirAccess.dir_exists_absolute(projects_folder):
		return

	var dir = DirAccess.open(projects_folder)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			projects.append({
				"name": file_name,
				"path": projects_folder.path_join(file_name)
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	refresh_list() 

func refresh_list():
	project_lists.clear()

	for project in projects:
		project_lists.add_item(project["name"])

	if projects.is_empty():
		project_lists.add_item("Nothing here")

#-----------------------------------
# File Import
#-----------------------------------
func _on_import_button_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM

	file_dialog.clear_filters()
	file_dialog.add_filter("*.c", "C Source Files")
	file_dialog.add_filter("*.h", "C Header Files")
	file_dialog.add_filter("*.cpp", "C++ Source Files") 

	if file_dialog.file_selected.is_connected(_on_file_selected):
		file_dialog.file_selected.disconnect(_on_file_selected)
	file_dialog.file_selected.connect(_on_file_selected)
	
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	Global.current_project_path = path 
	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

func _on_dir_selected(path: String):
	var folder_name = path.get_file() 
	var target_folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects").path_join(folder_name)

	if DirAccess.dir_exists_absolute(target_folder):
		Global.current_project_path = target_folder
		get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")
		return

	Global.current_project_path = path
	get_tree().change_scene_to_file("res://Redactor/Redactor_C/Scenes/redactor.tscn")

#   ∧,,,∧
#  ( •‿• )
#  /  づ♡
#  Thank you for reading my code to the end. Bye! (ASCII art was generated by neural network)


func _on_support_button_pressed() -> void:
	pass # Replace with function body.
