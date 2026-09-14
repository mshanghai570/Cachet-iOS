import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("useBrowserTool") private var useBrowserTool = true
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("simultaneousDownloads") private var simultaneousDownloads = 3
    @AppStorage("compatibilityLayer") private var compatibilityLayer = true
    @AppStorage("macMode") private var macMode = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        Group {
                            SectionHeader(title: "General")
                            SettingsGroup {
                                SettingsRow(icon: "play.tv", title: "Download quality", value: "Best available ›")
                                SettingsRow(icon: "folder", title: "Save location", value: "On My iPhone ›")
                                SettingsToggleRow(icon: "safari", title: "Browser tool for hard links", isOn: $useBrowserTool)
                            }
                        }
                        
                        Group {
                            SectionHeader(title: "Downloads")
                            SettingsGroup {
                                SettingsRow(icon: "arrow.down.circle", title: "Simultaneous downloads", value: "\(simultaneousDownloads) ›")
                                SettingsToggleRow(icon: "wifi", title: "Wi-Fi only", isOn: $wifiOnly)
                                SettingsToggleRow(icon: "cpu", title: "Compatibility Layer", isOn: $compatibilityLayer)
                                SettingsToggleRow(icon: "macbook", title: "Mac Mode (Desktop Agent)", isOn: $macMode)
                            }
                        }
                        
                        Group {
                            SectionHeader(title: "About")
                            SettingsGroup {
                                SettingsRow(title: "Version", value: "1.0.0")
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.aqua)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        VStack(spacing: 0) { content }
        .background(Theme.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }
}

struct SettingsRow: View {
    var icon: String? = nil
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.aquaDeep).frame(width: 30, height: 30)
                    Image(systemName: icon).foregroundColor(Theme.aqua).font(.system(size: 14))
                }
            }
            Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textHi)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundColor(Theme.textLow)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).background(Theme.surface)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.aquaDeep).frame(width: 30, height: 30)
                Image(systemName: icon).foregroundColor(Theme.aqua).font(.system(size: 14))
            }
            Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.textHi)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.aqua)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).background(Theme.surface)
    }
}
