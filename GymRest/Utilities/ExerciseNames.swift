import Foundation

/// Only the four reviewed variants. Broad names such as barbell curl or dumbbell
/// lunge remain separate exercises; names do not imply an equipment substitution.
enum ExerciseNames {
    private static let entries: [(id: String, name: String, aliases: [String])] = [
        ("neutral-pulldown", "窄距对握高位下拉", ["对握高位下拉", "窄握高位下拉", "Neutral Grip Lat Pulldown", "Close-Grip Lat Pulldown"]),
        ("guide-ez-bar-curl", "站姿 EZ 曲杆弯举", ["站姿EZ曲杆弯举", "EZ杆弯举", "EZ曲杆弯举", "曲杆弯举", "EZ-Bar Curl"]),
        ("guide-walking-lunge", "哑铃行进箭步蹲", ["Walking Lunge", "哑铃行走箭步蹲"]),
        ("guide-seated-calf-raise", "坐姿器械提踵", ["Seated Calf Raise", "器械坐姿提踵"])
    ]
    static func canonical(_ name: String, catalogID: String?) -> String {
        let key = ExerciseCatalog.normalizedName(name)
        for entry in entries where catalogID == nil || catalogID == entry.id {
            if ([entry.name] + entry.aliases).contains(where: { ExerciseCatalog.normalizedName($0) == key }) {
                return entry.name
            }
        }
        return name
    }
    static func standardize(_ exercises: [ExerciseSpec]) -> [ExerciseSpec] {
        exercises.map { original in
            var item = original
            item.prescription = item.prescription.map(ExerciseTiming.resolve)
            item.name = canonical(item.name, catalogID: item.catalogID)
            for index in item.alternatives.indices {
                let alternative = item.alternatives[index]
                item.alternatives[index].name = canonical(alternative.name, catalogID: alternative.catalogID)
                item.alternatives[index].prescription = alternative.prescription.map(ExerciseTiming.resolve)
            }
            return item
        }
    }
    // Preserve history prefill for custom exercises whose old name was part of
    // the profile key. Normalize for comparison without modifying saved history.
    static func canonicalProfileKey(_ key: String) -> String {
        guard let data = Data(base64Encoded: key),
              var parts = try? JSONDecoder().decode([String].self, from: data), [4, 6].contains(parts.count),
              parts[0].hasPrefix("custom:") else { return key }
        let old = String(parts[0].dropFirst("custom:".count))
        let name = canonical(old, catalogID: nil)
        guard name != old else { return key }
        parts[0] = "custom:" + name
        return (try? JSONEncoder().encode(parts).base64EncodedString()) ?? key
    }
}
