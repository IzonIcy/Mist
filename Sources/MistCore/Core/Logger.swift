import Foundation

/// Severity of a log message.
///
/// Four coarse buckets. If a message doesn't fit one, it isn't worth logging.
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short label used in the emitted line.
    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

/// A destination that accepts fully rendered log lines.
///
/// `Logger` is decoupled from *where* output goes so the sink can be swapped for
/// a file, a socket, or a test spy without touching callers.
public protocol LogSink: AnyObject {
    /// Writes one pre-rendered log line (the logger appends the newline).
    func write(line: String)
}

/// Writes log lines to standard error.
///
/// `stderr` is the correct default for diagnostics: app UI and tools often
/// consume stdout, and diagnostics belong on the error channel.
public final class StandardErrorSink: LogSink {
    private let file: UnsafeMutablePointer<FILE>

    public init(file: UnsafeMutablePointer<FILE> = stderr) {
        self.file = file
    }

    public func write(line: String) {
        fputs(line, file)
    }
}

/// A sink that captures every line in memory. Used by tests and by the UI log
/// pane so users can inspect diagnostics without touching a terminal.
public final class MemorySink: LogSink {
    private let lock = NSLock()
    private var lines: [String] = []

    public init() {}

    public func write(line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    /// Copy of every captured line, oldest first.
    public var capturedLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// Structured, thread-safe logger for the whole app.
///
/// Every public log call renders exactly one line, always prefixed with the
/// level label. There is intentionally no "random console output": diagnostics
/// pass through here, and the sink is injectable so tests can capture output
/// instead of spewing into a test runner log.
public final class Logger: @unchecked Sendable {
    /// The configured minimum level. Messages below this are dropped at the
    /// source, keeping hot paths cheap.
    public var minimumLevel: LogLevel {
        get { lock.withLock { _minimumLevel } }
        set { lock.withLock { self._minimumLevel = newValue } }
    }

    private let sink: LogSink
    private let lock = NSLock()

    /// Backing for `minimumLevel`.
    private var _minimumLevel: LogLevel

    /// Creates a logger that forwards rendered lines to `sink`.
    public init(minimumLevel: LogLevel = .info, sink: LogSink = StandardErrorSink()) {
        self._minimumLevel = minimumLevel
        self.sink = sink
    }

    /// A process-wide default logger. Most production code constructs its own,
    /// but this gives ad-hoc code a well-behaved instance without global state.
    public static let shared = Logger()

    public func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    public func info(_ message: String) {
        log(.info, message)
    }

    public func warning(_ message: String) {
        log(.warning, message)
    }

    public func error(_ message: String) {
        log(.error, message)
    }

    /// Logs an error together with the layer that produced it, so the line says
    /// both *where* and *why*.
    public func error(_ message: String, error: any Error) {
        log(.error, "\(message): \(String(describing: error))")
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else { return }
        let line = "\(self.timestamp)\t\(level.label)\t\(message)\n"
        sink.write(line: line)
    }

    /// Renders the current wall-clock time as `yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX`.
    ///
    /// A fresh `ISO8601DateFormatter` is created per call. Logging is not a hot
    /// path, and this avoids both Apple's "DateFormatter is not thread-safe"
    /// caveat and a shared static global.
    private var timestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

// Small, invisible helper so the property above can read the lock without
// exposing NSLock in the public surface.
private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}