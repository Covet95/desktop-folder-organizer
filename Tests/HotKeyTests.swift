import Carbon.HIToolbox
import Foundation

@main
struct HotKeyTests {
    static func main() {
        let hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            print("hot key fired")
        }

        print("registered:", hotKey.isRegistered, "status:", hotKey.registerStatus)
        print(hotKey.isRegistered ? "PASS  global hot key" : "FAIL  global hot key")
        exit(hotKey.isRegistered ? 0 : 1)
    }
}
