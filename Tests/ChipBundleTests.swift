import XCTest
@testable import PodPassportScanner

final class ChipBundleTests: XCTestCase {
    func testEncodesToContractJSON() throws {
        let bundle = ChipBundle(lds: .init(
            dg1: Data([0x61, 0x02, 0x5F, 0x1F]),
            sod: Data([0x77, 0x01, 0x00])
        ))
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(bundle)) as? [String: Any]
        )
        XCTAssertEqual(json["format"] as? String, "icao-9303-lds1")
        let lds = try XCTUnwrap(json["lds"] as? [String: Any])
        XCTAssertEqual(lds["dg1"] as? String, "YQJfHw==")
        XCTAssertEqual(lds["sod"] as? String, "dwEA")
        XCTAssertNil(lds["dg2"])
        XCTAssertNil(lds["dg11"])
        XCTAssertNil(lds["dg14"])
    }

    func testRoundTrip() throws {
        let bundle = ChipBundle(lds: .init(
            dg1: Data("dg1".utf8),
            dg2: Data("dg2".utf8),
            dg11: Data("dg11".utf8),
            dg14: Data("dg14".utf8),
            sod: Data("sod".utf8)
        ))
        let decoded = try JSONDecoder().decode(ChipBundle.self, from: JSONEncoder().encode(bundle))
        XCTAssertEqual(decoded, bundle)
    }

    /// The bundled sample fixture (same structure as the issuer-side
    /// `emrtd-bundle.json` test fixture) must decode and carry a parseable MRZ.
    func testSampleFixtureDecodesAndParses() throws {
        let bundle = try MockChipReader.loadSampleBundle()
        XCTAssertEqual(bundle.format, "icao-9303-lds1")
        XCTAssertNotNil(bundle.lds.dg2)
        XCTAssertNotNil(bundle.lds.dg11)
        XCTAssertNotNil(bundle.lds.dg14)
        XCTAssertFalse(bundle.lds.sod.isEmpty)

        let mrz = try XCTUnwrap(bundle.mrzFromDG1)
        let parsed = try MRZParser.parseTD3(contiguous: mrz)
        XCTAssertEqual(parsed.surname, "ERIKSSON")
        XCTAssertEqual(parsed.documentNumber, "L898902C3")
    }

    func testDG1StructureIsValidTLV() throws {
        let bundle = try MockChipReader.loadSampleBundle()
        let dg1 = [UInt8](bundle.lds.dg1)
        XCTAssertEqual(dg1[0], 0x61, "DG1 must start with tag 0x61")
        XCTAssertEqual(dg1[2], 0x5F)
        XCTAssertEqual(dg1[3], 0x1F)
        XCTAssertEqual(Int(dg1[4]), 88, "TD3 MRZ is 88 bytes")
        XCTAssertEqual(dg1.count, 5 + 88)
    }
}
