import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MTCore

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AudioRecorder.self) private var recorder
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @Binding var selection: PersistentIdentifier?
    let searchText: String
    @Binding var errorMessage: String?

    @State private var renaming: Recording?
    @State private var renameText = ""
    @State private var showImporter = false
    @State private var showSettings = false

    private var filtered: [Recording] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recordings }
        return recordings.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { recording in
                RecordingRow(recording: recording,
                             liveElapsed: recorder.activeRecordingID == recording.id ? recorder.elapsed : nil)
                    .tag(recording.persistentModelID)
                    .contextMenu { menuItems(for: recording) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(recording) } label: { Label("Delete", systemImage: "trash") }
                        Button { beginRename(recording) } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.blue)
                    }
            }
        }
        .overlay {
            if recordings.isEmpty {
                ContentUnavailableView("No Recordings", systemImage: "mic",
                                       description: Text("Tap the record button to start, or import audio."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Recordings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImporter = true } label: { Label("Import Audio", systemImage: "square.and.arrow.down") }
            }
            ToolbarItem(placement: .automatic) {
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): runImport(urls, channel: .filePicker)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            runImport(files, channel: .dragAndDrop)
            return true
        }
        .alert("Rename Recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private func menuItems(for recording: Recording) -> some View {
        Button { beginRename(recording) } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { delete(recording) } label: { Label("Delete", systemImage: "trash") }
            .disabled(recorder.activeRecordingID == recording.id)
    }

    private func runImport(_ urls: [URL], channel: ImportChannel) {
        Task {
            let errors = await ImportService.importFiles(urls, channel: channel, context: context)
            if !errors.isEmpty { errorMessage = "Some files could not be imported:\n" + errors.joined(separator: "\n") }
        }
    }

    private func beginRename(_ recording: Recording) {
        renameText = recording.name
        renaming = recording
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let renaming, !name.isEmpty {
            renaming.name = name
            try? context.save()
        }
        renaming = nil
    }

    private func delete(_ recording: Recording) {
        guard recorder.activeRecordingID != recording.id else {
            errorMessage = "Stop the recording before deleting it."
            return
        }
        if selection == recording.persistentModelID { selection = nil }
        AudioStorage.removeFiles(for: recording)
        context.delete(recording)
        try? context.save()
    }
}
