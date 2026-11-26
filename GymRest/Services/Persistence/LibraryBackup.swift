import Foundation
import SwiftData

struct LibraryBackup: Codable {
    let format: String
    let version: Int
    let createdAt: Date
    let programs: [Program]
    let days: [Day]
    let records: [Record]
    let preferences: Preferences
    struct Program: Codable { let id: UUID; let name: String; let position: Int; let weeklySessions: Int? }
    struct Day: Codable { let id: UUID; let name: String; let position: Int; let programID: UUID?; let exerciseData: Data }
    struct Preferences: Codable {
        let defaultSets: Int; let defaultRest: Int; let notificationFallback: Bool; let keepScreenOn: Bool
        @MainActor init(_ value: LibraryPreferences) {
            defaultSets = value.defaultSets; defaultRest = value.defaultRest
            notificationFallback = value.notificationFallback; keepScreenOn = value.keepScreenOn
        }
        @MainActor func apply(to value: LibraryPreferences) {
            value.defaultSets = defaultSets; value.defaultRest = defaultRest
            value.notificationFallback = notificationFallback; value.keepScreenOn = keepScreenOn
        }
    }
    struct Record: Codable {
        let id: UUID; let planName: String; let startedAt: Date?; let endedAt: Date; let finished: Bool
        let exerciseData: Data; let completedData: Data; let performedNamesData: Data?; let performancesData: Data?
        let workoutID: String?; let workoutSource: String?; let workoutStart: Date?; let workoutEnd: Date?
        @MainActor init(_ value: TrainingRecord) {
            id = value.id; planName = value.planName; startedAt = value.startedAt; endedAt = value.endedAt; finished = value.finished
            exerciseData = value.exerciseData; completedData = value.completedData; performedNamesData = value.performedNamesData; performancesData = value.performancesData
            workoutID = value.workoutID; workoutSource = value.workoutSource; workoutStart = value.workoutStart; workoutEnd = value.workoutEnd
        }
        @MainActor func make() -> TrainingRecord {
            let value = TrainingRecord(id: id, planName: planName, startedAt: startedAt, endedAt: endedAt, finished: finished,
                                       exerciseData: exerciseData, completedData: completedData)
            value.performedNamesData = performedNamesData; value.performancesData = performancesData
            value.workoutID = workoutID; value.workoutSource = workoutSource; value.workoutStart = workoutStart; value.workoutEnd = workoutEnd
            return value
        }
    }
    @MainActor static func capture(_ context: ModelContext, preferences: LibraryPreferences) throws -> Self {
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存已有编辑，再备份。") }
        return Self(format: "GymRestBackup", version: 1, createdAt: Date(),
            programs: try context.fetch(FetchDescriptor<TrainingProgram>(sortBy: [SortDescriptor(\TrainingProgram.position)])).map { Program(id: $0.id, name: $0.name, position: $0.position, weeklySessions: $0.weeklySessions) },
            days: try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\TrainingPlan.position)])).map { Day(id: $0.id, name: $0.name, position: $0.position, programID: $0.programID, exerciseData: $0.exerciseData) },
            records: try context.fetch(FetchDescriptor<TrainingRecord>(sortBy: [SortDescriptor(\TrainingRecord.endedAt)])).map(Record.init),
            preferences: Preferences(preferences))
    }
    @MainActor func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 50 * 1024 * 1024 else { throw ArchiveFailure.invalid("备份内容超过当前50MB上限。") }
        return data
    }
    @MainActor static func decode(_ data: Data) throws -> Self {
        guard data.count <= 50 * 1024 * 1024 else { throw ArchiveFailure.invalid("备份文件不能超过50MB。") }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["plans"] != nil, root["format"] == nil {
            throw ArchiveFailure.invalid("这是普通计划JSON，请到「计划 JSON 导入与导出」页面导入。")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value: Self
        do { value = try decoder.decode(Self.self, from: data) }
        catch { throw ArchiveFailure.invalid(PlanImportSupport.message(error)) }
        try value.validate(); return value
    }
    @MainActor func validate() throws {
        guard format == "GymRestBackup", version == 1 else { throw ArchiveFailure.invalid("请选择GymRest完整备份；普通计划JSON请到计划导入页面。") }
        guard Set(programs.map(\.id)).count == programs.count, Set(days.map(\.id)).count == days.count,
              Set(records.map(\.id)).count == records.count else { throw ArchiveFailure.invalid("备份中存在重复ID。") }
        guard (1...100).contains(preferences.defaultSets), (1...86400).contains(preferences.defaultRest) else { throw ArchiveFailure.invalid("备份默认组数或休息不合法。") }
        let parents = Set(programs.map(\.id))
        for program in programs {
            guard !program.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, program.name.count <= 100,
                  program.weeklySessions.map({ (1...7).contains($0) }) ?? true else { throw ArchiveFailure.invalid("备份计划信息不合法。") }
        }
        for day in days {
            guard !day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, day.name.count <= 100,
                  day.programID.map({ parents.contains($0) }) ?? true else { throw ArchiveFailure.invalid("备份训练日名称或归属不合法。") }
            let exercises = try JSONDecoder().decode([ExerciseSpec].self, from: day.exerciseData)
            var identifiers: Set<UUID> = []
            for item in exercises {
                try item.validate()
                for id in [item.id] + item.alternatives.map(\.id) {
                    guard identifiers.insert(id).inserted else { throw ArchiveFailure.invalid("备份动作ID重复。") }
                }
            }
        }
        for record in records {
            guard !record.planName.isEmpty, record.planName.count <= 100, record.startedAt.map({ $0 <= record.endedAt }) ?? true else { throw ArchiveFailure.invalid("训练记录名称或时间不合法。") }
            let value = record.make(); let exercises = try value.exercises(); let counts = try value.completed()
            for exercise in exercises { try exercise.validate() }
            guard exercises.count == counts.count, zip(exercises, counts).allSatisfy({ (0...$0.0.sets).contains($0.1) }) else { throw ArchiveFailure.invalid("训练记录组数不一致。") }
            _ = try value.performances()
            if let data = record.performedNamesData {
                let names = try JSONDecoder().decode([[String]].self, from: data)
                guard names.count == counts.count, zip(names, counts).allSatisfy({ $0.0.count == $0.1 }) else { throw ArchiveFailure.invalid("训练记录实际动作不完整。") }
            }
        }
    }
    struct Result { let programs: Int; let days: Int; let records: Int; let skipped: Int }
    /// Merge missing IDs only. Existing local plans/records win; restore never erases history.
    @MainActor func merge(into context: ModelContext, preferences local: LibraryPreferences, restorePreferences: Bool,
                          beforeCommit: () throws -> Void = {}) throws -> Result {
        try validate()
        guard local.modelContext === context else { throw ArchiveFailure.invalid("恢复设置的存储上下文不一致，请重新打开页面。") }
        guard !context.hasChanges else { throw ArchiveFailure.invalid("请先保存已有编辑，再恢复备份。") }
        guard try context.fetch(FetchDescriptor<ActiveTraining>()).isEmpty else { throw ArchiveFailure.invalid("请先结束或恢复当前训练，再恢复备份。") }
        let programIDs = Set(try context.fetch(FetchDescriptor<TrainingProgram>()).map(\.id))
        let dayIDs = Set(try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id))
        let recordIDs = Set(try context.fetch(FetchDescriptor<TrainingRecord>()).map(\.id))
        let newPrograms = programs.filter { !programIDs.contains($0.id) }
        let newDays = days.filter { !dayIDs.contains($0.id) }
        let newRecords = records.filter { !recordIDs.contains($0.id) }
        let old = Preferences(local)
        do {
            for item in newPrograms { context.insert(TrainingProgram(id: item.id, name: item.name, position: item.position, weeklySessions: item.weeklySessions)) }
            for item in newDays {
                let day = try TrainingPlan(name: item.name, position: item.position)
                day.id = item.id; day.programID = item.programID; day.exerciseData = item.exerciseData; context.insert(day)
            }
            for item in newRecords { context.insert(item.make()) }
            if restorePreferences { preferences.apply(to: local) }
            try beforeCommit(); try context.save()
        } catch {
            old.apply(to: local); context.discardPendingChanges()
            throw error
        }
        return Result(programs: newPrograms.count, days: newDays.count, records: newRecords.count,
                      skipped: programs.count + days.count + records.count - newPrograms.count - newDays.count - newRecords.count)
    }
}
