class_name SyntaxChecker
extends RefCounted

var main: Panel

func _init(main_node: Panel):
	main = main_node

func check_syntax():
	if main.file_manager.tcc_exe.is_empty():
		return

	var tcc_path = main.file_manager.get_real_tcc_path()

	if not FileAccess.file_exists(tcc_path):
		var exe_dir = OS.get_executable_path().get_base_dir()
		var alternative = exe_dir.path_join("Redactor/Redactor_C/bin/tcc.exe")
		if FileAccess.file_exists(alternative):
			tcc_path = alternative
		else:
			return

	var code = main.editor.text
	var tmp = OS.get_user_data_dir() + "/syntax_check.c"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(code)
	f.close()

	for i in range(main.editor.get_line_count()):
		main.editor.set_line_background_color(i, Color(0,0,0,0))
		main.editor.set_line_gutter_icon(i, 1, null)

	var out = []
	print("Executing TCC: ", tcc_path, " with args: ", ["-c", tmp])
	var res = OS.execute(tcc_path, ["-c", tmp], out, true)

	if res != 0 and out.size() > 0:
		mark_errors(out[0])

func mark_errors(err_txt: String):
	var lines = err_txt.split("\n")
	for l in lines:
		if ": error:" in l or "error:" in l or "warning:" in l:
			var parts = l.split(":")
			if parts.size() >= 2:
				var line_num = -1
				for p in parts:
					var n = p.to_int()
					if n > 0:
						line_num = n - 1
						break

				if line_num >= 0 and line_num < main.editor.get_line_count():
					main.editor.set_line_background_color(line_num, Color(1, 0, 0, 0.2))
					var icon = main.get_theme_icon("Error", "EditorIcons")
					main.editor.set_line_gutter_icon(line_num, 1, icon)
