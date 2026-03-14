#-----------------------------------
# Compiler - Handles code compilation and execution with memory monitoring
#-----------------------------------
class_name Compilier
extends RefCounted

var main: Panel
var _multiplayer: MultiplayerAPI 
var last_compile_time = 0
var running_processes = []
var temp_main_c_path = ""
var memory_monitor_timer: Timer
var cached_memory_info = ""
var cached_disk_info = ""

var cached_ram_used_percent = 0
var cached_ram_total = 0
var cached_ram_used = 0
var cached_disk_used_percent = 0
var cached_disk_total = 0
var cached_disk_used = 0

func _init(main_node: Panel, mp: MultiplayerAPI):
	main = main_node
	_multiplayer = mp

	memory_monitor_timer = Timer.new()
	memory_monitor_timer.wait_time = 5.0
	memory_monitor_timer.timeout.connect(_update_memory_display)
	memory_monitor_timer.autostart = true
	main.add_child(memory_monitor_timer)

	_update_memory_cache()

func run_code():
	if someone_compiling():
		main.log_box.text = ">>> " + who_is_compiling() + " is compiling. Wait.\n"
		main.log_box.add_theme_color_override("font_color", Color.YELLOW)
		return

	if main.file_manager.tcc_exe.is_empty():
		main.log_box.text = ">>> TCC not found!\n"
		main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		return

	var tcc_path = main.file_manager.get_real_tcc_path()
	
	if tcc_path.begins_with("res://"):
		tcc_path = ProjectSettings.globalize_path(tcc_path)

	if not FileAccess.file_exists(tcc_path):
		main.log_box.text = ">>> TCC file missing at: " + tcc_path + "\n"
		main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		return

	kill_all_processes()
	set_compile_status(true)

	var code = main.editor.text
	var exe_dir = get_executable_dir()

	if not DirAccess.dir_exists_absolute(exe_dir):
		DirAccess.make_dir_absolute(exe_dir)

	var src = exe_dir.path_join("temp_main.c")
	temp_main_c_path = src
	var exe = exe_dir.path_join("program.exe")

	var f = FileAccess.open(src, FileAccess.WRITE)
	f.store_string(code)
	f.close()

	main.log_box.text = ">>> Compiling...\n"

	var args = [src, "-o", exe]
	var out = []
	var code_res = OS.execute(tcc_path, args, out, true)

	if code_res != 0:
		main.log_box.text = ">>> Compile failed\n"
		for l in out:
			main.log_box.text += l + "\n"
		main.log_box.add_theme_color_override("font_color", Color.INDIAN_RED)
		main.syntax_checker.mark_errors(out[0] if out.size() > 0 else "")
		set_compile_status(false)
		return

	main.log_box.text += ">>> OK\n"
	main.log_box.add_theme_color_override("font_color", Color.PALE_GREEN)

	if FileAccess.file_exists(src):
		DirAccess.remove_absolute(src)
		main.log_box.text += ">>> Temporary C file removed\n"

	if not FileAccess.file_exists(exe):
		main.log_box.text += ">>> Error: program.exe does not created.\n"
		set_compile_status(false)
		return

	var bat_path = exe_dir.path_join("run_program.bat")
	var bat_content = '@echo off\n"' + exe + '"\necho.\necho Program finished. Press any key to close this window...\npause\n'

	var bat_file = FileAccess.open(bat_path, FileAccess.WRITE)
	bat_file.store_string(bat_content)
	bat_file.close()

	var pid = OS.create_process("cmd.exe", ["/c", "start", "cmd.exe", "/k", bat_path], false)

	if pid > 0:
		main.log_box.text += ">>> Program started (PID: " + str(pid) + ")\n"
		_show_cached_memory_info()

		var process_info = {
			"pid": pid,
			"timer": null,
			"bat_path": bat_path
		}
		running_processes.append(process_info)

		var timer = Timer.new()
		timer.wait_time = 1.0
		timer.timeout.connect(_check_process.bind(pid, process_info))
		timer.autostart = true
		main.add_child(timer)
		process_info.timer = timer
	else:
		main.log_box.text += ">>> Error: Could not start program\n"

	await main.get_tree().create_timer(1.0).timeout
	set_compile_status(false)

func _update_memory_cache():
	var memory_info = _get_memory_info_fast()
	var disk_info = _get_disk_info_fast()

	cached_ram_total = memory_info.total
	cached_ram_used = memory_info.used
	cached_ram_used_percent = memory_info.used_percent

	cached_disk_total = disk_info.total
	cached_disk_used = disk_info.used
	cached_disk_used_percent = disk_info.used_percent

	cached_memory_info = "RAM: %s/%s (%d%%)" % [
		_format_bytes(cached_ram_used),
		_format_bytes(cached_ram_total),
		cached_ram_used_percent
	]
	
	cached_disk_info = "Disk: %s/%s (%d%%)" % [
		_format_bytes(cached_disk_used),
		_format_bytes(cached_disk_total),
		cached_disk_used_percent
	]

func _show_cached_memory_info():
	main.log_box.text += "\nMemory Status\n"
	main.log_box.text += cached_memory_info + "\n"
	main.log_box.text += cached_disk_info + "\n"

func _update_memory_display():
	if not is_instance_valid(main):
		return

	_update_memory_cache()

	if main.has_node("MemoryLabel"):
		var mem_label = main.get_node("MemoryLabel")
		mem_label.text = cached_memory_info + " | " + cached_disk_info

func _get_memory_info_fast() -> Dictionary:
	var memory_info = {
		"total": 0,
		"free": 0,
		"used": 0,
		"used_percent": 0
	}
	
	if OS.get_name() == "Windows":
		var mem_dict = OS.get_memory_info()
		memory_info.total = mem_dict["physical"]
		memory_info.free = mem_dict["free"]
		memory_info.used = memory_info.total - memory_info.free
		
		if memory_info.total > 0:
			memory_info.used_percent = int((float(memory_info.used) / memory_info.total) * 100)
	
	return memory_info

func _get_disk_info_fast() -> Dictionary:
	var disk_info = {
		"total": 0,
		"free": 0,
		"used": 0,
		"used_percent": 0
	}
	
	var path = get_executable_dir()
	
	if OS.get_name() == "Windows":
		var drive = path.split(":")[0] + ":"
		var dir = DirAccess.open(drive + "/")
		if dir:
			disk_info.free = dir.get_space_left()
			var out = []
			OS.execute("cmd.exe", ["/c", "wmic logicaldisk where DeviceID='" + drive + "' get Size /value"], out, true)
			for line in out:
				if "Size=" in line:
					var val = line.split("=")[1].strip_edges()
					disk_info.total = val.to_int()
					break
			
			if disk_info.total > 0:
				disk_info.used = disk_info.total - disk_info.free
				disk_info.used_percent = int((float(disk_info.used) / disk_info.total) * 100)
	
	return disk_info

func _get_disk_info_simple(path: String) -> Dictionary:
	var disk_info = {
		"total": 0,
		"free": 0,
		"used": 0,
		"used_percent": 0
	}

	var project_size = _get_folder_size(path)
	disk_info.used = project_size
	disk_info.total = project_size + (100 * 1024 * 1024)
	disk_info.free = disk_info.total - disk_info.used
	disk_info.used_percent = 50 
	
	return disk_info

func _get_folder_size(path: String) -> int:
	var total_size = 0
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = path.path_join(file_name)
				if dir.current_is_dir():
					total_size += _get_folder_size(full_path)
				else:
					var file = FileAccess.open(full_path, FileAccess.READ)
					if file:
						total_size += file.get_length()
						file.close()
			file_name = dir.get_next()
		dir.list_dir_end()
	return total_size

func _format_bytes(bytes: int) -> String:
	if bytes <= 0:
		return "0 B"
		
	var units = ["B", "KB", "MB", "GB", "TB"]
	var size = float(bytes)
	var unit_index = 0
	
	while size >= 1024 and unit_index < units.size() - 1:
		size /= 1024
		unit_index += 1
	
	return str(round(size * 10) / 10) + " " + units[unit_index]

func get_executable_dir() -> String:
	if Global.current_project_path != "":
		if DirAccess.dir_exists_absolute(Global.current_project_path):
			return Global.current_project_path
		else:
			return Global.current_project_path.get_base_dir()

	return main.file_manager.proj_dir

func _check_process(pid: int, process_info: Dictionary):
	if not OS.is_process_running(pid):
		stop_process_monitoring(process_info)
		main.log_box.text += ">>> Program closed (PID: " + str(pid) + ")\n"
		main.log_box.text += ">>> Memory usage during execution:\n"
		main.log_box.text += cached_memory_info + " | " + cached_disk_info + "\n"

		if process_info.has("bat_path") and FileAccess.file_exists(process_info.bat_path):
			DirAccess.remove_absolute(process_info.bat_path)
			main.log_box.text += ">>> Temporary bat file removed\n"
			temp_main_c_path = ""

func stop_process_monitoring(process_info: Dictionary):
	if process_info.timer and is_instance_valid(process_info.timer):
		process_info.timer.stop()
		process_info.timer.queue_free()

	var idx = running_processes.find(process_info)

	if idx != -1:
		running_processes.remove_at(idx)

func kill_process(pid: int):
	if pid <= 0:
		return

	var result = false
	if OS.get_name() == "Windows":
		var out = []
		result = OS.execute("taskkill", ["/F", "/PID", str(pid)], out, true) == 0
		if not result:
			result = OS.execute("taskkill", ["/F", "/T", "/PID", str(pid)], out, true) == 0
	else:
		var out = []
		result = OS.execute("kill", ["-9", str(pid)], out, true) == 0

	if result:
		main.log_box.text += ">>> Process " + str(pid) + " killed\n"
	else:
		main.log_box.text += ">>> Failed to kill process " + str(pid) + "\n"

func kill_all_processes():
	if running_processes.is_empty():
		return

	main.log_box.text += ">>> Stopping previous processes...\n"

	var processes_to_kill = running_processes.duplicate()
	for proc in processes_to_kill:
		kill_process(proc.pid)
		stop_process_monitoring(proc)

	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/F", "/IM", "program.exe"], [], true)
	else:
		OS.execute("pkill", ["-f", "program.exe"], [], true)

	var processes_to_clean = running_processes.duplicate()
	running_processes.clear()

	await main.get_tree().create_timer(0.5).timeout
	cleanup_temp_files(processes_to_clean)

func cleanup_temp_files(processes_to_clean: Array = []):
	if temp_main_c_path != "" and FileAccess.file_exists(temp_main_c_path):
		DirAccess.remove_absolute(temp_main_c_path)
		main.log_box.text += ">>> Temporary C file removed\n"
		temp_main_c_path = ""

	for process in processes_to_clean:
		if process.has("bat_path") and FileAccess.file_exists(process.bat_path):
			DirAccess.remove_absolute(process.bat_path)
			main.log_box.text += ">>> Temporary bat file removed\n"

	# Optionally deleting exe files
	#var exe_dir = get_executable_dir()
	#var exe_path = exe_dir + "/program.exe"
	#if FileAccess.file_exists(exe_path):
		#DirAccess.remove_absolute(exe_path)
		#main.log_box.text += ">>> Executable file removed\n"

func set_compile_status(comp: bool):
	main.busy_compiling = comp
	var my_id = _multiplayer.get_unique_id()

	if _multiplayer.multiplayer_peer != null:
		if _multiplayer.is_server():
			main._update_comp_status(my_id, comp)
		else:
			main._update_comp_status.rpc_id(1, my_id, comp)

func update_compile_display():
	if not main.compile_status:
		return

	var compilers = []

	for id in Global.connected_peers:
		if Global.connected_peers[id].get("compiling", false):
			compilers.append(Global.connected_peers[id]["name"])

	if compilers.size() > 0:
		main.compile_status.text = "Compiling: " + ", ".join(compilers)
		main.compile_status.show()
	else:
		main.compile_status.hide()

func someone_compiling() -> bool:
	for id in Global.connected_peers:
		if Global.connected_peers[id].get("compiling", false):
			return true
	return false

func who_is_compiling() -> String:
	for id in Global.connected_peers:
		if Global.connected_peers[id].get("compiling", false):
			return Global.connected_peers[id]["name"]
	return "Someone"
