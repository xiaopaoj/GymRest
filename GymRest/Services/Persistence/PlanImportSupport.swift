import Foundation

enum PlanImportSupport {
    static func cleaned(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        if text.first == "\u{feff}" { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.components(separatedBy: .newlines)
        if let first = lines.first, ["```json", "```"].contains(first.lowercased()), lines.last == "```", lines.count >= 3 {
            text = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        return Data(text.utf8)
    }
    static func message(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            keys.reduce("$") { value, key in
                if let index = key.intValue { return value + "[\(index)]" }
                return value + "." + key.stringValue
            }
        }
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "缺少必填字段：" + path(context.codingPath + [key])
        case DecodingError.typeMismatch(_, let context):
            return "字段类型不正确：" + path(context.codingPath) + "。请检查数字、文本、布尔值或数组类型。"
        case DecodingError.valueNotFound(_, let context):
            return "必填字段不能为null：" + path(context.codingPath)
        case DecodingError.dataCorrupted(let context):
            return "内容无法解析：" + path(context.codingPath) + "。请检查JSON语法、UUID或枚举值。" + context.debugDescription
        default: return error.localizedDescription
        }
    }
}

struct ImportActionMatch: Identifiable {
    enum Kind: Equatable { case identifier, name, unmatched }
    let day: Int
    let exercise: Int
    let alternative: Int?
    let dayName: String
    let name: String
    let target: CatalogExercise?
    let kind: Kind
    var id: String { "\(day):\(exercise):\(alternative ?? -1)" }
    var status: String {
        switch kind { case .identifier: "标识已匹配"; case .name: "名称可匹配"; case .unmatched: "未匹配 · 可保留自定义" }
    }
}
enum ImportActionMatcher {
    static func rows(_ archive: PlanArchive, catalog: ExerciseCatalog) -> [ImportActionMatch] {
        var rows: [ImportActionMatch] = []
        for (di, day) in archive.plans.enumerated() {
            for (ei, item) in day.exercises.enumerated() {
                func append(name: String, id: String?, alternative: Int?) {
                    let direct = catalog.item(id)
                    let target = direct ?? catalog.matching(name: name)
                    rows.append(ImportActionMatch(day: di, exercise: ei, alternative: alternative, dayName: day.name,
                        name: name, target: target, kind: direct != nil ? .identifier : target != nil ? .name : .unmatched))
                }
                append(name: item.name, id: item.catalogID, alternative: nil)
                for (ai, alt) in item.alternatives.enumerated() { append(name: alt.name, id: alt.catalogID, alternative: ai) }
            }
        }
        return rows
    }
    static func assign(_ target: CatalogExercise?, row: ImportActionMatch, archive: inout PlanArchive, useCatalogName: Bool) {
        guard archive.plans.indices.contains(row.day), archive.plans[row.day].exercises.indices.contains(row.exercise) else { return }
        if let ai = row.alternative {
            guard archive.plans[row.day].exercises[row.exercise].alternatives.indices.contains(ai) else { return }
            archive.plans[row.day].exercises[row.exercise].alternatives[ai].catalogID = target?.id
            if useCatalogName, let target { archive.plans[row.day].exercises[row.exercise].alternatives[ai].name = target.name }
        } else {
            archive.plans[row.day].exercises[row.exercise].catalogID = target?.id
            if useCatalogName, let target { archive.plans[row.day].exercises[row.exercise].name = target.name }
        }
    }
}

enum PlanImportValidation {
    static func exercise(_ item: ExerciseSpec, path: String) throws {
        func check(_ valid: Bool, _ field: String, _ rule: String) throws {
            guard valid else { throw ArchiveFailure.invalid(path + "." + field + "：" + rule) }
        }
        try check(!item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.name.count <= 100, "name", "名称须为1–100字")
        try check((1...100).contains(item.sets), "sets", "组数须为1–100整数")
        try check((1...86400).contains(item.restSeconds), "restSeconds", "组间休息须为1–86400秒")
        try check(item.transitionRestSeconds.map({ (0...86400).contains($0) }) ?? true, "transitionRestSeconds", "动作间休息须为0–86400秒")
        try check(item.catalogID.map({ !$0.isEmpty && $0.count <= 100 }) ?? true, "catalogID", "动作标识须为1–100字符，也可省略")
        for (set, seconds) in item.restOverrides {
            try check((1...item.sets).contains(set) && (1...86400).contains(seconds), "restOverrides[\(set)]", "组号须在组数范围内，休息须为1–86400秒")
        }
        try values(item.prescription, path: path + ".prescription")
        for (index, alt) in item.alternatives.enumerated() {
            let prefix = "alternatives[\(index)]"
            try check(!alt.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && alt.name.count <= 100, prefix + ".name", "名称须为1–100字")
            try check(alt.catalogID.map({ !$0.isEmpty && $0.count <= 100 }) ?? true, prefix + ".catalogID", "动作标识须为1–100字符，也可省略")
            try check((1...86400).contains(alt.restSeconds), prefix + ".restSeconds", "组间休息须为1–86400秒")
            for (set, seconds) in alt.restOverrides {
                try check((1...item.sets).contains(set) && (1...86400).contains(seconds), prefix + ".restOverrides[\(set)]", "组号或休息不在范围内")
            }
            try values(alt.prescription, path: path + "." + prefix + ".prescription")
        }
        try item.validate()
    }
    private static func values(_ item: SetValues?, path: String) throws {
        guard let item else { return }
        var field: String?
        if let weight = item.weight, !weight.isFinite || !(0...10000).contains(weight) { field = "weight（0–10000有限数值）" }
        else if let repetitions = item.repetitions, !(1...1000).contains(repetitions) { field = "repetitions（1–1000整数或null）" }
        else if item.equipmentNote.count > 80 { field = "equipmentNote（至多80字）" }
        else if item.kind == .bodyweight && item.weight != nil { field = "weight（自重动作须留空）" }
        else if item.unit == .level && item.kind != .machine { field = "unit（档位只可用于machine器械口径）" }
        if let field { throw ArchiveFailure.invalid(path + "." + field + " 不合法") }
    }
}
