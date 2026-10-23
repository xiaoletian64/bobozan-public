import Foundation
@main struct BridgeHarness {
    static func main() {
        boboBleInitialize()
        let values = ["port":ProcessInfo.processInfo.environment["BOBO_BLE_PORT"] ?? "", "token":ProcessInfo.processInfo.environment["BOBO_BLE_TOKEN"] ?? ""]
        let data = try! JSONSerialization.data(withJSONObject:values)
        FileHandle.standardOutput.write(data + Data([10]))
        RunLoop.main.run()
    }
}
