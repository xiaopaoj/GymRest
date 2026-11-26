import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case shoulders, back, legs, posteriorChain, mobility, lowerBack, adductors, hips, cardio, grip
    case chest, upperChest, lats, upperBack, frontDelts, sideDelts, rearDelts, biceps, triceps, quads, hamstrings, glutes, calves, core, forearms
    var id: Self { self }
    var title: String {
        switch self {
        case .shoulders: "肩部"
        case .back: "背部"
        case .legs: "下肢"
        case .posteriorChain: "后侧链"
        case .mobility: "活动度"
        case .lowerBack: "下背"
        case .adductors: "内收肌"
        case .hips: "髋部"
        case .cardio: "心肺"
        case .grip: "握力"
        case .chest: "胸部"
        case .upperChest: "上胸"
        case .lats: "背阔肌"
        case .upperBack: "上背"
        case .frontDelts: "肩前束"
        case .sideDelts: "肩中束"
        case .rearDelts: "肩后束"
        case .biceps: "二头肌"
        case .triceps: "三头肌"
        case .quads: "股四头肌"
        case .hamstrings: "腘绳肌"
        case .glutes: "臀部"
        case .calves: "小腿"
        case .core: "核心"
        case .forearms: "前臂"
        }
    }
    func includes(_ other: Self) -> Bool { self == other || (self == .chest && other == .upperChest) }
}
struct CatalogMedia: Codable, Sendable {
    let status: String
    let frameAssets: [String]?
    let animationAsset: String?
    let equipmentAsset: String?
    let author: String?
    let licenseURL: String?
    let sourceURL: String?
    var approved: Bool { status == "approved" && author?.isEmpty == false && licenseURL?.hasPrefix("https://") == true && sourceURL?.hasPrefix("https://") == true }
}
struct CatalogExercise: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let aliases: [String]?
    let supportsOrderAdvice: Bool?
    let englishName: String
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let pattern: String
    let equipment: [String]
    let loadKind: LoadKind
    let compound: Bool
    let sets: Int
    let repetitions: Int?
    let restSeconds: Int
    let transitionRestSeconds: Int
    let cues: [String]
    let sourceURL: String
    let sourceAuthor: String
    let licenseURL: String
    let media: CatalogMedia
    var prescription: SetValues { SetValues(repetitions: repetitions, kind: loadKind) }
    func spec(alternatives: [CatalogExercise] = []) -> ExerciseSpec {
        ExerciseSpec(name: name, sets: sets, restSeconds: restSeconds,
            alternatives: alternatives.map { ExerciseAlternative(name: $0.name, restSeconds: $0.restSeconds, catalogID: $0.id, prescription: $0.prescription) },
            transitionRestSeconds: transitionRestSeconds, catalogID: id, prescription: prescription)
    }
}
struct ExerciseCatalog: Codable, Sendable {
    let version: Int
    let attribution: String
    let exercises: [CatalogExercise]
    static var equipmentNames: [String: String] { [
        "box":"训练箱", "chair":"椅子", "doorway":"门框", "kettlebell":"壶铃", "genericMachine":"固定器械",
        "plate":"杠铃片", "band":"弹力带", "stabilityBall":"健身球", "towel":"毛巾", "wall":"墙面", "cardio":"有氧器械",
        "bodyweight":"徒手", "barbell":"杠铃", "dumbbell":"哑铃", "bench":"平凳", "inclineBench":"可调训练凳", "rack":"深蹲架",
        "cable":"绳索器械", "pullupBar":"单杠", "assistedPullup":"辅助引体器械", "chestMachine":"推胸器械", "shoulderMachine":"肩推器械",
        "rowMachine":"划船器械", "pecDeck":"夹胸器械", "rearMachine":"反向飞鸟器械", "lateralMachine":"侧平举器械",
        "legPress":"腿举器械", "legCurl":"腿弯举器械", "legExtension":"腿屈伸器械", "mat":"垫子"
    ] }
    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "ExerciseCatalog", withExtension: "json") else { throw CatalogError.invalid }
        return try decode(Data(contentsOf: url))
    }
    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, !value.exercises.isEmpty, Set(value.exercises.map(\.id)).count == value.exercises.count else { throw CatalogError.invalid }
        for item in value.exercises {
            guard !item.id.isEmpty, !item.primary.isEmpty, !item.pattern.isEmpty, !item.equipment.isEmpty,
                  item.equipment.allSatisfy({ equipmentNames[$0] != nil }), !item.cues.isEmpty,
                  item.sourceURL.hasPrefix("https://"), item.licenseURL.hasPrefix("https://"),
                  !item.sourceAuthor.isEmpty, ["pending", "approved"].contains(item.media.status) else { throw CatalogError.invalid }
            try item.spec().validate()
            if item.media.status == "approved" {
                guard item.media.approved, item.media.animationAsset != nil || !(item.media.frameAssets ?? []).isEmpty else { throw CatalogError.invalid }
                for filename in [item.media.animationAsset, item.media.equipmentAsset].compactMap({ $0 }) + (item.media.frameAssets ?? []) {
                    guard filename == (filename as NSString).lastPathComponent, !filename.contains("..") else { throw CatalogError.invalid }
                }
                if let frames = item.media.frameAssets {
                    guard frames.count == 3, Set(frames).count == 3, frames.allSatisfy({ ($0 as NSString).pathExtension.lowercased() == "png" }) else { throw CatalogError.invalid }
                }
                if let filename = item.media.animationAsset, !["mp4", "mov"].contains((filename as NSString).pathExtension.lowercased()) { throw CatalogError.invalid }
                if let filename = item.media.equipmentAsset, !["png", "jpg", "jpeg", "webp"].contains((filename as NSString).pathExtension.lowercased()) { throw CatalogError.invalid }
            }
        }
        return value
    }
    func item(_ id: String?) -> CatalogExercise? { exercises.first { $0.id == id } }
    /// Exact normalized name/alias only; ambiguous names never silently pick a variant.
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    func matching(name: String) -> CatalogExercise? {
        let key = Self.normalizedName(name)
        guard !key.isEmpty else { return nil }
        let matches = exercises.filter { item in
            ([item.name, item.englishName] + (item.aliases ?? [])).contains { Self.normalizedName($0) == key }
        }
        return matches.count == 1 ? matches.first : nil
    }
    func resolve(_ exercise: ExerciseSpec) -> CatalogExercise? { item(exercise.catalogID) ?? matching(name: exercise.name) }
    func alternatives(to item: CatalogExercise, equipment available: Set<String>? = nil) -> [CatalogExercise] {
        exercises.filter { candidate in
            candidate.id != item.id && candidate.pattern == item.pattern &&
            candidate.primary.contains(where: { a in item.primary.contains { $0.includes(a) || a.includes($0) } }) &&
            (available.map { Set(candidate.equipment).isSubset(of: $0) } ?? true)
        }
    }
}
enum CatalogError: LocalizedError {
    case invalid, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "动作目录无法读取或校验失败，请保留现有计划并重试。"
        case .unavailable: "部分训练位置没有符合所选器材的动作，请调整器材或动作选择。"
        }
    }
}

struct TrainingOrderAdvice {
    let exercise: ExerciseSpec
    let reason: String
    static func suggest(_ exercises: [ExerciseSpec], catalog: ExerciseCatalog, priority: MuscleGroup?) -> [Self] {
        func score(_ item: CatalogExercise) -> Int {
            let focused = priority.map { focus in item.primary.contains { focus.includes($0) } } ?? false
            return (focused ? 0 : 2) + (item.compound ? 0 : 1)
        }
        // Leave unlinked custom exercises in place. Do not guess anatomy from names.
        var result = exercises
        let positions = exercises.indices.filter { catalog.item(exercises[$0].catalogID)?.supportsOrderAdvice != false && catalog.item(exercises[$0].catalogID) != nil }
        let sorted = positions.sorted { left, right in
            let a = score(catalog.item(exercises[left].catalogID)!), b = score(catalog.item(exercises[right].catalogID)!)
            return a == b ? left < right : a < b
        }.map { exercises[$0] }
        for (position, exercise) in zip(positions, sorted) { result[position] = exercise }
        return result.map { exercise in
            let reason: String
            if let item = catalog.item(exercise.catalogID), item.supportsOrderAdvice != false {
                if let priority, item.primary.contains(where: { priority.includes($0) }) { reason = "优先训练重点部位：" + priority.title }
                else { reason = item.compound ? "先安排多关节动作，保留完成质量" : "辅助与单关节动作随后安排" }
            } else { reason = "该动作未纳入顺序建议，保留原位置" }
            return Self(exercise: exercise, reason: reason)
        }
    }
}
