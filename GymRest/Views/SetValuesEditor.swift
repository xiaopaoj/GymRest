import SwiftUI

struct SetValuesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var values: SetValues
    var title = "本组重量与次数"
    let save: @MainActor (SetValues) async throws -> Void
    @State private var weight = ""
    @State private var repetitions = ""
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
                Section("次数（可选）") {
                    TextField("实际次数或预设次数", text: $repetitions).keyboardType(.numberPad)
                    Text("留空表示未记录，不会当作0次；完成本组时才保存为本组记录。")
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
                                if repetitions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { candidate.repetitions = nil }
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
