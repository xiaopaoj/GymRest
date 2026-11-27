import SwiftUI

/// Show only the alternatives configured for this exercise; selection still uses
/// the controller's guarded transition and never copies another exercise's load.
struct TrainingAlternativesView: View {
    let exercise: ExerciseSpec
    let catalog: ExerciseCatalog?
    let select: @MainActor (UUID?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var failure = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("以下为计划中配置的替代动作。查看肌群与器材后选择；替换后请核对重量，器械标重不一定等价。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("原动作") { choice(exercise, id: nil) }
                Section("计划中的替代选择") {
                    ForEach(exercise.alternatives) { alternative in
                        choice(ExerciseSpec(name: alternative.name, sets: exercise.sets, restSeconds: alternative.restSeconds,
                            catalogID: alternative.catalogID, prescription: alternative.prescription), id: alternative.id)
                    }
                }
                if failure { Text("未能切换，请关闭后重新查看当前训练状态。原有完成记录保留。").foregroundStyle(.red) }
            }
            .navigationTitle("选择替代动作").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() }.disabled(saving) }
            .disabled(saving).interactiveDismissDisabled(saving)
        }
    }
    private func choice(_ spec: ExerciseSpec, id: UUID?) -> some View {
        Button {
            saving = true
            Task {
                let success = await select(id)
                saving = false
                if success { dismiss() } else { failure = true }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let item = catalog?.resolve(spec) { CatalogExerciseRow(item: item) }
                else { Text(spec.name).font(.headline) }
                Text("组间休息 \(spec.restSeconds) 秒").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
