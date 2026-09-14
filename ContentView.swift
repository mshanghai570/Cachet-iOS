import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: DownloadManager
    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingBrowser = false
    @State private var shareItem: DownloadItem?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(downloading: manager.downloads.filter { $0.status == .downloading || $0.status == .extracting }.count,
                           queued: manager.downloads.filter { $0.status == .queued }.count,
                           saved: manager.downloads.filter { $0.status == .done }.count)

                SegmentedControl(selectedTab: $selectedTab)

                if manager.downloads.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if selectedTab == 0 || selectedTab == 2 {
                                let active = manager.downloads.filter { $0.status == .queued || $0.status == .extracting || $0.status == .downloading || $0.status == .failed }
                                if !active.isEmpty {
                                    SectionHeader(title: "Active")
                                    ForEach(active) { item in
                                        DownloadRow(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { shareItem = (item.status == .done && item.fileURL != nil) ? item : nil }
                                            .contextMenu { rowContextMenu(for: item) }
                                    }
                                }
                            }

                            if selectedTab == 1 || selectedTab == 2 {
                                let finished = manager.downloads.filter { $0.status == .done }
                                if !finished.isEmpty {
                                    SectionHeader(title: "Saved")
                                    ForEach(finished) { item in
                                        DownloadRow(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { shareItem = item }
                                            .contextMenu { rowContextMenu(for: item) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 140)
                    }
                }
            }

            VStack {
                Spacer()
                CustomToolbar(
                    onBrowser: { showingBrowser = true },
                    onAdd: { showingAddSheet = true },
                    onSettings: { showingSettings = true }
                )
            }
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLinkView().presentationDetents([.fraction(0.38)])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $shareItem) { item in
            if let url = item.fileURL {
                ActivityView(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showingBrowser) {
            BrowserView()
                .environmentObject(manager)
        }
    }

    @ViewBuilder
    private func rowContextMenu(for item: DownloadItem) -> some View {
        if item.status == .done, let _ = item.fileURL {
            Button("Share") { shareItem = item }
        }
        Button(role: .destructive, action: { manager.delete(item) }) {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Theme.aquaDeep.opacity(0.35)).frame(width: 96, height: 96)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44)).foregroundColor(Theme.aqua)
            }
            Text("No downloads yet")
                .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.textHi)
            Text("Tap + and paste a video link. Cachet will find\nthe stream and save it right to the Files app.")
                .font(.system(size: 13)).foregroundColor(Theme.textLow)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct BrowserSheetView: View {
    @Binding var isPresented: Bool
    let manager: DownloadManager
    @State private var address = ""

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("Browser Tool")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.textHi)
                    Spacer()
                    Button("Close") { isPresented = false }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.aqua)
                }
                .padding(.top, 18)

                HStack {
                    Image(systemName: "safari").foregroundColor(Theme.textLow)
                    TextField("Paste a video page URL", text: $address)
                        .foregroundColor(Theme.textHi)
                        .tint(Theme.aqua)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(14)
                .background(Theme.surface2)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))

                Button(action: {
                    manager.addDownload(url: address)
                    isPresented = false
                }) {
                    Text("Find & Download Video")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "00110E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.aqua)
                        .cornerRadius(14)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
        }
    }
}

struct HeaderView: View {
    let downloading: Int
    let queued: Int
    let saved: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("Cach").font(.system(size: 30, weight: .bold)).foregroundColor(Theme.textHi)
                    Text("é").font(.system(size: 30, weight: .bold)).foregroundColor(Theme.aqua)
                    Text("t").font(.system(size: 30, weight: .bold)).foregroundColor(Theme.textHi)
                }
                Text("\(downloading) downloading · \(queued) queued · \(saved) saved")
                    .font(.system(size: 13)).foregroundColor(Theme.textLow)
            }
            Spacer()
        }
        .padding(.horizontal, 22).padding(.bottom, 18).padding(.top, 10)
    }
}

struct SegmentedControl: View {
    @Binding var selectedTab: Int
    let tabs = ["Active", "Completed", "All"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    Text(tabs[index])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedTab == index ? Theme.aqua : Theme.textLow)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(selectedTab == index ? Theme.aquaDeep : Color.clear)
                        .cornerRadius(9)
                }
            }
        }
        .padding(3).background(Theme.surface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 22).padding(.bottom, 16)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).kerning(0.6).foregroundColor(Theme.textLow)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 8)
    }
}

struct DownloadRow: View {
    let item: DownloadItem

    private var icon: String {
        switch item.status {
        case .done: return "checkmark"
        case .queued: return "clock"
        case .extracting: return "magnifyingglass"
        case .failed: return "exclamationmark.triangle"
        default: return "arrow.down"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .done: return Theme.aquaDim
        case .extracting, .downloading: return Theme.aqua
        case .failed: return Color(hex: "FF7A59")
        default: return Theme.textLow
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: item.status == .done ? [Color(hex: "0b1a18"), Color(hex: "04100e")] : [Color(hex: "0d1f1d"), Color(hex: "051212")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))

                Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 20, weight: .medium))
            }
            .opacity(item.status == .queued ? 0.5 : 1.0)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(item.status == .queued ? Theme.textMid : Theme.textHi)
                    .lineLimit(1)
                Text(subtitle).font(.system(size: 12))
                    .foregroundColor(item.status == .failed ? Color(hex: "FF7A59") : Theme.textLow)
                    .lineLimit(item.status == .failed ? 2 : 1)

                if item.status == .downloading || item.status == .extracting {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "14201f")).frame(height: 4)
                            RoundedRectangle(cornerRadius: 2).fill(Theme.aqua).frame(width: geo.size.width * CGFloat(item.progress), height: 4)
                        }
                    }
                    .frame(height: 4).padding(.top, 4)

                    HStack {
                        Text("\(Int(item.progress * 100))%")
                        Spacer()
                        Text(item.speedString)
                    }
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textMid).padding(.top, 2)
                }
            }
        }
        .padding(12).background(Theme.surface).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }

    private var subtitle: String {
        switch item.status {
        case .done: return item.sizeString.isEmpty ? "Tap to share" : "\(item.sizeString) · tap to share"
        case .failed: return item.errorMessage ?? "Download failed"
        case .queued: return "Queued · \(item.urlString)"
        default: return item.sizeString.isEmpty ? item.urlString : item.sizeString
        }
    }
}

struct CustomToolbar: View {
    let onBrowser: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            Button(action: onBrowser) {
                VStack(spacing: 6) {
                    Image(systemName: "safari").font(.system(size: 20)).foregroundColor(Theme.textMid)
                        .frame(width: 52, height: 52).background(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.border, lineWidth: 1)).cornerRadius(26)
                    Text("Browser Tool").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.textLow)
                }
            }

            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 24, weight: .medium)).foregroundColor(Color(hex: "00110E"))
                    .frame(width: 64, height: 64).background(Theme.aqua).cornerRadius(32)
                    .shadow(color: Theme.aqua.opacity(0.25), radius: 12, y: 8)
                    .overlay(RoundedRectangle(cornerRadius: 32).stroke(Theme.aquaDeep, lineWidth: 6))
            }
            .offset(y: -10)

            Button(action: onSettings) {
                VStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 20)).foregroundColor(Theme.textMid)
                        .frame(width: 52, height: 52).background(Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.border, lineWidth: 1)).cornerRadius(26)
                    Text("Settings").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.textLow)
                }
            }
        }
        .padding(.top, 14).padding(.bottom, 36).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
