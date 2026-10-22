import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3,
      let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write("usage: click x y\n".data(using: .utf8)!)
    exit(2)
}
let p = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
        mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
        mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(90_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
        mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
print("clicked \(Int(x)),\(Int(y))")
