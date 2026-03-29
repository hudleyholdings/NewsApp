import SwiftUI

struct FaviconView: View {
    let url: URL?
    let fallbackText: String

    var body: some View {
        if let url = url, let host = url.host {
            let iconURL = FaviconService.url(for: host)
            AsyncImage(url: iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                IconAvatar(text: String(fallbackText.prefix(1)))
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            IconAvatar(text: String(fallbackText.prefix(1)))
        }
    }
}

enum FaviconService {
    static func url(for host: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "64"),
            URLQueryItem(name: "domain", value: host)
        ]
        return components?.url
    }
}
