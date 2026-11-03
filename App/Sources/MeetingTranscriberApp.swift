import SwiftUI
import SwiftData

@main
struct MeetingTranscriberApp: App {
    @State private var recorder = AudioRecorder()
    @State private var processor = RecordingProcessor()
    private let container: ModelContainer

    init() {
        do {
            // Local store only for now. Switching to `.automatic` (CloudKit private
            // database) enables iCloud sync once the app is signed with a paid developer team.
            let config = ModelConfiguration(cloudKitDatabase: .none)
            container = try ModelContainer(for: Recording.self, configurations: config)
        } catch {
            fatalError("Could not open the recordings database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
                .environment(processor)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1000, height: 680)
        #endif
    }
}
