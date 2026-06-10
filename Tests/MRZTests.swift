import XCTest
@testable import PodPassportScanner

final class MRZTests: XCTestCase {
    // ICAO 9303 specimen (Doc 9303 Part 4, Appendix B).
    let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
    let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

    // MARK: Check digits

    func testCheckDigitKnownValues() {
        // Worked examples from ICAO Doc 9303.
        XCTAssertEqual(MRZ.checkDigit("L898902C3"), 6)
        XCTAssertEqual(MRZ.checkDigit("740812"), 2)
        XCTAssertEqual(MRZ.checkDigit("120415"), 9)
        XCTAssertEqual(MRZ.checkDigit("<<<<<<<<<<<<<<"), 0)
    }

    func testCheckDigitRejectsInvalidCharacters() {
        XCTAssertNil(MRZ.checkDigit("ABC 123"))
        XCTAssertNil(MRZ.checkDigit("abc"))
    }

    // MARK: TD3 parsing

    func testParsesSpecimenTD3() throws {
        let parsed = try MRZParser.parseTD3(line1: line1, line2: line2)
        XCTAssertEqual(parsed.documentCode, "P")
        XCTAssertEqual(parsed.issuingState, "UTO")
        XCTAssertEqual(parsed.surname, "ERIKSSON")
        XCTAssertEqual(parsed.givenNames, "ANNA MARIA")
        XCTAssertEqual(parsed.fullName, "ANNA MARIA ERIKSSON")
        XCTAssertEqual(parsed.documentNumber, "L898902C3")
        XCTAssertEqual(parsed.nationality, "UTO")
        XCTAssertEqual(parsed.dateOfBirth, "740812")
        XCTAssertEqual(parsed.sex, "F")
        XCTAssertEqual(parsed.dateOfExpiry, "120415")
    }

    func testParsesContiguous88Chars() throws {
        let parsed = try MRZParser.parseTD3(contiguous: line1 + line2)
        XCTAssertEqual(parsed.documentNumber, "L898902C3")
    }

    func testRejectsWrongLength() {
        XCTAssertThrowsError(try MRZParser.parseTD3(line1: "P<UTO", line2: line2)) {
            XCTAssertEqual($0 as? MRZParseError, .wrongLineLength)
        }
    }

    func testRejectsBadDocumentNumberChecksum() {
        var bad = line2
        let idx = bad.index(bad.startIndex, offsetBy: 9)
        bad.replaceSubrange(idx...idx, with: "5") // correct digit is 6
        XCTAssertThrowsError(try MRZParser.parseTD3(line1: line1, line2: bad)) {
            XCTAssertEqual($0 as? MRZParseError, .checksumFailed(field: "documentNumber"))
        }
    }

    func testRejectsBadCompositeChecksum() {
        var bad = line2
        let idx = bad.index(bad.startIndex, offsetBy: 43)
        bad.replaceSubrange(idx...idx, with: "1") // correct digit is 0
        XCTAssertThrowsError(try MRZParser.parseTD3(line1: line1, line2: bad)) {
            XCTAssertEqual($0 as? MRZParseError, .checksumFailed(field: "composite"))
        }
    }

    // MARK: BAC key

    func testBACKeyStringForSpecimen() {
        let key = MRZKey(documentNumber: "L898902C3", dateOfBirth: "740812", dateOfExpiry: "120415")
        XCTAssertEqual(key.bacKeyString, "L898902C36" + "7408122" + "1204159")
    }

    func testBACKeyPadsShortDocumentNumbers() {
        let key = MRZKey(documentNumber: "AB12345", dateOfBirth: "740812", dateOfExpiry: "120415")
        let bac = key.bacKeyString
        XCTAssertNotNil(bac)
        XCTAssertTrue(bac!.hasPrefix("AB12345<<"))
        XCTAssertEqual(bac!.count, 10 + 7 + 7)
    }

    func testBACKeyNilForInvalidInput() {
        XCTAssertNil(MRZKey(documentNumber: "L898902C3", dateOfBirth: "74081", dateOfExpiry: "120415").bacKeyString)
        XCTAssertNil(MRZKey(documentNumber: "L8989?2C3", dateOfBirth: "740812", dateOfExpiry: "120415").bacKeyString)
    }

    // MARK: OCR normalisation

    func testNormalizeOCRLine() {
        XCTAssertEqual(MRZParser.normalizeOCRLine("p<uto eriksson«anna"), "P<UTOERIKSSON<ANNA")
    }
}
