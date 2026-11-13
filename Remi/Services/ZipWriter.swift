import Foundation

/// En küçük zip yazıcı: sıkıştırmasız ("stored") kayıtlar ve CRC-32. Excel bu dosyaları açar.
enum ZipWriter {
    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(output.count)
            var local = Data()
            local.append(le32(0x04034b50)); local.append(le16(20)); local.append(le16(0x0800)); local.append(le16(0))
            local.append(le16(0)); local.append(le16(0x21)) // saat, tarih (1980-01-01)
            local.append(le32(crc)); local.append(le32(UInt32(file.data.count))); local.append(le32(UInt32(file.data.count)))
            local.append(le16(UInt16(name.count))); local.append(le16(0))
            output.append(local); output.append(name); output.append(file.data)

            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20)); central.append(le16(0x0800)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(UInt32(file.data.count))); central.append(le32(UInt32(file.data.count)))
            central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0)); central.append(le32(offset)); central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le32(0x06054b50)); output.append(le16(0)); output.append(le16(0))
        output.append(le16(UInt16(files.count))); output.append(le16(UInt16(files.count)))
        output.append(le32(UInt32(central.count))); output.append(le32(centralOffset)); output.append(le16(0))
        return output
    }

    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(UInt32.max) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
