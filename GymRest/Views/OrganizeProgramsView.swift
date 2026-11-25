import SwiftUI
import SwiftData

struct OrganizeProgramsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainingProgram.position) private var programs: [TrainingProgram]
    @Query(sort: \TrainingPlan.position) private var days: [TrainingPlan]
    var initialProgramID: UUID? = nil
    @State private var targetID: UUID?
    @State private var name = "五分化"
    @State private var selection: Set<UUID> = []
    @State private var convertBlank = true
    @State private var error: String?
    @State private var initialized = false
    private var matchingBlank: TrainingPlan? {
        guard targetID == nil, convertBlank else { return nil }
        let candidates = days.filter {
            $0.programID == nil && $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !selection.contains($0.id) && (try? $0.exercises().isEmpty) == true
        }
        return candidates.count == 1 ? candidates.first : nil
    }
    var body: some View {
        Form {
            Section("上层训练计划") {
                Picker("归入计划", selection: $targetID) {
                    Text("新建计划").tag(UUID?.none)
                    ForEach(programs) { program in Text(program.name).tag(Optional(program.id)) }
                }
                if targetID == nil {
                    TextField("例如：五分化", text: $name)
                    Toggle("将同名空白项目转为计划", isOn: $convertBlank)
                    if let blank = matchingBlank {
                        Text("会将旧版空白项目“\(blank.name)”转为上层计划，所选训练日归到它下面。其他空白项目保留。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("选择要归入的训练日 · 已选 \(selection.count)") {
                ForEach(days) { day in
                    if day.id != matchingBlank?.id {
                        Button {
                            if selection.contains(day.id) { selection.remove(day.id) } else { selection.insert(day.id) }
                        } label: {
                            HStack {
                                Image(systemName: selection.contains(day.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.orange)
                                DayRow(day: day, index: nil)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Text("只修改所选项目的归属，不复制训练、不删除动作，进行中的训练和历史保持不变。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("整理训练计划").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
        }
        .onAppear {
            guard !initialized else { return }; initialized = true; targetID = initialProgramID
            selection = Set(days.filter { $0.programID == nil && (try? $0.exercises().isEmpty) == false }.map(\.id))
        }
    }
    private func save() {
        do {
            try ProgramLibrary.organize(name: name, days: days.filter { selection.contains($0.id) },
                existing: programs.first(where: { $0.id == targetID }), convertBlank: matchingBlank, context: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
