extends MultiplayerPeerExtension
var status := MultiplayerPeer.CONNECTION_DISCONNECTED
var server := false
var uid := 1
var relay := false
var closed := 0
var host_calls := 0
var client_calls: Array = []
var disconnects: Array = []
var steam_map := {1:76561198000000001,12:76561198000000002,13:76561198000000003}
var create_result := OK
func create_host(port: int) -> Error:
    host_calls += 1
    server = true
    status = MultiplayerPeer.CONNECTION_CONNECTED
    return create_result
func create_client(id: int, port: int) -> Error:
    client_calls.append([id,port])
    server = false
    uid = 12
    status = MultiplayerPeer.CONNECTION_CONNECTING
    return create_result
func set_server_relay(value: bool) -> void: relay=value
func get_steam_id_for_peer_id(id: int) -> int: return int(steam_map.get(id,0))
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return status
func _get_unique_id() -> int: return uid
func _is_server() -> bool: return server
func _is_server_relay_supported() -> bool: return relay
func _get_available_packet_count() -> int: return 0
func _poll() -> void: pass
func _close() -> void:
    closed+=1
    status=MultiplayerPeer.CONNECTION_DISCONNECTED
func _disconnect_peer(id: int, force: bool) -> void: disconnects.append([id,force])
func _set_target_peer(id: int) -> void: pass
func _get_packet_peer() -> int: return 0
func _get_transfer_channel() -> int: return 0
func _get_transfer_mode() -> MultiplayerPeer.TransferMode: return MultiplayerPeer.TRANSFER_MODE_RELIABLE
func _get_max_packet_size() -> int: return 524288
func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void: pass
func _set_transfer_channel(channel: int) -> void: pass
