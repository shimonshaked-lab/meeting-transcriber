import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Keys.trimSilence) private var trimSilence = true
    @AppStorage(AppSettings.Keys.minSilence) private var minSilence = 2.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Remove silent periods after recording", isOn: $trimSilence)
                    if trimSilence {
                        Stepper(value: $minSilence, in: 1...6, step: 0.5) {
                            LabeledContent("Remove pauses longer than", value: "\(minSilence.formatted(.number.precision(.fractionLength(1)))) s")
                        }
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Shorter pauses are kept, and 0.3 s is kept on each side of every cut so words are never clipped. Only the trimmed file is saved.")
                }

                Section("Privacy") {
                    Label("Recordings are stored only in this app's private, encrypted storage.", systemImage: "lock.shield")
                    Label("No analytics, tracking or telemetry of any kind.", systemImage: "eye.slash")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}
