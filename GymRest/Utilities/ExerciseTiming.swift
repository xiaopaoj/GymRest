import Foundation

/// Legacy v3 plans stored seconds in repetitions plus an explicit timing note.
/// Interpret only unambiguous effort hints; never infer timing from rest periods.
enum ExerciseTiming {
    private static let pattern = #"\A\s*(按秒计\s*[:：]?\s*|每侧\s*|每组\s*)?([0-9]{1,5})\s*(秒|s)(?:\s*/\s*(组|侧))?\s*\z"#
    private static let otherTarget = #"[0-9]\s*(?:秒|s\b|分钟|次|组)"#
    private static func hint(_ note: String) -> (seconds: Int, bilateral: Bool, range: NSRange)? {
        guard !note.contains("休息") else { return nil }
        let clauses = note.split(omittingEmptySubsequences: true) { "，,；;。\n".contains($0) }
        var hint: (Int, Bool, NSRange)?
        for clause in clauses {
            let text = String(clause)
            guard let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                if text.range(of: otherTarget, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
                continue
            }
            guard hint == nil, let digits = Range(match.range(at: 2), in: text),
                  let seconds = Int(text[digits]), (1...86400).contains(seconds) else { return nil }
            let prefix = Range(match.range(at: 1), in: text).map { text[$0] }
            let suffix = Range(match.range(at: 4), in: text).map { text[$0] }
            guard prefix != nil || suffix != nil || clauses.count == 1 else { return nil }
            guard !(prefix?.hasPrefix("每组") == true && suffix == "侧"),
                  !(prefix?.hasPrefix("每侧") == true && suffix == "组") else { return nil }
            let bilateral = prefix?.hasPrefix("每侧") == true || suffix == "侧"
            hint = (seconds, bilateral, NSRange(clause.startIndex..<clause.endIndex, in: note))
        }
        return hint
    }
    static func resolve(_ values: SetValues) -> SetValues {
        guard values.durationSeconds == nil, let hint = hint(values.equipmentNote),
              values.repetitions == nil || values.repetitions == hint.seconds else { return values }
        var result = values
        result.durationSeconds = hint.seconds; result.repetitions = nil
        if hint.bilateral { result.sideCount = 2 }
        return result
    }
    static func removingLegacyHint(from note: String) -> String {
        guard let hint = hint(note), let range = Range(hint.range, in: note) else { return note }
        var result = note; result.removeSubrange(range)
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,；;：:")))
    }
}
