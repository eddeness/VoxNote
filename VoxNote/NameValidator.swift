import Foundation

struct NameValidator {
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 50 else { return false }

        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        guard trimmed.rangeOfCharacter(from: invalidChars) == nil else { return false }

        return true
    }
}
