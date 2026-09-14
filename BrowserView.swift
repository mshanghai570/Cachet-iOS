import SwiftUI
import WebKit

struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: DownloadManager
    @AppStorage("browserAdBlockingEnabled") private var adBlockingEnabled = true
    @StateObject private var coordinator = BrowserCoordinator()
    @State private var address = "https://duckduckgo.com/"
    @State private var showingDownloads = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Search or enter website", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { coordinator.load(address) }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.surface2, in: Capsule())
                    Button { coordinator.load(address) } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Go")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                BrowserWebView(webView: coordinator.webView)
                    .overlay(alignment: .top) {
                        if coordinator.isLoading { ProgressView().tint(Theme.aqua) }
                    }

                HStack(spacing: 20) {
                    Button { coordinator.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!coordinator.canGoBack).accessibilityLabel("Back")
                    Button { coordinator.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!coordinator.canGoForward).accessibilityLabel("Forward")
                    Button { coordinator.reloadOrStop() } label: { Image(systemName: coordinator.isLoading ? "xmark" : "arrow.clockwise") }
                        .accessibilityLabel(coordinator.isLoading ? "Stop loading" : "Reload")
                    Spacer()
                    Toggle(isOn: $adBlockingEnabled) { Image(systemName: "hand.raised.fill") }
                        .labelsHidden().accessibilityLabel("Block ads")
                        .onChange(of: adBlockingEnabled) { enabled in coordinator.setAdBlocking(enabled: enabled) }
                    Button { showingDownloads = true } label: {
                        Label(coordinator.candidates.isEmpty ? "Download" : "Download \(coordinator.candidates.count)", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(coordinator.candidates.isEmpty)
                }
                .font(.title3)
                .padding(12)
                .foregroundStyle(Theme.aqua)
            }
            .navigationTitle(coordinator.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                coordinator.setAdBlocking(enabled: adBlockingEnabled)
                address = coordinator.address
            }
            .sheet(isPresented: $showingDownloads) {
                StreamPickerView(candidates: coordinator.candidates) { candidate in
                    Task {
                        manager.enqueue(await coordinator.downloadRequest(for: candidate))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StreamPickerView: View {
    let candidates: [MediaCandidate]
    let select: (MediaCandidate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let best = candidates.first {
                    Section("Recommended") {
                        Button { select(best) } label: {
                            Label("Best available · \(best.label)", systemImage: "star.fill")
                        }
                    }
                }
                Section("Detected streams") {
                    ForEach(candidates) { candidate in
                        Button { select(candidate) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(candidate.label)
                                    Text(candidate.source).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Download video")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
