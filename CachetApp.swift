import SwiftUI

@main
struct CachetApp: App {
    @StateObject private var downloadManager = DownloadManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .preferredColorScheme(.dark)
        }
    }
}
