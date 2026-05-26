//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Cassandra Client open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Cassandra Client project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Cassandra Client project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import Synchronization

@_implementationOnly import CDataStaxDriver

/// Global configuration
@available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
public final class CassandraLogConfiguration: Sendable {
    private let logger: Logger

    private init(logger: Logger) {
        self.logger = logger
    }

    /// Static property retaining the `CassandraLogConfiguration` captured by the context to `cass_log_set_callback`.
    private static let shared = Mutex<CassandraLogConfiguration?>(nil)

    /// Configure a logger to which log messages from the underlying DataStaxx Cassandra driver should be logged.
    ///
    /// The logger is shared across all Cassandra clients in the process.
    ///
    /// - Important : This must be called before any calls that might log (see requirement in `cass_log_set_callback`).
    public static func setLogger(logger: Logger, level logLevel: Logger.Level) throws {
        shared.withLock { logContext in
            let cassLevel: CassLogLevel
            switch logLevel {
            case .trace: cassLevel = CASS_LOG_TRACE
            case .debug: cassLevel = CASS_LOG_DEBUG
            case .info, .notice: cassLevel = CASS_LOG_INFO
            case .warning: cassLevel = CASS_LOG_WARN
            case .error: cassLevel = CASS_LOG_ERROR
            case .critical: cassLevel = CASS_LOG_CRITICAL
            }
            cass_log_set_level(cassLevel)

            let newLogContext = CassandraLogConfiguration(logger: logger)
            cass_log_set_callback(
                { logMessage, context in
                    guard var logMessage = logMessage?.pointee, let context else {
                        return
                    }
                    let logContext = Unmanaged<CassandraLogConfiguration>.fromOpaque(context).takeUnretainedValue()
                    let logLevel: Logger.Level
                    switch logMessage.severity {
                    case CASS_LOG_CRITICAL: logLevel = .critical
                    case CASS_LOG_ERROR: logLevel = .error
                    case CASS_LOG_WARN: logLevel = .warning
                    case CASS_LOG_INFO: logLevel = .info
                    case CASS_LOG_DEBUG: logLevel = .debug
                    case CASS_LOG_TRACE: logLevel = .trace
                    case CASS_LOG_DISABLED: return
                    default: return
                    }
                    let message = withUnsafePointer(to: &logMessage.message.0) { pointer in
                        String(cString: pointer)
                    }
                    logContext.logger.log(
                        level: logLevel,
                        "\(message)",
                        source: "Cassandra",
                        file: String(cString: logMessage.file),
                        function: String(cString: logMessage.function),
                        line: UInt(logMessage.line)
                    )
                },
                Unmanaged.passUnretained(newLogContext).toOpaque()
            )
            logContext = newLogContext
        }
    }
}
