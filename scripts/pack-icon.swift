import Foundation

// An icns file is a big-endian container of PNG images at macOS icon sizes.
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]
func sizeBytes(_ size: Int) -> Data {
    var value = UInt32(size).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var body = Data()
for (type, filename) in entries {
    let image = try Data(contentsOf: iconset.appendingPathComponent(filename))
    body.append(Data(type.utf8))
    body.append(sizeBytes(image.count + 8))
    body.append(image)
}
var result = Data("icns".utf8)
result.append(sizeBytes(body.count + 8))
result.append(body)
try result.write(to: destination, options: .atomic)
