import SwiftUI

struct SetValuesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var values: SetValues
    var title = "本组训练设置"
    let save: @MainActor (SetValues) async throws -> Void
    @State private var weight = ""
    @State private var repetitions = ""
    @State private var duration = ""
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("负重设置") {
                    Picker("记录口径", selection: $values.kind) {
                        ForEach(LoadKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if values.kind != .bodyweight {
                        Picker("单位", selection: $values.unit) {
                            ForEach(LoadUnit.allCases.filter { $0 != .level || values.kind == .machine }, id: \.self) { Text($0.title).tag($0) }
                        }
                        TextField("重量（可留空）", text: $weight).keyboardType(.decimalPad)
                    }
                    TextField("器械备注，例如健身房A的划船机", text: $values.equipmentNote)
                    Text("杠铃记总重，哑铃可记单只重量；器械按面板标重或档位记录。辅助重量与额外负重分别记录。不同器械的标重不等价，请分别填写器械备注，便于下次区分。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("计时与两侧") {
                    Toggle("按时长训练", isOn: Binding(get: { values.durationSeconds != nil }, set: { enabled in
                        values.durationSeconds = enabled ? 40 : nil
                        if enabled { values.repetitions = nil; repetitions = ""; duration = "40" }
                    }))
                    if values.durationSeconds != nil {
                        TextField(values.sideCount == 2 ? "每侧目标秒数" : "每组目标秒数", text: $duration).keyboardType(.numberPad)
                        Text("计时需手动开始；到时系统提醒，确认完成后才计入进度。此处记录目标时长，不代表实际有效保持时长。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        TextField(values.sideCount == 2 ? "每侧次数（可留空）" : "次数（可留空）", text: $repetitions).keyboardType(.numberPad)
                    }
                    Picker("整组完成方式", selection: $values.sideCount) {
                        Text("一次完成一组").tag(1)
                        Text("两侧完成才算一组").tag(2)
                    }
                    Text("两侧模式先做第1侧，再换侧完成第2侧。第一侧不计整组、不进入组间休息；左右先后可自行决定。交替动作可选择一次完成，并自行安排两侧总次数。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { @MainActor in
                            saving = true; defer { saving = false }
                            do {
                                var candidate = values
                                if candidate.kind == .bodyweight { candidate.weight = nil }
                                else if weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { candidate.weight = nil }
                                else {
                                    guard let number = Double(weight.replacingOccurrences(of: ",", with: ".")) else { throw PerformanceError.invalid }
                                    candidate.weight = number
                                }
                                if candidate.durationSeconds != nil {
                                    guard let seconds = Int(duration), (1...86400).contains(seconds) else { throw TimerFailure.invalidDuration }
                                    candidate.durationSeconds = seconds; candidate.repetitions = nil
                                } else if repetitions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { candidate.repetitions = nil }
                                else {
                                    guard let count = Int(repetitions) else { throw PerformanceError.invalid }
                                    candidate.repetitions = count
                                }
                                try candidate.validate(); try await save(candidate); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(saving)
                }
            }
            .onAppear {
                weight = values.weight.map { String($0) } ?? ""
                repetitions = values.repetitions.map(String.init) ?? ""
                duration = values.durationSeconds.map(String.init) ?? ""
            }
            .onChange(of: values.kind) { _, kind in
                weight = ""
                if kind == .bodyweight { values.unit = .kg }
                if kind != .machine && values.unit == .level { values.unit = .kg }
            }
            .onChange(of: values.unit) { _, _ in
                // Never silently relabel a kilogram number as pounds or an arbitrary machine level.
                weight = ""
            }
        }
    }
}
