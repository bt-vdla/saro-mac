import Foundation
import SQLite3

public enum SQLValue: Sendable, Hashable {
    case null, int(Int64), real(Double), text(String)

    public var string: String? { if case .text(let s) = self { s } else { nil } }
    public var int: Int? {
        switch self {
        case .int(let i): Int(i)
        case .real(let d): Int(d)
        default: nil
        }
    }
    public var double: Double? {
        switch self {
        case .real(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
    public var json: Any {
        switch self {
        case .null: NSNull()
        case .int(let i): i
        case .real(let d): d
        case .text(let s): s
        }
    }
}

public typealias Row = [String: SQLValue]

extension Row {
    func str(_ k: String) -> String? { self[k]?.string }
    func int(_ k: String) -> Int? { self[k]?.int }
    func dbl(_ k: String) -> Double? { self[k]?.double }
    func date(_ k: String) -> Date? { str(k).flatMap { Date(iso: $0) } }
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let description: String
}

/// ponytail: a minimal wrapper (open, run, transaction). Only `Ledger` owns one, so all access is serialised by that actor.
final class SQLite {
    private let db: OpaquePointer
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            throw SQLiteError(description: "Could not open \(path)")
        }
        db = handle
        sqlite3_busy_timeout(db, 2000)
    }

    deinit { sqlite3_close_v2(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError(description: message)
        }
    }

    @discardableResult
    func run(_ sql: String, _ args: [SQLValue] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw lastError(sql) }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            // An explicit length, so text holding a NUL isn't cut there.
            case .text(let v): sqlite3_bind_text(stmt, idx, v, Int32(v.utf8.count), Self.transient)
            }
        }
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError(sql) }
            var row: Row = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(stmt, c))
                case SQLITE_TEXT:
                    let bytes = UnsafeRawBufferPointer(start: sqlite3_column_text(stmt, c), count: Int(sqlite3_column_bytes(stmt, c)))
                    row[name] = .text(String(decoding: bytes, as: UTF8.self))
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func lastError(_ sql: String) -> SQLiteError {
        SQLiteError(description: "\(String(cString: sqlite3_errmsg(db))) in: \(sql.prefix(120))")
    }
}
