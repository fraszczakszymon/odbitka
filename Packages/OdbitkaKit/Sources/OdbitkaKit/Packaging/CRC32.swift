import Foundation

/// CRC-32 (wielomian IEEE 802.3), wymagany przez format ZIP.
public struct CRC32: Sendable {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            return value
        }
    }()

    private var state: UInt32 = 0xFFFF_FFFF

    public init() {}

    public mutating func update(_ bytes: UnsafeRawBufferPointer) {
        var value = state
        for byte in bytes {
            value = (value >> 8) ^ Self.table[Int((value ^ UInt32(byte)) & 0xFF)]
        }
        state = value
    }

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    public var checksum: UInt32 { state ^ 0xFFFF_FFFF }
}
