import SwiftUI

struct AddLinkView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var manager: DownloadManager
    @State private var urlString = ""
    
    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "233937"))
                    .frame(width: 36, height: 4)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                
                HStack {
                    Text("Add a video link")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textHi)
                    Spacer()
                }
                .padding(.bottom, 16)
                
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(Theme.textLow)
                    TextField("paste.link/video-url-here", text: $urlString)
                        .foregroundColor(Theme.textHi)
                        .tint(Theme.aqua)
                }
                .padding(14)
                .background(Theme.surface2)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                .padding(.bottom, 14)
                
                Button(action: {
                    if !urlString.isEmpty {
                        manager.addDownload(url: urlString)
                        dismiss()
                    }
                }) {
                    Text("Start download")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "00110E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.aqua)
                        .cornerRadius(14)
                }
                
                Button(action: {
                    if let clipboard = UIPasteboard.general.string {
                        urlString = clipboard
                    }
                }) {
                    Text("Paste from clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textMid)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                }
                .padding(.top, 10)
                
                Spacer()
            }
            .padding(.horizontal, 22)
        }
    }
}
