import Foundation

/// ICAO 9303 MRZ helpers: check digits, the BAC/PACE key, and a TD3 (passport
/// booklet, 2 × 44 chars) parser.
enum MRZ {
    /// ICAO 9303 check digit: weights 7-3-1 repeating; digits as value,
    /// A=10…Z=35, `<` = 0; result is mod 10.
    static func checkDigit(_ field: some StringProtocol) -> Int? {
        let weights = [7, 3, 1]
        var total = 0
        for (i, c) in field.enumerated() {
            let value: Int
            switch c {
            case "<": value = 0
            case "0"..."9": value = c.wholeNumberValue!
            case "A"..."Z": value = Int(c.asciiValue! - Character("A").asciiValue!) + 10
            default: return nil
            }
            total += value * weights[i % 3]
        }
        return total % 10
    }

    static func checkDigitMatches(_ field: some StringProtocol, digit: Character) -> Bool {
        guard let expected = checkDigit(field) else { return false }
        return digit.wholeNumberValue == expected
    }
}

/// The three fields that derive the Basic Access Control / PACE key.
/// Dates are MRZ-format `YYMMDD`.
struct MRZKey: Equatable, Sendable {
    let documentNumber: String
    let dateOfBirth: String // YYMMDD
    let dateOfExpiry: String // YYMMDD

    /// The key string `NFCPassportReader` expects:
    /// document number padded to 9 with `<` + check digit, DOB + check digit,
    /// expiry + check digit.
    var bacKeyString: String? {
        let doc = documentNumber.uppercased().padding(toLength: max(9, documentNumber.count), withPad: "<", startingAt: 0)
        guard let docCD = MRZ.checkDigit(doc),
              let dobCD = MRZ.checkDigit(dateOfBirth),
              let expCD = MRZ.checkDigit(dateOfExpiry),
              dateOfBirth.count == 6, dateOfExpiry.count == 6 else { return nil }
        return "\(doc)\(docCD)\(dateOfBirth)\(dobCD)\(dateOfExpiry)\(expCD)"
    }
}

/// Parsed fields from a TD3 MRZ (the two printed lines in a passport booklet).
struct ParsedMRZ: Equatable, Sendable {
    let documentCode: String
    let issuingState: String
    let surname: String
    let givenNames: String
    let documentNumber: String
    let nationality: String
    let dateOfBirth: String // YYMMDD
    let sex: String
    let dateOfExpiry: String // YYMMDD

    var key: MRZKey {
        MRZKey(documentNumber: documentNumber, dateOfBirth: dateOfBirth, dateOfExpiry: dateOfExpiry)
    }

    var fullName: String {
        [givenNames, surname].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum MRZParseError: Error, Equatable {
    case wrongLineLength
    case invalidCharacters
    case checksumFailed(field: String)
}

enum MRZParser {
    static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")

    /// Parses a TD3 MRZ from its two 44-character lines, verifying the
    /// document-number, date-of-birth, expiry and composite check digits.
    static func parseTD3(line1: String, line2: String) throws -> ParsedMRZ {
        guard line1.count == 44, line2.count == 44 else { throw MRZParseError.wrongLineLength }
        guard line1.unicodeScalars.allSatisfy(allowedCharacters.contains),
              line2.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw MRZParseError.invalidCharacters
        }

        let l1 = Array(line1)
        let l2 = Array(line2)

        let documentCode = String(l1[0...1]).replacingOccurrences(of: "<", with: "")
        let issuingState = String(l1[2...4]).replacingOccurrences(of: "<", with: "")
        let nameField = String(l1[5...43])
        let nameParts = nameField.components(separatedBy: "<<")
        let surname = (nameParts.first ?? "").replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let givenNames = (nameParts.count > 1 ? nameParts[1] : "").replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let documentNumberRaw = String(l2[0...8])
        guard MRZ.checkDigitMatches(documentNumberRaw, digit: l2[9]) else {
            throw MRZParseError.checksumFailed(field: "documentNumber")
        }
        let nationality = String(l2[10...12]).replacingOccurrences(of: "<", with: "")
        let dateOfBirth = String(l2[13...18])
        guard MRZ.checkDigitMatches(dateOfBirth, digit: l2[19]) else {
            throw MRZParseError.checksumFailed(field: "dateOfBirth")
        }
        let sex = String(l2[20]).replacingOccurrences(of: "<", with: "")
        let dateOfExpiry = String(l2[21...26])
        guard MRZ.checkDigitMatches(dateOfExpiry, digit: l2[27]) else {
            throw MRZParseError.checksumFailed(field: "dateOfExpiry")
        }
        // Composite check digit covers positions 0–9, 13–19 and 21–42.
        let composite = String(l2[0...9]) + String(l2[13...19]) + String(l2[21...42])
        guard MRZ.checkDigitMatches(composite, digit: l2[43]) else {
            throw MRZParseError.checksumFailed(field: "composite")
        }

        return ParsedMRZ(
            documentCode: documentCode,
            issuingState: issuingState,
            surname: surname,
            givenNames: givenNames,
            documentNumber: documentNumberRaw.replacingOccurrences(of: "<", with: ""),
            nationality: nationality,
            dateOfBirth: dateOfBirth,
            sex: sex,
            dateOfExpiry: dateOfExpiry
        )
    }

    /// Extracts the two TD3 lines from a single 88-character string
    /// (e.g. the MRZ body inside DG1).
    static func parseTD3(contiguous: String) throws -> ParsedMRZ {
        guard contiguous.count == 88 else { throw MRZParseError.wrongLineLength }
        let mid = contiguous.index(contiguous.startIndex, offsetBy: 44)
        return try parseTD3(line1: String(contiguous[..<mid]), line2: String(contiguous[mid...]))
    }

    /// Cleans an OCR candidate line: uppercase, strip spaces, map common
    /// misreads of the filler character.
    static func normalizeOCRLine(_ line: String) -> String {
        line.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "«", with: "<")
            .replacingOccurrences(of: "≤", with: "<")
    }
}
