import Foundation

enum SmartCriteriaField {
    static let name: UInt32 = 0x02
    static let album: UInt32 = 0x03
    static let artist: UInt32 = 0x04
    static let year: UInt32 = 0x07
    static let genre: UInt32 = 0x08
    static let kind: UInt32 = 0x09
    static let playCount: UInt32 = 0x16
    static let rating: UInt32 = 0x19
    static let mediaKind: UInt32 = 0x3c
    static let albumArtist: UInt32 = 0x47
    static let likedState: UInt32 = 0x9a
}

enum SmartCriteriaAction {
    static let numberIs: UInt32 = 0x00000001
    static let numberGreater: UInt32 = 0x00000010
    static let numberLess: UInt32 = 0x00000040
    static let numberInRange: UInt32 = 0x00000100
    static let textIs: UInt32 = 0x01000001
    static let textContains: UInt32 = 0x01000002
    static let textStartsWith: UInt32 = 0x01000004
    static let textEndsWith: UInt32 = 0x01000008
    static let textIsNot: UInt32 = 0x03000001
    static let textNotContains: UInt32 = 0x03000002
}

struct SmartCriteriaRule: Equatable, Codable {
    var field: UInt32
    var action: UInt32
    var text: String?
    var fromValue: Int64 = 0
    var fromDate: Int64 = 0
    var fromUnits: Int64 = 1
    var toValue: Int64 = 0
    var toDate: Int64 = 0
    var toUnits: Int64 = 1
    var trailer: Data = Data(count: 20)
    var pad: Data = Data(count: 44)

    var isText: Bool { text != nil }

    static func text(field: UInt32, action: UInt32 = SmartCriteriaAction.textContains, value: String) -> SmartCriteriaRule {
        SmartCriteriaRule(field: field, action: action, text: value)
    }

    static func number(field: UInt32, action: UInt32 = SmartCriteriaAction.numberIs, from: Int64, to: Int64? = nil) -> SmartCriteriaRule {
        SmartCriteriaRule(field: field, action: action, text: nil, fromValue: from, toValue: to ?? from)
    }
}

indirect enum SmartCriteriaItem: Equatable, Codable {
    case rule(SmartCriteriaRule)
    case group(SmartCriteriaGroup)
}

struct SmartCriteriaGroup: Equatable, Codable {
    var matchAll: Bool = true
    var items: [SmartCriteriaItem] = []
    var version: UInt32 = 0x00010001
    var headerPad: Data = Data(count: 120)
    var groupPad: Data = SmartCriteriaGroup.defaultGroupPad
    var groupAction: UInt32 = 1

    static var defaultGroupPad: Data {
        var pad = Data(count: 44)
        pad[0] = 0x01
        return pad
    }
}

enum SmartCriteriaCodec {
    private static let magic: [UInt8] = [0x53, 0x4c, 0x73, 0x74]
    private static let headerSize = 0x88
    private static let ruleHeaderSize = 56
    private static let numberDataSize = 68

    static func parse(_ data: Data) -> SmartCriteriaGroup? {
        let bytes = [UInt8](data)
        var end = 0
        guard let group = parseGroup(bytes, at: 0, end: &end, depth: 0), end == bytes.count else { return nil }
        return group
    }

    static func serialize(_ group: SmartCriteriaGroup) -> Data {
        var out = Data()
        write(group, to: &out)
        return out
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        return (UInt32(b[o]) << 24) | (UInt32(b[o + 1]) << 16) | (UInt32(b[o + 2]) << 8) | UInt32(b[o + 3])
    }

    private static func i64(_ b: [UInt8], _ o: Int) -> Int64? {
        guard o >= 0, o + 8 <= b.count else { return nil }
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(b[o + i]) }
        return Int64(bitPattern: v)
    }

    private static func parseGroup(_ b: [UInt8], at start: Int, end: inout Int, depth: Int) -> SmartCriteriaGroup? {
        guard depth < 16, start + headerSize <= b.count, Array(b[start..<start + 4]) == magic,
              let version = u32(b, start + 4), let count = u32(b, start + 8), let op = u32(b, start + 12),
              count < 1024 else { return nil }
        var group = SmartCriteriaGroup()
        group.version = version
        group.matchAll = op == 0
        group.headerPad = Data(b[start + 16..<start + headerSize])
        var pos = start + headerSize
        for _ in 0..<Int(count) {
            guard let field = u32(b, pos), let action = u32(b, pos + 4), pos + ruleHeaderSize <= b.count,
                  let length32 = u32(b, pos + 52) else { return nil }
            let length = Int(length32)
            let pad = Data(b[pos + 8..<pos + 52])
            let dataStart = pos + ruleHeaderSize
            guard dataStart + length <= b.count else { return nil }
            if field == 0 {
                var subEnd = 0
                guard let sub = parseGroup(b, at: dataStart, end: &subEnd, depth: depth + 1), subEnd == dataStart + length else { return nil }
                var nested = sub
                nested.groupPad = pad
                nested.groupAction = action
                group.items.append(.group(nested))
            } else if (action >> 24) == 1 || (action >> 24) == 3 {
                guard length % 2 == 0 else { return nil }
                let textBytes = Data(b[dataStart..<dataStart + length])
                guard let text = String(data: textBytes, encoding: .utf16BigEndian) else { return nil }
                var rule = SmartCriteriaRule(field: field, action: action, text: text)
                rule.pad = pad
                group.items.append(.rule(rule))
            } else {
                guard length == numberDataSize,
                      let fv = i64(b, dataStart), let fd = i64(b, dataStart + 8), let fu = i64(b, dataStart + 16),
                      let tv = i64(b, dataStart + 24), let td = i64(b, dataStart + 32), let tu = i64(b, dataStart + 40) else { return nil }
                var rule = SmartCriteriaRule(field: field, action: action, text: nil)
                rule.fromValue = fv
                rule.fromDate = fd
                rule.fromUnits = fu
                rule.toValue = tv
                rule.toDate = td
                rule.toUnits = tu
                rule.trailer = Data(b[dataStart + 48..<dataStart + numberDataSize])
                rule.pad = pad
                group.items.append(.rule(rule))
            }
            pos = dataStart + length
        }
        end = pos
        return group
    }

    private static func append32(_ v: UInt32, to out: inout Data) {
        out.append(UInt8((v >> 24) & 0xff))
        out.append(UInt8((v >> 16) & 0xff))
        out.append(UInt8((v >> 8) & 0xff))
        out.append(UInt8(v & 0xff))
    }

    private static func append64(_ v: Int64, to out: inout Data) {
        let u = UInt64(bitPattern: v)
        for i in (0..<8).reversed() { out.append(UInt8((u >> UInt64(i * 8)) & 0xff)) }
    }

    private static func fixed(_ data: Data, count: Int) -> Data {
        if data.count == count { return data }
        if data.count > count { return data.prefix(count) }
        return data + Data(count: count - data.count)
    }

    private static func write(_ group: SmartCriteriaGroup, to out: inout Data) {
        out.append(contentsOf: magic)
        append32(group.version, to: &out)
        append32(UInt32(group.items.count), to: &out)
        append32(group.matchAll ? 0 : 1, to: &out)
        out.append(fixed(group.headerPad, count: headerSize - 16))
        for item in group.items {
            switch item {
            case .group(let sub):
                var body = Data()
                write(sub, to: &body)
                append32(0, to: &out)
                append32(sub.groupAction, to: &out)
                out.append(fixed(sub.groupPad, count: 44))
                append32(UInt32(body.count), to: &out)
                out.append(body)
            case .rule(let rule):
                append32(rule.field, to: &out)
                append32(rule.action, to: &out)
                out.append(fixed(rule.pad, count: 44))
                if let text = rule.text {
                    let encoded = text.data(using: .utf16BigEndian) ?? Data()
                    append32(UInt32(encoded.count), to: &out)
                    out.append(encoded)
                } else {
                    append32(UInt32(numberDataSize), to: &out)
                    append64(rule.fromValue, to: &out)
                    append64(rule.fromDate, to: &out)
                    append64(rule.fromUnits, to: &out)
                    append64(rule.toValue, to: &out)
                    append64(rule.toDate, to: &out)
                    append64(rule.toUnits, to: &out)
                    out.append(fixed(rule.trailer, count: 20))
                }
            }
        }
    }
}
