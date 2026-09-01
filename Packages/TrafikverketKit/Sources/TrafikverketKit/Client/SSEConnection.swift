import Foundation

/// A single Server-Sent Event.
public struct SSEEvent: Sendable, Hashable {
    public var id: String?
    public var event: String?
    public var data: String
}

/// Minimal SSE reader built on `URLSession.bytes`.
public struct SSEConnection: Sendable {
    public let url: URL
    let session: URLSession
    let userAgent: String

    public init(url: URL, session: URLSession = .shared, userAgent: String = "Tagkollen") {
        self.url = url
        self.session = session
        self.userAgent = userAgent
    }

    public func events() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 60 * 60 * 24

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                        throw TrafikverketError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    var id: String?
                    var event: String?
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                continuation.yield(SSEEvent(id: id, event: event, data: dataLines.joined(separator: "\n")))
                            }
                            event = nil
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }
                        if line.hasPrefix(":") {
                            continue
                        } // comment / keep-alive
                        let (field, value) = Self.split(line)
                        switch field {
                        case "data": dataLines.append(value)
                        case "event": event = value
                        case "id": id = value
                        default: break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[..<colon])
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") {
            value = value.dropFirst()
        }
        return (field, String(value))
    }
}
