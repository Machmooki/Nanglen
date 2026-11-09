import Foundation

/// Maps provider metadata and names to a `VenueCategory`.
nonisolated enum CategoryClassifier {
    private static let coworkingKeywords = ["co-working", "coworking", "co working", "cowork", "โคเวิร์ก", "โคเวิร์ค", "workspace", "work space"]
    private static let libraryKeywords = ["library", "ห้องสมุด", "หอสมุด"]
    private static let cafeKeywords = ["cafe", "café", "coffee", "คาเฟ่", "กาแฟ", "คอฟฟี่"]
    private static let studyKeywords = ["study", "ติว", "อ่านหนังสือ", "learning", "tutor"]

    /// Category implied by words in a name or query, if any.
    static func category(fromKeywordsIn text: String) -> VenueCategory? {
        let lower = text.lowercased()
        if coworkingKeywords.contains(where: lower.contains) { return .coworking }
        if libraryKeywords.contains(where: lower.contains) { return .library }
        if studyKeywords.contains(where: lower.contains) { return .studySpace }
        if cafeKeywords.contains(where: lower.contains) { return .cafe }
        return nil
    }

    /// - Parameters:
    ///   - pointOfInterestCategory: raw MapKit POI category, e.g. "MKPOICategoryCafe".
    ///   - hint: category the user was searching for, used as a last resort.
    static func classify(name: String, pointOfInterestCategory: String?, hint: VenueCategory?) -> VenueCategory {
        let lowerName = name.lowercased()
        if coworkingKeywords.contains(where: lowerName.contains) { return .coworking }
        switch pointOfInterestCategory {
        case "MKPOICategoryCafe", "MKPOICategoryBakery": return .cafe
        case "MKPOICategoryLibrary": return .library
        case "MKPOICategoryUniversity", "MKPOICategorySchool": return .studySpace
        default: break
        }
        if let fromName = category(fromKeywordsIn: lowerName) { return fromName }
        return hint ?? .other
    }
}
