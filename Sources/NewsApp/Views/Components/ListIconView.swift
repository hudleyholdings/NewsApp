import SwiftUI
import AppKit

struct ListIconView: View {
    let name: String
    let iconSystemName: String?
    let iconURL: URL?

    var body: some View {
        if let iconURL = iconURL, iconURL.isFileURL, let image = NSImage(contentsOf: iconURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else if let iconURL = iconURL {
            AsyncImage(url: iconURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                IconAvatar(text: String(name.prefix(1)))
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else if let iconSystemName = iconSystemName, !iconSystemName.isEmpty {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: iconSystemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            IconAvatar(text: String(name.prefix(1)))
        }
    }
}
