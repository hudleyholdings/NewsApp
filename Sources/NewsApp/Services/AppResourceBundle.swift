import Foundation

extension Bundle {
    static let module: Bundle = {
        let fileManager = FileManager.default
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceResourcesURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let cwdResourcesURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Sources/NewsApp/Resources")

        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            sourceResourcesURL,
            cwdResourcesURL
        ].compactMap { $0 }

        for url in candidates where fileManager.fileExists(atPath: url.appendingPathComponent("feeds_seed.json").path) {
            return Bundle(path: url.path) ?? .main
        }

        return .main
    }()
}
