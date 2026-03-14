#-----------------------------------
# Network Manager - Handles multiplayer synchronization
#-----------------------------------
class_name NetworkManager
extends RefCounted

var main: Panel
var _multiplayer: MultiplayerAPI
var _upnp_helper: UPnPHelper

func _init(main_node: Panel, mp: MultiplayerAPI):
	main = main_node
	_multiplayer = mp

func init_network():
	_multiplayer.peer_connected.connect(_on_peer_join)
	_multiplayer.peer_disconnected.connect(_on_peer_leave)
	
	if Global.is_host:
		main._register_self(Global.local_user_name + " (host)")
	
	if not Global.is_host:
		_multiplayer.connected_to_server.connect(_on_connected)
	
	main.editor.text_changed.connect(_on_text_changed_net)

	if Global.is_host and Global.upnp_enabled:
		_upnp_helper = UPnPHelper.new()
		_upnp_helper.setup_port()

func _on_peer_join(_id):
	pass

func _on_peer_leave(id):
	Global.connected_peers.erase(id)
	if Global.is_host:
		main._update_userlist.rpc(Global.connected_peers)
		main.compiler.update_compile_display()
	Global.peer_left.emit(id)

func _on_connected():
	main._register_self.rpc_id(1, Global.local_user_name)

func _on_text_changed_net():
	if _multiplayer.multiplayer_peer == null:
		return
	if _multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if main.ignore_edits:
		return
	
	var txt = main.editor.text
	var cursor = [main.editor.get_caret_line(), main.editor.get_caret_column()]
	
	if _multiplayer.is_server():
		main._send_to_clients.rpc(txt, cursor, 1)
	else:
		main._send_change.rpc_id(1, txt, cursor)

	main.debounce_timer.start()
	main.scan_functions()

func _exit_tree():
	if Global.is_host and Global.upnp_enabled and _upnp_helper:
		_upnp_helper.remove_port()
