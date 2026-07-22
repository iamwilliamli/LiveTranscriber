import Foundation

/// IEEE-754 binary16 storage used only when Swift's native `Float16` is
/// unavailable, notably while Xcode compiles an x86_64 slice for a Mac archive.
/// The single `UInt16` field intentionally matches Core ML float16 buffers.
@frozen
public struct PortableFloat16: Sendable, Equatable, Hashable {
    public let bitPattern: UInt16

    public init(bitPattern: UInt16) {
        self.bitPattern = bitPattern
    }

    public init(_ value: Float) {
        bitPattern = Self.encode(value)
    }

    public var floatValue: Float {
        Float(bitPattern: Self.decode(bitPattern))
    }

    private static func encode(_ value: Float) -> UInt16 {
        let source = value.bitPattern
        let sign = UInt16((source >> 16) & 0x8000)
        let exponent = Int((source >> 23) & 0xFF)
        let mantissa = source & 0x7F_FFFF

        if exponent == 0xFF {
            guard mantissa != 0 else { return sign | 0x7C00 }
            let payload = UInt16(mantissa >> 13)
            return sign | 0x7C00 | (payload == 0 ? 1 : payload)
        }

        let halfExponent = exponent - 127 + 15
        if halfExponent >= 0x1F {
            return sign | 0x7C00
        }

        if halfExponent <= 0 {
            if halfExponent < -10 {
                return sign
            }

            let normalizedMantissa = mantissa | 0x80_0000
            let shift = UInt32(14 - halfExponent)
            var halfMantissa = UInt16(normalizedMantissa >> shift)
            let remainderMask = (UInt32(1) << shift) - 1
            let remainder = normalizedMantissa & remainderMask
            let halfway = UInt32(1) << (shift - 1)
            if remainder > halfway || (remainder == halfway && halfMantissa & 1 == 1) {
                halfMantissa &+= 1
            }
            return sign | halfMantissa
        }

        var encodedExponent = UInt16(halfExponent) << 10
        var encodedMantissa = UInt16(mantissa >> 13)
        let remainder = mantissa & 0x1FFF
        if remainder > 0x1000 || (remainder == 0x1000 && encodedMantissa & 1 == 1) {
            encodedMantissa &+= 1
            if encodedMantissa == 0x0400 {
                encodedMantissa = 0
                encodedExponent &+= 0x0400
                if encodedExponent >= 0x7C00 {
                    return sign | 0x7C00
                }
            }
        }

        return sign | encodedExponent | encodedMantissa
    }

    private static func decode(_ source: UInt16) -> UInt32 {
        let sign = UInt32(source & 0x8000) << 16
        let exponent = Int((source >> 10) & 0x1F)
        var mantissa = UInt32(source & 0x03FF)

        switch exponent {
        case 0 where mantissa == 0:
            return sign
        case 0:
            var unbiasedExponent = -14
            while mantissa & 0x0400 == 0 {
                mantissa <<= 1
                unbiasedExponent -= 1
            }
            mantissa &= 0x03FF
            return sign
                | (UInt32(unbiasedExponent + 127) << 23)
                | (mantissa << 13)
        case 0x1F:
            return sign | 0x7F80_0000 | (mantissa << 13)
        default:
            return sign
                | (UInt32(exponent - 15 + 127) << 23)
                | (mantissa << 13)
        }
    }
}

extension PortableFloat16: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(Float(value))
    }
}

extension PortableFloat16: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(Float(value))
    }
}

public extension Float {
    init(_ value: PortableFloat16) {
        self = value.floatValue
    }
}
