import SwiftUI
import SwiftData
import MTCore

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AudioRecorder.self) private var recorder
    @Environment(RecordingProcessor.self) private var processor

    @State private var selection: PersistentIdentifier?
    @State private var searchText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection, searchText: searchText, errorMessage: $errorMessage)
                .searchable(text: $searchText, prompt: "Search recordings")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    RecorderPanel(onRecord: { Task { await startRecording() } }, onStop: stopRecording)
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                #endif
        } detail: {
            if let selection, let recording: Recording = context.registeredModel(for: selection) {
                RecordingDetailView(recording: recording)
                    .id(selection)
            } else {
                ContentUnavailableView("No Recording Selected", systemImage: "waveform",
                                       description: Text("Record a meeting or import audio from Files or Voice Memos."))
            }
        }
        .onOpenURL { url in
            Task {
                let errors = await ImportService.importFiles([url], channel: .openIn, context: context)
                if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
            }
        }
        .task {
            await processor.recoverInterrupted(context: context, excluding: recorder.activeRecordingID)
        }
        .onChange(of: recorder.lastError) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil; recorder.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startRecording() async {
        let recording = Recording(name: Recording.defaultName(for: .now), source: .inApp, status: .recording)
        let rawURL = AudioStorage.rawURL(for: recording.id)
        recording.fileName = rawURL.lastPathComponent
        // Appears in the list immediately, with a live duration.
        context.insert(recording)
        try? context.save()
        do {
            try await recorder.start(id: recording.id, url: rawURL)
        } catch {
            context.delete(recording)
            try? context.save()
            try? FileManager.default.removeItem(at: rawURL)
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard let result = recorder.stop() else { return }
        let id = result.id
        let rawURL = result.rawURL
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
        guard let recording = try? context.fetch(descriptor).first else { return }
        Task { await processor.finalize(recording, rawURL: rawURL, context: context) }
    }
}
