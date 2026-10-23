import Foundation
import CoreBluetooth
import Security
import Darwin

@_cdecl("bobo_ble_initialize") public func boboBleInitialize() { BoboBle.shared.startBridge() }
@_cdecl("bobo_ble_deinitialize") public func boboBleDeinitialize() { BoboBle.shared.closeBridge() }

final class BoboBle: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    static let shared = BoboBle()
    let serviceID = CBUUID(string:"6a914a00-c746-4f03-9b53-0f997e62bd01")
    let rxID = CBUUID(string:"6a914a01-c746-4f03-9b53-0f997e62bd01")
    let txID = CBUUID(string:"6a914a02-c746-4f03-9b53-0f997e62bd01")
    var central: CBCentralManager?
    var peripheralManager: CBPeripheralManager?
    var found: [String:CBPeripheral] = [:]
    var peer: CBPeripheral?
    var subscriber: CBCentral?
    var rx: CBCharacteristic?
    var tx: CBMutableCharacteristic?
    var queue: [Data] = []
    var input = Data()
    var busy = false
    var live = false
    var mode = ""
    var generation = 0
    var listener: Int32 = -1
    var client: Int32 = -1
    let ioLock = NSLock()
    var token = ""
    let maxFrame = 8192
    func emit(_ event: String, _ fields: [String:Any] = [:]) {
        var object = fields; object["event"] = event
        guard var data = try? JSONSerialization.data(withJSONObject:object) else { return }
        data.append(10)
        ioLock.lock(); defer { ioLock.unlock() }
        if client < 0 { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(client,base.advanced(by:sent),data.count-sent,0)
                if n <= 0 { break }; sent += n
            }
        }
    }
    func error(_ message: String) { emit("error",["message":message]) }
    func startBridge() {
        if listener >= 0 { return }
        var secret = [UInt8](repeating:0,count:24)
        guard SecRandomCopyBytes(kSecRandomDefault,secret.count,&secret) == errSecSuccess else { return }
        token = Data(secret).base64EncodedString()
        listener = Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard listener >= 0 else { return }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(listener,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, Darwin.listen(listener,1) == 0 else { Darwin.close(listener); listener = -1; return }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(listener,$0,&length) } }
        setenv("BOBO_BLE_PORT",String(UInt16(bigEndian:address.sin_port)),1)
        setenv("BOBO_BLE_TOKEN",token,1)
        Thread.detachNewThread { [self] in
            while listener >= 0 {
                let fd = Darwin.accept(listener,nil,nil)
                if fd < 0 { break }
                var noSignal: Int32 = 1
                setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
                var timeout = timeval(tv_sec:5,tv_usec:0)
                setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                var buffer = Data(); var authorized = false; var byte: UInt8 = 0
                while Darwin.recv(fd,&byte,1,0) == 1 {
                    if byte != 10 { buffer.append(byte); if buffer.count > maxFrame { break }; continue }
                    guard let object = (try? JSONSerialization.jsonObject(with:buffer)) as? [String:Any] else { break }
                    buffer.removeAll(keepingCapacity:true)
                    if !authorized {
                        guard object["token"] as? String == token else { break }
                        authorized = true
                        timeout = timeval(tv_sec:0,tv_usec:0)
                        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                        ioLock.lock(); client = fd; ioLock.unlock()
                        emit("bridge_ready",["platform":"iOS"])
                    } else { DispatchQueue.main.async { self.command(object) } }
                }
                ioLock.lock(); client = -1; ioLock.unlock(); Darwin.close(fd)
                DispatchQueue.main.async { self.disconnect() }
            }
        }
    }
    func closeBridge() {
        if listener >= 0 { Darwin.close(listener); listener = -1 }
        ioLock.lock(); if client >= 0 { Darwin.shutdown(client,SHUT_RDWR) }; ioLock.unlock()
        DispatchQueue.main.async { self.disconnect() }
    }
    func command(_ object:[String:Any]) {
        guard let command = object["command"] as? String else { return }
        switch command {
        case "host":
            disconnect(); mode = "host"
            if peripheralManager == nil { peripheralManager = CBPeripheralManager(delegate:self,queue:.main) }
            else { beginHost() }
        case "scan":
            disconnect(); mode = "scan"
            if central == nil { central = CBCentralManager(delegate:self,queue:.main) }
            else { beginScan() }
        case "connect":
            guard let id = object["id"] as? String, let device = found[id] else { error("房间已失效，请重新搜索"); return }
            central?.stopScan(); mode = "connecting"; peer = device; device.delegate = self
            central?.connect(device)
            let g = generation
            DispatchQueue.main.asyncAfter(deadline:.now()+12) { if g == self.generation && !self.live { self.error("连接超时，请重新搜索"); self.disconnect() } }
        case "send":
            guard let packet = object["packet"] as? [String:Any], var data = try? JSONSerialization.data(withJSONObject:packet), live else { error("尚未连接对手"); return }
            data.append(10)
            if data.count > maxFrame || queue.count > 512 { error("蓝牙发送拥塞"); disconnect(); return }
            let chunk = mode == "host" ? (subscriber?.maximumUpdateValueLength ?? 20) : (peer?.maximumWriteValueLength(for:.withResponse) ?? 20)
            let size = max(20,min(chunk,185))
            for i in stride(from:0,to:data.count,by:size) { queue.append(data.subdata(in:i..<min(i+size,data.count))) }
            pump()
        case "disconnect": disconnect()
        default: break
        }
    }
    func describe(_ state:CBManagerState) -> String {
        switch state {
        case .poweredOff: return "请在系统设置中打开蓝牙后重试"
        case .unauthorized: return "未获蓝牙权限，请在系统设置中允许；单机仍可使用"
        case .unsupported: return "本机不支持蓝牙联机"
        default: return "蓝牙尚未就绪，请稍后重试"
        }
    }
    func centralManagerDidUpdateState(_ manager:CBCentralManager) {
        if manager.state == .poweredOn { if mode == "scan" { beginScan() } }
        else if !mode.isEmpty { error(describe(manager.state)); disconnect() }
    }
    func peripheralManagerDidUpdateState(_ manager:CBPeripheralManager) {
        if manager.state == .poweredOn { if mode == "host" { beginHost() } }
        else if !mode.isEmpty { error(describe(manager.state)); disconnect() }
    }
    func beginScan() {
        guard let c = central, c.state == .poweredOn else { if let c = central { error(describe(c.state)) }; return }
        found.removeAll(); c.scanForPeripherals(withServices:[serviceID],options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
        emit("status",["message":"正在搜索附近房间…"])
        let g = generation
        DispatchQueue.main.asyncAfter(deadline:.now()+15) { if g == self.generation && self.mode == "scan" { self.central?.stopScan(); self.emit("status",["message":"搜索结束；未找到时确认对方已创建房间，并重试"]) } }
    }
    func beginHost() {
        guard let p = peripheralManager, p.state == .poweredOn else { if let p = peripheralManager { error(describe(p.state)) }; return }
        p.removeAllServices()
        let service = CBMutableService(type:serviceID,primary:true)
        let receive = CBMutableCharacteristic(type:rxID,properties:[.write],value:nil,permissions:[.writeable])
        let notify = CBMutableCharacteristic(type:txID,properties:[.notify],value:nil,permissions:[.readable])
        service.characteristics = [receive,notify]; tx = notify; p.add(service)
    }
    func peripheralManager(_ manager:CBPeripheralManager,didAdd service:CBService,error:Error?) {
        guard mode == "host" else { return }
        if error != nil { self.error("创建房间失败"); return }
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[serviceID],CBAdvertisementDataLocalNameKey:"波波赞"])
    }
    func peripheralManagerDidStartAdvertising(_ manager:CBPeripheralManager,error:Error?) {
        if error != nil { self.error("无法广播房间，请由对方创建") }
        else { emit("status",["message":"房间已创建，等待另一台手机加入"]) }
    }
    func centralManager(_ manager:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi:NSNumber) {
        let id = peripheral.identifier.uuidString
        guard mode == "scan", found[id] == nil, found.count < 12 else { return }
        found[id] = peripheral
        emit("peer",["id":id,"name":"附近玩家 "+id.suffix(4)])
    }
    func centralManager(_ manager:CBCentralManager,didConnect peripheral:CBPeripheral) {
        guard peer == peripheral else { return }; peripheral.discoverServices([serviceID])
    }
    func centralManager(_ manager:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) {
        if peer == peripheral { self.error("连接失败，请重试"); disconnect() }
    }
    func centralManager(_ manager:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        if peer == peripheral { emit("disconnected",["message":"对方已断开"]); disconnect() }
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard peer == peripheral else { return }
        guard error == nil, let s = peripheral.services?.first(where:{$0.uuid == serviceID}) else { self.error("对方不是兼容房间"); disconnect(); return }
        peripheral.discoverCharacteristics([rxID,txID],for:s)
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard peer == peripheral else { return }
        guard error == nil, let receive = service.characteristics?.first(where:{$0.uuid == rxID}), let notify = service.characteristics?.first(where:{$0.uuid == txID}) else { self.error("对方协议不完整"); disconnect(); return }
        rx = receive; peripheral.setNotifyValue(true,for:notify)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        guard peer == peripheral else { return }
        if error == nil && characteristic.isNotifying { live = true; mode = "client"; emit("connected",["host":false]) }
        else { self.error("无法订阅对战数据"); disconnect() }
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard peer == peripheral, characteristic.uuid == txID else { return }
        if error == nil, let data = characteristic.value { accept(data) }
    }
    func peripheral(_ peripheral:CBPeripheral,didWriteValueFor characteristic:CBCharacteristic,error:Error?) {
        guard peer == peripheral else { return }
        if error != nil { self.error("发送失败，连接已中断"); disconnect(); return }
        busy = false; pump()
    }
    func peripheralManager(_ manager:CBPeripheralManager,central:CBCentral,didSubscribeTo characteristic:CBCharacteristic) {
        guard mode == "host", characteristic.uuid == txID else { return }
        if let old = subscriber, old.identifier != central.identifier { return }
        subscriber = central; live = true; manager.stopAdvertising(); emit("connected",["host":true])
    }
    func peripheralManager(_ manager:CBPeripheralManager,central:CBCentral,didUnsubscribeFrom characteristic:CBCharacteristic) {
        if subscriber?.identifier == central.identifier { emit("disconnected",["message":"对方已断开"]); disconnect() }
    }
    func peripheralManager(_ manager:CBPeripheralManager,didReceiveWrite requests:[CBATTRequest]) {
        for request in requests {
            guard request.central.identifier == subscriber?.identifier, request.characteristic.uuid == rxID, request.offset == 0, let data = request.value else { manager.respond(to:request,withResult:.writeNotPermitted); continue }
            manager.respond(to:request,withResult:.success); accept(data)
        }
    }
    func peripheralManagerIsReady(toUpdateSubscribers manager:CBPeripheralManager) { pump() }
    func accept(_ bytes:Data) {
        for b in bytes {
            if b == 10 {
                guard let object = (try? JSONSerialization.jsonObject(with:input)) as? [String:Any] else { error("收到损坏的对战数据"); disconnect(); return }
                input.removeAll(keepingCapacity:true); emit("packet",["packet":object])
            } else { input.append(b); if input.count > maxFrame { error("对战消息过大"); disconnect(); return } }
        }
    }
    func pump() {
        guard live, !queue.isEmpty else { return }
        if mode == "host" {
            guard let manager = peripheralManager, let characteristic = tx, let central = subscriber else { return }
            while let data = queue.first {
                if !manager.updateValue(data,for:characteristic,onSubscribedCentrals:[central]) { return }
                queue.removeFirst()
            }
        } else if !busy, let p = peer, let characteristic = rx {
            busy = true; p.writeValue(queue.removeFirst(),for:characteristic,type:.withResponse)
        }
    }
    func disconnect() {
        generation += 1; live = false; busy = false; mode = ""
        central?.stopScan()
        let oldPeer = peer; peer = nil
        if let p = oldPeer { central?.cancelPeripheralConnection(p) }
        peripheralManager?.stopAdvertising(); peripheralManager?.removeAllServices()
        subscriber = nil; rx = nil; tx = nil; queue.removeAll(); input.removeAll(); found.removeAll()
    }
}
