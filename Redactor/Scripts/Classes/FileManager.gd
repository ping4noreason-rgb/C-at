#-----------------------------------
# File Manager - Handles all file operations
#-----------------------------------
class_name FileManager
extends RefCounted

var main: Panel
var cur_file_path = ""
var proj_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects")
var tcc_exe = ""

func _init(main_node: Panel):
	main = main_node
	tcc_exe = get_real_tcc_path()

func get_real_tcc_path() -> String:
	var extracted = ensure_tcc_extracted()
	if extracted != "":
		return extracted

	var tcc_in_bin = "res://Redactor/Redactor_C/bin/tcc.exe"
	if FileAccess.file_exists(tcc_in_bin):
		if OS.has_feature("editor"):
			return tcc_in_bin
		else:
			return ProjectSettings.globalize_path(tcc_in_bin)

	var exe_dir = OS.get_executable_path().get_base_dir()
	var nearby = exe_dir.path_join("bin/tcc.exe")
	if FileAccess.file_exists(nearby):
		return nearby

	return ""

func ensure_tcc_extracted() -> String:
	var extract_dir = OS.get_user_data_dir().path_join("tcc")

	if DirAccess.dir_exists_absolute(extract_dir):
		return extract_dir.path_join("tcc.exe")

	DirAccess.make_dir_absolute(extract_dir)
	DirAccess.make_dir_absolute(extract_dir.path_join("include"))
	DirAccess.make_dir_absolute(extract_dir.path_join("lib"))

	DirAccess.copy_absolute("res://Redactor/Redactor_C/bin/tcc.exe", extract_dir.path_join("tcc.exe"))
	DirAccess.copy_absolute("res://Redactor/Redactor_C/bin/libtcc.dll", extract_dir.path_join("libtcc.dll"))

	copy_directory("res://Redactor/Redactor_C/bin/include", extract_dir.path_join("include"))
	copy_directory("res://Redactor/Redactor_C/bin/lib", extract_dir.path_join("lib"))
	
	return extract_dir.path_join("tcc.exe")

func copy_directory(src: String, dst: String):
	var dir = DirAccess.open(src)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		
		var src_path = src.path_join(file_name)
		var dst_path = dst.path_join(file_name)
		
		if dir.current_is_dir():
			DirAccess.make_dir_absolute(dst_path)
			copy_directory(src_path, dst_path)
		else:
			DirAccess.copy_absolute(src_path, dst_path)
		
		file_name = dir.get_next()
	dir.list_dir_end()

func load_initial_file():
	if Global.current_project_path != "":
		if FileAccess.file_exists(Global.current_project_path):
			load_file(Global.current_project_path)
		elif DirAccess.dir_exists_absolute(Global.current_project_path):
			load_first_c_file_in_dir(Global.current_project_path)

	if not DirAccess.dir_exists_absolute(proj_dir):
		DirAccess.make_dir_absolute(proj_dir)

func load_first_c_file_in_dir(dir_path: String):
	var main_file = dir_path.path_join("main.c")
	if FileAccess.file_exists(main_file):
		load_file(main_file)
		Global.current_file = main_file
	else:
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while fname != "":
				if fname.ends_with(".c") and not dir.current_is_dir():
					var cfile = dir_path.path_join(fname)
					load_file(cfile)
					Global.current_file = cfile
					break
				fname = dir.get_next()
			dir.list_dir_end()

func load_file(path: String):
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			main.editor.text = f.get_as_text()
			f.close()
	main.scan_functions()

func save_current():
	var path = Global.current_file

	if path != "" and FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(main.editor.text)
			f.close()
			main.log_box.text = "Saved: " + path.get_file() + "\n"
			return

	show_save_dialog()

func show_save_dialog():
	var dlg = FileDialog.new()
	main.add_child(dlg)

	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.title = "Save"
	dlg.add_filter("*.c", "C Files")
	dlg.add_filter("*.h", "Header Files")

	var docs = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MyProjects")
	if not DirAccess.dir_exists_absolute(docs):
		DirAccess.make_dir_absolute(docs)
	dlg.current_dir = docs
	dlg.current_file = "main.c"

	dlg.file_selected.connect(_on_save_selected.bind(dlg))
	dlg.popup_centered(Vector2i(600, 400))

func _on_save_selected(path: String, dlg: FileDialog):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(main.editor.text)
		f.close()
		Global.current_project_path = path
		main.log_box.text = "Saved to: " + path.get_file() + "\n"

	if dlg and dlg.is_inside_tree():
		dlg.queue_free()

func build_file_tree():
	main.file_browser.hide_root = true
	main.file_browser.item_selected.connect(_on_file_select)
	refresh_tree()

func refresh_tree():
	main.file_browser.clear()
	var root = main.file_browser.create_item()
	root.set_text(0, proj_dir.get_file())
	scan_dir(proj_dir, root)

func scan_dir(path: String, parent: TreeItem):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var name = dir.get_next()
		while name != "":
			if name != "." and name != "..":
				var full = path.path_join(name)
				if dir.current_is_dir():
					var diritem = main.file_browser.create_item(parent)
					diritem.set_text(0, name + "/")
					diritem.set_metadata(0, full)
					scan_dir(full, diritem)
				else:
					var fileitem = main.file_browser.create_item(parent)
					fileitem.set_text(0, name)
					fileitem.set_metadata(0, full)
			name = dir.get_next()
		dir.list_dir_end()

func _on_file_select():
	var sel = main.file_browser.get_selected()
	if sel:
		var path = sel.get_metadata(0)
		if FileAccess.file_exists(path):
			load_file(path)

func handle_tree_right_click(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var mouse_pos = main.file_browser.get_local_mouse_position()
		var item = main.file_browser.get_item_at_position(mouse_pos)

		var global_mouse_pos = main.get_global_mouse_position()

		if item:
			var path = item.get_metadata(0)
			if DirAccess.dir_exists_absolute(path):
				show_folder_menu(path, global_mouse_pos, item)
			else:
				show_file_menu(path, global_mouse_pos)
		else:
			show_folder_menu(proj_dir, global_mouse_pos, null)

		main.get_viewport().set_input_as_handled()

func handle_tree_item_click():
	var sel = main.file_browser.get_selected()
	if sel:
		var path = sel.get_metadata(0)
		if FileAccess.file_exists(path):
			load_file(path)

func show_file_menu(file_path: String, pos: Vector2):
	var menu = PopupMenu.new()
	main.add_child(menu)

	menu.add_icon_item(main.get_theme_icon("Load", "EditorIcons"), "Open", 0)
	menu.add_icon_item(main.get_theme_icon("Rename", "EditorIcons"), "Rename", 1)
	menu.add_icon_item(main.get_theme_icon("Remove", "EditorIcons"), "Delete", 2)
	menu.add_separator()
	menu.add_icon_item(main.get_theme_icon("FolderOpen", "EditorIcons"), "Show in Explorer", 3)

	menu.id_pressed.connect(func(id):
		match id:
			0: load_file(file_path)
			1: rename_dialog(file_path)
			2: delete_dialog(file_path)
			3: OS.shell_open(file_path.get_base_dir())
	)
	@warning_ignore("narrowing_conversion")
	menu.popup(Rect2i(pos.x, pos.y, 0, 0))

func show_folder_menu(folder_path: String, pos: Vector2, folder_item: TreeItem):
	var menu = PopupMenu.new()
	main.add_child(menu)

	menu.add_icon_item(main.get_theme_icon("NewFile", "EditorIcons"), "New C File", 0)
	menu.add_icon_item(main.get_theme_icon("NewFile", "EditorIcons"), "New Header", 1)
	menu.add_icon_item(main.get_theme_icon("Folder", "EditorIcons"), "New Folder", 2)
	menu.add_separator()
	menu.add_icon_item(main.get_theme_icon("Refresh", "EditorIcons"), "Refresh", 3)
	menu.add_separator()
	menu.add_icon_item(main.get_theme_icon("FolderOpen", "EditorIcons"), "Open in Explorer", 4)

	menu.id_pressed.connect(func(id):
		match id:
			0: create_file_dialog(folder_path, "new_file.c", folder_item)
			1: create_file_dialog(folder_path, "new_file.h", folder_item)
			2: create_folder_dialog(folder_path, folder_item)
			3: refresh_tree()
			4: OS.shell_open(folder_path)
	)
	@warning_ignore("narrowing_conversion")
	menu.popup(Rect2i(pos.x, pos.y, 0, 0))

func rename_dialog(old_path: String):
	var dlg = AcceptDialog.new()
	dlg.title = "Rename"
	dlg.size = Vector2i(300, 120)
	dlg.dialog_text = "New name:"
	main.add_child(dlg)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg.add_child(vb)

	var input = LineEdit.new()
	input.text = old_path.get_file()
	input.select_all()
	vb.add_child(input)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)

	var ok_btn = Button.new()
	ok_btn.text = "Rename"
	hb.add_child(ok_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	hb.add_child(cancel_btn)

	var do_rename = func():
		var new_name = input.text.strip_edges()
		if new_name.is_empty() or new_name == old_path.get_file():
			dlg.queue_free()
			return

		var new_path = old_path.get_base_dir().path_join(new_name)
		if FileAccess.file_exists(new_path):
			main.log_box.text = ">>> File already exists!\n"
			main.log_box.add_theme_color_override("font_color", Color.YELLOW)
			return

		var dir = DirAccess.open(old_path.get_base_dir())
		if dir:
			var err = dir.rename(old_path.get_file(), new_name)
			if err == OK:
				refresh_tree()
				if Global.current_file == old_path:
					Global.current_file = new_path
				main.log_box.text = "Renamed to: " + new_name + "\n"
				main.log_box.add_theme_color_override("font_color", Color.PALE_GREEN)
			else:
				main.log_box.text = ">>> Rename failed: " + error_string(err) + "\n"
				main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
			dlg.queue_free()

	ok_btn.pressed.connect(do_rename)
	cancel_btn.pressed.connect(func(): dlg.queue_free())
	dlg.popup_centered()
	input.grab_focus()

func delete_dialog(file_path: String):
	var dlg = ConfirmationDialog.new()
	dlg.title = "Delete?"
	dlg.dialog_text = "Delete:\n" + file_path.get_file() + "?"
	dlg.ok_button_text = "Delete"
	main.add_child(dlg)
	dlg.confirmed.connect(func():
		var dir = DirAccess.open(file_path.get_base_dir())
		if dir:
			dir.remove(file_path.get_file())
			refresh_tree()
			if Global.current_file == file_path:
				main.editor.text = ""
				Global.current_file = ""
			main.log_box.text = "Deleted: " + file_path.get_file() + "\n"
	)
	dlg.popup_centered()

func create_file_dialog(folder_path: String, default_name: String, parent_item: TreeItem):
	var dlg = AcceptDialog.new()
	dlg.title = "New File"
	dlg.size = Vector2i(300, 120)
	dlg.dialog_text = "File name:"
	main.add_child(dlg)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg.add_child(vb)

	var input = LineEdit.new()
	input.text = default_name
	input.select_all()
	vb.add_child(input)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)

	var create_btn = Button.new()
	create_btn.text = "Create"
	hb.add_child(create_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	hb.add_child(cancel_btn)

	var do_create = func():
		var fname = input.text.strip_edges()
		if fname.is_empty():
			return
		if not fname.contains("."):
			fname += ".c"
		var full = folder_path.path_join(fname)
		if FileAccess.file_exists(full):
			var confirm = AcceptDialog.new()
			confirm.dialog_text = "Overwrite?"
			confirm.add_button("Yes", true, "yes")
			confirm.add_button("No", true, "no")
			main.add_child(confirm)
			confirm.confirmed.connect(func(btn):
				if btn == "yes":
					save_new_file(full, parent_item)
					confirm.queue_free()
					dlg.queue_free()
				else:
					confirm.queue_free()
			)
			confirm.popup_centered()
		else:
			save_new_file(full, parent_item)
			dlg.queue_free()

	create_btn.pressed.connect(do_create)
	cancel_btn.pressed.connect(func(): dlg.queue_free())
	dlg.popup_centered()
	input.grab_focus()

func save_new_file(path: String, parent: TreeItem):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		var template = ""
		if path.ends_with(".c"):
			template = '#include <stdio.h>\n\nint main() {\n    printf("Hello World!\\n");\n    return 0;\n}\n'
		elif path.ends_with(".h"):
			var guard = path.get_file().replace(".", "_").to_upper()
			template = "#ifndef " + guard + "\n#define " + guard + "\n\n\n#endif\n"
		f.store_string(template)
		f.close()

		refresh_tree()
		if parent and is_instance_valid(parent):
			parent.collapsed = false
		load_file(path)
		main.log_box.text = "Created: " + path.get_file() + "\n"

func create_folder_dialog(parent_path: String, parent_item: TreeItem):
	var dlg = AcceptDialog.new()
	dlg.title = "New Folder"
	dlg.size = Vector2i(300, 120)
	dlg.dialog_text = "Folder name:"
	main.add_child(dlg)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg.add_child(vb)

	var input = LineEdit.new()
	input.text = "new_folder"
	input.select_all()
	vb.add_child(input)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)

	var create_btn = Button.new()
	create_btn.text = "Create"
	hb.add_child(create_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	hb.add_child(cancel_btn)

	var do_create = func():
		var fname = input.text.strip_edges()
		if fname.is_empty():
			return

		var full = parent_path.path_join(fname)
		if DirAccess.dir_exists_absolute(full):
			main.log_box.text = ">>> Folder exists!\n"
			main.log_box.add_theme_color_override("font_color", Color.YELLOW)
			return

		var dir = DirAccess.open(parent_path)
		if dir:
			dir.make_dir(fname)
			refresh_tree()
			if parent_item:
				parent_item.collapsed = false
			main.log_box.text = "Folder: " + fname + "\n"
			dlg.queue_free()

	create_btn.pressed.connect(do_create)
	cancel_btn.pressed.connect(func(): dlg.queue_free())
	dlg.popup_centered()
	input.grab_focus()
