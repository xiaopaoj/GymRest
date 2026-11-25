import Foundation

enum LoadUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb, level
    var title: String { self == .level ? "档位" : rawValue }
}
enum LoadKind: String, Codable, CaseIterable, Sendable {
    case total, perHand, machine, bodyweight, added, assistance
    var title: String {
        switch self {
        case .total: "总重量"
        case .perHand: "单只重量"
        case .machine: "器械标重"
        case .bodyweight: "自重"
        case .added: "额外负重"
        case .assistance: "辅助重量"
        }
    }
}
struct SetValues: Codable, Equatable, Sendable {
    var weight: Double?
    var repetitions: Int?
    var unit: LoadUnit = .kg
    var kind: LoadKind = .total
    var equipmentNote = ""
    enum CodingKeys: String, CodingKey { case weight, repetitions, unit, kind, equipmentNote }
    init(weight: Double? = nil, repetitions: Int? = nil, unit: LoadUnit = .kg, kind: LoadKind = .total, equipmentNote: String = "") {
        self.weight = weight; self.repetitions = repetitions; self.unit = unit; self.kind = kind; self.equipmentNote = equipmentNote
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weight = try values.decodeIfPresent(Double.self, forKey: .weight)
        repetitions = try values.decodeIfPresent(Int.self, forKey: .repetitions)
        unit = try values.decodeIfPresent(LoadUnit.self, forKey: .unit) ?? .kg
        kind = try values.decodeIfPresent(LoadKind.self, forKey: .kind) ?? .total
        equipmentNote = try values.decodeIfPresent(String.self, forKey: .equipmentNote) ?? ""
    }
    func validate() throws {
        guard equipmentNote.count <= 80,
              repetitions.map({ (1...1000).contains($0) }) ?? true,
              weight.map({ $0.isFinite && (0...10000).contains($0) }) ?? true,
              kind != .bodyweight || weight == nil,
              unit != .level || kind == .machine else { throw PerformanceError.invalid }
    }
    var summary: String {
        let load: String
        if kind == .bodyweight { load = "自重" }
        else if let weight { load = "\(weight.formatted(.number.precision(.fractionLength(0...2)))) \(unit.title)（\(kind.title)）" }
        else { load = "重量未记录（\(kind.title)）" }
        return load + (repetitions.map { " · \($0) 次" } ?? " · 次数未记录")
    }
}
struct SetPerformance: Codable, Equatable, Sendable {
    let exerciseName: String
    let catalogID: String?
    let values: SetValues?
    let profileKey: String?
    let completedAt: Date?
    func validate() throws {
        guard !exerciseName.isEmpty, exerciseName.count <= 100 else { throw PerformanceError.invalid }
        try values?.validate()
    }
}
enum PerformanceError: LocalizedError {
    case invalid, staleOrder
    var errorDescription: String? {
        switch self {
        case .invalid: "重量须为0–10000的有限数值，次数可留空或填写1–1000整数；档位只适用于器械，自重无需填写重量，器械备注限80字。"
        case .staleOrder: "训练进度已变化，请重新查看尚未开始动作的顺序建议。"
        }
    }
}
