extends Node

@warning_ignore("unused_signal")
signal peer_left(id)

var current_project_path: String = ""
var current_file: String = ""
var upnp_enabled = true

var is_host: bool = false
var local_user_name: String = "User"
var connected_peers: Dictionary = {}  # id -> {name: String, cursor: int, compiling: bool}

var server_ip: String = "localhost"
var server_port: int = 25565
