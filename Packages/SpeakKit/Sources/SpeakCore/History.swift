import Foundation

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// Transcript before polishing.
    public var raw: String
    /// What was actually inserted.
    public var text: String
    public var appName: String?

    public init(id: UUID = UUID(), date: Date = .now, raw: String, text: String, appName: String?) {
        self.id = id
        self.date = date
        self.raw = raw
        self.text = text
        self.appName = appName
    }
}

/// Recent dictations, newest first, persisted as a small JSON file. Text only — audio is never kept.
public struct History: Sendable {
    public private(set) var items: [HistoryItem]
    public let limit: Int
    private let fileURL: URL?

    public init(fileURL: URL?, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = limit
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = Array(decoded.prefix(limit))
        } else {
            items = []
        }
    }

    public mutating func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    public mutating func clear() {
        items = []
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            // History is a convenience; losing it is not worth interrupting dictation.
        }
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Speak/history.json")
    }
}
