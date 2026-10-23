class_name BleBridge
extends Node
signal message(value: Dictionary)
var socket = StreamPeerTCP.new()
var buffer = PackedByteArray()
var started = 0
var authenticated = false
var active = false
func open() -> void:
	close()
	var port = OS.get_environment("BOBO_BLE_PORT").to_int()
	if port <= 0:
		message.emit({"event":"error","message":"此构建未包含原生蓝牙模块，请使用完整手机安装包"})
		return
	active = true
	started = Time.get_ticks_msec()
	if socket.connect_to_host("127.0.0.1",port) != OK:
		close()
		message.emit({"event":"error","message":"无法启动蓝牙模块"})
func _process(_delta: float) -> void:
	if not active: return
	socket.poll()
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if not authenticated:
			authenticated = true
			write({"token":OS.get_environment("BOBO_BLE_TOKEN")})
		var available = socket.get_available_bytes()
		if available > 0:
			var data = socket.get_data(mini(available,8192))
			if data[0] != OK: return
			buffer.append_array(data[1])
			while buffer.has(10):
				var end = buffer.find(10)
				var line = buffer.slice(0,end).get_string_from_utf8()
				buffer = buffer.slice(end+1)
				var value = JSON.parse_string(line)
				if value is Dictionary: message.emit(value)
			if buffer.size() > 8192:
				close()
				message.emit({"event":"error","message":"蓝牙模块消息超出限制"})
	elif authenticated or Time.get_ticks_msec()-started > 5000:
		close()
		message.emit({"event":"error","message":"蓝牙模块已断开，请重试"})
func write(value: Dictionary) -> void:
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.put_data((JSON.stringify(value)+"\n").to_utf8_buffer())
func command(name: String, fields: Dictionary = {}) -> void:
	var value = fields.duplicate(true)
	value["command"] = name
	write(value)
func close() -> void:
	if authenticated: command("disconnect")
	socket.disconnect_from_host()
	active = false
	authenticated = false
	buffer.clear()
