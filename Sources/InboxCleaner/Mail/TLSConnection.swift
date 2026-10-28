import Foundation
import Network

enum MailError: LocalizedError {
    case connect(String)
    case auth(String)
    case server(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .connect(let m): return "Connection problem: \(m)"
        case .auth(let m): return "Sign-in failed: \(m)"
        case .server(let m): return "Mail server said: \(m)"
        case .timeout: return "The mail server took too long to respond."
        }
    }
}

/// A small blocking TLS socket. Callers run it off the main thread.
final class TLSConnection {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "inboxcleaner.tls")
    private var buffer = Data()
    private let timeout: TimeInterval

    init(host: String, port: UInt16, timeout: TimeInterval = 45) throws {
        self.timeout = timeout
        guard let p = NWEndpoint.Port(rawValue: port) else { throw MailError.connect("Bad port \(port)") }
        conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tls)

        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        var signalled = false
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !signalled { signalled = true; sem.signal() }
            case .failed(let e), .waiting(let e):
                if !signalled { failure = e; signalled = true; sem.signal() }
            default:
                break
            }
        }
        conn.start(queue: queue)
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            conn.cancel()
            throw MailError.connect("Timed out reaching \(host)")
        }
        if let failure {
            conn.cancel()
            throw MailError.connect("\(host): \(failure.localizedDescription)")
        }
    }

    deinit { conn.cancel() }

    func close() { conn.cancel() }

    private func fill() throws {
        let sem = DispatchSemaphore(value: 0)
        var chunk: Data?
        var err: Error?
        var complete = false
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            chunk = data
            err = error
            complete = isComplete
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut { throw MailError.timeout }
        if let err { throw MailError.connect(err.localizedDescription) }
        if let chunk, !chunk.isEmpty {
            buffer.append(chunk)
        } else if complete {
            throw MailError.connect("The server closed the connection.")
        }
    }

    /// Reads up to CRLF and returns the line without it.
    func readLine() throws -> String {
        let crlf = Data([13, 10])
        while true {
            if let r = buffer.range(of: crlf) {
                let lineData = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
                buffer = buffer.subdata(in: r.upperBound..<buffer.endIndex)
                return String(data: lineData, encoding: .utf8) ?? String(decoding: lineData, as: UTF8.self)
            }
            try fill()
        }
    }

    func readBytes(_ count: Int) throws -> Data {
        while buffer.count < count { try fill() }
        let out = buffer.subdata(in: buffer.startIndex..<(buffer.startIndex + count))
        buffer = buffer.subdata(in: (buffer.startIndex + count)..<buffer.endIndex)
        return out
    }

    func write(_ string: String) throws {
        try write(Data(string.utf8))
    }

    func write(_ data: Data) throws {
        let sem = DispatchSemaphore(value: 0)
        var err: Error?
        conn.send(content: data, completion: .contentProcessed { e in
            err = e
            sem.signal()
        })
        if sem.wait(timeout: .now() + timeout) == .timedOut { throw MailError.timeout }
        if let err { throw MailError.connect(err.localizedDescription) }
    }
}
