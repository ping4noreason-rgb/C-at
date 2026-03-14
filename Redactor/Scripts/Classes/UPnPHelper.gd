#-----------------------------------
# UPnPHelper - Helping To The NetworkManager (check class NetworkManager)
#-----------------------------------
class_name UPnPHelper
extends RefCounted

var upnp = UPNP.new()
var port = DEFAULT_PORT

const DEFAULT_PORT = 8910

func setup_port():
	var result = upnp.discover()
	if result != UPNP.UPNP_RESULT_SUCCESS:
		print("No UPnP gateway found")
		return false

	var gateway = upnp.get_gateway()
	if not gateway:
		print("No gateway")
		return false

	var ip = gateway.query_external_address()
	if ip:
		Global.external_ip = ip
		print("External IP: ", ip)

	gateway.delete_port_mapping(port, "TCP")

	var map_result = gateway.add_port_mapping(port, port, "C-at Editor", "TCP", 0)

	if map_result == UPNP.UPNP_RESULT_SUCCESS:
		print("Port forwarded!")
		return true
	else:
		print("Port forward failed")
		return false

func remove_port():
	var gateway = upnp.get_gateway()
	if gateway:
		gateway.delete_port_mapping(port, "TCP")
