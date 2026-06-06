import AppKit
@testable import Cider
import Darwin
import Foundation
import OSLog

/// CiderCLI — Full command-line interface to Cider's storage layer.
/// Anything you can do in Cider, you can do here.
@main
@MainActor
struct CiderCLI {
    static var processExitCode: Int32 = 0

    static func handleRemovedLegacyTopLevelCommand(_ command: String, subcommand: String?) -> Bool {
        let replacement: String
        let reason: String
        switch command {
        case "memory":
            replacement = "Use cider-cli item context/search plus Kanban resistance cards for missing durable-memory affordances."
            reason = "memory was a parallel Markdown memory backend outside the second-brain item graph."
        case "embeddings":
            replacement = "Use cider-cli item search; semantic backfill will return only after the item graph/FTS contract is stable."
            reason = "embeddings backfill was a bookmark-only sidecar path, not the current retrieval foundation."
        case "search", "query":
            replacement = "Use cider-cli item search <query> --json."
            reason = "\(command) was a legacy broad search surface over per-domain stores."
        case "recent":
            replacement = "Use cider-cli item search/context, board recent for Kanban work, or dashboard/agenda surfaces."
            reason = "recent was a legacy per-domain sweep rather than a second-brain item surface."
        case "snapshot", "status":
            replacement = "Use cider-cli storage audit --json and cider-cli db integrity."
            reason = "\(command) was a legacy summary surface that competed with storage/db admin commands."
        default:
            return false
        }

        printRemovedLegacyCommand(command: command, replacement: replacement, reason: reason)
        return true
    }

    struct LegacyRemovedCommand {
        var command: String
        var replacement: String
        var reason: String = "Use the Second Brain v1 agent API."
    }

    static func hiddenLegacyCommandResponse(command rawCommand: String, subcommand rawSubcommand: String?, args: [String]) -> LegacyRemovedCommand? {
        let command = rawCommand.lowercased()
        let subcommand = rawSubcommand?.lowercased()
        let label = legacyCommandLabel(command: command, subcommand: subcommand)

        switch command {
        case "bookmark", "bm":
            if subcommand == "add" || subcommand == "create" { return nil }
            if subcommand == "update" || subcommand == "set" { return nil }
            if subcommand == "move" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item move bookmark <id> --folder <name|path> --json")
            }
            if subcommand == "enrich", args.contains("--all") {
                return LegacyRemovedCommand(
                    command: "bookmark enrich --all",
                    replacement: "cider-cli review enrich-batch --confirm --json"
                )
            }
            if subcommand == "enrich" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli review enrich <item-id> --json")
            }
            if subcommand == "date-suggestions" || subcommand == "dates" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli review list --kind date-suggestion --json")
            }
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "note":
            if subcommand == "create" || subcommand == "project-artifact" || subcommand == "artifact" || subcommand == "daily" { return nil }
            if subcommand == "move" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item move note <id> --folder <name|path> --json")
            }
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "todo", "todos", "task", "tasks":
            if subcommand == "create" || subcommand == "add" { return nil }
            if subcommand == "move" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item move todo <id> --folder <name|path> --json")
            }
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "event", "datecard":
            if subcommand != "create" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
            }
            return LegacyRemovedCommand(
                command: label,
                replacement: "cider-cli capture add --kind event --title \"<title>\" --date yyyy-MM-dd --stdin --json"
            )
        case "contact":
            if subcommand == "profile" || subcommand == "field" || subcommand == "fields" { return nil }
            if subcommand != "create" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
            }
            return LegacyRemovedCommand(
                command: label,
                replacement: "cider-cli capture add --kind contact --name \"<name>\" --stdin --json"
            )
        case "file":
            if subcommand == "import" || subcommand == "add" { return nil }
            if subcommand == "move" {
                return LegacyRemovedCommand(command: label, replacement: "cider-cli item move file <id> --folder <name|path> --json")
            }
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "folder":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "label", "tag":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "link":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item link")
        case "dashboard", "dash":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item graph-health --json")
        case "view", "saved-view":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item project-context <project-id-or-name> --json")
        case "trash":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli storage audit --json")
        case "clipboard", "cb":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli capture add --kind note --stdin --json")
        case "media":
            if subcommand == "identify" { return nil }
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "recall":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <query> --json")
        case "duplicate-check", "dupecheck":
            return LegacyRemovedCommand(command: label, replacement: "cider-cli item search <url-or-query> --json")
        default:
            return nil
        }
    }

    static func printHiddenLegacyCommandIfRemoved(command: String, subcommand: String?, args: [String]) -> Bool {
        guard let removed = hiddenLegacyCommandResponse(command: command, subcommand: subcommand, args: args) else {
            return false
        }
        printRemovedLegacyCommand(
            command: removed.command,
            replacement: removed.replacement,
            reason: removed.reason
        )
        return true
    }

    static func legacyCommandLabel(command: String, subcommand: String?) -> String {
        if command == "dashboard" || command == "dash", subcommand == "topic" {
            return "dashboard topic"
        }
        if let subcommand {
            return "\(command) \(subcommand)"
        }
        return command
    }

    static func printRemovedLegacyCommand(command: String, replacement: String, reason: String) {
        let message = "Legacy command '\(command)' has been removed from the blessed second-brain CLI surface."
        processExitCode = 1
        if jsonOutput {
            outputJSON([
                "ok": false,
                "error": message,
                "command": command,
                "legacyRemoved": true,
                "reason": reason,
                "replacement": replacement,
            ] as [String: Any])
        } else {
            print("Error: \(message)")
            print("Replacement: \(replacement)")
            print("Reason: \(reason)")
        }
    }

    static func main() async {
        processExitCode = 0
        defer {
            if processExitCode != 0 {
                Darwin.exit(processExitCode)
            }
        }
        var args = Array(CommandLine.arguments.dropFirst())

        // Sandbox vault override — `--vault <path>` points the CLI at an
        // alternate vault root for the duration of this invocation. Must run
        // BEFORE any storage service is touched, since StoragePaths memoizes
        // the vault URL on first read.
        if let idx = args.firstIndex(of: "--vault") {
            guard idx + 1 < args.count else {
                print("Error: --vault requires a path argument.")
                return
            }
            let path = NSString(string: args[idx + 1]).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            StoragePaths.vaultOverride = url
            args.removeSubrange(idx...(idx + 1))
            FileHandle.standardError.write(Data("Using sandbox vault: \(url.path)\n".utf8))
        }

        guard let command = args.first else {
            printUsage()
            return
        }
        let subcommand = args.count > 1 ? args[1] : nil
        let remaining = Array(args.dropFirst(2))

        if handleRemovedLegacyTopLevelCommand(command, subcommand: subcommand) {
            return
        }
        if let removed = hiddenLegacyCommandResponse(command: command, subcommand: subcommand, args: remaining) {
            printRemovedLegacyCommand(
                command: removed.command,
                replacement: removed.replacement,
                reason: removed.reason
            )
            return
        }

        // Initialize storage services
        StoragePaths.ensureVaultStructure()

        // Open SQLite before any storage service is touched — services check
        // CiderDatabase.shared.isOpen and use it as the primary store when available.
        // Without this, CLI writes skip the SQLite persist path and only hit the
        // filesystem, leaving the DB out of sync with the app.
        do {
            let vaultRoot = StoragePaths.cachedVaultDirectoryURL
            let dbPath = vaultRoot.appendingPathComponent(".cider/cider.db")
            try FileManager.default.createDirectory(
                at: dbPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            DatabaseSafetyService.shared.capturePreOpenSnapshotIfNeeded(databaseURL: dbPath)
            try CiderDatabase.shared.open(at: dbPath)
            DatabaseSafetyService.shared.performStartupSafetyPass(database: CiderDatabase.shared)
        } catch {
            let databaseOpenError = error
            Logger(subsystem: "Cider", category: "CLI")
                .error("Failed to open SQLite database: \(error.localizedDescription).")
            if requiresCanonicalDatabase(command: command, subcommand: subcommand, args: remaining) {
                printCLIError(
                    "Cannot run \(commandDescription(command: command, subcommand: subcommand)) because the canonical SQLite database is unavailable. Cider no longer falls back to JSON or filesystem mutation paths.",
                    details: [
                        "command": command,
                        "subcommand": subcommand ?? NSNull(),
                        "underlyingError": databaseOpenError.localizedDescription
                    ]
                )
                return
            }
        }

        if command == "db" {
            handleDatabase(subcommand: subcommand, args: remaining)
            return
        }

        let bookmarkService = VaultBookmarkService.shared
        let notesStorage = NotesStorage.shared
        let todoStorage = TodoCardStorage.shared
        let vaultFileService = VaultFileService.shared
        vaultFileService.ensureInboxDirectories()
        vaultFileService.scan()

        // Force-init the remaining folder-aware singletons so that
        // `folder delete` (and any other command that iterates these
        // collections) sees live in-memory state loaded from SQLite.
        // Without this, the three lazy-loading services below would
        // appear empty to an early-invoked `folder delete`, which would
        // silently drag their items along with the folder into trash.
        _ = DateCardStorage.shared
        _ = ContactStorage.shared

        // Wait for async storage initialization — poll until notes are loaded
        // (NotesStorage uses Task { @MainActor } in init which needs actor time)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if !notesStorage.notes.isEmpty { break }
        }

        switch command {
        case "capture":
            await handleCapture(subcommand: subcommand, args: remaining, bookmarkService: bookmarkService)
        case "review":
            await handleReview(subcommand: subcommand, args: remaining, bookmarkService: bookmarkService)
        case "space", "spaces":
            handleSpace(subcommand: subcommand, args: remaining)
        case "routing", "route":
            handleRouting(subcommand: subcommand, args: remaining, bookmarkService: bookmarkService)
        case "bookmark", "bm":
            await handleBookmark(subcommand: subcommand, args: remaining, service: bookmarkService)
        case "note":
            await handleNote(subcommand: subcommand, args: remaining, storage: notesStorage)
        case "todo":
            await handleTodo(subcommand: subcommand, args: remaining, storage: todoStorage)
        case "event", "datecard":
            handleEvent(subcommand: subcommand, args: remaining)
        case "contact":
            handleContact(subcommand: subcommand, args: remaining)
        case "link":
            handleLink(subcommand: subcommand, args: remaining)
        case "item":
            handleItem(subcommand: subcommand, args: remaining)
        case "export":
            handleExport(subcommand: subcommand, args: remaining)
        case "file":
            handleFile(subcommand: subcommand, args: remaining, service: vaultFileService)
        case "folder":
            handleFolder(subcommand: subcommand, args: remaining)
        case "board":
            handleBoard(subcommand: subcommand, args: remaining)
        case "label", "tag":
            handleLabel(subcommand: subcommand, args: remaining)
        case "trash":
            handleTrash(subcommand: subcommand, args: remaining)
        case "db":
            handleDatabase(subcommand: subcommand, args: remaining)
        case "doctor":
            handleFolder(subcommand: "doctor", args: Array(args.dropFirst()))
        case "clipboard", "cb":
            handleClipboard(subcommand: subcommand, args: remaining)
        case "dashboard", "dash":
            handleDashboard(subcommand: subcommand, args: remaining)
        case "media":
            handleMedia(subcommand: subcommand, args: remaining, bookmarks: bookmarkService.bookmarks)
        case "agenda", "brief":
            handleAgenda(args: Array(args.dropFirst()))
        case "reminder", "reminders":
            handleReminder(subcommand: subcommand, args: remaining)
        case "recall":
            handleRecall(subcommand: subcommand, args: remaining)
        case "storage":
            handleStorage(subcommand: subcommand, args: remaining)
        case "duplicate-check", "dupecheck":
            handleDuplicateCheck(args: Array(args.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            printCLIError("Unknown command: \(command). Run 'cider-cli help' for usage.")
        }
    }

    static func requiresCanonicalDatabase(command rawCommand: String, subcommand rawSubcommand: String?, args: [String]) -> Bool {
        let command = rawCommand.lowercased()
        let subcommand = rawSubcommand?.lowercased()

        switch command {
        case "capture":
            return subcommand == nil || subcommand == "add"
        case "bookmark", "bm":
            return isMutationSubcommand(
                subcommand,
                in: ["add", "create", "move", "delete", "rm", "update", "set", "tag", "untag", "assign-label", "date-suggestions"]
            )
        case "note":
            return isMutationSubcommand(subcommand, in: ["create", "move", "delete", "rm", "update", "rename"])
        case "todo", "todos", "task", "tasks":
            return isMutationSubcommand(
                subcommand,
                in: ["create", "add", "complete", "done", "delete", "rm", "update", "set", "checklist"]
            )
        case "event", "datecard":
            return isMutationSubcommand(subcommand, in: ["create", "delete", "rm", "update", "set"])
        case "contact":
            return isMutationSubcommand(subcommand, in: ["create", "delete", "rm", "update", "set", "profile", "field", "link"])
        case "file":
            return isMutationSubcommand(subcommand, in: ["add", "import", "move", "delete", "rm", "update", "set"])
        case "folder":
            if subcommand == "doctor" {
                return args.contains("--fix") || args.contains("--apply") || args.contains("--execute")
            }
            return isMutationSubcommand(
                subcommand,
                in: ["create", "mkdir", "move", "mv", "delete", "rm", "restore", "rename", "set-icon", "remove-icon", "set-cover", "remove-cover"]
            )
        case "routing", "route":
            return isMutationSubcommand(subcommand, in: ["approve", "correct", "rerun"])
        case "review":
            return isMutationSubcommand(subcommand, in: ["approve", "correct", "defer", "enrich", "enrich-batch"])
        case "item":
            return isMutationSubcommand(subcommand, in: ["move", "unfile", "delete", "rm", "route", "link", "backfill-kanban", "rebuild-chunks", "rebuild-content", "rebuild-enrichment", "rebuild-similarity", "dogfood-intelligence", "accept-similarity", "sync-project", "project-sync"])
        case "label", "tag":
            return isMutationSubcommand(subcommand, in: ["create", "rename", "delete", "rm"])
        case "trash":
            return isMutationSubcommand(subcommand, in: ["restore", "empty", "purge"])
        case "reminder", "reminders":
            return isMutationSubcommand(subcommand, in: ["complete", "done", "snooze"])
        case "storage":
            return subcommand == "doctor-apply" || subcommand == "bookmark-drift-repair" || (subcommand == "repair-schema" && args.contains("--execute"))
        case "doctor":
            return args.contains("--fix") || args.contains("--apply") || args.contains("--execute")
        default:
            return false
        }
    }

    static func isMutationSubcommand(_ subcommand: String?, in mutationSubcommands: Set<String>) -> Bool {
        guard let subcommand else { return false }
        return mutationSubcommands.contains(subcommand)
    }

    static func commandDescription(command: String, subcommand: String?) -> String {
        if let subcommand {
            return "\(command) \(subcommand)"
        }
        return command
    }

    // MARK: - Storage Audit Commands

    static func handleStorage(subcommand: String?, args: [String]) {
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Storage commands:
              cider-cli storage audit [--json]
              cider-cli storage doctor-plan [--limit <n>] [--json]
              cider-cli storage doctor-apply --finding <id> --canonical <path> --duplicate <path> --approve <token> [--execute] [--json]
              cider-cli storage active-duplicate-invariants [--limit <n>] [--json]
              cider-cli storage restart-duplicate-regression [--limit <n>] [--json]
              cider-cli storage bookmark-drift-audit [--limit <n>] [--json]
              cider-cli storage bookmark-drift-repair --item <id> --approve <token> [--execute] [--json]
              cider-cli storage repair-schema [--approve REPAIR_SCHEMA] [--execute] [--json]
            """)

        case "audit":
            do {
                let report = try CiderStorageAuditService().audit()
                if jsonOutput {
                    var payload = storageAuditReportToDict(report)
                    payload["ok"] = true
                    payload["command"] = "storage.audit"
                    payload["readOnly"] = true
                    payload["changed"] = false
                    outputJSON(payload)
                } else {
                    print("Storage audit")
                    print("  Doctor findings: \(report.totalDoctorFindings) (\(report.fixableDoctorFindings) fixable)")
                    print("  Schema findings: \(report.schemaFindings.count)")
                    print("  Mismatches: \(report.mismatches.count)")
                    print("  Model counts:")
                    for key in report.modelCounts.keys.sorted() {
                        print("    \(key): \(report.modelCounts[key] ?? 0)")
                    }
                    print("  SQLite counts:")
                    for key in report.sqliteCounts.keys.sorted() {
                        print("    \(key): \(report.sqliteCounts[key] ?? 0)")
                    }
                    if !report.mismatches.isEmpty {
                        print("  Count mismatches:")
                        for mismatch in report.mismatches {
                            print("    \(mismatch.detail)")
                        }
                    }
                    if !report.schemaFindings.isEmpty {
                        print("  Schema findings:")
                        for finding in report.schemaFindings {
                            print("    [\(finding.severity)] \(finding.summary)")
                            print("      \(finding.nextSafeAction)")
                        }
                    }
                    if !report.doctorFindingGroups.isEmpty {
                        print("  Doctor groups:")
                        for key in report.doctorFindingGroups.keys.sorted() {
                            print("    \(key): \(report.doctorFindingGroups[key] ?? 0)")
                        }
                    }
                    if !report.duplicateFindingGroups.isEmpty {
                        print("  Duplicate groups:")
                        for key in report.duplicateFindingGroups.keys.sorted() {
                            print("    \(key): \(report.duplicateFindingGroups[key] ?? 0)")
                        }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "doctor-plan":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
            let report = CiderStorageAuditService().doctorRemediationPlan(limit: limit)
            if jsonOutput {
                outputJSON(storageDoctorRemediationPlanReportToDict(report))
            } else {
                print("Storage doctor remediation dry-run plan")
                print("  Mutating: \(report.isMutating ? "yes" : "no")")
                print("  Approval required: \(report.approvalRequired ? "yes" : "no")")
                print("  Plans: \(report.plans.count)")
                for plan in report.plans {
                    print("    [\(plan.severity)] \(plan.summary)")
                    if let canonical = plan.candidateCanonicalRelativePath {
                        print("      Candidate canonical path: \(canonical)")
                    }
                    if !plan.duplicateRelativePaths.isEmpty {
                        print("      Duplicate path(s): \(plan.duplicateRelativePaths.joined(separator: ", "))")
                    }
                    print("      Action: \(plan.proposedAction) (\(plan.confidence))")
                    print("      No files or folders were changed.")
                }
            }

        case "active-duplicate-invariants", "duplicate-invariants":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
            do {
                let report = try CiderStorageAuditService().activeDuplicateInvariantCheck(limit: limit)
                if jsonOutput {
                    outputJSON(activeDuplicateInvariantReportToDict(report))
                } else {
                    print("Active duplicate invariant check")
                    print("  Mutating: \(report.isMutating ? "yes" : "no")")
                    print("  Status: \(report.status)")
                    print("  Duplicate findings: \(report.duplicateFindings.count)")
                    print("  Duplicate relative paths: \(report.duplicateRelativePaths.count)")
                    print("  SQLite mismatches: \(report.sqliteMismatches.count)")
                    print("  Vault/SQLite path mismatches: \(report.vaultSQLiteMismatches.count)")
                    for finding in report.duplicateFindings {
                        print("    [\(finding.entityType.rawValue)/\(finding.kind.rawValue)] \(finding.summary)")
                    }
                    for finding in report.duplicateRelativePaths {
                        print("    [relative_path] \(finding.relativePath): \(finding.items.count) active rows")
                    }
                    for mismatch in report.sqliteMismatches {
                        print("    [mismatch] \(mismatch.detail)")
                    }
                    for mismatch in report.vaultSQLiteMismatches {
                        print("    [\(mismatch.kind)] \(mismatch.relativePath): \(mismatch.detail)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "restart-duplicate-regression", "restart-rebuild-duplicate-regression", "duplicate-restart-regression":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
            do {
                let report = try CiderStorageAuditService().restartRebuildDuplicateRegressionLoop(limit: limit)
                if jsonOutput {
                    outputJSON(restartDuplicateRegressionReportToDict(report))
                } else {
                    print("Restart/rebuild duplicate regression loop")
                    print("  Mutating: \(report.isMutating ? "yes" : "no")")
                    print("  Status: \(report.status)")
                    print("  Passed: \(report.passed ? "yes" : "no")")
                    print("  Before issues: \(report.regression.beforeIssueCount)")
                    print("  After issues: \(report.regression.afterIssueCount)")
                    print("  New issue fingerprints: \(report.regression.newIssueFingerprints.count)")
                    for fingerprint in report.regression.newIssueFingerprints {
                        print("    \(fingerprint)")
                    }
                    if !report.regression.sqliteTableCountChanges.isEmpty {
                        print("  SQLite table count changes:")
                        for key in report.regression.sqliteTableCountChanges.keys.sorted() {
                            print("    \(key): \(report.regression.sqliteTableCountChanges[key] ?? 0)")
                        }
                    }
                    if report.regression.vaultArtifactFingerprintChanged {
                        print("  Vault artifact fingerprint changed")
                    }
                    print("  Machine-readable output: rerun with --json")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "doctor-apply":
            guard let findingID = parseFlag("--finding", from: args),
                  let canonicalPath = parseFlag("--canonical", from: args),
                  let duplicatePath = parseFlag("--duplicate", from: args) else {
                printCLIError("Usage: cider-cli storage doctor-apply --finding <id> --canonical <path> --duplicate <path> --approve <token> [--execute] [--json]")
                return
            }
            let approvalToken = parseFlag("--approve", from: args)
            let report = CiderStorageAuditService().applyDoctorRemediation(
                findingID: findingID,
                canonicalRelativePath: canonicalPath,
                duplicateRelativePath: duplicatePath,
                approvalToken: approvalToken,
                execute: args.contains("--execute")
            )
            if jsonOutput {
                outputJSON(storageDoctorRemediationApplyReportToDict(report))
            } else {
                print("Storage doctor approved remediation")
                print("  Status: \(report.status)")
                print("  Mutating: \(report.isMutating ? "yes" : "no")")
                print("  Approval required: \(report.approvalRequired ? "yes" : "no")")
                print("  Finding: \(report.findingID)")
                print("  Canonical path: \(report.canonicalRelativePath)")
                print("  Duplicate path: \(report.duplicateRelativePath)")
                print("  Required approval token: \(report.requiredApprovalToken)")
                if !report.plannedActions.isEmpty {
                    print("  Planned actions:")
                    for action in report.plannedActions {
                        print("    \(action)")
                    }
                }
                if !report.appliedActions.isEmpty {
                    print("  Applied actions:")
                    for action in report.appliedActions {
                        print("    \(action)")
                    }
                }
                if let trashPath = report.trashRelativePath {
                    print("  Trash path: \(trashPath)")
                }
                if !report.blockers.isEmpty {
                    print("  Blockers:")
                    for blocker in report.blockers {
                        print("    \(blocker)")
                    }
                }
            }

        case "bookmark-drift-audit":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
            do {
                let report = try CiderStorageAuditService().bookmarkDriftAudit(limit: limit)
                if jsonOutput {
                    outputJSON(bookmarkDriftAuditReportToDict(report))
                } else {
                    print("Bookmark drift audit")
                    print("  Mutating: \(report.isMutating ? "yes" : "no")")
                    print("  Approval required: \(report.approvalRequired ? "yes" : "no")")
                    print("  Findings: \(report.findings.count)")
                    for finding in report.findings {
                        print("    [\(finding.severity)] \(finding.currentTitle)")
                        if finding.proposedTitle != finding.currentTitle {
                            print("      Proposed title: \(finding.proposedTitle)")
                        }
                        print("      Item: \(finding.itemID)")
                        print("      Current path: \(finding.currentRelativePath)")
                        print("      Proposed path: \(finding.proposedRelativePath)")
                        print("      Path drift: \(finding.pathDrift ? "yes" : "no"), chunk drift: \(finding.chunkDrift ? "yes" : "no")")
                        print("      Repair: \(finding.repairCommand)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "bookmark-drift-repair":
            guard let itemID = parseFlag("--item", from: args) else {
                printCLIError("Usage: cider-cli storage bookmark-drift-repair --item <id> --approve <token> [--execute] [--json]")
                return
            }
            let approvalToken = parseFlag("--approve", from: args)
            do {
                let report = try CiderStorageAuditService().repairBookmarkDrift(
                    itemID: itemID,
                    approvalToken: approvalToken,
                    execute: args.contains("--execute")
                )
                if jsonOutput {
                    outputJSON(bookmarkDriftRepairReportToDict(report))
                } else {
                    print("Bookmark drift repair")
                    print("  Status: \(report.status)")
                    print("  Mutating: \(report.isMutating ? "yes" : "no")")
                    print("  Approval required: \(report.approvalRequired ? "yes" : "no")")
                    print("  Item: \(report.itemID)")
                    if let currentTitle = report.currentTitle {
                        print("  Current title: \(currentTitle)")
                    }
                    if let proposedTitle = report.proposedTitle, proposedTitle != report.currentTitle {
                        print("  Proposed title: \(proposedTitle)")
                    }
                    if let current = report.currentRelativePath {
                        print("  Current path: \(current)")
                    }
                    print("  Proposed path: \(report.proposedRelativePath)")
                    if let token = report.requiredApprovalToken {
                        print("  Required approval token: \(token)")
                    }
                    if !report.plannedActions.isEmpty {
                        print("  Planned actions:")
                        for action in report.plannedActions {
                            print("    \(action)")
                        }
                    }
                    if !report.appliedActions.isEmpty {
                        print("  Applied actions:")
                        for action in report.appliedActions {
                            print("    \(action)")
                        }
                    }
                    if !report.blockers.isEmpty {
                        print("  Blockers:")
                        for blocker in report.blockers {
                            print("    \(blocker)")
                        }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "repair-schema":
            let approvalToken = parseFlag("--approve", from: args)
            let execute = args.contains("--execute")
            do {
                let report = try CiderStorageAuditService().repairSchemaFindings(
                    approvalToken: approvalToken,
                    execute: execute
                )
                if jsonOutput {
                    outputJSON(storageAuditSchemaRepairReportToDict(report))
                } else {
                    print("Storage schema repair")
                    print("  Status: \(report.status)")
                    print("  Mutating: \(report.isMutating ? "yes" : "no")")
                    print("  Approval required: \(report.approvalRequired ? "yes" : "no")")
                    print("  Required approval token: \(report.requiredApprovalToken)")
                    if !report.plannedActions.isEmpty {
                        print("  Planned actions:")
                        for action in report.plannedActions {
                            print("    \(action)")
                        }
                    }
                    if !report.appliedActions.isEmpty {
                        print("  Applied actions:")
                        for action in report.appliedActions {
                            print("    \(action)")
                        }
                    }
                    if !report.blockers.isEmpty {
                        print("  Blockers:")
                        for blocker in report.blockers {
                            print("    \(blocker)")
                        }
                    }
                    print("  Repaired: \(report.repairedFindingIDs.count)")
                    for id in report.repairedFindingIDs {
                        print("    \(id)")
                    }
                    print("  Skipped: \(report.skippedFindingIDs.count)")
                    for id in report.skippedFindingIDs {
                        print("    \(id)")
                    }
                    print("  Remaining findings: \(report.remainingFindings.count)")
                    for finding in report.remainingFindings {
                        print("    [\(finding.severity)] \(finding.summary)")
                        print("      \(finding.nextSafeAction)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        default:
            printCLIError("Unknown storage command: \(subcommand ?? "nil"). Commands: audit, doctor-plan, doctor-apply, active-duplicate-invariants, restart-duplicate-regression, bookmark-drift-audit, bookmark-drift-repair, repair-schema")
        }
    }

    // MARK: - Recall / Evaluation Commands

    static func handleRecall(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "recall", subcommand: subcommand, args: args) else {
            return
        }
        let service = CiderRecallScorecardService()
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Recall evaluation commands:
              cider-cli recall scorecard [--limit <n>] [--search-limit <n>] [--json]
              cider-cli recall probes [--limit <n>] [--json]
            """)

        case "scorecard", "evaluate", "run":
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? 12
            let searchLimit = Int(parseFlag("--search-limit", from: args) ?? "") ?? 5
            do {
                let scorecard = try service.evaluateSuggested(limit: limit, searchLimit: searchLimit)
                if jsonOutput {
                    outputJSON(recallScorecardToDict(scorecard))
                } else {
                    print("Recall scorecard: \(scorecard.passedProbeCount)/\(scorecard.totalProbeCount) probes passed")
                    for capability in CiderRecallCapability.allCases {
                        let score = scorecard.capabilityScores[capability]
                            ?? CiderRecallCapabilityScore(capability: capability, passed: 0, failed: 0)
                        print("  \(capability.rawValue): \(score.passed)/\(score.total)")
                    }
                    for result in scorecard.results where !result.passed {
                        print("  Failed: \(result.probe.title)")
                        for check in result.checks where !check.passed {
                            print("    \(check.capability.rawValue): \(check.detail)")
                        }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "probes":
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? 12
            do {
                let probes = try service.suggestedProbes(limit: limit)
                if jsonOutput {
                    outputJSON(probes.map(recallProbeToDict))
                } else if probes.isEmpty {
                    print("No recall probes available.")
                } else {
                    print("Recall probes (\(probes.count)):")
                    for probe in probes {
                        print("  \(probe.id): \(probe.query) -> \(probe.expectedRef.type.rawValue):\(probe.expectedRef.entityID.uuidString)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        default:
            printCLIError("Unknown recall command: \(subcommand ?? "nil"). Commands: scorecard, probes")
        }
    }

    // MARK: - Reminder Action Commands

    struct CiderReminderIDCandidate: Equatable {
        let id: UUID
        let title: String
    }

    enum CiderReminderIDResolution: Equatable {
        case missing
        case notFound(String)
        case unique(UUID)
        case ambiguous([CiderReminderIDCandidate])
    }

    static func handleReminder(subcommand: String?, args: [String]) {
        let service = CiderReminderActionService()
        let positionalArgs = args.filter { !$0.hasPrefix("--") }
        do {
            let result: CiderReminderActionResult
            switch subcommand {
            case "complete", "done":
                let usage = "Usage: cider-cli reminder complete <todo|dateCard> <id-prefix> [--json]"
                guard let itemType = parseReminderItemType(positionalArgs.first) else {
                    printCLIError(usage)
                    return
                }
                let idResolution = resolveUniqueReminderID(type: itemType, prefix: positionalArgs.dropFirst().first)
                guard case .unique(let id) = idResolution else {
                    printReminderIDResolutionError(idResolution, itemType: itemType, usage: usage)
                    return
                }
                result = try service.complete(itemType, id: id)

            case "snooze", "defer":
                let usage = "Usage: cider-cli reminder snooze <todo|dateCard> <id-prefix> --until yyyy-MM-dd [--time \"h:mm a\"] [--json]"
                guard let itemType = parseReminderItemType(positionalArgs.first) else {
                    printCLIError(usage)
                    return
                }
                let idResolution = resolveUniqueReminderID(type: itemType, prefix: positionalArgs.dropFirst().first)
                guard case .unique(let id) = idResolution else {
                    printReminderIDResolutionError(idResolution, itemType: itemType, usage: usage)
                    return
                }
                guard let untilString = parseFlag("--until", from: args) ?? parseFlag("--date", from: args),
                      let until = resolveEventStartAt(dateString: untilString, timeString: parseFlag("--time", from: args)) else {
                    printCLIError("--until yyyy-MM-dd required for reminder snooze")
                    return
                }
                result = try service.snooze(itemType, id: id, until: until)

            default:
                printCLIError("Unknown reminder command: \(subcommand ?? "nil"). Commands: complete, snooze")
                return
            }

            if jsonOutput {
                outputJSON(reminderActionResultToDict(result))
            } else {
                switch result.action {
                case .complete:
                    print("Completed \(result.itemType.rawValue): \(result.title)")
                case .snooze:
                    let until = result.snoozedUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                    print("Snoozed \(result.itemType.rawValue): \(result.title) until \(until)")
                }
            }
        } catch {
            printCLIError(error.localizedDescription)
        }
    }

    private static func parseReminderItemType(_ raw: String?) -> CiderReminderActionItemType? {
        switch raw?.lowercased() {
        case "todo", "todos", "task", "tasks":
            return .todo
        case "datecard", "date-card", "event", "events":
            return .dateCard
        default:
            return nil
        }
    }

    static func resolveUniqueReminderID(
        prefix: String?,
        candidates: [CiderReminderIDCandidate]
    ) -> CiderReminderIDResolution {
        guard let prefix else { return .missing }
        let normalized = prefix.lowercased()
        let matches = candidates.filter { $0.id.uuidString.lowercased().hasPrefix(normalized) }
        if matches.isEmpty { return .notFound(prefix) }
        if matches.count == 1, let match = matches.first { return .unique(match.id) }
        return .ambiguous(matches)
    }

    private static func resolveUniqueReminderID(
        type: CiderReminderActionItemType,
        prefix: String?
    ) -> CiderReminderIDResolution {
        let candidates: [CiderReminderIDCandidate]
        switch type {
        case .todo:
            candidates = TodoCardStorage.shared.todoCards.map { CiderReminderIDCandidate(id: $0.id, title: $0.title) }
        case .dateCard:
            candidates = DateCardStorage.shared.dateCards.map { CiderReminderIDCandidate(id: $0.id, title: $0.title) }
        }
        return resolveUniqueReminderID(prefix: prefix, candidates: candidates)
    }

    private static func printReminderIDResolutionError(
        _ resolution: CiderReminderIDResolution,
        itemType: CiderReminderActionItemType,
        usage: String
    ) {
        switch resolution {
        case .missing:
            printCLIError(usage)
        case .notFound(let prefix):
            printCLIError("No \(itemType.rawValue) found with ID prefix: \(prefix)")
        case .ambiguous(let matches):
            printCLIError(
                "Ambiguous \(itemType.rawValue) ID prefix. Use more characters.",
                details: [
                    "matches": matches.map { ["id": $0.id.uuidString, "title": $0.title] }
                ]
            )
        case .unique:
            return
        }
    }

    // MARK: - Agenda Commands

    static func handleAgenda(args: [String]) {
        let includeLater = args.contains("--all") || args.contains("--include-later")
        let includeSuppressed = args.contains("--all") || args.contains("--include-suppressed")
        let now = Date()
        let brief = AgendaBriefingService.build(
            todos: TodoCardStorage.shared.todoCards,
            dateCards: DateCardStorage.shared.dateCards,
            now: now
        )

        let visibleItems = brief.items.filter { item in
            if item.surfaceToday { return true }
            if includeLater && item.bucket == .later { return true }
            if includeSuppressed && item.bucket == .suppressed { return true }
            return false
        }
        let visibleBrief = AgendaBriefing(generatedAt: brief.generatedAt, items: visibleItems)

        if jsonOutput {
            outputJSON(agendaBriefingToDict(visibleBrief))
        } else {
            if visibleItems.isEmpty {
                print("No agenda items due to surface today.")
                return
            }
            for item in visibleItems {
                print("[\(item.itemType.rawValue)] \(item.title) — \(item.reason)")
            }
        }
    }

    // MARK: - Dashboard Commands

    static func handleDashboard(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "dashboard", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "topic", "topics":
            handleDashboardTopic(subcommand: args.first, args: Array(args.dropFirst()))
        case "card", "cards":
            handleDashboardCard(subcommand: args.first, args: Array(args.dropFirst()))
        default:
            printCLIError("Unknown dashboard command: \(subcommand ?? "nil"). Commands: topic list, topic upsert, topic move, topic archive, card list, card upsert, card move, card seen, card dismiss, card archive, card delete, card feedback")
        }
    }

    static func handleDashboardTopic(subcommand: String?, args: [String]) {
        let storage = DashboardStorage.shared
        switch subcommand {
        case "list":
            let topics = dashboardTopics(storage: storage)
            if jsonOutput {
                outputJSON(topics.map(dashboardTopicToDict))
            } else {
                for topic in topics {
                    let archived = topic.isArchived == true ? " archived" : ""
                    print("  [\(topic.ciderSyncId.prefix(8))] \(topic.title) pos=\(topic.position)\(archived)")
                }
            }

        case "upsert":
            guard let title = parseFlag("--title", from: args) ?? args.first(where: { !$0.hasPrefix("--") }) else {
                print("Error: Usage: cider-cli dashboard topic upsert --title <title> [--id <id>] [--icon <sf-symbol>] [--position <n>] [--color <token>] [--pinned true|false]")
                return
            }
            let explicitID = parseFlag("--id", from: args)?.lowercased()
            let existing = explicitID.flatMap { id in
                dashboardTopics(storage: storage).first { $0.ciderSyncId == id }
            } ?? dashboardTopics(storage: storage).first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
            let now = dashboardNowMilliseconds()
            let topic = DashboardTopic(
                ciderSyncId: explicitID ?? existing?.ciderSyncId,
                title: title,
                icon: parseFlag("--icon", from: args) ?? existing?.icon,
                colorToken: parseFlag("--color", from: args) ?? existing?.colorToken,
                position: parseFlag("--position", from: args).flatMap(Int.init) ?? existing?.position ?? dashboardTopics(storage: storage).count,
                isPinned: parseOptionalBoolFlag("--pinned", from: args) ?? (args.contains("--pinned") ? true : existing?.isPinned),
                isArchived: false,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            storage.upsertTopic(topic)
            printDashboardTopicResult(topic)

        case "move":
            guard let ref = args.first,
                  let position = parseFlag("--position", from: args).flatMap(Int.init) else {
                print("Error: Usage: cider-cli dashboard topic move <id|title> --position <n>")
                return
            }
            guard let topic = resolveDashboardTopic(ref, storage: storage) else { return }
            if !storage.topics.contains(where: { $0.ciderSyncId == topic.ciderSyncId }) {
                storage.upsertTopic(topic)
            }
            guard storage.moveTopic(topic.ciderSyncId, to: position) else {
                print("Error: Could not move dashboard topic '\(ref)'")
                return
            }
            printDashboardTopicResult(resolveDashboardTopic(topic.ciderSyncId, storage: storage) ?? topic)

        case "archive", "delete":
            guard let ref = args.first else {
                print("Error: Usage: cider-cli dashboard topic archive <id|title>")
                return
            }
            guard let topic = resolveDashboardTopic(ref, storage: storage) else { return }
            if !storage.topics.contains(where: { $0.ciderSyncId == topic.ciderSyncId }) {
                storage.upsertTopic(topic)
            }
            guard storage.archiveTopic(topic.ciderSyncId) else {
                print("Error: Could not archive dashboard topic '\(ref)'")
                return
            }
            printDashboardTopicResult(resolveDashboardTopic(topic.ciderSyncId, storage: storage) ?? topic)

        default:
            print("Unknown dashboard topic command: \(subcommand ?? "nil")")
            print("Commands: list, upsert, move, archive")
        }
    }

    static func handleDashboardCard(subcommand: String?, args: [String]) {
        let storage = DashboardStorage.shared
        switch subcommand {
        case "list":
            let topicRef = parseFlag("--topic", from: args)
            let topicID = topicRef.flatMap { resolveDashboardTopic($0, storage: storage)?.ciderSyncId }
            if topicRef != nil, topicID == nil { return }
            let includeHidden = args.contains("--all") || args.contains("--include-hidden") || args.contains("--include-dismissed")
            let cards = storage.cards
                .filter { card in
                    if let topicID, !card.topicSyncIds.contains(topicID) { return false }
                    if includeHidden { return true }
                    return card.deleted != true && card.status != .dismissed && card.status != .archived
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            if jsonOutput {
                outputJSON(cards.map(dashboardCardToDict))
            } else {
                for card in cards {
                    print("  [\(card.ciderSyncId.prefix(8))] \(card.title) (\(card.status.rawValue), \(card.priority.rawValue))")
                }
            }

        case "upsert":
            guard let payload = readDashboardCardPayload(from: args) else { return }
            guard let card = dashboardCard(from: payload, storage: storage) else { return }
            storage.upsertCard(card)
            printDashboardCardResult(resolveDashboardCard(card.ciderSyncId, storage: storage) ?? card)

        case "move":
            guard let ref = args.first else {
                print("Error: Usage: cider-cli dashboard card move <card-id> --topic <id|title> [--topic <id|title> ...]")
                return
            }
            guard let card = resolveDashboardCard(ref, storage: storage) else { return }
            let topicIDs = resolveDashboardTopicIDs(from: args, storage: storage)
            guard !topicIDs.isEmpty else {
                print("Error: At least one --topic <id|title> is required.")
                return
            }
            guard storage.setCardTopics(card.ciderSyncId, topicSyncIds: topicIDs) else {
                print("Error: Could not move dashboard card '\(ref)'")
                return
            }
            printDashboardCardResult(resolveDashboardCard(card.ciderSyncId, storage: storage) ?? card)

        case "seen":
            mutateDashboardCard(args.first, storage: storage, usage: "cider-cli dashboard card seen <card-id>") { card in
                storage.markSeen(card.ciderSyncId)
            }

        case "dismiss":
            mutateDashboardCard(args.first, storage: storage, usage: "cider-cli dashboard card dismiss <card-id>") { card in
                storage.dismissCard(card.ciderSyncId)
            }

        case "archive":
            mutateDashboardCard(args.first, storage: storage, usage: "cider-cli dashboard card archive <card-id>") { card in
                storage.archiveCard(card.ciderSyncId)
            }

        case "delete":
            mutateDashboardCard(args.first, storage: storage, usage: "cider-cli dashboard card delete <card-id>") { card in
                storage.deleteCard(card.ciderSyncId)
            }

        case "feedback":
            guard let ref = args.first else {
                print("Error: Usage: cider-cli dashboard card feedback <card-id> [--more-like-this|--less-like-this|--clear-preference] [--rating 1-5]")
                return
            }
            guard let card = resolveDashboardCard(ref, storage: storage) else { return }
            var changed = false
            if args.contains("--more-like-this") {
                changed = storage.markMoreLikeThis(card.ciderSyncId) || changed
            }
            if args.contains("--less-like-this") {
                changed = storage.markLessLikeThis(card.ciderSyncId) || changed
            }
            if args.contains("--clear-preference") {
                changed = storage.setCardPreference(card.ciderSyncId, moreLikeThis: false, lessLikeThis: false) || changed
            }
            if let rating = parseFlag("--rating", from: args).flatMap(Int.init) {
                changed = storage.rateCard(card.ciderSyncId, rating: rating) || changed
            }
            guard changed else {
                print("Error: No feedback change requested.")
                return
            }
            printDashboardCardResult(resolveDashboardCard(card.ciderSyncId, storage: storage) ?? card)

        default:
            print("Unknown dashboard card command: \(subcommand ?? "nil")")
            print("Commands: list, upsert, move, seen, dismiss, archive, delete, feedback")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Bookmark Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleCapture(subcommand: String?, args: [String], bookmarkService: VaultBookmarkService) async {
        switch subcommand {
        case "add":
            if isHelpRequested(in: args) {
                printCaptureUsage()
                return
            }

            let source: CaptureAddSource
            do {
                source = try resolveCaptureAddSource(from: args)
            } catch {
                printCLIError(error.localizedDescription)
                return
            }

            let targetFolder: VaultFolder?
            switch resolveCaptureFolderArg(from: args, source: source) {
            case .unspecified: targetFolder = nil
            case .resolved(let folder): targetFolder = folder
            case .failed: return
            }

            do {
                let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
                let service = CiderCaptureService(bookmarkService: bookmarkService, database: database)
                let title = parseFlag("--title", from: args)
                let sourceContext = captureSourceContext(from: args, originalText: source.originalText)
                let result: CiderCaptureResult
                switch source {
                case .inferred(let raw):
                    result = try service.add(
                        raw,
                        title: title,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .note(let raw):
                    result = try service.addNoteCapture(
                        title: title,
                        content: raw,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .todo(let raw):
                    result = try service.addTodoCapture(
                        title: title ?? service.derivedTodoTitle(from: raw),
                        sourceText: raw,
                        dueDate: nil,
                        priority: nil,
                        folderID: targetFolder?.id,
                        titleState: title == nil ? "derived" : "manual",
                        sourceContext: sourceContext
                    )
                case .bookmark(let url):
                    result = try service.addBookmarkCapture(
                        urlString: url,
                        title: title,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .file(let path):
                    result = try service.addFileCapture(
                        sourcePath: path,
                        title: title,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .event(let event):
                    result = try service.addDateCardCapture(
                        title: event.title,
                        sourceText: event.sourceText,
                        startAt: event.startAt,
                        endAt: nil,
                        allDay: event.allDay,
                        location: event.location,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .contact(let contact):
                    result = try service.addContactCapture(
                        displayName: contact.displayName,
                        sourceText: contact.sourceText,
                        relationshipLabel: contact.relationship,
                        email: contact.email,
                        phone: contact.phone,
                        folderID: targetFolder?.id,
                        sourceContext: sourceContext
                    )
                case .journal(let raw):
                    let payload = try captureAddJournalPayload(rawContent: raw, args: args, storage: NotesStorage.shared)
                    if jsonOutput {
                        outputJSON(payload)
                    } else {
                        print("Captured journal entry: \(payload["date"] as? String ?? "")")
                        if let item = payload["item"] as? [String: Any],
                           let title = item["title"] as? String {
                            print("  Journal: \(title)")
                        }
                        print("  Next safe action: \(payload["nextSafeAction"] as? String ?? "inspect_item")")
                    }
                    return
                }
                let waitResult: BookmarkNativeCaptureWaitResult?
                if result.item.type == "bookmark", let timeout = bookmarkNativeCaptureWaitTimeout(from: args) {
                    waitResult = await waitForNativeBookmarkCapture(
                        result.item.id,
                        in: bookmarkService,
                        timeout: timeout
                    )
                } else {
                    waitResult = nil
                }
                let finalBookmark = waitResult?.bookmark
                    ?? bookmarkService.bookmarks.first(where: { $0.id == result.item.id })
                if jsonOutput {
                    var dict = result.toDictionary(finalBookmark: finalBookmark)
                    if let waitResult {
                        dict["nativeCaptureStatus"] = waitResult.timedOut ? "timedOut" : "settled"
                        dict["nativeCaptureElapsedSeconds"] = waitResult.elapsedSeconds
                        if let quality = dict["captureQuality"] as? [String: Any],
                           let qualityStatus = quality["semanticStatus"] as? String {
                            dict["nativeCaptureQualityStatus"] = qualityStatus
                        }
                    }
                    if let finalBookmark {
                        dict["bookmark"] = bookmarkToDict(finalBookmark)
                        dict["dateSuggestions"] = CiderBookmarkDateSuggestionService()
                            .suggestions(for: finalBookmark)
                            .map(bookmarkDateSuggestionToDict)
                    }
                    outputJSON(dict)
                } else {
                    let title = finalBookmark?.title ?? result.item.title
                    print("Captured: \(title) (\(result.item.id.uuidString.prefix(8)))")
                    print("  Type: \(result.item.type)")
                    print("  Source: \(result.source.kind)")
                    if let relativePath = finalBookmark?.relativePath ?? result.item.relativePath {
                        print("  Path: \(relativePath)")
                    }
                    print("  Duplicate: \(result.duplicate.status)")
                    print("  Enrichment: \(result.enrichment.status)")
                    if let waitResult {
                        print("  Native capture: \(waitResult.timedOut ? "timed out" : "settled") after \(String(format: "%.1f", waitResult.elapsedSeconds))s")
                    }
                    if let finalBookmark,
                       let quality = result.toDictionary(finalBookmark: finalBookmark)["captureQuality"] as? [String: Any],
                       let qualityStatus = quality["semanticStatus"] as? String {
                        print("  Visible quality: \(qualityStatus)")
                    }
                    print("  Review needed: \(result.routing.reviewNeeded)")
                    print("  Next safe action: \(result.nextSafeAction)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "archive-artifacts":
            do {
                let result = try archiveGeneratedArtifacts(args: args, bookmarkService: bookmarkService)
                if jsonOutput {
                    outputJSON(result)
                } else {
                    print("Archived artifacts: \(result["title"] as? String ?? "Generated artifact archive")")
                    print("  Source: \(result["sourcePath"] as? String ?? "")")
                    print("  Files: \(result["fileCount"] ?? 0)")
                    print("  Omitted: \(result["omittedArtifactCount"] ?? 0) files")
                    if let cleanup = result["cleanup"] as? [String: Any],
                       cleanup["performed"] as? Bool == true,
                       let trashPath = cleanup["trashPath"] as? String {
                        print("  Trashed: \(trashPath)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "review-queue", "worklist":
            do {
                let result = try CiderReviewQueueService().captureReviewWorklist(
                    limit: parseFlag("--limit", from: args).flatMap(Int.init) ?? 50,
                    includeDeferred: args.contains("--include-deferred")
                )
                if jsonOutput {
                    outputJSON(result.toDictionary())
                } else {
                    print("Capture review queue: \(result.totalCount) item(s) need attention.")
                    for item in result.items {
                        print("  [\(item.severity)] \(item.kind) \(item.ownerType):\(item.ownerID) - \(item.title)")
                        print("    \(item.reasonCodes.joined(separator: ", "))")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case nil, "help", "--help", "-h":
            printCaptureUsage()

        default:
            print("Unknown capture command: \(subcommand ?? "nil")")
            print("Commands: add, review-queue, archive-artifacts")
        }
    }

    static func isHelpRequested(in args: [String]) -> Bool {
        args.contains("help") || args.contains("--help") || args.contains("-h")
    }

    static func printCaptureUsage() {
        print("Usage: cider-cli capture add [--kind note|todo|bookmark|file|event|contact|journal] (--stdin|--text-file <text-file-path>|--content <text>|--url <url>|--path <source-file-path>|<url|text|file-path>) [--title <title>] [--date yyyy-MM-dd|today] [--time <time>] [--all-day] [--location <place>] [--details <text>] [--name <name>] [--relationship <text>] [--email <email>] [--phone <phone>] [--folder <target-folder-path>] [--surface <surface>] [--channel <channel>] [--message-id <id>] [--sender-id <id>] [--timeout <seconds>|--no-wait] [--json]")
        print("       cider-cli capture review-queue [--limit <n>] [--include-deferred] [--json]")
        print("       Example destination: --folder \"Inbox/Notes\". In capture add, --path is always a source file, not a destination.")
        print("       cider-cli capture archive-artifacts <path> [--title <title>] [--card <id>] [--commit <sha>] [--cleanup none|trash] [--large-threshold-bytes <bytes>] [--json]")
    }

    static func handleReview(subcommand: String?, args: [String], bookmarkService: VaultBookmarkService) async {
        let service = CiderReviewQueueService()

        switch subcommand {
        case "list", "ls":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 50
            do {
                let result = try service.list(
                    limit: limit,
                    includeDeferred: args.contains("--include-deferred"),
                    kind: parseFlag("--kind", from: args),
                    itemType: parseFlag("--item-type", from: args),
                    reviewState: parseFlag("--state", from: args),
                    requiredSafeAction: parseFlag("--safe-action", from: args)
                )
                printReviewQueueResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "summary":
            do {
                let result = try service.summary(
                    includeDeferred: args.contains("--include-deferred")
                )
                printReviewQueueSummaryResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "enrichment-diagnosis", "diagnose-enrichment", "diagnosis":
            do {
                let result = try service.enrichmentDiagnosis(
                    sampleLimit: parseFlag("--sample-limit", from: args).flatMap(Int.init)
                        ?? parseFlag("--limit", from: args).flatMap(Int.init)
                        ?? 10
                )
                printReviewEnrichmentDiagnosisResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "enrichment-reconcile-plan", "reconcile-enrichment", "enrichment-plan":
            do {
                let result = try service.enrichmentReconciliationPlan(
                    sampleLimit: parseFlag("--sample-limit", from: args).flatMap(Int.init)
                        ?? parseFlag("--limit", from: args).flatMap(Int.init)
                        ?? 10
                )
                printReviewEnrichmentReconciliationPlanResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "enrichment-reconcile-samples", "reconcile-enrichment-samples", "enrichment-samples":
            do {
                let result = try service.enrichmentReconciliationSamples(
                    groupID: parseFlag("--group", from: args),
                    limit: parseFlag("--limit", from: args).flatMap(Int.init)
                        ?? parseFlag("--sample-limit", from: args).flatMap(Int.init)
                        ?? 10
                )
                printReviewEnrichmentReconciliationSampleResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "enrichment-reconcile-apply", "reconcile-enrichment-apply", "enrichment-apply":
            do {
                let result = try service.applyEnrichmentReconciliation(
                    groupID: parseFlag("--group", from: args),
                    limit: parseFlag("--limit", from: args).flatMap(Int.init)
                        ?? parseFlag("--sample-limit", from: args).flatMap(Int.init)
                        ?? 10,
                    approvalToken: parseFlag("--approve", from: args),
                    execute: args.contains("--execute"),
                    actor: parseFlag("--actor", from: args) ?? "user"
                )
                printReviewEnrichmentReconciliationApplyResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "drilldown", "lane":
            guard let groupID = args.first else {
                printCLIError("Usage: cider-cli review drilldown <group-id> [--limit <n>] [--offset <n>] [--json]")
                return
            }
            do {
                let result = try service.drilldown(
                    groupID: groupID,
                    limit: parseFlag("--limit", from: args).flatMap(Int.init) ?? 50,
                    offset: parseFlag("--offset", from: args).flatMap(Int.init) ?? 0
                )
                printReviewQueueDrilldownResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "approve":
            guard let itemRef = firstPositionalArgument(from: args, valueFlags: ["--actor"]) else {
                printCLIError("Usage: cider-cli review approve <item-id> [--actor user|agent] [--json]")
                return
            }
            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let result = try service.approve(
                    itemID: itemID,
                    actor: parseFlag("--actor", from: args) ?? "user"
                )
                printReviewRoutingActionResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "correct":
            guard let itemRef = firstPositionalArgument(from: args, valueFlags: ["--folder", "--path", "--reason", "--actor"]) else {
                printCLIError("Usage: cider-cli review correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]")
                return
            }

            let target: CiderRoutingDecisionTarget
            if args.contains("--inbox") {
                target = CiderRoutingDecisionTarget(
                    kind: "inbox",
                    name: "Inbox/Bookmarks",
                    relativePath: "Inbox/Bookmarks",
                    folderID: nil
                )
            } else {
                switch resolveFolderArg(from: args) {
                case .unspecified:
                    printCLIError("review correct requires --folder, --path, or --inbox.")
                    return
                case .failed:
                    return
                case .resolved(let folder):
                    target = CiderRoutingDecisionTarget(
                        kind: "folder",
                        name: folder.name,
                        relativePath: folder.relativePath,
                        folderID: folder.id
                    )
                }
            }

            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let result = try service.correctBookmark(
                    itemID: itemID,
                    target: target,
                    reason: parseFlag("--reason", from: args) ?? "Corrected from review queue.",
                    actor: parseFlag("--actor", from: args) ?? "user",
                    bookmarkService: bookmarkService
                )
                printReviewRoutingActionResult(result)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "defer":
            guard let itemRef = args.first else {
                print("Error: Usage: cider-cli review defer <item-id> [--reason <text>] [--actor user|agent] [--json]")
                return
            }
            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let result = try service.deferReview(
                    itemID: itemID,
                    reason: parseFlag("--reason", from: args) ?? "Deferred from review queue.",
                    actor: parseFlag("--actor", from: args) ?? "user"
                )
                printReviewRoutingActionResult(result)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "enrich":
            guard let itemRef = args.first else {
                printCLIError("Usage: cider-cli review enrich <item-id> [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]")
                return
            }
            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let actor = parseFlag("--actor", from: args) ?? "user"
                let before = bookmarkService.bookmarks.first(where: { $0.id == itemID })
                let result: CiderReviewQueueActionResult
                do {
                    result = try service.enrich(itemID: itemID, actor: actor)
                } catch CiderReviewQueueActionError.noEnrichmentIssue {
                    guard let before else { throw CiderReviewQueueActionError.itemNotFound(itemID) }
                    bookmarkService.refetchMetadata(for: itemID)
                    result = CiderReviewQueueActionResult(
                        action: "review.enrich",
                        itemID: itemID,
                        itemType: "bookmark",
                        title: before.title,
                        status: "scheduled",
                        message: "Scheduled bookmark enrichment for an explicit bookmark refetch.",
                        actor: actor,
                        safeActions: ["review list", "item get"]
                    )
                }
                if let timeout = bookmarkNativeCaptureWaitTimeout(from: args) {
                    let waitResult = await waitForNativeBookmarkCapture(
                        itemID,
                        in: bookmarkService,
                        timeout: timeout
                    )
                    let after = waitResult.bookmark ?? bookmarkService.bookmarks.first(where: { $0.id == itemID })
                    printReviewEnrichmentLifecycleResult(
                        scheduledResult: result,
                        before: before,
                        after: after,
                        waitResult: waitResult,
                        reviewResolved: isReviewEnrichmentResolved(itemID)
                    )
                } else {
                    printReviewQueueActionResult(result)
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "enrich-batch":
            guard args.contains("--confirm") else {
                printCLIError("Usage: cider-cli review enrich-batch --confirm [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]")
                return
            }
            do {
                let candidates = try service.list(limit: Int.max).items.filter { item in
                    item.kind == "enrichment"
                        && item.itemType == "bookmark"
                        && item.safeActions.contains("enrich")
                }
                let result = try service.enrichBatch(
                    actor: parseFlag("--actor", from: args) ?? "user"
                )
                if let timeout = reviewBatchWaitTimeout(from: args) {
                    await recordReviewBatchEnrichmentResults(
                        result,
                        candidates: candidates,
                        actor: parseFlag("--actor", from: args) ?? "user",
                        timeout: timeout,
                        bookmarkService: bookmarkService
                    )
                }
                printReviewQueueBatchEnrichmentResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "jobs", "history":
            do {
                let result = try service.actionJobHistory(
                    limit: parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
                )
                printReviewActionJobHistoryResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case nil, "help", "--help", "-h":
            print("""
            Usage:
              cider-cli review list [--include-deferred] [--limit <n>] [--kind <kind>] [--item-type <type>] [--state <state>] [--safe-action <action>] [--json]
              cider-cli review summary [--include-deferred] [--json]
              cider-cli review enrichment-diagnosis [--sample-limit <n>] [--json]
              cider-cli review enrichment-reconcile-plan [--sample-limit <n>] [--json]
              cider-cli review enrichment-reconcile-samples [--group <group-id>] [--limit <n>] [--json]
              cider-cli review enrichment-reconcile-apply [--group <group-id>] [--limit <n>] [--approve <token>] [--actor user|agent] [--execute] [--json]
              cider-cli review drilldown <group-id> [--limit <n>] [--offset <n>] [--json]
              cider-cli review approve <item-id> [--actor user|agent] [--json]
              cider-cli review correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]
              cider-cli review defer <item-id> [--reason <text>] [--actor user|agent] [--json]
              cider-cli review enrich <item-id> [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]
              cider-cli review enrich-batch --confirm [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]
              cider-cli review jobs [--limit <n>] [--json]
            """)

        default:
            printCLIError("Unknown review command: \(subcommand ?? "nil"). Commands: list, summary, enrichment-diagnosis, enrichment-reconcile-plan, enrichment-reconcile-samples, enrichment-reconcile-apply, drilldown, approve, correct, defer, enrich, enrich-batch, jobs")
        }
    }

    static func handleSpace(subcommand: String?, args: [String]) {
        let storage = CiderSpaceStorage.shared

        switch subcommand {
        case "captures", "capture-dashboard":
            guard let spaceRef = firstPositionalArgument(from: args, valueFlags: ["--limit"]) else {
                printCLIError("Usage: cider-cli space captures <space-id|name> [--limit <n>] [--json]")
                return
            }
            guard let space = resolveSpace(spaceRef, storage: storage) else { return }
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 10
            do {
                let dashboard = try CiderSpaceCaptureDashboardService().dashboard(
                    for: space,
                    recentLimit: limit,
                    reviewLimit: limit
                )
                printSpaceCaptureDashboard(dashboard)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "items":
            guard let spaceRef = firstPositionalArgument(from: args) else {
                printCLIError("Usage: cider-cli space items <space-id|name> [--json]")
                return
            }
            guard let space = resolveSpace(spaceRef, storage: storage) else { return }
            do {
                let items = try CiderItemContextService(database: .shared).items(inSpaceID: space.id)
                if jsonOutput {
                    outputJSON([
                        "ok": true,
                        "space": spaceToDict(space),
                        "items": items.map(itemSummaryToDict),
                    ])
                } else if items.isEmpty {
                    print("No native membership items in Space \(space.name).")
                } else {
                    print("Space items: \(space.name) (\(items.count))")
                    for item in items {
                        let path = item.relativePath.map { " — \($0)" } ?? ""
                        print("  [\(item.type.rawValue):\(item.id.uuidString.prefix(8))] \(item.title)\(path)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "list", "ls":
            let spaces = storage.spaces.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if jsonOutput {
                outputJSON(spaces.map(spaceToDict))
            } else if spaces.isEmpty {
                print("No Spaces found.")
            } else {
                for space in spaces {
                    print("[\(space.id.prefix(8))] \(space.name) — \(space.rootRelativePath)")
                }
            }

        case "explain":
            guard let ref = args.first else {
                printCLIError("Usage: cider-cli space explain <name-or-id> [--json]")
                return
            }
            guard let space = resolveSpace(ref, storage: storage) else { return }
            var dict = spaceToDict(space)
            dict["loadIssues"] = storage.loadIssues
            if jsonOutput {
                outputJSON(dict)
            } else {
                print("\(space.name) (\(space.id))")
                print("Path: \(space.rootRelativePath)")
                print("Purpose: \(space.purpose)")
                if !space.routingHints.isEmpty {
                    print("Routing hints:")
                    for hint in space.routingHints {
                        print("  - \(hint)")
                    }
                }
                if !space.aiInstructions.isEmpty {
                    print("Agent instructions: \(space.aiInstructions)")
                }
            }

        case nil, "help", "--help", "-h":
            print("""
            Usage:
              cider-cli space list [--json]
              cider-cli space explain <name-or-id> [--json]
              cider-cli space captures <space-id|name> [--limit <n>] [--json]
              cider-cli space items <space-id|name> [--json]
            """)

        default:
            printCLIError("Unknown space command: \(subcommand ?? "nil"). Commands: list, explain, captures")
        }
    }

    static func handleRouting(subcommand: String?, args: [String], bookmarkService: VaultBookmarkService) {
        let service = CiderRoutingDecisionService()

        switch subcommand {
        case "explain":
            guard let itemRef = firstPositionalArgument(from: args) else {
                printCLIError("Usage: cider-cli routing explain <item-id> [--json]")
                return
            }
            do {
                let explanation = try service.explain(itemRef: itemRef)
                printRoutingExplanation(explanation)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "approve":
            guard let itemRef = args.first else {
                print("Error: Usage: cider-cli routing approve <item-id> [--actor user|agent] [--json]")
                return
            }
            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let explanation = try service.approve(itemID: itemID, actor: parseFlag("--actor", from: args) ?? "user")
                printRoutingExplanation(explanation)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "correct":
            guard let itemRef = firstPositionalArgument(from: args, valueFlags: ["--folder", "--path", "--reason", "--actor"]) else {
                printCLIError("Usage: cider-cli routing correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]")
                return
            }

            let target: CiderRoutingDecisionTarget
            if args.contains("--inbox") {
                target = CiderRoutingDecisionTarget(
                    kind: "inbox",
                    name: "Inbox/Bookmarks",
                    relativePath: "Inbox/Bookmarks",
                    folderID: nil
                )
            } else {
                switch resolveFolderArg(from: args) {
                case .unspecified:
                    printCLIError("routing correct requires --folder, --path, or --inbox.")
                    return
                case .failed:
                    return
                case .resolved(let folder):
                    target = CiderRoutingDecisionTarget(
                        kind: "folder",
                        name: folder.name,
                        relativePath: folder.relativePath,
                        folderID: folder.id
                    )
                }
            }

            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let explanation = try service.correctBookmark(
                    itemID: itemID,
                    target: target,
                    reason: parseFlag("--reason", from: args) ?? "Corrected route.",
                    actor: parseFlag("--actor", from: args) ?? "user",
                    bookmarkService: bookmarkService
                )
                printRoutingExplanation(explanation)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "rerun":
            guard let itemRef = args.first else {
                print("Error: Usage: cider-cli routing rerun <item-id> [--actor user|agent] [--json]")
                return
            }
            do {
                let itemID = try service.resolveItemID(ref: itemRef)
                let explanation = try service.rerunDeterministic(
                    itemID: itemID,
                    actor: parseFlag("--actor", from: args) ?? "agent"
                )
                printRoutingExplanation(explanation)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case nil, "help", "--help", "-h":
            print("""
            Usage:
              cider-cli routing explain <item-id> [--json]
              cider-cli routing approve <item-id> [--actor user|agent] [--json]
              cider-cli routing correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]
              cider-cli routing rerun <item-id> [--actor user|agent] [--json]
            """)

        default:
            printCLIError("Unknown routing command: \(subcommand ?? "nil"). Commands: explain, approve, correct, rerun")
        }
    }

    static func handleBookmark(subcommand: String?, args: [String], service: VaultBookmarkService) async {
        guard !printHiddenLegacyCommandIfRemoved(command: "bookmark", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "list", "ls":
            let folderName = parseFlag("--folder", from: args)
            let bookmarks: [Bookmark]
            if let folderName {
                let folder = findFolder(named: folderName)
                bookmarks = service.bookmarks.filter { $0.folderID == folder?.id }
            } else {
                bookmarks = service.bookmarks
            }
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? bookmarks.count
            if jsonOutput {
                outputJSON(Array(bookmarks.prefix(limit)).map(bookmarkToDict))
            } else {
                print("Bookmarks (\(bookmarks.count)):")
                for bm in bookmarks.prefix(limit) {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let manual = bm.titleManuallySet ? " 🔒" : ""
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title)\(manual) — \(bm.hostDisplay) (\(folder))")
                }
            }

        case "add", "create":
            guard let url = firstPositionalArgument(
                from: args,
                valueFlags: ["--title", "--folder", "--path", "--timeout", "--wait-timeout", "--capture-timeout"]
            ) else {
                printCLIError("URL required. Usage: cider-cli bookmark add <url> [--title <title>] [--folder <name|path>] [--path <target-folder-path>] [--timeout <seconds>|--no-wait] [--json]")
                return
            }
            // Resolve the destination folder BEFORE creating, so that a bad
            // --folder/--path doesn't leave an orphan bookmark in Inbox.
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }
            let title = parseFlag("--title", from: args)
            do {
                let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
                let result = try CiderBookmarkCaptureAdapter(bookmarkService: service, database: database).addURLBookmark(
                    urlString: url,
                    title: title,
                    folderID: targetFolder?.id
                )
                let bookmark = result.bookmark
                let waitResult: BookmarkNativeCaptureWaitResult?
                if let timeout = bookmarkNativeCaptureWaitTimeout(from: args) {
                    waitResult = await waitForNativeBookmarkCapture(
                        bookmark.id,
                        in: service,
                        timeout: timeout
                    )
                } else {
                    waitResult = nil
                }
                let finalBookmark = waitResult?.bookmark ?? service.bookmarks.first(where: { $0.id == bookmark.id }) ?? bookmark
                if jsonOutput {
                    var dict = bookmarkToDict(finalBookmark)
                    dict["command"] = "bookmark.add"
                    dict["compatibilityWrapper"] = true
                    dict["backendCommand"] = result.captureResult.command
                    dict["capture"] = result.captureResult.toDictionary(finalBookmark: finalBookmark)
                    if let waitResult {
                        dict["nativeCaptureStatus"] = waitResult.timedOut ? "timedOut" : "settled"
                        dict["nativeCaptureElapsedSeconds"] = waitResult.elapsedSeconds
                    }
                    outputJSON(dict)
                } else {
                    print("Created bookmark: \(finalBookmark.title) (\(finalBookmark.id.uuidString.prefix(8)))")
                    if let waitResult, waitResult.timedOut {
                        print("  Native capture: still running after \(Int(waitResult.elapsedSeconds.rounded()))s")
                    }
                }
            } catch {
                printCLIError("Could not create bookmark for URL: \(url)")
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                if jsonOutput {
                    outputJSON(bookmarkToDict(bm))
                } else {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("Bookmark: \(bm.title)")
                    print("  ID:        \(bm.id.uuidString)")
                    print("  URL:       \(bm.urlString)")
                    print("  Folder:    \(folder)")
                    print("  Tags:      \(bm.tags.isEmpty ? "(none)" : bm.tags.joined(separator: ", "))")
                    print("  Labels:    \(bm.labelIDs.count)")
                    print("  Notes:     \(bm.notes.isEmpty ? "(none)" : bm.notes)")
                    print("  Created:   \(bm.createdAt.formatted())")
                    print("  Updated:   \(bm.updatedAt.formatted())")
                    print("  Manual:    title=\(bm.titleManuallySet) notes=\(bm.notesManuallySet)")
                    if let ocr = bm.ocrText, !ocr.isEmpty { print("  OCR:       \(ocr.prefix(200))") }
                    if let colors = bm.dominantColors { print("  Colors:    \(colors.joined(separator: ", "))") }
                    if let summary = bm.aiSummary, !summary.isEmpty {
                        // Show aiSummary in full — this is where the agent writes
                        // its enrichment output and needs to be able to read it back.
                        print("  AI Summary:")
                        print(summary)
                    }
                }
            }

        case "search":
            let query = args.filter { $0 != "--json" }.joined(separator: " ")
            let results = service.bookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.urlString.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query) ||
                ($0.ocrText ?? "").localizedCaseInsensitiveContains(query)
            }
            if jsonOutput {
                outputJSON(results.map(bookmarkToDict))
            } else {
                print("Bookmark search '\(query)' (\(results.count)):")
                for bm in results {
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) — \(bm.urlString)")
                }
            }

        case "move":
            guard let firstArg = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark move <id>[,id,...] [--folder <name|path> | --path <target-folder-path>]")
                return
            }
            let prefixes = splitIDs(firstArg)
            let folder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: folder = nil
            case .resolved(let f): folder = f
            case .failed: return
            }
            let newFolderName = folder?.name ?? "Inbox"
            var moved = 0
            var misses: [String] = []
            for prefix in prefixes {
                guard let bm = service.bookmarks.first(where: { $0.id.uuidString.lowercased().hasPrefix(prefix.lowercased()) }) else {
                    misses.append(prefix)
                    continue
                }
                let oldFolder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let target: CiderRoutingDecisionTarget
                if let folder {
                    target = CiderRoutingDecisionTarget(
                        kind: "folder",
                        name: folder.name,
                        relativePath: folder.relativePath,
                        folderID: folder.id
                    )
                } else {
                    target = CiderRoutingDecisionTarget(
                        kind: "inbox",
                        name: "Inbox/Bookmarks",
                        relativePath: "Inbox/Bookmarks",
                        folderID: nil
                    )
                }
                do {
                    _ = try CiderRoutingDecisionService().moveBookmarkManually(
                        itemID: bm.id,
                        target: target,
                        reason: "Moved with bookmark move.",
                        actor: "user",
                        source: "bookmark.move",
                        bookmarkService: service
                    )
                    print("Moved '\(bm.title)' from \(oldFolder) → \(newFolderName)")
                    moved += 1
                } catch {
                    print("Error: Could not move '\(bm.title)': \(error.localizedDescription)")
                }
            }
            if prefixes.count > 1 {
                print("Total moved: \(moved)/\(prefixes.count)")
            }
            for miss in misses {
                print("Error: No bookmark found with ID prefix: \(miss)")
            }

        case "tag":
            guard let idPrefix = args.first, args.count > 1 else {
                printCLIError("Usage: cider-cli bookmark tag <id> <label-name>")
                return
            }
            let labelName = args.dropFirst().joined(separator: " ")
            if let bm = findBookmark(idPrefix, in: service) {
                let label = CardLabelStorage.shared.findOrCreate(name: labelName, colorHex: nil)
                if service.assignLabel(bm.id, labelID: label.id) {
                    print("Tagged '\(bm.title)' with '\(label.name)'")
                } else {
                    print("Error: Failed to tag '\(bm.title)' with '\(label.name)'")
                }
            }

        case "untag":
            guard let idPrefix = args.first, args.count > 1 else {
                print("Error: Usage: cider-cli bookmark untag <id> <label-name>")
                return
            }
            let labelName = args.dropFirst().joined(separator: " ")
            if let bm = findBookmark(idPrefix, in: service) {
                if let label = CardLabelStorage.shared.labels.first(where: { $0.name.localizedCaseInsensitiveCompare(labelName) == .orderedSame }) {
                    if service.removeLabel(bm.id, labelID: label.id) {
                        print("Removed tag '\(label.name)' from '\(bm.title)'")
                    } else {
                        print("Error: Failed to remove tag '\(label.name)' from '\(bm.title)'")
                    }
                } else {
                    print("Error: Label '\(labelName)' not found")
                }
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                print("About to delete bookmark:")
                print("  \(bm.title)")
                print("  URL: \(bm.urlString)")
                print("  Folder: \(folder)  Tags: [\(bm.tags.joined(separator: ", "))]  Labels: \(bm.labelIDs.count)")
                let items = service.removeAll([bm])
                if let item = items.first {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: item))
                    print("Deleted: \(bm.title) (moved to trash)")
                }
            }

        case "enrich":
            let replacement = args.contains("--all")
                ? "cider-cli review enrich-batch --confirm --json"
                : "cider-cli review enrich <item-id> --json"
            printRemovedLegacyCommand(
                command: args.contains("--all") ? "bookmark enrich --all" : "bookmark enrich",
                replacement: replacement,
                reason: "Bookmark enrichment now runs through the review-backed enrichment API."
            )

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark update <id> [--title <t>] [--notes <n>] [--url <u>] [--ai-summary <text>|--clear-ai-summary] [--enrichment-status none|partial|complete] [--media-type image|gif|video] [--hero-mode <mode>] [--reader-unavailable true|false]")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let newTitle = parseFlag("--title", from: args) ?? bm.title
                let newNotes = parseFlag("--notes", from: args) ?? bm.notes
                let newURL = parseFlag("--url", from: args)
                let newAISummary = parseFlag("--ai-summary", from: args)
                let clearAISummary = args.contains("--clear-ai-summary")
                if clearAISummary, newAISummary != nil {
                    print("Error: Use either --ai-summary <text> or --clear-ai-summary, not both.")
                    return
                }
                let newEnrichmentStatus = parseFlag("--enrichment-status", from: args)
                let updated = service.updateDetails(
                    for: bm.id,
                    title: newTitle,
                    notes: newNotes,
                    tags: bm.tags,
                    urlString: newURL
                )
                let enriched = service.updateEnrichment(
                    for: bm.id,
                    aiSummary: newAISummary,
                    clearAISummary: clearAISummary,
                    enrichmentStatus: newEnrichmentStatus
                )
                if let mt = parseFlag("--media-type", from: args),
                   let mediaType = BookmarkMediaType(rawValue: mt) {
                    service.setMediaType(mediaType, for: bm.id)
                }
                if let hm = parseFlag("--hero-mode", from: args) {
                    service.setPreferredHeroMode(hm, for: bm.id)
                }
                if let ru = parseFlag("--reader-unavailable", from: args) {
                    service.setReaderUnavailable(ru.lowercased() == "true", for: bm.id)
                }
                if updated || enriched
                    || parseFlag("--media-type", from: args) != nil
                    || parseFlag("--hero-mode", from: args) != nil
                    || parseFlag("--reader-unavailable", from: args) != nil {
                    print("Updated: \(newTitle) (\(bm.id.uuidString.prefix(8)))")
                } else {
                    print("No changes to apply")
                }
            }

        case "date-suggestions", "dates":
            if args.first == "approve" {
                let approvalArgs = Array(args.dropFirst())
                let approvalPositionals = approvalArgs.filter { !$0.hasPrefix("--") }
                guard let idPrefix = approvalPositionals.first else {
                    printCLIError("ID prefix required. Usage: cider-cli bookmark date-suggestions approve <id> [--index <n>|--key <suggestion-key>] [--json]")
                    return
                }
                let suggestionKey = parseFlag("--key", from: approvalArgs)
                    ?? parseFlag("--suggestion-key", from: approvalArgs)
                let suggestionIndex = parseFlag("--index", from: approvalArgs).flatMap(Int.init) ?? 0
                if suggestionKey == nil {
                    guard suggestionIndex >= 0 else {
                        printCLIError("--index must be 0 or greater")
                        return
                    }
                }
                guard let bm = findBookmark(idPrefix, in: service) else { return }
                do {
                    let approvalService = CiderBookmarkDateSuggestionApprovalService()
                    let result: CiderBookmarkDateSuggestionApprovalResult
                    if let suggestionKey {
                        result = try approvalService.approve(bookmarkID: bm.id, suggestionKey: suggestionKey)
                    } else {
                        result = try approvalService.approve(
                            bookmarkID: bm.id,
                            suggestionIndex: suggestionIndex
                        )
                    }
                    if jsonOutput {
                        outputJSON(bookmarkDateSuggestionApprovalResultToDict(result))
                    } else {
                        let action = result.created ? "Created" : "Reused"
                        if let todo = result.todo {
                            print("\(action) todo: \(todo.title) (\(todo.id.uuidString.prefix(8)))")
                        } else if let dateCard = result.dateCard {
                            print("\(action) date card: \(dateCard.title) (\(dateCard.id.uuidString.prefix(8)))")
                        }
                        print("  Date suggestion: \(result.suggestion.kind)")
                        print("  Source bookmark: \(result.bookmarkTitle) (\(result.bookmarkID.uuidString.prefix(8)))")
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }

            let dateSuggestionPositionals = args.filter { !$0.hasPrefix("--") }
            guard let idPrefix = dateSuggestionPositionals.first else {
                printCLIError("ID prefix required. Usage: cider-cli bookmark date-suggestions <id> [--json]")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let result = CiderBookmarkDateSuggestionService().result(for: bm)
                if jsonOutput {
                    outputJSON(bookmarkDateSuggestionResultToDict(result))
                } else {
                    print("Date suggestions for '\(bm.title)' (\(result.suggestions.count)):")
                    if result.suggestions.isEmpty {
                        print("  No clear date suggestions.")
                    } else {
                        bookmarkDateSuggestionHumanLines(result: result).forEach { print($0) }
                    }
                }
            }

        case "carousel-add":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli bookmark carousel-add <id> <image-path>")
                return
            }
            guard let bookmark = findBookmark(idPrefix, in: service) else { return }
            guard args.count > 1 else {
                print("Error: Image path required")
                return
            }
            let imagePath = NSString(string: args[1]).expandingTildeInPath
            let imageURL = URL(fileURLWithPath: imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                print("Error: File not found: \(imageURL.path)")
                return
            }
            guard let data = try? Data(contentsOf: imageURL) else {
                print("Error: Could not read file: \(imageURL.path)")
                return
            }
            let ext = imageURL.pathExtension.isEmpty ? nil : imageURL.pathExtension
            if service.addCarouselImage(for: bookmark.id, imageData: data, preferredFileExtension: ext) {
                print("Added carousel image to '\(bookmark.title)' from \(imageURL.lastPathComponent)")
            } else {
                print("Error: Failed to add carousel image")
            }

        case "carousel-remove":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli bookmark carousel-remove <id> --index <n>")
                return
            }
            guard let bookmark = findBookmark(idPrefix, in: service) else { return }
            guard let idxStr = parseFlag("--index", from: args), let idx = Int(idxStr) else {
                print("Error: --index <n> required")
                return
            }
            if service.removeCarouselImage(for: bookmark.id, at: idx) {
                print("Removed carousel image at index \(idx) from '\(bookmark.title)'")
            } else {
                print("Error: Failed to remove carousel image (index out of range?)")
            }

        case "carousel-reorder":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli bookmark carousel-reorder <id> --from <n> --to <n>")
                return
            }
            guard let bookmark = findBookmark(idPrefix, in: service) else { return }
            guard let fromStr = parseFlag("--from", from: args), let fromIdx = Int(fromStr) else {
                print("Error: --from <n> required")
                return
            }
            guard let toStr = parseFlag("--to", from: args), let toIdx = Int(toStr) else {
                print("Error: --to <n> required")
                return
            }
            if service.reorderCarouselImages(for: bookmark.id, fromIndex: fromIdx, toIndex: toIdx) {
                print("Reordered carousel image \(fromIdx) → \(toIdx) for '\(bookmark.title)'")
            } else {
                print("Error: Failed to reorder carousel images")
            }

        case "similar":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli bookmark similar <id> [--limit <n>]")
                return
            }
            guard let bookmark = findBookmark(idPrefix, in: service) else { return }
            let limitStr = parseFlag("--limit", from: args)
            let limit = limitStr.flatMap(Int.init) ?? 5
            let store = EmbeddingStore.shared
            store.load()
            guard store.vector(for: bookmark.id) != nil else {
                print("No embedding found for '\(bookmark.title)'. Run 'review enrich \(bookmark.id.uuidString) --json' first.")
                return
            }
            let similarIDs = SimilarItemsService.findSimilar(to: bookmark.id, in: store, limit: limit)
            if similarIDs.isEmpty {
                print("No similar items found for '\(bookmark.title)'")
                return
            }
            let similarBookmarks = similarIDs.compactMap { id in service.bookmarks.first(where: { $0.id == id }) }
            if jsonOutput {
                outputJSON(similarBookmarks.map(bookmarkToDict))
            } else {
                print("Similar to '\(bookmark.title)' (\(similarBookmarks.count)):")
                for bm in similarBookmarks {
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title)")
                }
            }

        default:
            printCLIError("Unknown bookmark command: \(subcommand ?? "nil"). Commands: list, add, get, search, move, tag, untag, delete, enrich, update, date-suggestions, similar, carousel-add, carousel-remove, carousel-reorder")
        }
    }

    static func bookmarkDateSuggestionHumanLines(result: CiderBookmarkDateSuggestionResult) -> [String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return result.suggestions.enumerated().flatMap { index, suggestion in
            [
                "  [\(index)] \(suggestion.kind): \(formatter.string(from: suggestion.date))",
                "    Confidence: \(String(format: "%.2f", suggestion.confidence))",
                "    Source: \(suggestion.sourceField) - \(suggestion.sourceSnippet)",
                "    Key: \(suggestion.suggestionKey)",
                "    Next safe action: \(suggestion.nextSafeAction)",
            ]
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Note Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleNote(subcommand: String?, args: [String], storage: NotesStorage) async {
        guard !printHiddenLegacyCommandIfRemoved(command: "note", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "list", "ls":
            let folderName = parseFlag("--folder", from: args)
            let notes: [Note]
            if let folderName {
                let folder = findFolder(named: folderName)
                notes = storage.notes.filter { $0.folderID == folder?.id }
            } else {
                notes = storage.notes
            }
            if jsonOutput {
                outputJSON(notes.map(noteToDict))
            } else {
                print("Notes (\(notes.count)):")
                for note in notes {
                    let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let pinned = note.isPinned ? " 📌" : ""
                    print("  [\(note.id.uuidString.prefix(8))] \(note.title)\(pinned) (\(folder))")
                }
            }

        case "create":
            // Resolve target folder BEFORE creating to avoid orphaning a note
            // in Inbox when --folder/--path was given but didn't resolve.
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }
            let title = args.first ?? "Untitled"
            let content = (parseFlag("--content", from: args) ?? "")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
            do {
                let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
                let result = try CiderCaptureService(notesStorage: storage, database: database).addNoteCapture(
                    title: title,
                    content: content,
                    folderID: targetFolder?.id
                )
                let note = storage.notes.first(where: { $0.id == result.item.id })
                if jsonOutput, let note {
                    var dict = noteToDict(note)
                    dict["content"] = storage.loadContent(for: note)
                    dict["command"] = "note.create"
                    dict["compatibilityWrapper"] = true
                    dict["backendCommand"] = result.command
                    dict["capture"] = result.toDictionary()
                    outputJSON(dict)
                } else {
                    print("Created note: \(result.item.title) (\(result.item.id.uuidString.prefix(8)))")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "project-artifact", "artifact":
            handleProjectArtifactNoteCommand(args: args, storage: storage)

        case "daily":
            handleDailyNoteCommand(args: args, storage: storage)

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                let content = storage.loadContent(for: note)
                if jsonOutput {
                    var dict = noteToDict(note)
                    dict["content"] = content
                    outputJSON(dict)
                } else {
                    let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("Note: \(note.title)")
                    print("  ID:      \(note.id.uuidString)")
                    print("  Folder:  \(folder)")
                    print("  Pinned:  \(note.isPinned)")
                    print("  Tags:    \(note.tags.isEmpty ? "(none)" : note.tags.joined(separator: ", "))")
                    print("  Labels:  \(note.labelIDs.count)")
                    print("  Created: \(note.createdAt.formatted())")
                    print("  Path:    \(note.relativePath)")
                    print("  Content:")
                    print(content.isEmpty ? "(empty)" : content)
                }
            }

        case "pin":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                storage.togglePin(note.id)
                let state = storage.notes.first(where: { $0.id == note.id })?.isPinned ?? false
                print("\(state ? "Pinned" : "Unpinned"): \(note.title)")
            }

        case "move":
            guard let firstArg = args.first else {
                print("Error: ID prefix required. Usage: cider-cli note move <id>[,id,...] [--folder <name|path> | --path <target-folder-path>]")
                return
            }
            let prefixes = splitIDs(firstArg)
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }
            let targetName = targetFolder?.name ?? "Inbox"
            var moved = 0
            var misses: [String] = []
            for prefix in prefixes {
                guard let note = storage.notes.first(where: { $0.id.uuidString.lowercased().hasPrefix(prefix.lowercased()) }) else {
                    misses.append(prefix)
                    continue
                }
                let didMove = storage.assignNote(note.id, toFolder: targetFolder?.id)
                guard didMove else {
                    print("Error: Failed to move note '\(note.title)'")
                    continue
                }
                _ = try? CiderRoutingDecisionService().recordManualMove(
                    itemID: note.id,
                    target: routingTarget(for: targetFolder, inboxPath: "Inbox/Notes"),
                    reason: "Moved with note move.",
                    actor: "user",
                    source: "note.move"
                )
                print("Moved '\(note.title)' → \(targetName)")
                moved += 1
            }
            if prefixes.count > 1 {
                print("Total moved: \(moved)/\(prefixes.count)")
            }
            for miss in misses {
                print("Error: No note found with ID prefix: \(miss)")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                print("About to delete note:")
                print("  \(note.title)")
                print("  Path: \(note.relativePath)")
                print("  Folder: \(folder)  Tags: [\(note.tags.joined(separator: ", "))]  Labels: \(note.labelIDs.count)")
                let trashItem = storage.delete(note: note)
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .note, trashItem: trashItem))
                print("Deleted: \(note.title) (moved to trash)")
            }

        case "update", "rename":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli note update <id> [--title <title>] [--content <content>]")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                var changed = false
                if let newTitle = parseFlag("--title", from: args) {
                    storage.rename(note: note, to: newTitle)
                    print("Renamed: '\(note.title)' → '\(newTitle)'")
                    changed = true
                }
                if let rawContent = parseFlag("--content", from: args) {
                    let newContent = rawContent
                        .replacingOccurrences(of: "\\n", with: "\n")
                        .replacingOccurrences(of: "\\t", with: "\t")
                    // Get current note (may have been renamed above), update content, save
                    let current = storage.notes.first(where: { $0.id == note.id }) ?? note
                    var updated = current
                    updated.content = newContent
                    storage.save(note: updated)
                    print("Updated content for: \(current.title)")
                    changed = true
                }
                if !changed {
                    print("No changes specified. Use --title or --content")
                }
            }

        case "tag":
            guard let idPrefix = firstPositionalArgument(from: args, valueFlags: ["--tag"]) else {
                printCLIError("Usage: cider-cli note tag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                printCLIError("At least one --tag <name> is required")
                return
            }
            var added = 0
            for name in tagNames where storage.addTag(note.id, tag: name) {
                added += 1
            }
            let current = storage.notes.first(where: { $0.id == note.id })?.tags ?? []
            print("Tagged '\(note.title)' with \(tagNames.joined(separator: ", ")) — now: [\(current.joined(separator: ", "))]")

        case "untag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli note untag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            var removed = 0
            for name in tagNames where storage.removeTag(note.id, tag: name) {
                removed += 1
            }
            let current = storage.notes.first(where: { $0.id == note.id })?.tags ?? []
            print("Removed \(removed) tag(s) from '\(note.title)' — now: [\(current.joined(separator: ", "))]")

        case "snapshots":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli note snapshots <id>")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            let snaps = storage.snapshots(for: note)
            if jsonOutput {
                let dicts: [[String: Any]] = snaps.enumerated().map { idx, snap in
                    [
                        "index": idx,
                        "date": ISO8601DateFormatter().string(from: snap.modifiedAt),
                        "path": snap.url.path,
                    ]
                }
                outputJSON(["noteID": note.id.uuidString, "title": note.title, "snapshots": dicts])
            } else {
                if snaps.isEmpty {
                    print("No snapshots for: \(note.title)")
                } else {
                    print("Snapshots for '\(note.title)' (\(snaps.count)):")
                    for (idx, snap) in snaps.enumerated() {
                        print("  [\(idx)] \(snap.modifiedAt.formatted())")
                    }
                }
            }

        case "restore-snapshot":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli note restore-snapshot <id> --at <index>")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            guard let atStr = parseFlag("--at", from: args), let idx = Int(atStr) else {
                print("Error: --at <index> required (use 'note snapshots <id>' to list)")
                return
            }
            let snaps = storage.snapshots(for: note)
            guard idx >= 0, idx < snaps.count else {
                print("Error: Index \(idx) out of range (0..\(snaps.count - 1))")
                return
            }
            guard let content = storage.loadSnapshotContent(at: snaps[idx].url) else {
                print("Error: Could not read snapshot content")
                return
            }
            var updated = note
            updated.content = content
            storage.save(note: updated)
            print("Restored '\(note.title)' to snapshot [\(idx)] from \(snaps[idx].modifiedAt.formatted())")

        case "attach-image":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli note attach-image <id> <image-path>")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            guard args.count > 1 else {
                print("Error: Image path required. Usage: cider-cli note attach-image <id> <image-path>")
                return
            }
            let imagePath = NSString(string: args[1]).expandingTildeInPath
            let imageURL = URL(fileURLWithPath: imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                print("Error: File not found: \(imageURL.path)")
                return
            }
            guard let data = try? Data(contentsOf: imageURL) else {
                print("Error: Could not read file: \(imageURL.path)")
                return
            }
            let filename = imageURL.lastPathComponent
            let savedURL = storage.saveImage(data: data, filename: filename, for: note)
            print("Attached '\(filename)' to '\(note.title)' → \(savedURL.path)")

        default:
            printCLIError("Unknown note command: \(subcommand ?? "nil"). Commands: list, create, daily, get, pin, move, delete, update, tag, untag, snapshots, restore-snapshot, attach-image")
        }
    }

    static func handleDailyNoteCommand(args: [String], storage: NotesStorage) {
        let subcommand = args.first
        let rest = Array(args.dropFirst())
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Daily note commands:
              cider-cli note daily append --kind journal|food-log [--date YYYY-MM-DD|today] [--time HH:mm] (--stdin|--text-file <path>|--content <text>) [--source <source>] [--json]
            """)

        case "append":
            guard let spec = dailyNoteKindSpec(parseFlag("--kind", from: rest) ?? "journal") else {
                printCLIError("Usage: cider-cli note daily append --kind journal|food-log [--date YYYY-MM-DD|today] [--time HH:mm] (--stdin|--text-file <path>|--content <text>) [--source <source>] [--json]")
                return
            }
            guard let rawContent = projectArtifactContent(from: rest) else { return }
            do {
                let result = try appendDailyNoteEntry(
                    spec: spec,
                    dateRaw: parseFlag("--date", from: rest),
                    timeRaw: parseFlag("--time", from: rest),
                    rawContent: rawContent,
                    source: parseFlag("--source", from: rest) ?? "cider-cli",
                    storage: storage,
                    emptyContentMessage: "Daily append content cannot be empty."
                )
                if jsonOutput {
                    outputJSON(dailyNoteAppendPayload(result))
                } else {
                    print("Appended \(result.spec.kind) entry to \(result.note.title) (\(result.note.id.uuidString.prefix(8)))")
                    print("  Path: \(result.note.relativePath)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        default:
            printCLIError("Unknown daily note command: \(subcommand ?? "nil"). Commands: append")
        }
    }

    struct DailyNoteAppendResult {
        let spec: DailyNoteKindSpec
        let date: String
        let time: String
        let created: Bool
        let note: Note
        let content: String
        let appendedEntry: String
        let rawContent: String
        let source: String
    }

    static func captureAddJournalPayload(rawContent: String, args: [String], storage: NotesStorage) throws -> [String: Any] {
        let result = try appendDailyNoteEntry(
            spec: DailyNoteKindSpec(kind: "journal", titlePrefix: "Daily Journal"),
            dateRaw: parseFlag("--date", from: args),
            timeRaw: parseFlag("--time", from: args),
            rawContent: rawContent,
            source: parseFlag("--source", from: args) ?? "capture.add",
            storage: storage,
            emptyContentMessage: "Journal capture content cannot be empty."
        )
        let sourceContext = captureSourceContext(from: args, originalText: result.rawContent)
        let provenance = recordJournalCaptureProvenance(result, sourceContext: sourceContext)
        return journalCapturePayload(result, args: args, sourceContext: sourceContext, provenance: provenance)
    }

    static func appendDailyNoteEntry(
        spec: DailyNoteKindSpec,
        dateRaw: String?,
        timeRaw: String?,
        rawContent: String,
        source: String,
        storage: NotesStorage,
        emptyContentMessage: String
    ) throws -> DailyNoteAppendResult {
        let dateString = try resolveDailyNoteDateString(dateRaw)
        let timeString = timeRaw ?? twentyFourHourTimeFormatter.string(from: Date())
        guard isValidClockTimeString(timeString) else {
            throw CaptureAddArgumentError.message("--time must be HH:mm")
        }
        let body = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw CaptureAddArgumentError.message(emptyContentMessage)
        }

        let title = "\(spec.titlePrefix) \(dateString)"
        let existing = storage.notes.first { note in
            note.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
        let created = existing == nil
        let note: Note
        if let existing {
            note = existing
        } else {
            let createdNote = storage.createNew(initialContent: dailyNoteSeedContent(title: title))
            storage.rename(note: createdNote, to: title)
            note = storage.notes.first(where: { $0.id == createdNote.id }) ?? createdNote
        }
        let before = MutationAuditSnapshots.note(note)
        let existingContent = storage.loadContent(for: note)
        let entry = "- \(timeString) - \(body)"
        var updated = note
        updated.content = dailyNoteContentByAppending(entry: entry, to: existingContent, title: title)
        storage.save(note: updated)
        let current = storage.notes.first(where: { $0.id == note.id }) ?? updated
        let content = storage.loadContent(for: current)
        MutationAuditService.shared.record(
            action: "daily_append",
            itemType: "note",
            itemID: current.id,
            before: before,
            after: MutationAuditSnapshots.note(current),
            metadata: [
                "kind": spec.kind,
                "date": dateString,
                "time": timeString,
                "source": source,
            ]
        )

        return DailyNoteAppendResult(
            spec: spec,
            date: dateString,
            time: timeString,
            created: created,
            note: current,
            content: content,
            appendedEntry: entry,
            rawContent: rawContent,
            source: source
        )
    }

    static func resolveDailyNoteDateString(_ raw: String?) throws -> String {
        guard let raw else { return localDateFormatter.string(from: Date()) }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if normalized == "today" {
            return localDateFormatter.string(from: Date())
        }
        guard isValidLocalDateString(raw) else {
            throw CaptureAddArgumentError.message("--date must be YYYY-MM-DD or today")
        }
        return raw
    }

    static func dailyNoteAppendPayload(_ result: DailyNoteAppendResult) -> [String: Any] {
        [
            "ok": true,
            "command": "note.daily.append",
            "kind": result.spec.kind,
            "date": result.date,
            "time": result.time,
            "created": result.created,
            "note": noteToDict(result.note),
            "content": result.content,
            "appendedEntry": result.appendedEntry,
            "sourceContext": [
                "source": result.source,
                "kind": result.spec.kind,
                "date": result.date,
                "time": result.time,
            ],
            "indexing": [
                "status": "indexed",
                "ownerType": "note",
                "ownerID": result.note.id.uuidString,
            ],
            "safeNextCommands": [
                "cider-cli item get note \(result.note.id.uuidString) --json",
                "cider-cli item context note \(result.note.id.uuidString) --json",
            ],
        ] as [String: Any]
    }

    static func recordJournalCaptureProvenance(
        _ result: DailyNoteAppendResult,
        sourceContext: CaptureSourceContext?
    ) -> [String: Any] {
        guard CiderDatabase.shared.isOpen else {
            return [
                "status": "unavailable",
                "ownerType": "capture_event",
                "ownerID": NSNull(),
                "captureEventID": NSNull(),
                "reason": "Capture provenance could not be recorded because no writable database is available.",
                "auditAction": "daily_append",
            ] as [String: Any]
        }

        let eventID = UUID()
        let database = CiderDatabase.shared
        var metadata = sourceContext?.metadata ?? [:]
        metadata["command"] = "capture.add"
        metadata["kind"] = "journal"
        metadata["date"] = result.date
        metadata["time"] = result.time
        let encodedMetadata = DatabaseHelpers.encodeJSON(metadata) ?? "{}"

        do {
            try database.withTransaction {
                let stmt = try database.prepare("""
                    INSERT INTO capture_events (
                        id, source_kind, surface, channel, channel_id, thread_id, message_id,
                        sender_id, sender_name, source_url, source_file, source_text,
                        attachment_count, metadata, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """)
                stmt.bind(eventID.uuidString, at: 1)
                    .bind("journal", at: 2)
                    .bind(sourceContext?.surface, at: 3)
                    .bind(sourceContext?.channel, at: 4)
                    .bind(sourceContext?.channelID, at: 5)
                    .bind(sourceContext?.threadID, at: 6)
                    .bind(sourceContext?.messageID, at: 7)
                    .bind(sourceContext?.senderID, at: 8)
                    .bind(sourceContext?.senderName, at: 9)
                    .bind(nil as String?, at: 10)
                    .bind(nil as String?, at: 11)
                    .bind(sourceContext?.originalText ?? result.rawContent, at: 12)
                    .bind(sourceContext?.attachments.count ?? 0, at: 13)
                    .bind(encodedMetadata, at: 14)
                    .bind(DatabaseHelpers.encode(Date()), at: 15)
                try stmt.step()

                let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
                let itemOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: result.note.id.uuidString)
                try SecondBrainStore(database: database).recordRelation(SecondBrainRelation(
                    sourceOwner: captureOwner,
                    targetOwner: itemOwner,
                    relationType: "produced_item",
                    evidence: "Journal capture appended to \(result.note.title).",
                    source: "capture.add",
                    actor: "system",
                    confidence: 1,
                    metadata: metadata
                ))
            }

            return [
                "status": "recorded",
                "ownerType": "capture_event",
                "ownerID": eventID.uuidString,
                "captureEventID": eventID.uuidString,
                "auditAction": "daily_append",
            ] as [String: Any]
        } catch {
            return [
                "status": "failed",
                "ownerType": "capture_event",
                "ownerID": NSNull(),
                "captureEventID": NSNull(),
                "reason": "Capture provenance failed: \(error.localizedDescription)",
                "auditAction": "daily_append",
            ] as [String: Any]
        }
    }

    static func journalCapturePayload(
        _ result: DailyNoteAppendResult,
        args: [String],
        sourceContext: CaptureSourceContext?,
        provenance: [String: Any]
    ) -> [String: Any] {
        let item: [String: Any] = [
            "id": result.note.id.uuidString,
            "type": "note",
            "title": result.note.title,
            "folderName": result.note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
            "folderID": result.note.folderID?.uuidString as Any,
            "relativePath": result.note.relativePath,
        ]
        var payload: [String: Any] = [
            "ok": true,
            "changed": true,
            "readOnly": false,
            "command": "capture.add",
            "kind": "journal",
            "captureKind": "journal",
            "date": result.date,
            "time": result.time,
            "created": result.created,
            "source": [
                "kind": "text",
                "itemID": result.note.id.uuidString,
                "itemType": "note",
                "text": result.rawContent,
            ],
            "item": item,
            "note": noteToDict(result.note),
            "content": result.content,
            "appendedEntry": result.appendedEntry,
            "destination": [
                "kind": "daily_note",
                "relativePath": result.note.relativePath,
                "title": result.note.title,
            ],
            "enrichment": [
                "status": "not_applicable",
                "isEnriching": false,
                "titleState": "daily_journal",
            ],
            "duplicate": [
                "status": "not_checked",
            ],
            "routing": [
                "reviewNeeded": false,
                "confidence": 1,
                "reason": "Daily journal append does not require folder routing review.",
                "reviewState": "ok",
                "status": "recorded",
            ],
            "provenance": provenance,
            "indexing": [
                "status": "indexed",
                "ownerType": "note",
                "ownerID": result.note.id.uuidString,
            ],
            "nextSafeAction": "inspect_item",
            "safeNextCommands": [
                "cider-cli item get note \(result.note.id.uuidString) --json",
                "cider-cli item context note \(result.note.id.uuidString) --json",
            ],
        ] as [String: Any]
        if let sourceContext {
            payload["sourceContext"] = sourceContext.toDictionary()
        }
        return payload
    }

    struct DailyNoteKindSpec {
        let kind: String
        let titlePrefix: String
    }

    static func dailyNoteKindSpec(_ raw: String) -> DailyNoteKindSpec? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            .replacingOccurrences(of: "_", with: "-") {
        case "journal", "daily", "daily-journal":
            return DailyNoteKindSpec(kind: "journal", titlePrefix: "Daily Journal")
        case "food", "food-log":
            return DailyNoteKindSpec(kind: "food-log", titlePrefix: "Food Log")
        default:
            return nil
        }
    }

    static func dailyNoteSeedContent(title: String) -> String {
        "# \(title)\n\n## Entries"
    }

    static func dailyNoteContentByAppending(entry: String, to existing: String, title: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? dailyNoteSeedContent(title: title) : trimmed
        return "\(base)\n\(entry)"
    }

    static func isValidLocalDateString(_ value: String) -> Bool {
        localDateFormatter.date(from: value).map { localDateFormatter.string(from: $0) == value } ?? false
    }

    static func isValidClockTimeString(_ value: String) -> Bool {
        twentyFourHourTimeFormatter.date(from: value).map { twentyFourHourTimeFormatter.string(from: $0) == value } ?? false
    }

    static func handleProjectArtifactNoteCommand(args: [String], storage: NotesStorage) {
        let subcommand = args.first
        let rest = Array(args.dropFirst())
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Project artifact note commands:
              cider-cli note project-artifact create --project <project-id-or-name> --type note|plan|handoff|decision|qa --title <title> (--stdin|--text-file <path>|--content <text>) [--card <id>] [--card-id <id>] [--decided-from-card <id>] [--decided-from-note <id>] [--source-card <id>] [--source-note <id>] [--validates-card <id>] [--validates-note <id>] [--found-bug-in-card <id>] [--found-bug-in-note <id>] [--json]
              cider-cli note project-artifact link <note-id-prefix> --card <id|display-key|board/card> [--board <board>] [--relation documents|validates|found-bug-in|decided-from] [--json]
              cider-cli note project-artifact append <note-id-prefix> (--stdin|--text-file <path>|--content <text>) [--json]
              cider-cli note project-artifact list --project <project-id-or-name> [--type note|plan|handoff|decision|decisions|qa|audit|qa-audits|plans-handoffs] [--json]
              cider-cli note project-artifact get <note-id-prefix> [--json]
            """)

        case "create":
            guard let project = parseFlag("--project", from: rest) ?? parseFlag("--project-id", from: rest) else {
                printCLIError("Usage: cider-cli note project-artifact create --project <project-id-or-name> --type <type> --title <title> (--stdin|--text-file <path>|--content <text>) [--card <id>] [--decided-from-card <id>] [--validates-card <id>] [--found-bug-in-card <id>] [--json]")
                return
            }
            let type = parseFlag("--type", from: rest) ?? parseFlag("--artifact-type", from: rest) ?? "handoff"
            let title = parseFlag("--title", from: rest)
                ?? firstPositionalArgument(from: rest, valueFlags: projectArtifactValueFlags)
                ?? "Untitled Project Artifact"
            guard let content = projectArtifactContent(from: rest) else { return }
            let note = storage.createProjectNote(
                projectID: project,
                title: title,
                content: content,
                artifactType: type
            )
            let linkedRelations = recordProjectArtifactRelations(note: note, args: rest)
            if jsonOutput {
                var dict = noteToDict(note)
                dict["ok"] = true
                dict["command"] = "note.project-artifact.create"
                dict["content"] = storage.loadContent(for: note)
                dict["linkedRelations"] = linkedRelations.map(relationToDict)
                dict["linkedCards"] = linkedRelations
                    .filter { $0.targetOwner.ownerType == "kanban_card" }
                    .map { ownerToDict($0.targetOwner) }
                outputJSON(dict)
            } else {
                print("Created project \(note.artifactType ?? "artifact"): \(note.title) (\(note.id.uuidString.prefix(8)))")
                print("  Path: \(note.relativePath)")
                if !linkedRelations.isEmpty {
                    print("  Linked relations: \(linkedRelations.map { "\(ProjectArtifactRelationType.displayName(for: $0.relationType)): \($0.targetOwner.canonicalRef)" }.joined(separator: ", "))")
                }
            }

        case "link":
            let positional = leadingPositionalArgs(from: rest)
            guard let idPrefix = positional.first,
                  let note = findNote(idPrefix, in: storage),
                  let cardRef = parseFlag("--card", from: rest) ?? parseFlag("--card-id", from: rest) else {
                printCLIError("Usage: cider-cli note project-artifact link <note-id-prefix> --card <id|display-key|board/card> [--board <board>] [--relation documents|validates|found-bug-in|decided-from] [--json]")
                return
            }
            guard let resolvedCard = resolveKanbanCardRef(cardRef, boardRef: parseFlag("--board", from: rest)) else { return }
            guard let relationType = parseProjectArtifactRelationType(parseFlag("--relation", from: rest) ?? "documents") else { return }
            let target = ProjectArtifactRelationService.ArtifactRelationTarget(
                owner: SecondBrainKanbanProjectionService.owner(boardID: resolvedCard.board.id, cardID: resolvedCard.card.id),
                relationType: relationType,
                title: resolvedCard.card.title,
                evidence: "Project artifact \(note.title) \(ProjectArtifactRelationType.displayName(for: relationType)) Kanban card \(resolvedCard.card.title) [\(resolvedCard.card.id)]."
            )
            let linkedRelations = ProjectArtifactRelationService.recordArtifactRelations(
                note: note,
                targets: [target],
                actor: parseFlag("--source-agent", from: rest) ?? "cider-cli",
                source: ProjectArtifactRelationService.cliSource
            )
            guard let relation = linkedRelations.first else {
                printCLIError("Could not record artifact relation.")
                return
            }
            if jsonOutput {
                outputJSON([
                    "ok": true,
                    "command": "note.project-artifact.link",
                    "artifact": noteToDict(note),
                    "target": [
                        "board": ["id": resolvedCard.board.id, "name": resolvedCard.board.name],
                        "card": boardCardSummaryToDict(board: resolvedCard.board, card: resolvedCard.card),
                    ],
                    "relation": relationToDict(relation),
                ])
            } else {
                print("Linked project artifact '\(note.title)' to card \(resolvedCard.board.displayKey(for: resolvedCard.card))")
            }

        case "append":
            let positional = leadingPositionalArgs(from: rest)
            guard let idPrefix = positional.first, let note = findNote(idPrefix, in: storage) else {
                printCLIError("Usage: cider-cli note project-artifact append <note-id-prefix> (--stdin|--text-file <path>|--content <text>) [--json]")
                return
            }
            guard let addition = projectArtifactContent(from: rest) else { return }
            var updated = note
            let existing = storage.loadContent(for: note)
            let separator = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            updated.content = existing + separator + addition
            storage.save(note: updated)
            let current = storage.notes.first(where: { $0.id == note.id }) ?? updated
            if jsonOutput {
                var dict = noteToDict(current)
                dict["ok"] = true
                dict["command"] = "note.project-artifact.append"
                dict["content"] = storage.loadContent(for: current)
                outputJSON(dict)
            } else {
                print("Appended project artifact: \(current.title)")
                print("  Path: \(current.relativePath)")
            }

        case "list", "ls":
            guard let project = parseFlag("--project", from: rest) ?? parseFlag("--project-id", from: rest) else {
                printCLIError("Usage: cider-cli note project-artifact list --project <project-id-or-name> [--type <type>] [--json]")
                return
            }
            let projectID = SecondBrainProjectGraphService.normalizedProjectID(project)
            let typeFilter = parseFlag("--type", from: rest) ?? parseFlag("--artifact-type", from: rest)
            let allowedTypes: Set<String>? = typeFilter.map { filter in
                let normalized = filter.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
                if normalized == "plans-handoffs" || normalized == "plans_handoffs" {
                    return ["plan", "handoff"]
                }
                if normalized == "decisions" { return ["decision"] }
                if normalized == "qa-audits" || normalized == "qa_audits" || normalized == "audits" {
                    return ["qa", "audit"]
                }
                return [normalized]
            }
            let notes = storage.notes.filter { note in
                guard SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID else { return false }
                guard let allowedTypes else { return true }
                return allowedTypes.contains(note.artifactType?.localizedLowercase ?? "note")
            }.sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            if jsonOutput {
                outputJSON([
                    "ok": true,
                    "command": "note.project-artifact.list",
                    "projectID": projectID,
                    "count": notes.count,
                    "notes": notes.map(noteToDict),
                ])
            } else {
                print("Project artifacts for \(projectID) (\(notes.count)):")
                for note in notes {
                    print("  [\(note.id.uuidString.prefix(8))] \(note.artifactType ?? "note") — \(note.title) — \(note.relativePath)")
                }
            }

        case "get", "show":
            let positional = leadingPositionalArgs(from: rest)
            guard let idPrefix = positional.first, let note = findNote(idPrefix, in: storage) else {
                printCLIError("Usage: cider-cli note project-artifact get <note-id-prefix> [--json]")
                return
            }
            if jsonOutput {
                var dict = noteToDict(note)
                dict["ok"] = true
                dict["command"] = "note.project-artifact.get"
                dict["content"] = storage.loadContent(for: note)
                dict["relations"] = projectArtifactRelations(for: note).map(relationToDict)
                outputJSON(dict)
            } else {
                print("Project artifact: \(note.title)")
                print("  ID:   \(note.id.uuidString)")
                print("  Type: \(note.artifactType ?? "note")")
                print("  Path: \(note.relativePath)")
                print("  Content:")
                let content = storage.loadContent(for: note)
                print(content.isEmpty ? "(empty)" : content)
            }

        default:
            printCLIError("Unknown project-artifact command: \(subcommand ?? "nil"). Commands: create, link, append, list, get")
        }
    }

    static let projectArtifactValueFlags: Set<String> = [
        "--project", "--project-id", "--type", "--artifact-type", "--title",
        "--content", "--text-file", "--card", "--card-id", "--source-agent", "--target-agent",
        "--decided-from-card", "--decided-from-note", "--source-card", "--source-note",
        "--validates-card", "--validates-note", "--found-bug-in-card", "--found-bug-in-note",
        "--relation", "--board",
    ]

    static func projectArtifactContent(from args: [String]) -> String? {
        if let raw = parseFlag("--content", from: args) {
            return raw
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
        }
        do {
            return try rawCaptureText(from: args)
        } catch {
            printCLIError(error.localizedDescription)
            return nil
        }
    }

    static func recordProjectArtifactRelations(note: Note, args: [String]) -> [SecondBrainRelation] {
        let targets = projectArtifactRelationTargets(from: args)
        return ProjectArtifactRelationService.recordArtifactRelations(
            note: note,
            targets: targets,
            actor: parseFlag("--source-agent", from: args) ?? "cider-cli",
            source: ProjectArtifactRelationService.cliSource
        )
    }

    static func parseProjectArtifactRelationType(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            .replacingOccurrences(of: "-", with: "_") {
        case ProjectArtifactRelationType.documents:
            return ProjectArtifactRelationType.documents
        case ProjectArtifactRelationType.validates:
            return ProjectArtifactRelationType.validates
        case ProjectArtifactRelationType.foundBugIn:
            return ProjectArtifactRelationType.foundBugIn
        case ProjectArtifactRelationType.decidedFrom:
            return ProjectArtifactRelationType.decidedFrom
        case ProjectArtifactRelationType.spawnedFrom:
            return ProjectArtifactRelationType.spawnedFrom
        case ProjectArtifactRelationType.derivesFrom:
            return ProjectArtifactRelationType.derivesFrom
        case ProjectArtifactRelationType.implements:
            return ProjectArtifactRelationType.implements
        case ProjectArtifactRelationType.supersedes:
            return ProjectArtifactRelationType.supersedes
        default:
            printCLIError("Invalid project artifact relation '\(raw)'. Use documents, validates, found-bug-in, decided-from, spawned-from, derives-from, implements, or supersedes.")
            return nil
        }
    }

    static func resolveKanbanCardRef(_ rawRef: String, boardRef: String? = nil) -> (board: KanbanBoard, card: KanbanCard)? {
        let trimmed = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            printCLIError("Card reference cannot be empty.")
            return nil
        }

        if let boardRef, !boardRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let board = findBoard(boardRef, in: KanbanStorage.shared) else { return nil }
            guard let card = board.card(matching: trimmed) else {
                printCLIError("Card '\(trimmed)' not found in board '\(board.name)'")
                return nil
            }
            return (board, card)
        }

        if let slash = trimmed.firstIndex(of: "/") {
            let boardPart = String(trimmed[..<slash])
            let cardPart = String(trimmed[trimmed.index(after: slash)...])
            guard let board = findBoard(boardPart, in: KanbanStorage.shared) else { return nil }
            guard let card = board.card(matching: cardPart) else {
                printCLIError("Card '\(cardPart)' not found in board '\(board.name)'")
                return nil
            }
            return (board, card)
        }

        if let detail = KanbanStorage.shared.findCard(id: trimmed) {
            return (detail.board, detail.card)
        }

        let matches = KanbanStorage.shared.boards.compactMap { board -> (board: KanbanBoard, card: KanbanCard)? in
            guard let card = board.card(matching: trimmed) else { return nil }
            return (board, card)
        }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.count > 1 {
            printCLIError("Card reference '\(trimmed)' is ambiguous. Pass --board <board> or use board/card.")
        } else {
            printCLIError("Card '\(trimmed)' not found.")
        }
        return nil
    }

    static func projectArtifactRelationTargets(from args: [String]) -> [ProjectArtifactRelationService.ArtifactRelationTarget] {
        var targets: [ProjectArtifactRelationService.ArtifactRelationTarget] = []
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--card", from: args) + parseFlagAll("--card-id", from: args),
            ownerType: "kanban_card",
            relationType: ProjectArtifactRelationType.documents,
            evidencePrefix: "Project artifact documents Kanban card"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--decided-from-card", from: args) + parseFlagAll("--source-card", from: args),
            ownerType: "kanban_card",
            relationType: ProjectArtifactRelationType.decidedFrom,
            evidencePrefix: "Decision artifact was decided from Kanban card"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--decided-from-note", from: args) + parseFlagAll("--source-note", from: args),
            ownerType: "note",
            relationType: ProjectArtifactRelationType.decidedFrom,
            evidencePrefix: "Decision artifact was decided from note"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--validates-card", from: args),
            ownerType: "kanban_card",
            relationType: ProjectArtifactRelationType.validates,
            evidencePrefix: "QA artifact validates Kanban card"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--validates-note", from: args),
            ownerType: "note",
            relationType: ProjectArtifactRelationType.validates,
            evidencePrefix: "QA artifact validates note"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--found-bug-in-card", from: args),
            ownerType: "kanban_card",
            relationType: ProjectArtifactRelationType.foundBugIn,
            evidencePrefix: "QA artifact found bug in Kanban card"
        )
        appendRelationTargets(
            &targets,
            owners: parseFlagAll("--found-bug-in-note", from: args),
            ownerType: "note",
            relationType: ProjectArtifactRelationType.foundBugIn,
            evidencePrefix: "QA artifact found bug in note"
        )
        return targets
    }

    static func appendRelationTargets(
        _ targets: inout [ProjectArtifactRelationService.ArtifactRelationTarget],
        owners: [String],
        ownerType: String,
        relationType: String,
        evidencePrefix: String
    ) {
        for ownerID in owners {
            let owner = normalizedOwner(type: ownerType, ref: ownerID)
            targets.append(ProjectArtifactRelationService.ArtifactRelationTarget(
                owner: owner,
                relationType: relationType,
                evidence: "\(evidencePrefix) \(ownerID)."
            ))
        }
    }

    static func projectArtifactRelations(for note: Note) -> [SecondBrainRelation] {
        let db = CiderDatabase.shared
        guard db.isOpen else { return [] }
        do {
            let stmt = try db.prepare("""
                SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                       relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at
                FROM owner_relations
                WHERE source_owner_type = 'note'
                  AND source_owner_id = ?
                  AND (source = ? OR source = ?)
                ORDER BY updated_at DESC, relation_type COLLATE NOCASE ASC;
                """)
            stmt.bind(note.id.uuidString, at: 1)
                .bind(ProjectArtifactRelationService.cliSource, at: 2)
                .bind(ProjectArtifactRelationService.source, at: 3)
            var relations: [SecondBrainRelation] = []
            while try stmt.step() {
                relations.append(SecondBrainRelation(
                    id: stmt.string(at: 0),
                    sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
                    targetOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 3), ownerID: stmt.string(at: 4)),
                    relationType: stmt.string(at: 5),
                    evidence: stmt.string(at: 6),
                    source: stmt.string(at: 7),
                    actor: stmt.string(at: 8),
                    confidence: stmt.optionalDouble(at: 9),
                    metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 10)) ?? [:],
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 12))
                ))
            }
            return relations
        } catch {
            return []
        }
    }

    static func relationToDict(_ relation: SecondBrainRelation) -> [String: Any] {
        [
            "id": relation.id,
            "relationType": relation.relationType,
            "relationLabel": ProjectArtifactRelationType.displayName(for: relation.relationType),
            "sourceOwner": ownerToDict(relation.sourceOwner),
            "targetOwner": ownerToDict(relation.targetOwner),
            "evidence": relation.evidence,
            "source": relation.source,
            "actor": relation.actor,
            "metadata": relation.metadata,
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Todo Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleTodo(subcommand: String?, args: [String], storage: TodoCardStorage) async {
        guard !printHiddenLegacyCommandIfRemoved(command: "todo", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "list", "ls":
            let showCompleted = args.contains("--completed")
            let todos = showCompleted ? storage.todoCards : storage.todoCards.filter { !$0.isCompleted }
            if jsonOutput {
                outputJSON(todos.map(todoToDict))
            } else {
                print("Todos (\(todos.count)):")
                for todo in todos {
                    let status = todo.isCompleted ? "✅" : "⬜"
                    let due = todo.dueDate.map { " due: \(formattedTodoDueDate($0))" } ?? ""
                    let priority = todo.priority.map { " [\($0.rawValue)]" } ?? ""
                    print("  \(status) [\(todo.id.uuidString.prefix(8))] \(todo.title)\(priority)\(due)")
                }
            }

        case "get":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            guard let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
                return
            }
            if jsonOutput {
                outputJSON(todoToDict(todo))
            } else {
                print("Todo: \(todo.title) (\(todo.id.uuidString.prefix(8)))")
                print("Status: \(todo.isCompleted ? "completed" : "open")")
                if let dueDate = todo.dueDate {
                    print("Due: \(formattedTodoDueDate(dueDate))")
                }
                if let priority = todo.priority {
                    print("Priority: \(priority.rawValue)")
                }
                let folderName = todo.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                print("Folder: \(folderName)")
                if !todo.details.isEmpty {
                    print("Details: \(todo.details)")
                }
            }

        case "create":
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }
            let title = args.first ?? "Untitled Todo"
            let dueString = parseFlag("--due", from: args)
            let timeString = parseFlag("--time", from: args)
            let priorityString = parseFlag("--priority", from: args)
            let dueDate: Date?
            if let dueString {
                guard let resolvedDueDate = resolveEventStartAt(dateString: dueString, timeString: timeString) else {
                    print("Error: Invalid todo due date/time. Use --due yyyy-MM-dd and optional --time \"h:mm a\" or \"HH:mm\".")
                    return
                }
                dueDate = resolvedDueDate
            } else {
                dueDate = nil
            }
            let priority: TodoPriority? = {
                switch priorityString?.lowercased() {
                case "high": return .high
                case "medium": return .medium
                case "low": return .low
                default: return nil
                }
            }()
            do {
                let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
                let result = try CiderCaptureService(todoStorage: storage, database: database).addTodoCapture(
                    title: title,
                    sourceText: title,
                    dueDate: dueDate,
                    priority: priority,
                    folderID: targetFolder?.id
                )
                if let todo = storage.todoCards.first(where: { $0.id == result.item.id }) {
                    if jsonOutput {
                        var dict = todoToDict(todo)
                        dict["command"] = "todo.create"
                        dict["compatibilityWrapper"] = true
                        dict["backendCommand"] = result.command
                        dict["capture"] = result.toDictionary()
                        outputJSON(dict)
                    } else {
                        print("Created todo: \(todo.title) (\(todo.id.uuidString.prefix(8)))")
                    }
                } else {
                    print("Error: Failed to create todo (disk write failed)")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "complete", "done":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var updated = todo
                updated.isCompleted = true
                updated.completedAt = Date()
                if storage.updateTodoCard(updated) {
                    print("Completed: \(todo.title)")
                } else {
                    print("Error: Failed to complete todo: \(todo.title)")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteTodoCard(todo.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                    print("Deleted: \(todo.title) (moved to trash)")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli todo update <id> [--title <title>] [--details <details>] [--due yyyy-MM-dd] [--time \"h:mm a\"] [--priority high|medium|low]")
                return
            }
            if var todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) { todo.title = t; changed = true }
                if let d = parseFlag("--details", from: args) { todo.details = d; changed = true }
                let dueArg = parseFlag("--due", from: args)
                let timeArg = parseFlag("--time", from: args)
                if dueArg != nil || timeArg != nil {
                    let baseDateString: String
                    if let dueArg {
                        baseDateString = dueArg
                    } else if let existingDueDate = todo.dueDate {
                        baseDateString = localDateFormatter.string(from: existingDueDate)
                    } else {
                        print("Error: --time requires an existing due date or an explicit --due yyyy-MM-dd.")
                        return
                    }

                    let desiredTimeString: String?
                    if let timeArg {
                        desiredTimeString = timeArg
                    } else {
                        desiredTimeString = todo.dueDate.map { localTimeFormatter.string(from: $0) }
                    }

                    guard let updatedDueDate = resolveEventStartAt(dateString: baseDateString, timeString: desiredTimeString) else {
                        print("Error: Invalid todo due date/time. Use --due yyyy-MM-dd and optional --time \"h:mm a\" or \"HH:mm\".")
                        return
                    }
                    todo.dueDate = updatedDueDate
                    changed = true
                }
                if let p = parseFlag("--priority", from: args) {
                    switch p.lowercased() {
                    case "high": todo.priority = .high; changed = true
                    case "medium": todo.priority = .medium; changed = true
                    case "low": todo.priority = .low; changed = true
                    default: break
                    }
                }
                if changed {
                    todo.updatedAt = Date()
                    if storage.updateTodoCard(todo) {
                        print("Updated: \(todo.title) (\(todo.id.uuidString.prefix(8)))")
                    } else {
                        print("Error: Failed to update todo: \(todo.title)")
                    }
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "export":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli todo export <id> --to <path>")
                return
            }
            guard let destPath = parseFlag("--to", from: args) else {
                print("Error: --to <path> required")
                return
            }
            if let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let url = URL(fileURLWithPath: NSString(string: destPath).expandingTildeInPath)
                if storage.writeICSFile(for: todo, to: url) {
                    print("Exported: \(todo.title) → \(url.path)")
                } else {
                    print("Error: Could not write ICS file")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "checklist":
            let checklistCmd = args.first
            let checklistArgs = Array(args.dropFirst())
            await handleTodoChecklist(subcommand: checklistCmd, args: checklistArgs, storage: storage)

        default:
            printCLIError("Unknown todo command: \(subcommand ?? "nil"). Commands: list, get, create, complete, delete, update, export, checklist")
        }
    }

    static func handleTodoChecklist(subcommand: String?, args: [String], storage: TodoCardStorage) async {
        switch subcommand {
        case "list", "ls":
            guard let idPrefix = args.first else {
                print("Error: Todo ID prefix required. Usage: cider-cli todo checklist list <todo-id>")
                return
            }
            guard let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
                return
            }
            if jsonOutput {
                let items = todo.checklist.map { item -> [String: Any] in
                    var d: [String: Any] = [
                        "id": item.id.uuidString,
                        "title": item.title,
                        "completed": item.isCompleted,
                        "sortOrder": item.sortOrder,
                    ]
                    if !item.subtasks.isEmpty {
                        d["subtasks"] = item.subtasks.map { [
                            "id": $0.id.uuidString,
                            "title": $0.title,
                            "completed": $0.isCompleted,
                        ] as [String: Any] }
                    }
                    return d
                }
                outputJSON(["todoID": todo.id.uuidString, "title": todo.title, "checklist": items])
            } else {
                if todo.checklist.isEmpty {
                    print("No checklist items for: \(todo.title)")
                } else {
                    print("Checklist for '\(todo.title)' (\(todo.checklist.count) items):")
                    for item in todo.checklist {
                        let status = item.isCompleted ? "[x]" : "[ ]"
                        print("  \(status) [\(item.id.uuidString.prefix(8))] \(item.title)")
                        for sub in item.subtasks {
                            let subStatus = sub.isCompleted ? "[x]" : "[ ]"
                            print("      \(subStatus) [\(sub.id.uuidString.prefix(8))] \(sub.title)")
                        }
                    }
                }
            }

        case "add":
            guard let idPrefix = firstPositionalArgument(from: args, valueFlags: ["--title"]) else {
                printCLIError("Usage: cider-cli todo checklist add <todo-id> --title <title>")
                return
            }
            guard var todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
                return
            }
            guard let title = parseFlag("--title", from: args) else {
                print("Error: --title required")
                return
            }
            let newItem = TodoChecklistItem(
                title: title,
                sortOrder: todo.checklist.count
            )
            todo.checklist.append(newItem)
            todo.updatedAt = Date()
            if storage.updateTodoCard(todo) {
                print("Added checklist item '\(title)' to '\(todo.title)' (\(newItem.id.uuidString.prefix(8)))")
            } else {
                print("Error: Failed to add checklist item to '\(todo.title)'")
            }

        case "toggle":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli todo checklist toggle <todo-id> --item <item-id>")
                return
            }
            guard let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
                return
            }
            guard let itemPrefix = parseFlag("--item", from: args) else {
                print("Error: --item <checklist-item-id> required")
                return
            }
            if let subtaskPrefix = parseFlag("--subtask", from: args) {
                guard let item = todo.checklist.first(where: { $0.id.uuidString.lowercased().hasPrefix(itemPrefix.lowercased()) }) else {
                    print("Error: No checklist item found with ID prefix: \(itemPrefix)")
                    return
                }
                guard let subtask = item.subtasks.first(where: { $0.id.uuidString.lowercased().hasPrefix(subtaskPrefix.lowercased()) }) else {
                    print("Error: No subtask found with ID prefix: \(subtaskPrefix)")
                    return
                }
                if storage.toggleSubtask(todo.id, checklistItemID: item.id, subtaskID: subtask.id) {
                    print("Toggled subtask '\(subtask.title)' → \(!subtask.isCompleted ? "done" : "undone")")
                } else {
                    print("Error: Failed to toggle subtask")
                }
            } else {
                guard let item = todo.checklist.first(where: { $0.id.uuidString.lowercased().hasPrefix(itemPrefix.lowercased()) }) else {
                    print("Error: No checklist item found with ID prefix: \(itemPrefix)")
                    return
                }
                if storage.toggleChecklistItem(todo.id, checklistItemID: item.id) {
                    print("Toggled '\(item.title)' → \(!item.isCompleted ? "done" : "undone")")
                } else {
                    print("Error: Failed to toggle checklist item")
                }
            }

        case "remove", "rm":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli todo checklist remove <todo-id> --item <item-id>")
                return
            }
            guard var todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
                return
            }
            guard let itemPrefix = parseFlag("--item", from: args) else {
                print("Error: --item <checklist-item-id> required")
                return
            }
            guard let idx = todo.checklist.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(itemPrefix.lowercased()) }) else {
                print("Error: No checklist item found with ID prefix: \(itemPrefix)")
                return
            }
            let removed = todo.checklist.remove(at: idx)
            todo.updatedAt = Date()
            if storage.updateTodoCard(todo) {
                print("Removed checklist item '\(removed.title)' from '\(todo.title)'")
            } else {
                print("Error: Failed to remove checklist item from '\(todo.title)'")
            }

        default:
            printCLIError("Unknown todo checklist command: \(subcommand ?? "nil"). Commands: list, add, toggle, remove")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Event (DateCard) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleEvent(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "event", subcommand: subcommand, args: args) else {
            return
        }
        let storage = DateCardStorage.shared
        switch subcommand {
        case "list", "ls":
            let cards = storage.dateCards
            if jsonOutput {
                outputJSON(cards.map(eventToDict))
            } else {
                print("Events (\(cards.count)):")
                for card in cards {
                    let date = dateFormatter.string(from: card.startAt)
                    let completed = card.isCompleted ? " ✅" : ""
                    print("  [\(card.id.uuidString.prefix(8))] \(card.title) — \(date)\(completed)")
                }
            }

        case "create":
            printRemovedLegacyCommand(
                command: "event create",
                replacement: "cider-cli capture add --kind event --title \"<title>\" --date yyyy-MM-dd --stdin --json",
                reason: "event create was removed so event intake always goes through CiderCaptureService."
            )

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let card = storage.dateCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteDateCard(card.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    print("Deleted: \(card.title) (moved to trash)")
                }
            } else {
                print("Error: No event found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli event update <id> [--title <title>] [--date yyyy-MM-dd] [--time \"h:mm a\"] [--location <location>] [--details <text>]")
                return
            }
            if var card = storage.dateCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) { card.title = t; changed = true }
                let dateArg = parseFlag("--date", from: args)
                let timeArg = parseFlag("--time", from: args)
                if dateArg != nil || timeArg != nil || args.contains("--all-day") || args.contains("--timed") {
                    let existingDateString = localDateFormatter.string(from: card.startAt)
                    let existingTimeString = localTimeFormatter.string(from: card.startAt)
                    let baseDateString = dateArg ?? existingDateString
                    let desiredTimeString: String? = {
                        if args.contains("--all-day") { return nil }
                        if let timeArg { return timeArg }
                        if args.contains("--timed") || !card.allDay { return existingTimeString }
                        return nil
                    }()

                    guard let updatedStartAt = resolveEventStartAt(dateString: baseDateString, timeString: desiredTimeString) else {
                        print("Error: Invalid event date/time. Use --date yyyy-MM-dd and optional --time \"h:mm a\" or \"HH:mm\".")
                        return
                    }
                    card.startAt = args.contains("--all-day")
                        ? Calendar.autoupdatingCurrent.startOfDay(for: updatedStartAt)
                        : updatedStartAt
                    if args.contains("--all-day") {
                        card.allDay = true
                    } else if timeArg != nil || args.contains("--timed") {
                        card.allDay = false
                    }
                    changed = true
                }
                if let loc = parseFlag("--location", from: args) { card.location = loc; changed = true }
                if let details = parseFlag("--details", from: args) { card.details = details; changed = true }
                // Reminder rules: --remind replaces existing, --clear-reminders removes all
                if args.contains("--clear-reminders") {
                    card.rules.removeAll { $0.type == .remindBeforeMinutes }
                    changed = true
                }
                let remindValues = parseFlagAll("--remind", from: args)
                if !remindValues.isEmpty {
                    // Replace existing reminder rules
                    card.rules.removeAll { $0.type == .remindBeforeMinutes }
                    for value in remindValues {
                        guard let minutes = Int(value) else {
                            print("Error: --remind requires an integer (minutes before event). Got: '\(value)'")
                            return
                        }
                        card.rules.append(SurfacingRule(
                            type: .remindBeforeMinutes,
                            integerValue: minutes
                        ))
                    }
                    changed = true
                }
                // Recurrence rule on update
                if let freqStr = parseFlag("--frequency", from: args) {
                    let freq: DateCardRecurrenceFrequency
                    switch freqStr.lowercased() {
                    case "daily": freq = .daily
                    case "weekly": freq = .weekly
                    case "monthly": freq = .monthly
                    case "yearly": freq = .yearly
                    default:
                        print("Error: Invalid frequency '\(freqStr)'. Use daily, weekly, monthly, or yearly.")
                        return
                    }
                    let interval = parseFlag("--interval", from: args).flatMap(Int.init) ?? 1
                    let endDate = parseFlag("--end-date", from: args).flatMap { dateFormatter.date(from: $0) }
                    card.recurrenceRule = DateCardRecurrenceRule(frequency: freq, interval: interval, endDate: endDate)
                    changed = true
                }
                if changed {
                    _ = storage.updateDateCard(card)
                    print("Updated: \(card.title) (\(card.id.uuidString.prefix(8)))")
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No event found with ID prefix: \(idPrefix)")
            }

        case "export":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli event export <id> --to <path>")
                return
            }
            guard let destPath = parseFlag("--to", from: args) else {
                print("Error: --to <path> required")
                return
            }
            if let card = storage.dateCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let url = URL(fileURLWithPath: NSString(string: destPath).expandingTildeInPath)
                if storage.writeICSFile(for: card, to: url) {
                    print("Exported: \(card.title) → \(url.path)")
                } else {
                    print("Error: Could not write ICS file")
                }
            } else {
                print("Error: No event found with ID prefix: \(idPrefix)")
            }

        default:
            printCLIError("Unknown event command: \(subcommand ?? "nil"). Commands: list, create, delete, update, export")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Contact Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleContact(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "contact", subcommand: subcommand, args: args) else {
            return
        }
        let storage = ContactStorage.shared
        switch subcommand {
        case nil, "help", "--help", "-h":
            print(ContactCLIHelpText.contact)

        case "list", "ls":
            let contacts = storage.contacts
            if jsonOutput {
                outputJSON(contacts.map(contactToDict))
            } else {
                print("Contacts (\(contacts.count)):")
                for contact in contacts {
                    let email = contact.email.isEmpty ? "" : " — \(contact.email)"
                    print("  [\(contact.id.uuidString.prefix(8))] \(contact.displayName)\(email)")
                }
            }

        case "profile":
            handleContactProfile(subcommand: args.first, args: Array(args.dropFirst()), storage: storage)

        case "field", "fields":
            handleContactField(subcommand: args.first, args: Array(args.dropFirst()), storage: storage)

        case "create":
            printRemovedLegacyCommand(
                command: "contact create",
                replacement: "cider-cli capture add --kind contact --name \"<name>\" --stdin --json",
                reason: "contact create was removed so contact intake always goes through CiderCaptureService."
            )

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteContact(contact.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    print("Deleted: \(contact.displayName) (moved to trash)")
                }
            } else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli contact update <id> [--name <n>] [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>]")
                return
            }
            if var contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let n = parseFlag("--name", from: args) { contact.displayName = n; changed = true }
                if let e = parseFlag("--email", from: args) { contact.email = e; changed = true }
                if let p = parseFlag("--phone", from: args) { contact.phone = p; changed = true }
                if let a = parseFlag("--address", from: args) { contact.address = a; changed = true }
                if let r = parseFlag("--relationship", from: args) { contact.relationshipLabel = r; changed = true }
                if let notes = parseFlag("--notes", from: args) { contact.notes = notes; changed = true }
                if let bday = parseFlag("--birthday", from: args) {
                    let localDF = DateFormatter()
                    localDF.dateFormat = "yyyy-MM-dd"
                    localDF.timeZone = .current
                    if let date = localDF.date(from: bday) {
                        contact.birthday = date; changed = true
                        LibraryItemEditor.createOrUpdateBirthdayDateCard(for: contact, birthday: date)
                    }
                }
                if changed {
                    _ = storage.updateContact(contact)
                    print("Updated: \(contact.displayName) (\(contact.id.uuidString.prefix(8)))")
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
            }

        case "export":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli contact export <id> --to <path>")
                return
            }
            guard let destPath = parseFlag("--to", from: args) else {
                print("Error: --to <path> required")
                return
            }
            if let contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let url = URL(fileURLWithPath: NSString(string: destPath).expandingTildeInPath)
                if storage.writeVCardFile(for: contact, to: url) {
                    print("Exported: \(contact.displayName) → \(url.path)")
                } else {
                    print("Error: Could not write vCard file")
                }
            } else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
            }

        case "set-avatar":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli contact set-avatar <id> <image-path>")
                return
            }
            guard let contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
                return
            }
            guard args.count > 1 else {
                print("Error: Image path required")
                return
            }
            let imagePath = NSString(string: args[1]).expandingTildeInPath
            let imageURL = URL(fileURLWithPath: imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                print("Error: File not found: \(imageURL.path)")
                return
            }
            guard let image = NSImage(contentsOf: imageURL) else {
                print("Error: Could not load image: \(imageURL.path)")
                return
            }
            if storage.saveAvatar(image, for: contact.id) {
                print("Set avatar for '\(contact.displayName)' from \(imageURL.lastPathComponent)")
            } else {
                print("Error: Failed to save avatar")
            }

        case "remove-avatar":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli contact remove-avatar <id>")
                return
            }
            guard let contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
                return
            }
            storage.deleteAvatar(for: contact.id)
            print("Removed avatar for '\(contact.displayName)'")

        default:
            printCLIError("Unknown contact command: \(subcommand ?? "nil"). \(ContactCLIHelpText.contact)")
        }
    }

    static func handleContactProfile(subcommand: String?, args: [String], storage: ContactStorage) {
        switch subcommand {
        case "show", "get":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.profile)
                return
            }
            let ref = leadingPositionalArgs(from: args).joined(separator: " ")
            guard !ref.isEmpty else {
                print("Error: Contact ID prefix or name required. Usage: cider-cli contact profile show <id|name> [--json]")
                return
            }
            guard let contact = findContact(ref, in: storage) else { return }
            if jsonOutput {
                outputJSON(contactProfileEnvelope(contact, action: "show", readOnly: true, changed: false))
            } else {
                printContactProfile(contact)
            }

        case "apply", "set":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.profile)
                return
            }
            let ref = leadingPositionalArgs(from: args).joined(separator: " ")
            let createIfMissing = args.contains("--create")
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }

            guard !ref.isEmpty || createIfMissing else {
                print("Error: Contact ID prefix or name required. Usage: cider-cli contact profile apply <id|name> --profile-json <json> [--create] [--json]")
                return
            }
            guard let json = readContactProfileJSON(from: args) else { return }

            let patch: ContactProfilePatch
            do {
                patch = try ContactProfileJSON.decodePatch(from: json)
            } catch {
                print("Error: Invalid profile JSON: \(error.localizedDescription)")
                return
            }

            let existing = ref.isEmpty ? nil : resolveContact(ref, in: storage, reportErrors: false)
            let originalBirthday = existing?.birthday
            let updated: ContactCard
            let action: String
            do {
                if var contact = existing {
                    contact = try patch.apply(to: contact)
                    if let targetFolder {
                        contact.folderID = targetFolder.id
                    }
                    guard storage.updateContact(contact) else {
                        print("Error: Failed to update contact '\(contact.displayName)'")
                        return
                    }
                    updated = storage.contact(for: contact.id) ?? contact
                    action = "updated"
                } else if createIfMissing {
                    let baseName = ref.isEmpty ? "New Contact" : ref
                    let desired = try patch.apply(to: ContactCard(displayName: baseName))
                    let finalName = desired.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !finalName.isEmpty, finalName != "New Contact" || !ref.isEmpty else {
                        print("Error: --create requires a contact name or displayName in profile JSON")
                        return
                    }
                    var contact = storage.createContact(displayName: finalName)
                    guard storage.contacts.contains(where: { $0.id == contact.id }) else {
                        print("Error: Failed to create contact (disk write failed)")
                        return
                    }
                    contact.displayName = finalName
                    contact.relationshipLabel = desired.relationshipLabel
                    contact.birthday = desired.birthday
                    contact.notes = desired.notes
                    contact.email = desired.email
                    contact.phone = desired.phone
                    contact.address = desired.address
                    contact.linkedEntities = desired.linkedEntities
                    contact.customFields = desired.customFields
                    if let targetFolder {
                        contact.folderID = targetFolder.id
                    }
                    guard storage.updateContact(contact) else {
                        print("Error: Failed to finish created contact '\(finalName)'")
                        return
                    }
                    updated = storage.contact(for: contact.id) ?? contact
                    action = "created"
                } else {
                    print("Error: No contact found with ID prefix or name: \(ref)")
                    return
                }
            } catch {
                print("Error: \(error.localizedDescription)")
                return
            }

            if let birthday = updated.birthday, birthday != originalBirthday {
                LibraryItemEditor.createOrUpdateBirthdayDateCard(for: updated, birthday: birthday)
            }

            if jsonOutput {
                outputJSON(contactProfileEnvelope(updated, action: action, readOnly: false, changed: true))
            } else {
                print("\(action.capitalized): \(updated.displayName) (\(updated.id.uuidString.prefix(8)))")
            }

        case nil, "help", "--help", "-h":
            print(ContactCLIHelpText.profile)

        default:
            print("Unknown contact profile command: \(subcommand ?? "nil")")
            print(ContactCLIHelpText.profile)
        }
    }

    static func handleContactField(subcommand: String?, args: [String], storage: ContactStorage) {
        switch subcommand {
        case "list", "ls":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.field)
                return
            }
            let ref = leadingPositionalArgs(from: args).joined(separator: " ")
            guard !ref.isEmpty else {
                print("Error: Contact ID prefix or name required. Usage: cider-cli contact field list <contact> [--json]")
                return
            }
            guard let contact = findContact(ref, in: storage) else { return }
            if jsonOutput {
                outputJSON(contactFieldEnvelope(
                    contact: contact,
                    action: "list",
                    readOnly: true,
                    changed: false,
                    fields: contact.customFields.map(contactFieldToDict)
                ))
            } else {
                print("Fields for \(contact.displayName) (\(contact.customFields.count)):")
                for field in contact.customFields {
                    print("  [\(field.id.uuidString.prefix(8))] \(field.section) / \(field.label): \(field.value)\(field.isPinned ? " (pinned)" : "")")
                }
            }

        case "add":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.field)
                return
            }
            let ref = leadingPositionalArgs(from: args).joined(separator: " ")
            guard !ref.isEmpty else {
                print("Error: Contact ID prefix or name required. Usage: cider-cli contact field add <contact> --section <s> --label <l> --value <v> [--kind text|phone|email|url|date|number] [--pinned]")
                return
            }
            guard var contact = findContact(ref, in: storage) else { return }
            guard let section = parseFlag("--section", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty,
                  let label = parseFlag("--label", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
                  let value = parseFlag("--value", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                print("Error: --section, --label, and --value are required")
                return
            }
            let kind = parseContactFieldKind(from: args)
            let pinned = parseOptionalBoolFlag("--pinned", from: args) ?? args.contains("--pinned")
            let field = ContactCustomField(section: section, label: label, value: value, kind: kind, isPinned: pinned)
            contact.customFields.append(field)
            guard storage.updateContact(contact) else {
                print("Error: Failed to add field to \(contact.displayName)")
                return
            }
            if jsonOutput {
                outputJSON(contactFieldEnvelope(contact: contact, action: "added", readOnly: false, changed: true, field: field))
            } else {
                print("Added field: \(field.section) / \(field.label) (\(field.id.uuidString.prefix(8)))")
            }

        case "update", "set":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.field)
                return
            }
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                print("Error: Usage: cider-cli contact field update <contact> <field-id|label> [--section <s>] [--label <l>] [--value <v>] [--kind text|phone|email|url|date|number] [--pinned true|false]")
                return
            }
            let contactRef = positional.dropLast().joined(separator: " ")
            let fieldRef = positional.last ?? ""
            guard var contact = findContact(contactRef, in: storage) else { return }
            guard let idx = resolveContactFieldIndex(fieldRef, in: contact) else {
                print("Error: No field found on \(contact.displayName) matching '\(fieldRef)'")
                return
            }
            if let section = parseFlag("--section", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty {
                contact.customFields[idx].section = section
            }
            if let label = parseFlag("--label", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                contact.customFields[idx].label = label
            }
            if let value = parseFlag("--value", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                contact.customFields[idx].value = value
            }
            if parseFlag("--kind", from: args) != nil {
                contact.customFields[idx].kind = parseContactFieldKind(from: args)
            }
            if let pinned = parseOptionalBoolFlag("--pinned", from: args) {
                contact.customFields[idx].isPinned = pinned
            } else if args.contains("--pinned") {
                contact.customFields[idx].isPinned = true
            } else if args.contains("--unpinned") {
                contact.customFields[idx].isPinned = false
            }
            let updatedField = contact.customFields[idx]
            guard storage.updateContact(contact) else {
                print("Error: Failed to update field on \(contact.displayName)")
                return
            }
            if jsonOutput {
                outputJSON(contactFieldEnvelope(contact: contact, action: "updated", readOnly: false, changed: true, field: updatedField))
            } else {
                print("Updated field: \(updatedField.section) / \(updatedField.label) (\(updatedField.id.uuidString.prefix(8)))")
            }

        case "delete", "remove", "rm":
            if hasHelpArg(args) {
                print(ContactCLIHelpText.field)
                return
            }
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                print("Error: Usage: cider-cli contact field delete <contact> <field-id|label>")
                return
            }
            let contactRef = positional.dropLast().joined(separator: " ")
            let fieldRef = positional.last ?? ""
            guard var contact = findContact(contactRef, in: storage) else { return }
            guard let idx = resolveContactFieldIndex(fieldRef, in: contact) else {
                print("Error: No field found on \(contact.displayName) matching '\(fieldRef)'")
                return
            }
            let removed = contact.customFields.remove(at: idx)
            guard storage.updateContact(contact) else {
                print("Error: Failed to delete field on \(contact.displayName)")
                return
            }
            if jsonOutput {
                outputJSON(contactFieldEnvelope(contact: contact, action: "deleted", readOnly: false, changed: true, field: removed))
            } else {
                print("Deleted field: \(removed.section) / \(removed.label) (\(removed.id.uuidString.prefix(8)))")
            }

        case nil, "help", "--help", "-h":
            print(ContactCLIHelpText.field)

        default:
            print("Unknown contact field command: \(subcommand ?? "nil")")
            print(ContactCLIHelpText.field)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Link Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleLink(subcommand: String?, args: [String]) {
        let service = ItemLinkService.shared
        switch subcommand {
        case nil, "help", "--help", "-h":
            print(ItemLinkCLIHelpText.link)

        case "add":
            if hasHelpArg(args) {
                print(ItemLinkCLIHelpText.link)
                return
            }
            do {
                let (source, target) = try resolveLinkPair(from: args, service: service)
                try service.addLink(from: source, to: target)
                printLinkMutation(action: "linked", source: source, target: target, service: service)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "remove", "rm", "delete":
            if hasHelpArg(args) {
                print(ItemLinkCLIHelpText.link)
                return
            }
            do {
                let (source, target) = try resolveLinkPair(from: args, service: service)
                try service.removeLink(from: source, to: target)
                printLinkMutation(action: "unlinked", source: source, target: target, service: service)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "list":
            if hasHelpArg(args) {
                print(ItemLinkCLIHelpText.link)
                return
            }
            do {
                let ref = try resolveSingleLinkRef(from: args, service: service)
                let refs = try service.outgoingRefs(for: ref)
                printLinkSummaries(refs, service: service)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "backlinks":
            if hasHelpArg(args) {
                print(ItemLinkCLIHelpText.link)
                return
            }
            do {
                let ref = try resolveSingleLinkRef(from: args, service: service)
                let refs = try service.backlinkRefs(for: ref)
                printLinkSummaries(refs, service: service)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "related":
            if hasHelpArg(args) {
                print(ItemLinkCLIHelpText.link)
                return
            }
            do {
                let ref = try resolveSingleLinkRef(from: args, service: service)
                let refs = try service.relatedRefs(for: ref)
                printLinkSummaries(refs, service: service)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        default:
            print("Unknown link command: \(subcommand ?? "nil")")
            print(ItemLinkCLIHelpText.link)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Item Graph / Agent Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleItem(subcommand: String?, args: [String]) {
        let store = SecondBrainStore(database: .shared)
        let contextService = CiderItemContextService(database: .shared, secondBrainStore: store)
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Item graph commands:
              cider-cli item search <query> [--space <space-id|name>] [--limit <n>] [--json]
              cider-cli item search-debug <query> [--limit <n>] [--json]
              cider-cli item get <type> <id-or-ref> [--json]
              cider-cli item owner-get <owner-type> <owner-id-or-ref> [--json]
                Use owner-get folder <id|path|name|Inbox> for read-only folder metadata, counts, and health.
              cider-cli item open <type> <id-or-ref> [--json]
              cider-cli item context <type> <id-or-ref> [--max-sections <n>] [--max-chunks <n>] [--max-related <n>] [--max-history <n>] [--max-body <chars>] [--json]
              cider-cli item why-surfaced <type> <id-or-ref> [--json]
              cider-cli item capability-map [--json]
              cider-cli item graph-health [--json]
              cider-cli item related <type> <id-or-ref> [--json]
              cider-cli item relations <owner-type> <owner-id-or-ref> [--json]
              cider-cli item backlinks <owner-type> <owner-id-or-ref> [--json]
              cider-cli item related-owners <owner-type> <owner-id-or-ref> [--json]
              cider-cli item rebuild-references <note|card|board> <id-or-ref> [--json]
              cider-cli item rebuild-chunks <type|all> [id-or-ref] [--limit <n>] [--json]
              cider-cli item rebuild-enrichment <owner-type> <owner-id-or-ref> [--json]
              cider-cli item memory-suggest <owner-type> <owner-id-or-ref> --kind preference|pattern|project_context|relationship_context|agent_lesson --value <text> --evidence <text> [--source <source>] [--confidence <0-1>] [--json]
              cider-cli item rebuild-similarity <owner-type> <owner-id-or-ref> [--threshold <0-1>] [--limit <n>] [--json]
              cider-cli item dogfood-intelligence [--limit <n>] [--threshold <0-1>] [--candidate-limit <n>] [--json]
              cider-cli item similarity <owner-type> <owner-id-or-ref> [--json]
              cider-cli item accept-similarity <candidate-id> [--relation similar_to|duplicates|grouped_with] [--actor <name>] [--json]
              cider-cli item project-context <project-id-or-name> [--summary] [--limit <n>] [--full] [--json]
              cider-cli item sync-project <project-id-or-name> [--json]
              cider-cli item link <source-type> <source-ref> <target-type> <target-ref>
              cider-cli item move <type> <id-or-ref> (--folder <name|path>|--path <target-folder-path>) [--actor <name>] [--source <source>] [--json]
                Do not pass artifact filenames such as Example.webloc to item move --path.
              cider-cli item unfile <type> <id-or-ref> [--actor <name>] [--source <source>] [--json]
              cider-cli item delete <type> <id-or-ref> --reason <text> [--approve <token> --execute] [--actor <name>] [--source <source>] [--json]
              cider-cli item apply-intent <type> <id-or-ref> --intent space|project [--actor <name>] [--json]
              cider-cli item route <type> <id-or-ref> --target-type <space|folder|board> [--target-id <id>] [--target-path <path>] --reason <text> [--confidence <0-1>] [--status accepted|needs_review] [--actor <name>] [--source <source>] [--json]
              cider-cli item backfill-kanban [--board <name-or-id>] [--json]
              cider-cli item doctor [--json]
            """)

        case "search":
            let query = leadingPositionalArgs(from: args).joined(separator: " ")
            guard !query.isEmpty else {
                printCLIError("Usage: cider-cli item search <query> [--limit <n>] [--json]")
                return
            }
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? 20
            do {
                let space = resolveOptionalSpaceFlag(from: args)
                if parseFlag("--space", from: args) != nil, space == nil { return }
                let results = try contextService.search(query, limit: limit, inSpaceID: space?.id)
                if jsonOutput {
                    if let space {
                        outputJSON([
                            "ok": true,
                            "space": spaceToDict(space),
                            "results": results.map(itemSearchResultToDict),
                        ])
                    } else {
                        outputJSON(results.map(itemSearchResultToDict))
                    }
                } else if results.isEmpty {
                    if let space {
                        print("No item graph results for '\(query)' in Space \(space.name).")
                    } else {
                        print("No item graph results for '\(query)'.")
                    }
                } else {
                    let scope = space.map { " in Space \($0.name)" } ?? ""
                    print("Item graph search '\(query)'\(scope) (\(results.count) results):")
                    for result in results {
                        let label = result.kind == .item ? "item" : "chunk"
                        print("  [\(label) \(result.owner.ownerType):\(result.owner.ownerID)] \(result.title) — \(result.snippet)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "search-debug", "debug-search":
            let query = leadingPositionalArgs(from: args).joined(separator: " ")
            guard !query.isEmpty else {
                printCLIError("Usage: cider-cli item search-debug <query> [--limit <n>] [--json]")
                return
            }
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? 20
            do {
                let report = try contextService.searchDiagnostics(query, limit: limit)
                if jsonOutput {
                    outputJSON(itemSearchDiagnosticsReportToDict(report))
                } else {
                    print("Item search diagnostics for '\(report.query)':")
                    print("  Ranked results: \(report.exactMatches.count)")
                    print("  Matched chunks: \(report.matchedChunks.count)")
                    print("  Index warnings: \(report.indexWarnings.count)")
                    print("  Semantic: \(report.semanticStatus.status)")
                    for warning in report.warnings {
                        print("  Warning [\(warning.kind)]: \(warning.message)")
                    }
                    for error in report.errors {
                        print("  Error [\(error.kind)]: \(error.message)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "owner-get", "owner-inspect":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item owner-get <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            if positional[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_") == "folder" {
                printFolderOwnerInspection(ref: positional[1])
                return
            }
            do {
                try printOwnerInspection(
                    type: positional[0],
                    ref: positional[1],
                    store: store,
                    command: "item.owner-get",
                    deprecated: false
                )
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "open":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item open <type> <id-or-ref> [--json]")
                return
            }
            do {
                let result = try itemOpenPayload(type: positional[0], ref: positional[1], store: store)
                let posted = CiderExternalOpenBridge.post(userInfo: result.notificationUserInfo)
                var payload = result.payload
                payload["notificationPosted"] = posted
                if jsonOutput {
                    outputJSON(payload)
                } else if let target = payload["target"] as? [String: Any] {
                    print("Requested Cider open: \(target["type"] ?? positional[0]):\(target["id"] ?? positional[1])")
                    print("  Notification: \(CiderExternalOpenBridge.notificationName.rawValue)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "get", "inspect":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item get <type> <id-or-ref> [--json]")
                return
            }
            if isKanbanCardItemType(positional[0]) {
                do {
                    let payload = try kanbanCardItemPayload(ref: positional[1], store: store)
                    if jsonOutput {
                        outputJSON(payload)
                    } else if let item = payload["item"] as? [String: Any] {
                        print("kanban_card:\(item["id"] ?? positional[1])")
                        print("  Title: \(item["title"] ?? "")")
                        print("  Board: \(item["boardName"] ?? "")")
                        print("  Sections: \((payload["sections"] as? [[String: Any]])?.count ?? 0)")
                        print("  Related: \((payload["related"] as? [[String: Any]])?.count ?? 0)")
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }
            if let entityType = try? ItemLinkService.entityType(from: positional[0]) {
                do {
                    let ref = try ItemLinkService.shared.resolve(type: entityType, ref: positional[1])
                    let bundle = try contextService.context(for: ref)
                    if jsonOutput {
                        var dict = itemContextBundleToDict(bundle)
                        dict["ok"] = true
                        dict["command"] = "item.get"
                        dict["readOnly"] = true
                        dict["changed"] = false
                        dict["exists"] = true
                        dict["ownerResolved"] = true
                        dict["sourceRef"] = [
                            "type": positional[0],
                            "ref": positional[1],
                        ]
                        outputJSON(dict)
                    } else {
                        print("\(bundle.item.type.rawValue):\(bundle.item.id.uuidString)")
                        print("  Title: \(bundle.item.title)")
                        if let relativePath = bundle.item.relativePath {
                            print("  Path: \(relativePath)")
                        }
                        print("  Sections: \(bundle.sections.count)")
                        print("  Chunks: \(bundle.chunks.count)")
                        print("  Related: \(bundle.related.count)")
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }
            do {
                try printOwnerInspection(
                    type: positional[0],
                    ref: positional[1],
                    store: store,
                    command: "item.get.legacy-owner-fallback",
                    deprecated: true
                )
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "context", "agent-context":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item context <type> <id-or-ref> [--json]")
                return
            }
            if isKanbanCardItemType(positional[0]) {
                do {
                    let packet = try kanbanCardAgentContextPayload(ref: positional[1], args: args, store: store)
                    if jsonOutput {
                        outputJSON(packet)
                    } else {
                        print("kanban_card:\(positional[1])")
                        print("  Summary: \(packet["summary"] ?? "")")
                        print("  Context blocks: \((packet["contentBlocks"] as? [[String: Any]])?.count ?? 0)")
                        print("  Related: \((packet["related"] as? [[String: Any]])?.count ?? 0)")
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }
            do {
                let type = try ItemLinkService.entityType(from: positional[0])
                let ref = try ItemLinkService.shared.resolve(type: type, ref: positional[1])
                let packet = try contextService.agentContext(for: ref, limits: itemAgentContextLimits(from: args))
                if jsonOutput {
                    var dict = itemAgentContextPacketToDict(packet)
                    dict["ok"] = true
                    dict["sourceRef"] = [
                        "type": positional[0],
                        "ref": positional[1],
                    ]
                    outputJSON(dict)
                } else {
                    print("\(packet.item.type.rawValue):\(packet.item.id.uuidString)")
                    print("  Title: \(packet.item.title)")
                    print("  Summary: \(packet.summary)")
                    if let review = packet.review {
                        print("  Review: \(review.status) - \(review.reason)")
                    }
                    print("  Context blocks: \(packet.contentBlocks.count)")
                    print("  Related: \(packet.related.count)")
                    if !packet.safeCommands.isEmpty {
                        print("  Safe commands:")
                        for command in packet.safeCommands {
                            print("    \(command)")
                        }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "apply-intent":
            let positional = leadingPositionalArgs(from: args)
            let intent = (parseFlag("--intent", from: args) ?? "").lowercased()
            guard positional.count >= 2,
                  ["space", "project"].contains(intent) else {
                printCLIError("Usage: cider-cli item apply-intent <type> <id-or-ref> --intent space|project [--actor <name>] [--json]")
                return
            }
            do {
                let actor = parseFlag("--actor", from: args) ?? "agent"
                let source = parseFlag("--source", from: args) ?? "item.apply-intent"
                let payload: [String: Any]
                if intent == "space" {
                    payload = try itemApplySpaceIntentPayload(
                        type: positional[0],
                        ref: positional[1],
                        actor: actor,
                        source: source
                    )
                } else {
                    payload = try itemApplyProjectIntentPayload(
                        type: positional[0],
                        ref: positional[1],
                        actor: actor,
                        source: source
                    )
                }
                if jsonOutput {
                    outputJSON(payload)
                } else if let intent = payload["approvedIntent"] as? [String: Any] {
                    print("Applied staged \(payload["intent"] ?? "intent") intent: \(intent["spaceName"] ?? intent["projectName"] ?? "Intent")")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "capability-map", "capabilities":
            let payload = secondBrainCapabilityMapPayload()
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("Second-brain agent capability map")
                if let areas = payload["areas"] as? [[String: Any]] {
                    for area in areas {
                        print("  \(area["id"] ?? ""): \(area["status"] ?? "")")
                    }
                }
            }

        case "graph-health", "health", "readiness":
            do {
                let status = try secondBrainGraphHealthStatus()
                if jsonOutput {
                    outputJSON(status)
                } else {
                    print("Second-brain graph health: \(status["status"] ?? "")")
                    if let components = status["components"] as? [[String: Any]] {
                        for component in components {
                            let id = component["id"] as? String ?? "component"
                            let state = component["state"] as? String ?? "unknown"
                            let count = component["count"] as? Int
                            print("  \(id): \(state)\(count.map { " (\($0))" } ?? "")")
                        }
                    }
                    if let commands = status["suggestedCommands"] as? [String], !commands.isEmpty {
                        print("Safe next commands:")
                        commands.forEach { print("  \($0)") }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "why-surfaced", "why":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item why-surfaced <type> <id-or-ref> [--json]")
                return
            }
            if isKanbanCardItemType(positional[0]) {
                do {
                    let packet = try kanbanCardAgentContextPayload(ref: positional[1], args: args, store: store)
                    var payload: [String: Any] = [
                        "ok": true,
                        "command": "item.why-surfaced",
                        "readOnly": true,
                        "changed": false,
                        "sourceRef": [
                            "type": "card",
                            "ref": positional[1],
                        ],
                        "item": packet["item"] ?? [:],
                        "surfacing": packet["surfacing"] ?? [:],
                        "safeCommands": packet["safeCommands"] ?? [],
                    ]
                    payload["summary"] = packet["summary"]
                    if jsonOutput {
                        outputJSON(payload)
                    } else if let surfacing = payload["surfacing"] as? [String: Any] {
                        print("Why: \(surfacing["reason"] ?? "")")
                        print("Next: \(surfacing["suggestedAction"] ?? "")")
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }
            do {
                let type = try ItemLinkService.entityType(from: positional[0])
                let ref = try ItemLinkService.shared.resolve(type: type, ref: positional[1])
                let packet = try contextService.agentContext(for: ref, limits: itemAgentContextLimits(from: args))
                var payload: [String: Any] = [
                    "ok": true,
                    "command": "item.why-surfaced",
                    "readOnly": true,
                    "changed": false,
                    "sourceRef": [
                        "type": positional[0],
                        "ref": positional[1],
                    ],
                    "item": itemSummaryToDict(packet.item),
                    "surfacing": surfacingExplanationToDict(packet.surfacing),
                    "safeCommands": packet.safeCommands,
                    "summary": packet.summary,
                ]
                CiderAgentDecisionContract.merge(itemAgentDecisionDictionary(for: packet), into: &payload)
                if jsonOutput {
                    outputJSON(payload)
                } else {
                    print("Why: \(packet.surfacing.reason)")
                    print("Next: \(packet.surfacing.suggestedAction)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "relations", "owner-relations":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item relations <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let relations = try store.outgoingRelations(for: owner)
                printOwnerRelations(relations, command: "item.relations", sourceType: positional[0], sourceRef: positional[1], owner: owner)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "backlinks", "owner-backlinks":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item backlinks <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let relations = try store.backlinks(for: owner)
                printOwnerRelations(relations, command: "item.backlinks", sourceType: positional[0], sourceRef: positional[1], owner: owner)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "related-owners", "owner-related":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item related-owners <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let relations = try store.relatedRelations(for: owner)
                printOwnerRelations(relations, command: "item.related-owners", sourceType: positional[0], sourceRef: positional[1], owner: owner)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "rebuild-references", "reference-rebuild", "references-rebuild":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item rebuild-references <note|card|board> <id-or-ref> [--json]")
                return
            }
            do {
                let extractor = SecondBrainReferenceExtractionService(store: store)
                let rawType = positional[0].lowercased().replacingOccurrences(of: "-", with: "_")
                switch rawType {
                case "note":
                    guard let note = findNote(positional[1], in: NotesStorage.shared) else { return }
                    let result = try extractor.rebuildNote(note)
                    printReferenceExtractionResults([result], command: "item.rebuild-references", sourceType: positional[0], sourceRef: positional[1])
                case "card", "kanban_card", "kanban":
                    let detail = try resolveKanbanCardDetail(ref: positional[1])
                    let result = try extractor.rebuildCard(boardID: detail.board.id, card: detail.card)
                    printReferenceExtractionResults([result], command: "item.rebuild-references", sourceType: positional[0], sourceRef: positional[1])
                case "board", "kanban_board":
                    guard let board = findBoard(positional[1], in: KanbanStorage.shared) else { return }
                    let results = try extractor.rebuildBoard(board)
                    printReferenceExtractionResults(results, command: "item.rebuild-references", sourceType: positional[0], sourceRef: positional[1])
                default:
                    printCLIError("Unsupported reference rebuild type '\(positional[0])'. Use note, card, or board.")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "rebuild-chunks", "rebuild-content", "content-rebuild":
            let positional = leadingPositionalArgs(from: args)
            guard let type = positional.first else {
                printCLIError("Usage: cider-cli item rebuild-chunks <type|all> [id-or-ref] [--limit <n>] [--json]")
                return
            }
            do {
                let indexer = SecondBrainItemContentIndexingService(database: .shared, store: store)
                let results: [SecondBrainItemContentIndexResult]
                if type.lowercased() == "all" {
                    let limit = parseFlag("--limit", from: args).flatMap(Int.init)
                    results = try indexer.rebuildAll(limit: limit)
                } else {
                    guard positional.count >= 2 else {
                        printCLIError("Usage: cider-cli item rebuild-chunks <type|all> [id-or-ref] [--limit <n>] [--json]")
                        return
                    }
                    let owner = normalizedOwner(type: positional[0], ref: positional[1])
                    results = [try indexer.rebuild(owner: owner)]
                }
                printItemContentIndexResults(results, command: "item.rebuild-chunks", sourceType: type, sourceRef: positional.dropFirst().first)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "rebuild-enrichment", "enrichment-rebuild":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item rebuild-enrichment <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let result = try SecondBrainEnrichmentOutputService(database: .shared).rebuildFromChunks(owner: owner)
                if jsonOutput {
                    outputJSON([
                        "ok": true,
                        "command": "item.rebuild-enrichment",
                        "owner": ownerToDict(result.owner),
                        "outputCount": result.outputCount,
                        "kindCounts": result.kindCounts,
                    ])
                } else {
                    print("Rebuilt enrichment outputs for \(result.owner.canonicalRef): \(result.outputCount)")
                    for key in result.kindCounts.keys.sorted() {
                        print("  \(key): \(result.kindCounts[key] ?? 0)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "memory-suggest", "suggest-memory":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item memory-suggest <owner-type> <owner-id-or-ref> --kind <kind> --value <text> --evidence <text> [--source <source>] [--confidence <0-1>] [--json]")
                return
            }
            guard let kind = parseFlag("--kind", from: args) else {
                printCLIError("Missing required flag --kind.")
                return
            }
            guard let value = parseFlag("--value", from: args) else {
                printCLIError("Missing required flag --value.")
                return
            }
            guard let evidence = parseFlag("--evidence", from: args) else {
                printCLIError("Missing required flag --evidence.")
                return
            }
            let confidence: Double?
            if let rawConfidence = parseFlag("--confidence", from: args) {
                guard let parsed = Double(rawConfidence) else {
                    printCLIError("Invalid --confidence '\(rawConfidence)'. Use a number from 0 to 1.")
                    return
                }
                confidence = parsed
            } else {
                confidence = nil
            }
            do {
                let service = SecondBrainMemoryCandidateService(database: .shared, store: store)
                let result: SecondBrainMemoryCandidateResult
                if positional[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "project" {
                    result = try service.suggest(
                        ownerType: positional[0],
                        ownerRef: positional[1],
                        kind: kind,
                        value: value,
                        evidence: evidence,
                        source: parseFlag("--source", from: args),
                        confidence: confidence
                    )
                } else {
                    result = try service.suggest(
                        owner: normalizedOwner(type: positional[0], ref: positional[1]),
                        requestedOwnerType: positional[0],
                        requestedOwnerRef: positional[1],
                        kind: kind,
                        value: value,
                        evidence: evidence,
                        source: parseFlag("--source", from: args),
                        confidence: confidence
                    )
                }
                let payload = memoryCandidateResultToDict(
                    result,
                    sourceType: positional[0],
                    sourceRef: positional[1]
                )
                if jsonOutput {
                    outputJSON(payload)
                } else {
                    print("Suggested memory candidate \(result.candidate.id) for \(result.owner.canonicalRef)")
                    print("  Review state: \(result.candidate.reviewState)")
                    print("  Kind: \(result.candidate.metadata["memory_kind"] ?? result.candidate.kind)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "rebuild-similarity", "similarity-rebuild":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item rebuild-similarity <owner-type> <owner-id-or-ref> [--threshold <0-1>] [--limit <n>] [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let threshold = parseFlag("--threshold", from: args).flatMap(Double.init) ?? 0.34
                let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 10
                let service = SecondBrainSimilarityCandidateService(database: .shared, store: store)
                let result = try service.rebuildChunkOverlapCandidates(for: owner, threshold: threshold, limit: limit)
                let candidates = try service.candidates(for: owner)
                printSimilarityCandidates(
                    candidates,
                    command: "item.rebuild-similarity",
                    owner: result.owner,
                    extra: [
                        "candidateCount": result.candidateCount,
                        "signal": result.signal,
                    ]
                )
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "dogfood-intelligence", "intelligence-dogfood":
            do {
                let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 5
                let threshold = parseFlag("--threshold", from: args).flatMap(Double.init) ?? 0.34
                let candidateLimit = parseFlag("--candidate-limit", from: args).flatMap(Int.init) ?? 10
                let result = try SecondBrainIntelligenceDogfoodService(database: .shared, store: store)
                    .rebuild(limit: limit, threshold: threshold, candidateLimit: candidateLimit)
                printIntelligenceDogfoodResult(result)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "similarity", "similarity-candidates":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item similarity <owner-type> <owner-id-or-ref> [--json]")
                return
            }
            do {
                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                let candidates = try SecondBrainSimilarityCandidateService(database: .shared, store: store).candidates(for: owner)
                printSimilarityCandidates(candidates, command: "item.similarity", owner: owner)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "accept-similarity", "similarity-accept":
            let positional = leadingPositionalArgs(from: args)
            guard let candidateID = positional.first else {
                printCLIError("Usage: cider-cli item accept-similarity <candidate-id> [--relation similar_to|duplicates|grouped_with] [--actor <name>] [--json]")
                return
            }
            do {
                let relation = parseFlag("--relation", from: args)
                let actor = parseFlag("--actor", from: args) ?? "agent"
                let accepted = try SecondBrainSimilarityCandidateService(database: .shared, store: store)
                    .accept(candidateID: candidateID, relationType: relation, actor: actor)
                if jsonOutput {
                    outputJSON([
                        "ok": true,
                        "command": "item.accept-similarity",
                        "candidate": similarityCandidateToDict(accepted),
                    ])
                } else {
                    print("Accepted \(accepted.id): \(accepted.sourceOwner.canonicalRef) -> \(accepted.targetOwner.canonicalRef) as \(relation ?? accepted.candidateType)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "project-context", "project":
            let positional = leadingPositionalArgs(from: args)
            guard let ref = positional.first else {
                printCLIError("Usage: cider-cli item project-context <project-id-or-name> [--summary] [--limit <n>] [--full] [--json]")
                return
            }
            do {
                let payload = try SecondBrainProjectGraphService(database: .shared, store: store).context(for: ref)
                printProjectContext(
                    payload,
                    command: "item.project-context",
                    sourceRef: ref,
                    limits: projectContextOutputLimits(from: args)
                )
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "sync-project", "project-sync":
            let positional = leadingPositionalArgs(from: args)
            guard let ref = positional.first else {
                printCLIError("Usage: cider-cli item sync-project <project-id-or-name> [--json]")
                return
            }
            let catalog = ProjectWorkspaceCatalog.defaultCatalog(
                boards: KanbanStorage.shared.boards,
                boardAssociations: ProjectWorkspaceAssociationStore.shared.associations
            )
            guard let workspace = projectWorkspace(ref: ref, catalog: catalog) else {
                printCLIError("Project workspace '\(ref)' not found")
                return
            }
            do {
                let payload = try SecondBrainProjectGraphService(database: .shared, store: store).syncWorkspace(
                    workspace,
                    boards: KanbanStorage.shared.boards
                )
                printProjectContext(payload, command: "item.sync-project", sourceRef: ref)
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "related":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item related <type> <id-or-ref> [--json]")
                return
            }
            if isKanbanCardItemType(positional[0]) {
                do {
                    let related = try relatedKanbanCardItems(ref: positional[1])
                    if jsonOutput {
                        outputJSON(related)
                    } else if related.isEmpty {
                        print("No related items.")
                    } else {
                        for summary in related {
                            print("  [\(summary["id"] ?? "")] \(summary["type"] ?? "item"): \(summary["title"] ?? "")")
                        }
                    }
                } catch {
                    printCLIError(error.localizedDescription)
                }
                return
            }
            do {
                let type = try ItemLinkService.entityType(from: positional[0])
                let ref = try ItemLinkService.shared.resolve(type: type, ref: positional[1])
                let related = try contextService.related(for: ref)
                if jsonOutput {
                    outputJSON(related.map(itemLinkSummaryToDict))
                } else if related.isEmpty {
                    print("No related items.")
                } else {
                    for summary in related {
                        print("  [\(summary.ref.entityID.uuidString.prefix(8))] \(summary.ref.type.rawValue): \(summary.title) — \(summary.subtitle)")
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "backfill-kanban":
            let storage = KanbanStorage.shared
            let boards: [KanbanBoard]
            if let boardRef = parseFlag("--board", from: args) {
                guard let board = findBoard(boardRef, in: storage) else {
                    if jsonOutput { outputJSON(["ok": false, "error": "Board '\(boardRef)' not found"]) }
                    return
                }
                boards = [board]
            } else {
                boards = storage.boards
            }

            let projector = SecondBrainKanbanProjectionService(store: store)
            var refreshedCards = 0
            var failures: [[String: Any]] = []
            for board in boards {
                for card in board.allCards {
                    do {
                        try projector.refreshCard(boardID: board.id, card: card)
                        refreshedCards += 1
                    } catch {
                        failures.append([
                            "boardID": board.id,
                            "cardID": card.id,
                            "error": error.localizedDescription,
                        ])
                    }
                }
            }

            if jsonOutput {
                outputJSON([
                    "boards": boards.count,
                    "cards": refreshedCards,
                    "failures": failures,
                ])
            } else {
                print("Backfilled \(refreshedCards) Kanban card projection(s) across \(boards.count) board(s).")
                if !failures.isEmpty {
                    print("Failures: \(failures.count)")
                }
            }

        case "doctor":
            do {
                let status = try secondBrainDoctorStatus()
                if jsonOutput {
                    outputJSON(status)
                } else {
                    let ok = status["ok"] as? Bool == true
                    print("Second-brain foundation: \(ok ? "ok" : "needs attention")")
                    if let tables = status["tables"] as? [[String: Any]] {
                        for table in tables {
                            let name = table["name"] as? String ?? "table"
                            let exists = table["exists"] as? Bool == true
                            let count = table["count"] as? Int
                            print("  \(exists ? "✓" : "x") \(name)\(count.map { " (\($0))" } ?? "")")
                        }
                    }
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "link":
            handleLink(subcommand: "add", args: args)

        case "batch-plan":
            handleItemBatchPlan(args: args)

        case "batch-apply":
            handleItemBatchApply(args: args)

        case "move":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item move <type> <id-or-ref> (--folder <name|path>|--path <target-folder-path>) [--actor <name>] [--source <source>] [--json]")
                return
            }
            let folder: VaultFolder
            switch resolveFolderArg(from: args) {
            case .resolved(let resolved):
                folder = resolved
            case .unspecified:
                printCLIError("item move requires --folder or --path.")
                return
            case .failed:
                return
            }
            do {
                let entityType = try ItemLinkService.entityType(from: positional[0])
                let ref = try ItemLinkService.shared.resolve(type: entityType, ref: positional[1])
                let result = try CiderItemMutationService(database: .shared).move(
                    ref: ref,
                    toFolder: folder.id,
                    targetRelativePath: folder.relativePath,
                    actor: parseFlag("--actor", from: args) ?? "cider-cli",
                    source: parseFlag("--source", from: args) ?? "cli.item.move"
                )
                if jsonOutput {
                    outputJSON(result.toDictionary())
                } else if result.ok {
                    print("Moved \(ref.type.rawValue):\(ref.entityID.uuidString.prefix(8)) to \(folder.relativePath)")
                } else {
                    printCLIError("Item move was not confirmed.", details: result.toDictionary())
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "unfile":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2 else {
                printCLIError("Usage: cider-cli item unfile <type> <id-or-ref> [--actor <name>] [--source <source>] [--json]")
                return
            }
            do {
                let entityType = try ItemLinkService.entityType(from: positional[0])
                let ref = try ItemLinkService.shared.resolve(type: entityType, ref: positional[1])
                let result = try CiderItemMutationService(database: .shared).unfile(
                    ref: ref,
                    actor: parseFlag("--actor", from: args) ?? "cider-cli",
                    source: parseFlag("--source", from: args) ?? "cli.item.unfile"
                )
                if jsonOutput {
                    outputJSON(result.toDictionary())
                } else if result.ok {
                    print("Unfiled \(ref.type.rawValue):\(ref.entityID.uuidString.prefix(8))")
                } else {
                    printCLIError("Item unfile was not confirmed.", details: result.toDictionary())
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        case "delete", "rm":
            handleItemDelete(args: args, contextService: contextService, store: store)

        case "route":
            let positional = leadingPositionalArgs(from: args)
            guard positional.count >= 2,
                  let targetType = parseFlag("--target-type", from: args),
                  let reason = parseFlag("--reason", from: args) else {
                printCLIError("Usage: cider-cli item route <type> <id-or-ref> --target-type <space|folder|board> [--target-id <id>] [--target-path <path>] --reason <text>")
                return
            }
            let normalizedTargetType = targetType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["space", "folder", "board"].contains(normalizedTargetType) else {
                printCLIError("--target-type must be one of: space, folder, board")
                return
            }
            let status = parseFlag("--status", from: args) ?? "accepted"
            guard ["accepted", "needs_review", "rejected"].contains(status) else {
                printCLIError("--status must be one of: accepted, needs_review, rejected")
                return
            }
            let confidence = Double(parseFlag("--confidence", from: args) ?? "") ?? 1.0
            guard confidence >= 0, confidence <= 1 else {
                printCLIError("--confidence must be between 0 and 1")
                return
            }
            let actor = parseFlag("--actor", from: args) ?? "cider-cli"
            let source = parseFlag("--source", from: args) ?? "cli"
            let targetID = parseFlag("--target-id", from: args)
            let targetPath = parseFlag("--target-path", from: args)
            var resolvedTargetID = targetID
            var resolvedTargetPath = targetPath
            var resolvedTargetName = targetPath ?? targetID ?? normalizedTargetType
            var resolvedTargetFolderID: UUID? = normalizedTargetType == "folder" ? targetID.flatMap(UUID.init(uuidString:)) : nil
            if normalizedTargetType == "folder" {
                guard let folderRef = (targetID ?? targetPath)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !folderRef.isEmpty else {
                    printCLIError("Folder routes require --target-id <folder-id> or --target-path <folder-path>.")
                    return
                }
                switch resolveFolderOwner(ref: folderRef) {
                case .folder(let folder):
                    resolvedTargetID = folder.id.uuidString
                    resolvedTargetPath = folder.relativePath
                    resolvedTargetName = folder.name
                    resolvedTargetFolderID = folder.id
                case .inbox:
                    resolvedTargetID = "Inbox"
                    resolvedTargetPath = "Inbox"
                    resolvedTargetName = "Inbox"
                    resolvedTargetFolderID = nil
                case .missing:
                    processExitCode = 1
                    let payload = folderRouteResolutionFailurePayload(
                        sourceRef: folderRef,
                        targetType: normalizedTargetType,
                        targetPath: targetPath ?? targetID,
                        error: "No folder found matching '\(folderRef)'.",
                        matches: []
                    )
                    if jsonOutput {
                        outputJSON(payload)
                    } else {
                        print("Error: No folder found matching '\(folderRef)'.")
                    }
                    return
                case .ambiguous(let matches):
                    processExitCode = 1
                    let payload = folderRouteResolutionFailurePayload(
                        sourceRef: folderRef,
                        targetType: normalizedTargetType,
                        targetPath: targetPath ?? targetID,
                        error: "Ambiguous folder reference '\(folderRef)'. Use one of the returned relativePath or id values.",
                        matches: matches
                    )
                    if jsonOutput {
                        outputJSON(payload)
                    } else {
                        print("Error: Ambiguous folder reference '\(folderRef)'.")
                    }
                    return
                }
            }
            do {
                if let entityType = try? ItemLinkService.entityType(from: positional[0]) {
                    let ref = try ItemLinkService.shared.resolve(type: entityType, ref: positional[1])
                    if normalizedTargetType == "space" {
                        guard targetID != nil || targetPath != nil else {
                            printCLIError("Space routes require --target-id <space-id> or --target-path <space-name-or-path>.")
                            return
                        }
                        let space = resolveSpaceTarget(targetID: targetID, targetPath: targetPath)
                        let finalSpaceID = space?.id ?? targetID ?? targetPath!
                        let finalSpaceName = space?.name ?? targetPath ?? targetID ?? finalSpaceID
                        let routingService = CiderRoutingDecisionService()
                        let explanation: CiderRoutingExplanation
                        if status == "accepted" {
                            explanation = try routingService.recordSpaceAssignment(
                                itemID: ref.entityID,
                                spaceID: finalSpaceID,
                                spaceName: finalSpaceName,
                                reason: reason,
                                confidence: confidence,
                                actor: actor,
                                source: source
                            )
                        } else {
                            _ = try routingService.recordDecision(
                                itemID: ref.entityID,
                                itemType: ref.type.rawValue,
                                target: CiderRoutingDecisionTarget(
                                    kind: "space",
                                    name: finalSpaceName,
                                    relativePath: targetPath ?? finalSpaceName,
                                    folderID: nil,
                                    spaceID: finalSpaceID
                                ),
                                confidence: confidence,
                                reason: reason,
                                actor: actor,
                                source: source,
                                reviewState: status
                            )
                            explanation = try routingService.explain(itemID: ref.entityID)
                        }
                        let owner = SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
                        try store.recordAgentAction(
                            SecondBrainAgentAction(
                                owner: owner,
                                itemID: ref.entityID.uuidString,
                                toolName: "item.route",
                                actionType: "route.space",
                                source: source,
                                status: "succeeded",
                                summary: reason
                            )
                        )
                        if jsonOutput {
                            outputJSON([
                                "ok": true,
                                "targetType": "space",
                                "space": [
                                    "id": finalSpaceID,
                                    "name": finalSpaceName,
                                ],
                                "explanation": explanation.toDictionary(),
                            ])
                        } else {
                            print("Recorded native Space route for \(owner.ownerType):\(owner.ownerID) -> \(finalSpaceName)")
                        }
                        return
                    }
                    let target = CiderRoutingDecisionTarget(
                        kind: normalizedTargetType,
                        name: resolvedTargetName,
                        relativePath: resolvedTargetPath ?? resolvedTargetID ?? normalizedTargetType,
                        folderID: resolvedTargetFolderID
                    )
                    let routingDecision = try CiderRoutingDecisionService().recordDecision(
                        itemID: ref.entityID,
                        itemType: ref.type.rawValue,
                        target: target,
                        confidence: confidence,
                        reason: reason,
                        actor: actor,
                        source: source,
                        reviewState: status
                    )
                    let owner = SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
                    try store.recordAgentAction(
                        SecondBrainAgentAction(
                            owner: owner,
                            itemID: ref.entityID.uuidString,
                            toolName: "item.route",
                            actionType: "route",
                            source: source,
                            status: "succeeded",
                            summary: reason
                        )
                    )
                    guard let decision = try store.routingDecisions(for: owner)
                        .first(where: { $0.id == routingDecision.id.uuidString }) else {
                        printCLIError("Recorded route but could not read back second-brain provenance.")
                        return
                    }
                    if jsonOutput {
                        outputJSON(routingDecisionToDict(decision))
                    } else {
                        print("Recorded route for \(owner.ownerType):\(owner.ownerID) -> \(targetType)")
                    }
                    return
                }

                let owner = normalizedOwner(type: positional[0], ref: positional[1])
                guard ownerExists(type: positional[0], ref: positional[1], owner: owner) else {
                    printCLIError("No resolved owner found for \(positional[0]):\(positional[1]); item route will not write phantom provenance.")
                    return
                }
                let decision = SecondBrainRoutingDecision(
                    owner: owner,
                    targetType: normalizedTargetType,
                    targetID: resolvedTargetID,
                    targetPath: resolvedTargetPath,
                    confidence: confidence,
                    reason: reason,
                    status: status,
                    actor: actor,
                    source: source
                )
                try store.recordRoutingDecision(decision)
                try store.recordAgentAction(
                    SecondBrainAgentAction(
                        owner: owner,
                        toolName: "item.route",
                        actionType: "route",
                        source: decision.source,
                        status: "succeeded",
                        summary: reason
                    )
                )
                if jsonOutput {
                    outputJSON(routingDecisionToDict(decision))
                } else {
                    print("Recorded route for \(owner.ownerType):\(owner.ownerID) -> \(targetType)")
                }
            } catch {
                printCLIError(error.localizedDescription)
            }

        default:
            printCLIError("Unknown item command: \(subcommand ?? "nil"). Run 'cider-cli item help' for usage.")
        }
    }

    struct ItemBatchOperationPlan {
        var index: Int
        var operationID: String
        var action: String
        var type: String?
        var ref: String?
        var status: String
        var error: String?
        var itemRef: LibraryEntityRef?
        var targetItemRef: LibraryEntityRef?
        var targetType: String?
        var targetID: String?
        var targetRef: String?
        var targetFolder: VaultFolder?
        var targetRelativePath: String?
        var reason: String?
        var confidence: Double?
        var routeStatus: String?
        var applySupported: Bool

        init(
            index: Int,
            operationID: String,
            action: String,
            type: String?,
            ref: String?,
            status: String,
            error: String?,
            itemRef: LibraryEntityRef?,
            targetItemRef: LibraryEntityRef? = nil,
            targetType: String? = nil,
            targetID: String? = nil,
            targetRef: String? = nil,
            targetFolder: VaultFolder?,
            targetRelativePath: String?,
            reason: String? = nil,
            confidence: Double? = nil,
            routeStatus: String? = nil,
            applySupported: Bool
        ) {
            self.index = index
            self.operationID = operationID
            self.action = action
            self.type = type
            self.ref = ref
            self.status = status
            self.error = error
            self.itemRef = itemRef
            self.targetItemRef = targetItemRef
            self.targetType = targetType
            self.targetID = targetID
            self.targetRef = targetRef
            self.targetFolder = targetFolder
            self.targetRelativePath = targetRelativePath
            self.reason = reason
            self.confidence = confidence
            self.routeStatus = routeStatus
            self.applySupported = applySupported
        }

        @MainActor
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "index": index,
                "id": operationID,
                "action": action,
                "status": status,
                "applySupported": applySupported,
            ]
            if let type { dict["type"] = type }
            if let ref { dict["ref"] = ref }
            if let itemRef {
                dict["item"] = ["type": itemRef.type.rawValue, "id": itemRef.entityID.uuidString]
            }
            if let targetItemRef {
                dict["targetItem"] = ["type": targetItemRef.type.rawValue, "id": targetItemRef.entityID.uuidString]
            }
            if let targetType { dict["targetType"] = targetType }
            if let targetID { dict["targetID"] = targetID }
            if let targetRef { dict["targetRef"] = targetRef }
            if let targetRelativePath { dict["targetRelativePath"] = targetRelativePath }
            if let targetFolder { dict["target"] = folderToDict(targetFolder) }
            if let reason { dict["reason"] = reason }
            if let confidence { dict["confidence"] = confidence }
            if let routeStatus { dict["routeStatus"] = routeStatus }
            if let error { dict["error"] = error }
            return dict
        }
    }

    static func handleItemBatchPlan(args: [String]) {
        do {
            let input = try itemBatchInput(from: args)
            let plans = try itemBatchOperations(from: input).enumerated().map { index, operation in
                itemBatchOperationPlan(index: index, operation: operation)
            }
            outputJSON(itemBatchEnvelope(
                command: "item.batch.plan",
                readOnly: true,
                changed: false,
                operations: plans,
                approvalToken: itemBatchApprovalToken(for: plans),
                partialFailures: []
            ))
        } catch {
            printItemBatchError(command: "item.batch.plan", message: error.localizedDescription)
        }
    }

    static func handleItemBatchApply(args: [String]) {
        do {
            let input = try itemBatchInput(from: args)
            let plans = try itemBatchOperations(from: input).enumerated().map { index, operation in
                itemBatchOperationPlan(index: index, operation: operation)
            }
            let token = itemBatchApprovalToken(for: plans)
            guard parseFlag("--approve", from: args) == token else {
                printItemBatchError(command: "item.batch.apply", message: "Batch apply requires --approve \(token).", approvalToken: token, operations: plans)
                return
            }
            guard args.contains("--execute") else {
                printItemBatchError(command: "item.batch.apply", message: "Batch apply requires --execute after approval.", approvalToken: token, operations: plans)
                return
            }

            let mutationService = CiderItemMutationService(database: .shared)
            var changed = false
            var partialFailures: [String] = []
            var outputOperations: [[String: Any]] = []
            for plan in plans {
                var dict = plan.toDictionary()
                guard plan.status == "valid" else {
                    partialFailures.append("\(plan.operationID): \(plan.error ?? "invalid_operation")")
                    outputOperations.append(dict)
                    continue
                }
                guard plan.applySupported, let ref = plan.itemRef else {
                    let message = "apply_not_supported_for_\(plan.action)"
                    dict["status"] = "skipped"
                    dict["error"] = message
                    partialFailures.append("\(plan.operationID): \(message)")
                    outputOperations.append(dict)
                    continue
                }

                do {
                    let result: CiderItemMutationResult
                    if plan.action == "move" {
                        guard let folder = plan.targetFolder else {
                            throw CaptureAddArgumentError.message("missing_target_folder")
                        }
                        result = try mutationService.move(
                            ref: ref,
                            toFolder: folder.id,
                            targetRelativePath: folder.relativePath,
                            actor: parseFlag("--actor", from: args) ?? "agent",
                            source: "item.batch.apply",
                            reason: "Applied through approval-gated item batch."
                        )
                    } else if plan.action == "unfile" {
                        result = try mutationService.unfile(
                            ref: ref,
                            actor: parseFlag("--actor", from: args) ?? "agent",
                            source: "item.batch.apply",
                            reason: "Applied through approval-gated item batch."
                        )
                    } else if plan.action == "route" {
                        let route = try applyItemBatchRoute(plan: plan, ref: ref, actor: parseFlag("--actor", from: args) ?? "agent")
                        var routeDict = plan.toDictionary()
                        routeDict["status"] = "applied"
                        routeDict["routingDecision"] = route
                        outputOperations.append(routeDict)
                        changed = true
                        continue
                    } else if plan.action == "link" {
                        let link = try applyItemBatchLink(plan: plan, ref: ref, actor: parseFlag("--actor", from: args) ?? "agent")
                        var linkDict = plan.toDictionary()
                        linkDict["status"] = "applied"
                        linkDict["link"] = link
                        outputOperations.append(linkDict)
                        changed = true
                        continue
                    } else {
                        throw CaptureAddArgumentError.message("apply_not_supported_for_\(plan.action)")
                    }
                    var resultDict = result.toDictionary()
                    resultDict["index"] = plan.index
                    resultDict["id"] = plan.operationID
                    resultDict["status"] = result.ok ? "applied" : "failed"
                    outputOperations.append(resultDict)
                    changed = changed || result.ok
                    partialFailures.append(contentsOf: result.partialFailures.map { "\(plan.operationID): \($0)" })
                } catch {
                    dict["status"] = "failed"
                    dict["error"] = error.localizedDescription
                    partialFailures.append("\(plan.operationID): \(error.localizedDescription)")
                    outputOperations.append(dict)
                }
            }

            outputJSON([
                "ok": partialFailures.isEmpty,
                "command": "item.batch.apply",
                "readOnly": false,
                "changed": changed,
                "approvalRequired": true,
                "requiredApprovalToken": token,
                "operationCount": plans.count,
                "operations": outputOperations,
                "partialFailures": partialFailures,
                "nextSafeAction": partialFailures.isEmpty ? "inspect_items" : "inspect_partial_failures",
                "safeNextCommands": ["cider-cli db audit --source cli --json", "cider-cli item search <query> --json"],
                "rollbackGuidance": "Use the per-operation before/after payloads and mutation audit entries to inspect or reverse each item with blessed item commands.",
            ] as [String: Any])
        } catch {
            printItemBatchError(command: "item.batch.apply", message: error.localizedDescription)
        }
    }

    static func applyItemBatchRoute(plan: ItemBatchOperationPlan, ref: LibraryEntityRef, actor: String) throws -> [String: Any] {
        guard let targetType = plan.targetType,
              let reason = plan.reason else {
            throw CaptureAddArgumentError.message("invalid_route_operation")
        }
        let targetPath = plan.targetRelativePath
        let targetID = plan.targetID
        let target = CiderRoutingDecisionTarget(
            kind: targetType,
            name: targetPath ?? targetID ?? targetType,
            relativePath: targetPath ?? targetID ?? targetType,
            folderID: targetType == "folder" ? targetID.flatMap(UUID.init(uuidString:)) : nil,
            spaceID: targetType == "space" ? targetID : nil
        )
        let routingDecision = try CiderRoutingDecisionService().recordDecision(
            itemID: ref.entityID,
            itemType: ref.type.rawValue,
            target: target,
            confidence: plan.confidence ?? 1.0,
            reason: reason,
            actor: actor,
            source: "item.batch.apply",
            reviewState: plan.routeStatus ?? "accepted"
        )
        let owner = SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
        let store = SecondBrainStore(database: .shared)
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: ref.entityID.uuidString,
                toolName: "item.batch.apply",
                actionType: "route",
                source: "item.batch.apply",
                status: "succeeded",
                summary: reason
            )
        )
        if let decision = try store.routingDecisions(for: owner)
            .first(where: { $0.id == routingDecision.id.uuidString }) {
            return routingDecisionToDict(decision)
        }
        return [
            "id": routingDecision.id.uuidString,
            "owner": ownerToDict(owner),
            "targetType": targetType,
            "targetPath": targetPath ?? "",
            "targetID": targetID ?? "",
            "confidence": plan.confidence ?? 1.0,
            "reason": reason,
            "status": plan.routeStatus ?? "accepted",
            "actor": actor,
            "source": "item.batch.apply",
        ]
    }

    static func applyItemBatchLink(plan: ItemBatchOperationPlan, ref: LibraryEntityRef, actor: String) throws -> [String: Any] {
        guard let target = plan.targetItemRef else {
            throw CaptureAddArgumentError.message("invalid_link_operation")
        }
        try ItemLinkService.shared.addLink(from: ref, to: target)
        let owner = SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
        try SecondBrainStore(database: .shared).recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: ref.entityID.uuidString,
                toolName: "item.batch.apply",
                actionType: "link",
                source: "item.batch.apply",
                status: "succeeded",
                summary: "Linked \(ref.type.rawValue):\(ref.entityID.uuidString) to \(target.type.rawValue):\(target.entityID.uuidString)."
            )
        )
        return [
            "source": [
                "type": ref.type.rawValue,
                "id": ref.entityID.uuidString,
            ],
            "target": [
                "type": target.type.rawValue,
                "id": target.entityID.uuidString,
            ],
            "actor": actor,
            "sourceCommand": "item.batch.apply",
        ]
    }

    static func itemBatchInput(from args: [String]) throws -> String {
        guard args.contains("--stdin") else {
            throw CaptureAddArgumentError.message("Usage: cider-cli item batch-plan --stdin --json or cider-cli item batch-apply --stdin --approve <token> --execute --json")
        }
        guard let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8),
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureAddArgumentError.message("Could not read batch JSON from stdin.")
        }
        return input
    }

    static func itemBatchOperations(from input: String) throws -> [[String: Any]] {
        guard let data = input.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operations = object["operations"] as? [[String: Any]],
              !operations.isEmpty else {
            throw CaptureAddArgumentError.message("Batch JSON must be an object with a non-empty operations array.")
        }
        return operations
    }

    static func itemBatchOperationPlan(index: Int, operation: [String: Any]) -> ItemBatchOperationPlan {
        let id = (operation["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = ((operation["action"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let type = (operation["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = (operation["ref"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let operationID = id?.isEmpty == false ? id! : "op-\(index)"
        guard ["move", "unfile", "route", "link"].contains(action) else {
            return ItemBatchOperationPlan(index: index, operationID: operationID, action: action.isEmpty ? "unknown" : action, type: type, ref: ref, status: "invalid", error: "action_must_be_move_unfile_route_or_link", itemRef: nil, targetFolder: nil, targetRelativePath: nil, applySupported: false)
        }
        guard let type, let ref, !type.isEmpty, !ref.isEmpty else {
            return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: type, ref: ref, status: "invalid", error: "type_and_ref_required", itemRef: nil, targetFolder: nil, targetRelativePath: nil, applySupported: false)
        }
        let entityType: LibraryEntityType
        let itemRef: LibraryEntityRef
        do {
            entityType = try ItemLinkService.entityType(from: type)
            itemRef = try ItemLinkService.shared.resolve(type: entityType, ref: ref)
        } catch {
            return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: type, ref: ref, status: "invalid", error: error.localizedDescription, itemRef: nil, targetFolder: nil, targetRelativePath: nil, applySupported: false)
        }

        if action == "move" {
            let path = (operation["path"] as? String) ?? (operation["targetPath"] as? String) ?? (operation["folder"] as? String)
            guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "path_required_for_move", itemRef: itemRef, targetFolder: nil, targetRelativePath: nil, applySupported: false)
            }
            if looksLikeVaultArtifactPath(path) {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_path_must_be_folder_path", itemRef: itemRef, targetFolder: nil, targetRelativePath: path, applySupported: false)
            }
            let folder: VaultFolder?
            if operation["folder"] as? String != nil,
               operation["path"] == nil,
               operation["targetPath"] == nil {
                switch resolveFolderOwner(ref: path) {
                case .folder(let resolvedFolder):
                    folder = resolvedFolder
                case .inbox:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_is_inbox", itemRef: itemRef, targetFolder: nil, targetRelativePath: path, applySupported: false)
                case .ambiguous:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_ambiguous", itemRef: itemRef, targetFolder: nil, targetRelativePath: path, applySupported: false)
                case .missing:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_not_found", itemRef: itemRef, targetFolder: nil, targetRelativePath: path, applySupported: false)
                }
            } else {
                folder = findOrCreateFolderByPath(path)
            }
            guard let folder else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_not_found", itemRef: itemRef, targetFolder: nil, targetRelativePath: path, applySupported: false)
            }
            return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "valid", error: nil, itemRef: itemRef, targetFolder: folder, targetRelativePath: folder.relativePath, applySupported: true)
        }

        if action == "route" {
            let targetType = ((operation["targetType"] as? String) ?? (operation["target-type"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard ["space", "folder", "board"].contains(targetType) else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_type_must_be_space_folder_or_board", itemRef: itemRef, targetFolder: nil, targetRelativePath: operation["targetPath"] as? String, applySupported: false)
            }
            let targetID = (operation["targetID"] as? String) ?? (operation["targetId"] as? String) ?? (operation["target-id"] as? String)
            let targetPath = (operation["targetPath"] as? String) ?? (operation["target-path"] as? String) ?? (operation["path"] as? String)
            guard targetID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || targetPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_id_or_target_path_required_for_route", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, applySupported: false)
            }
            let reason = ((operation["reason"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "reason_required_for_route", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, applySupported: false)
            }
            let routeStatus = ((operation["status"] as? String) ?? "accepted").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["accepted", "needs_review", "rejected"].contains(routeStatus) else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "route_status_must_be_accepted_needs_review_or_rejected", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, reason: reason, applySupported: false)
            }
            let confidence = Double("\(operation["confidence"] ?? "")") ?? 1.0
            guard confidence >= 0, confidence <= 1 else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "confidence_must_be_between_0_and_1", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, reason: reason, routeStatus: routeStatus, applySupported: false)
            }
            var resolvedTargetID = targetID
            var resolvedTargetPath = targetPath
            var resolvedTargetFolder: VaultFolder?
            if targetType == "folder" {
                let folderRef = (targetID ?? targetPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                switch resolveFolderOwner(ref: folderRef) {
                case .folder(let folder):
                    resolvedTargetID = folder.id.uuidString
                    resolvedTargetPath = folder.relativePath
                    resolvedTargetFolder = folder
                case .inbox:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_is_inbox", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, reason: reason, routeStatus: routeStatus, applySupported: false)
                case .ambiguous:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_ambiguous", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, reason: reason, routeStatus: routeStatus, applySupported: false)
                case .missing:
                    return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_folder_not_found", itemRef: itemRef, targetType: targetType, targetID: targetID, targetFolder: nil, targetRelativePath: targetPath, reason: reason, routeStatus: routeStatus, applySupported: false)
                }
            }
            return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "valid", error: nil, itemRef: itemRef, targetType: targetType, targetID: resolvedTargetID, targetFolder: resolvedTargetFolder, targetRelativePath: resolvedTargetPath, reason: reason, confidence: confidence, routeStatus: routeStatus, applySupported: true)
        }

        if action == "link" {
            let targetType = ((operation["targetType"] as? String) ?? (operation["target-type"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let targetRef = ((operation["targetRef"] as? String) ?? (operation["target-ref"] as? String) ?? (operation["targetID"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetType.isEmpty, !targetRef.isEmpty else {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: "target_type_and_target_ref_required_for_link", itemRef: itemRef, targetType: targetType.isEmpty ? nil : targetType, targetRef: targetRef.isEmpty ? nil : targetRef, targetFolder: nil, targetRelativePath: nil, applySupported: false)
            }
            do {
                let targetEntityType = try ItemLinkService.entityType(from: targetType)
                let targetItemRef = try ItemLinkService.shared.resolve(type: targetEntityType, ref: targetRef)
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "valid", error: nil, itemRef: itemRef, targetItemRef: targetItemRef, targetType: targetEntityType.rawValue, targetRef: targetRef, targetFolder: nil, targetRelativePath: nil, applySupported: true)
            } catch {
                return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "invalid", error: error.localizedDescription, itemRef: itemRef, targetType: targetType, targetRef: targetRef, targetFolder: nil, targetRelativePath: nil, applySupported: false)
            }
        }

        return ItemBatchOperationPlan(index: index, operationID: operationID, action: action, type: entityType.rawValue, ref: ref, status: "valid", error: nil, itemRef: itemRef, targetFolder: nil, targetRelativePath: operation["targetPath"] as? String, applySupported: action == "unfile")
    }

    static func itemBatchApprovalToken(for plans: [ItemBatchOperationPlan]) -> String {
        let seed = plans.map {
            "\($0.index)|\($0.operationID)|\($0.action)|\($0.type ?? "")|\($0.ref ?? "")|\($0.targetRelativePath ?? "")|\($0.status)"
        }.joined(separator: "\n")
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "APPROVE_BATCH_" + String(hash, radix: 16).uppercased()
    }

    static func itemBatchEnvelope(
        command: String,
        readOnly: Bool,
        changed: Bool,
        operations: [ItemBatchOperationPlan],
        approvalToken: String,
        partialFailures: [String]
    ) -> [String: Any] {
        let invalidCount = operations.filter { $0.status != "valid" }.count
        return [
            "ok": invalidCount == 0 && partialFailures.isEmpty,
            "command": command,
            "readOnly": readOnly,
            "changed": changed,
            "approvalRequired": true,
            "requiredApprovalToken": approvalToken,
            "operationCount": operations.count,
            "validOperationCount": operations.count - invalidCount,
            "invalidOperationCount": invalidCount,
            "operations": operations.map { $0.toDictionary() },
            "partialFailures": partialFailures,
            "nextSafeAction": invalidCount == 0 ? "approve_batch_apply" : "fix_batch_request",
            "safeNextCommands": ["cider-cli item batch-apply --stdin --approve \(approvalToken) --execute --json"],
            "rollbackGuidance": "No mutation has happened in the plan step. Apply only after reviewing every operation.",
        ] as [String: Any]
    }

    static func printItemBatchError(
        command: String,
        message: String,
        approvalToken: String? = nil,
        operations: [ItemBatchOperationPlan] = []
    ) {
        processExitCode = 1
        if jsonOutput {
            var payload: [String: Any] = [
                "ok": false,
                "command": command,
                "readOnly": command == "item.batch.plan",
                "changed": false,
                "approvalRequired": true,
                "error": message,
                "operations": operations.map { $0.toDictionary() },
                "partialFailures": [message],
                "nextSafeAction": "fix_batch_request",
                "safeNextCommands": ["cider-cli item batch-plan --stdin --json"],
            ]
            if let approvalToken {
                payload["requiredApprovalToken"] = approvalToken
            }
            outputJSON(payload)
        } else {
            print("Error: \(message)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Agent-safe Export Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleExport(subcommand: String?, args: [String]) {
        switch subcommand {
        case nil, "help", "--help", "-h":
            print("""
            Agent-safe export commands:
              cider-cli export folder <relative-path|id|Inbox> --format json|md [--limit <n>] [--json]
              cider-cli export item <type> <id-or-ref> --format json|md [--json]
              cider-cli export card <board-id/card-id|card-id> --format json|md [--json]
              cider-cli export project <project-id-or-name> --format json|md [--limit <n>] [--json]

            Whole-vault export is intentionally unavailable; export bounded folders, projects, cards, or items.
            """)
        case "folder":
            handleFolderExport(args: args)
        case "item":
            handleItemExport(args: args)
        case "card":
            handleCardExport(args: args)
        case "project":
            handleProjectExport(args: args)
        case "vault", "all":
            printExportError(
                command: "export.vault",
                message: "Whole-vault export is not available through the agent CLI. Export a bounded folder, project, card, or item instead.",
                safeNextCommands: [
                    "cider-cli export folder <relative-path> --format json --limit 100 --json",
                    "cider-cli export project <project-id-or-name> --format json --limit 100 --json",
                    "cider-cli export card <board-id/card-id> --format json --json",
                    "cider-cli export item <type> <id-or-ref> --format json --json",
                ]
            )
        default:
            printExportError(
                command: "export",
                message: "Unknown export scope '\(subcommand ?? "nil")'. Run 'cider-cli export help' for usage.",
                safeNextCommands: ["cider-cli export help"]
            )
        }
    }

    static func handleFolderExport(args: [String]) {
        let positional = leadingPositionalArgs(from: args)
        guard let folderRef = positional.first else {
            printExportError(
                command: "export.folder",
                message: "Usage: cider-cli export folder <relative-path|id|Inbox> --format json|md [--limit <n>] [--json]",
                safeNextCommands: ["cider-cli item owner-get folder <relative-path-or-id> --json"]
            )
            return
        }
        let format = exportFormat(from: args)
        guard exportFormatIsSupported(format) else {
            printExportError(command: "export.folder", message: "--format must be json or md.")
            return
        }
        guard let limit = exportLimit(from: args) else {
            printExportError(command: "export.folder", message: "--limit must be a positive integer.")
            return
        }

        let folderPath: String
        let folderIDs: Set<UUID>
        let scope: [String: Any]
        switch resolveFolderOwner(ref: folderRef) {
        case .folder(let folder):
            let descendants = VaultFolderService.shared.folders.filter { $0.relativePath.hasPrefix(folder.relativePath + "/") }
            folderIDs = Set(([folder] + descendants).map(\.id))
            folderPath = folder.relativePath
            scope = [
                "type": "folder",
                "id": folder.id.uuidString,
                "name": folder.name,
                "relativePath": folder.relativePath,
                "descendantFolderCount": descendants.count,
            ]
        case .inbox:
            folderIDs = []
            folderPath = "Inbox"
            scope = [
                "type": "folder",
                "id": "Inbox",
                "name": "Inbox",
                "relativePath": "Inbox",
                "descendantFolderCount": 0,
            ]
        case .ambiguous(let matches):
            printExportError(
                command: "export.folder",
                message: "Ambiguous folder reference '\(folderRef)'. Use a returned relativePath or id.",
                payload: ["matches": matches.map(folderOwnerMatchDict)],
                safeNextCommands: ["cider-cli item owner-get folder <relative-path-or-id> --json"]
            )
            return
        case .missing:
            printExportError(
                command: "export.folder",
                message: "No folder found matching '\(folderRef)'.",
                safeNextCommands: ["cider-cli item owner-get folder <relative-path-or-id> --json"]
            )
            return
        }

        let refs = exportRefs(inFolderIDs: folderIDs, includeInbox: folderPath == "Inbox")
        guard refs.count <= limit else {
            printExportError(
                command: "export.folder",
                message: "Export scope contains \(refs.count) items, which exceeds --limit \(limit). Increase --limit after reviewing the scope.",
                payload: [
                    "scope": scope,
                    "counts": ["totalItems": refs.count, "limit": limit],
                    "nextSafeAction": "inspect_export_scope",
                ],
                safeNextCommands: [
                    "cider-cli item owner-get folder \"\(folderPath)\" --json",
                    "cider-cli export folder \"\(folderPath)\" --format json --limit \(refs.count) --json",
                ]
            )
            return
        }

        let payload = exportPayload(
            command: "export.folder",
            format: format,
            scope: scope,
            refs: refs,
            limit: limit,
            safeNextCommands: [
                "cider-cli export folder \"\(folderPath)\" --format json --limit \(limit) --json",
                "cider-cli export folder \"\(folderPath)\" --format md --limit \(limit)",
                "cider-cli item owner-get folder \"\(folderPath)\" --json",
            ]
        )
        printExportPayload(payload, format: format)
    }

    static func handleItemExport(args: [String]) {
        let positional = leadingPositionalArgs(from: args)
        guard positional.count >= 2 else {
            printExportError(command: "export.item", message: "Usage: cider-cli export item <type> <id-or-ref> --format json|md [--json]")
            return
        }
        do {
            let type = try ItemLinkService.entityType(from: positional[0])
            let ref = try ItemLinkService.shared.resolve(type: type, ref: positional[1])
            let format = exportFormat(from: args)
            guard exportFormatIsSupported(format) else {
                printExportError(command: "export.item", message: "--format must be json or md.")
                return
            }
            let payload = exportPayload(
                command: "export.item",
                format: format,
                scope: [
                    "type": "item",
                    "itemType": ref.type.rawValue,
                    "id": ref.entityID.uuidString,
                    "ref": "\(ref.type.rawValue):\(ref.entityID.uuidString)",
                ],
                refs: [ref],
                limit: 1,
                safeNextCommands: [
                    "cider-cli item get \(ref.type.rawValue) \(ref.entityID.uuidString) --json",
                    "cider-cli export item \(ref.type.rawValue) \(ref.entityID.uuidString) --format md",
                ]
            )
            printExportPayload(payload, format: format)
        } catch {
            printExportError(command: "export.item", message: error.localizedDescription)
        }
    }

    static func handleCardExport(args: [String]) {
        let positional = leadingPositionalArgs(from: args)
        guard let cardRef = positional.first else {
            printExportError(command: "export.card", message: "Usage: cider-cli export card <board-id/card-id|card-id> --format json|md [--json]")
            return
        }
        let format = exportFormat(from: args)
        guard exportFormatIsSupported(format) else {
            printExportError(command: "export.card", message: "--format must be json or md.")
            return
        }
        do {
            let detail = try resolveKanbanCardDetail(ref: cardRef)
            let store = SecondBrainStore(database: .shared)
            var cardPayload = try kanbanCardItemPayload(ref: "\(detail.board.id)/\(detail.card.id)", store: store)
            cardPayload["command"] = "item.get"
            let markdown = KanbanCardMarkdownExporter.markdown(
                for: detail.card,
                boardName: detail.board.name,
                columnName: detail.column.name
            )
            let payload: [String: Any] = [
                "ok": true,
                "command": "export.card",
                "readOnly": true,
                "changed": false,
                "format": format,
                "scope": [
                    "type": "card",
                    "boardID": detail.board.id,
                    "boardName": detail.board.name,
                    "columnID": detail.column.id,
                    "columnName": detail.column.name,
                    "cardID": detail.card.id,
                    "ref": "kanban_card:\(detail.board.id)/\(detail.card.id)",
                ],
                "counts": ["totalItems": 1, "includedItems": 1, "limit": 1, "truncated": false],
                "card": cardPayload,
                "markdown": markdown,
                "safeNextCommands": [
                    "cider-cli board card inspect \(detail.board.id) --card \(detail.card.id) --json",
                    "cider-cli item get card \(detail.card.id) --json",
                    "cider-cli export card \(detail.board.id)/\(detail.card.id) --format md",
                ],
            ]
            if format == "md" && !jsonOutput {
                print(markdown)
            } else {
                outputJSON(payload)
            }
        } catch {
            printExportError(command: "export.card", message: error.localizedDescription)
        }
    }

    static func handleProjectExport(args: [String]) {
        let positional = leadingPositionalArgs(from: args)
        guard let projectRef = positional.first else {
            printExportError(command: "export.project", message: "Usage: cider-cli export project <project-id-or-name> --format json|md [--limit <n>] [--json]")
            return
        }
        guard let limit = exportLimit(from: args) else {
            printExportError(command: "export.project", message: "--limit must be a positive integer.")
            return
        }
        let format = exportFormat(from: args)
        guard exportFormatIsSupported(format) else {
            printExportError(command: "export.project", message: "--format must be json or md.")
            return
        }
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: KanbanStorage.shared.boards)
        guard let workspace = projectWorkspace(ref: projectRef, catalog: catalog) else {
            printExportError(command: "export.project", message: "No project found matching '\(projectRef)'.")
            return
        }
        let refs = NotesStorage.shared.notes
            .filter { $0.projectID == workspace.id }
            .map { LibraryEntityRef(type: .note, entityID: $0.id) }
        let payload = exportPayload(
            command: "export.project",
            format: format,
            scope: ["type": "project", "id": workspace.id, "title": workspace.title],
            refs: refs,
            limit: limit,
            safeNextCommands: [
                "cider-cli item project-context \(workspace.id) --summary --json",
                "cider-cli export project \(workspace.id) --format md --limit \(limit)",
            ]
        )
        printExportPayload(payload, format: format)
    }

    static func exportFormat(from args: [String]) -> String {
        let raw = parseFlag("--format", from: args)?.lowercased() ?? (jsonOutput ? "json" : "md")
        return raw == "markdown" ? "md" : raw
    }

    static func exportFormatIsSupported(_ format: String) -> Bool {
        format == "json" || format == "md"
    }

    static func exportLimit(from args: [String]) -> Int? {
        let raw = parseFlag("--limit", from: args) ?? "100"
        guard let limit = Int(raw), limit > 0 else { return nil }
        return limit
    }

    static func exportRefs(inFolderIDs folderIDs: Set<UUID>, includeInbox: Bool) -> [LibraryEntityRef] {
        func matches(_ folderID: UUID?) -> Bool {
            includeInbox ? folderID == nil : folderID.map { folderIDs.contains($0) } == true
        }
        var refs: [LibraryEntityRef] = []
        refs += VaultBookmarkService.shared.bookmarks.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .bookmark, entityID: $0.id) }
        refs += NotesStorage.shared.notes.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .note, entityID: $0.id) }
        refs += TodoCardStorage.shared.todoCards.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .todo, entityID: $0.id) }
        refs += DateCardStorage.shared.dateCards.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .dateCard, entityID: $0.id) }
        refs += ContactStorage.shared.contacts.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .contact, entityID: $0.id) }
        refs += VaultFileService.shared.files.filter { matches($0.folderID) }.map { LibraryEntityRef(type: .vaultFile, entityID: $0.id) }
        return refs.sorted {
            let left = ItemLinkService.shared.summary(for: $0)?.title ?? $0.entityID.uuidString
            let right = ItemLinkService.shared.summary(for: $1)?.title ?? $1.entityID.uuidString
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    static func exportPayload(
        command: String,
        format: String,
        scope: [String: Any],
        refs: [LibraryEntityRef],
        limit: Int,
        safeNextCommands: [String]
    ) -> [String: Any] {
        let items = refs.prefix(limit).map(exportedItemDict)
        return [
            "ok": true,
            "command": command,
            "readOnly": true,
            "changed": false,
            "format": format,
            "scope": scope,
            "counts": [
                "totalItems": refs.count,
                "includedItems": items.count,
                "limit": limit,
                "truncated": refs.count > items.count,
            ],
            "items": items,
            "markdown": exportMarkdown(scope: scope, items: items),
            "safeNextCommands": safeNextCommands,
        ]
    }

    static func exportedItemDict(_ ref: LibraryEntityRef) -> [String: Any] {
        let store = SecondBrainStore(database: .shared)
        let contextService = CiderItemContextService(database: .shared, secondBrainStore: store)
        var dict: [String: Any] = [
            "type": ref.type.rawValue,
            "id": ref.entityID.uuidString,
            "ref": "\(ref.type.rawValue):\(ref.entityID.uuidString)",
            "owner": ownerToDict(SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)),
        ]
        if let summary = ItemLinkService.shared.summary(for: ref) {
            dict["title"] = summary.title
            dict["subtitle"] = summary.subtitle
        }
        switch ref.type {
        case .bookmark:
            if let item = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == ref.entityID }) { dict.merge(bookmarkToDict(item)) { _, new in new } }
        case .note:
            if let item = NotesStorage.shared.notes.first(where: { $0.id == ref.entityID }) {
                dict.merge(noteToDict(item)) { _, new in new }
                dict["content"] = item.resolvedContent
            }
        case .todo:
            if let item = TodoCardStorage.shared.todoCard(for: ref.entityID) { dict.merge(todoToDict(item)) { _, new in new } }
        case .dateCard:
            if let item = DateCardStorage.shared.dateCard(for: ref.entityID) { dict.merge(eventToDict(item)) { _, new in new } }
        case .contact:
            if let item = ContactStorage.shared.contact(for: ref.entityID) { dict.merge(contactToDict(item)) { _, new in new } }
        case .vaultFile:
            if let item = VaultFileService.shared.file(for: ref.entityID) { dict.merge(vaultFileToDict(item)) { _, new in new } }
        case .externalFile, .session:
            break
        }
        if let bundle = try? contextService.context(for: ref) {
            dict["item"] = itemSummaryToDict(bundle.item, ownerRelations: bundle.ownerRelations)
            dict["related"] = bundle.related.map(itemLinkSummaryToDict)
            dict["ownerRelations"] = bundle.ownerRelations.map(ownerRelationToDict)
            dict["backlinks"] = bundle.backlinks.map(ownerRelationToDict)
            dict["routingDecisions"] = bundle.routingDecisions.map(routingDecisionToDict)
            dict["captureProvenance"] = bundle.captureProvenance.map(captureProvenanceToDict)
        } else {
            dict["related"] = []
            dict["ownerRelations"] = []
            dict["backlinks"] = []
            dict["routingDecisions"] = []
            dict["captureProvenance"] = []
        }
        return dict
    }

    static func printExportPayload(_ payload: [String: Any], format: String) {
        if format == "md" && !jsonOutput {
            print(payload["markdown"] as? String ?? "")
        } else {
            outputJSON(payload)
        }
    }

    static func printExportError(
        command: String,
        message: String,
        payload: [String: Any] = [:],
        safeNextCommands: [String] = [
            "cider-cli export folder <relative-path> --format json --limit 100 --json",
            "cider-cli export item <type> <id-or-ref> --format json --json",
        ]
    ) {
        processExitCode = 1
        var dict = payload
        dict["ok"] = false
        dict["command"] = command
        dict["readOnly"] = true
        dict["changed"] = false
        dict["error"] = message
        dict["safeNextCommands"] = safeNextCommands
        if jsonOutput {
            outputJSON(dict)
        } else {
            print("Error: \(message)")
        }
    }

    static func exportMarkdown(scope: [String: Any], items: [[String: Any]]) -> String {
        let scopeType = scope["type"] as? String ?? "unknown"
        let title = (scope["relativePath"] as? String) ?? (scope["title"] as? String) ?? (scope["ref"] as? String) ?? scopeType
        var lines: [String] = [
            "# Cider Export: \(title)",
            "",
            "- Scope: \(scopeType)",
            "- Items: \(items.count)",
            "",
        ]
        for item in items {
            let itemTitle = item["title"] as? String ?? item["displayTitle"] as? String ?? item["id"] as? String ?? "Untitled"
            lines.append("## \(itemTitle)")
            lines.append("")
            lines.append("- Type: \(item["type"] as? String ?? "")")
            lines.append("- ID: \(item["id"] as? String ?? "")")
            lines.append("- Ref: \(item["ref"] as? String ?? "")")
            if let relativePath = item["relativePath"] as? String {
                lines.append("- Path: \(relativePath)")
            }
            if let related = item["related"] as? [[String: Any]] {
                lines.append("- Related: \(related.count)")
            }
            if let backlinks = item["backlinks"] as? [[String: Any]] {
                lines.append("- Backlinks: \(backlinks.count)")
            }
            if let content = item["content"] as? String, !content.isEmpty {
                lines.append("")
                lines.append(content)
            } else if let notes = item["notes"] as? String, !notes.isEmpty {
                lines.append("")
                lines.append(notes)
            } else if let details = item["details"] as? String, !details.isEmpty {
                lines.append("")
                lines.append(details)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - File Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleFile(subcommand: String?, args: [String], service: VaultFileService) {
        guard !printHiddenLegacyCommandIfRemoved(command: "file", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "add", "import":
            guard let sourcePath = args.first else {
                print("Error: Source path required. Usage: cider-cli file import <path> [--title <title>] [--folder <name|path>] [--json]")
                return
            }

            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let folder): targetFolder = folder
            case .failed: return
            }

            do {
                let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
                let result = try CiderCaptureService(vaultFileStorage: VaultFileStorage.shared, database: database).addFileCapture(
                    sourcePath: sourcePath,
                    title: parseFlag("--title", from: args),
                    folderID: targetFolder?.id
                )
                if jsonOutput {
                    if let file = service.files.first(where: { $0.id == result.item.id }) {
                        var dict = vaultFileToDict(file)
                        dict["command"] = "file.import"
                        dict["compatibilityWrapper"] = true
                        dict["backendCommand"] = result.command
                        dict["capture"] = result.toDictionary()
                        outputJSON(dict)
                    } else {
                        var dict: [String: Any] = [
                            "id": result.item.id.uuidString,
                            "displayTitle": result.item.title,
                            "folder": result.item.folderName,
                            "command": "file.import",
                            "compatibilityWrapper": true,
                            "backendCommand": result.command,
                            "capture": result.toDictionary(),
                        ]
                        if let relativePath = result.item.relativePath {
                            dict["relativePath"] = relativePath
                        }
                        outputJSON(dict)
                    }
                } else {
                    print("Imported file: \(result.item.title) (\(result.item.id.uuidString.prefix(8)))")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }

        case "list", "ls":
            let typeFilter = parseFlag("--type", from: args)
            let folderName = parseFlag("--folder", from: args)
            var files = service.files
            if let typeFilter, let fileType = VaultFileType(rawValue: typeFilter) {
                files = files.filter { $0.fileType == fileType }
            }
            if let folderName {
                let folder = findFolder(named: folderName)
                files = files.filter { $0.folderID == folder?.id }
            }
            if jsonOutput {
                outputJSON(files.map(vaultFileToDict))
            } else {
                print("Vault files (\(files.count)):")
                for file in files {
                    let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                    print("  [\(file.id.uuidString.prefix(8))] \(file.displayTitle) — \(file.fileType.displayName), \(size) (\(folder))")
                }
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if jsonOutput {
                    outputJSON(vaultFileToDict(file))
                } else {
                    let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                    print("File: \(file.displayTitle)")
                    print("  ID:       \(file.id.uuidString)")
                    print("  Filename: \(file.filename)")
                    print("  Type:     \(file.fileType.displayName)")
                    print("  Size:     \(size)")
                    print("  Folder:   \(folder)")
                    print("  Path:     \(file.relativePath)")
                    print("  Notes:    \(file.notes.isEmpty ? "(none)" : file.notes)")
                    print("  Tags:     \(file.tags.isEmpty ? "(none)" : file.tags.joined(separator: ", "))")
                    print("  Labels:   \(file.labelIDs.count)")
                    if let ocr = file.ocrText, !ocr.isEmpty { print("  OCR:      \(ocr.prefix(200))") }
                    if let colors = file.dominantColors { print("  Colors:   \(colors.joined(separator: ", "))") }
                }
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "move":
            guard let firstArg = args.first else {
                print("Error: ID prefix required. Usage: cider-cli file move <id>[,id,...] [--folder <name|path> | --path <target-folder-path>]")
                return
            }
            let prefixes = splitIDs(firstArg)
            let targetFolder: VaultFolder?
            switch resolveFolderArg(from: args) {
            case .unspecified: targetFolder = nil
            case .resolved(let f): targetFolder = f
            case .failed: return
            }
            let targetName = targetFolder?.name ?? "Inbox"
            var moved = 0
            var misses: [String] = []
            for prefix in prefixes {
                guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(prefix.lowercased()) }) else {
                    misses.append(prefix)
                    continue
                }
                let didMove = service.assignFile(file.id, toFolder: targetFolder?.id)
                guard didMove else {
                    print("Error: Failed to move file '\(file.displayTitle)'")
                    continue
                }
                _ = try? CiderRoutingDecisionService().recordManualMove(
                    itemID: file.id,
                    target: routingTarget(for: targetFolder, inboxPath: "Inbox/Files"),
                    reason: "Moved with file move.",
                    actor: "user",
                    source: "file.move"
                )
                print("Moved '\(file.displayTitle)' → \(targetName)")
                moved += 1
            }
            if prefixes.count > 1 {
                print("Total moved: \(moved)/\(prefixes.count)")
            }
            for miss in misses {
                print("Error: No file found with ID prefix: \(miss)")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                print("About to delete file:")
                print("  \(file.displayTitle)")
                print("  Path: \(file.relativePath)  Type: \(file.fileType.displayName)  Size: \(size)")
                print("  Folder: \(folder)  Tags: [\(file.tags.joined(separator: ", "))]  Labels: \(file.labelIDs.count)")
                let trashItem = TrashStorage.shared.trashVaultFile(file)
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFile, trashItem: trashItem))
                print("Deleted: \(file.displayTitle) (moved to trash)")
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli file update <id> [--title <title>] [--notes <notes>]")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) {
                    VaultFileStorage.shared.updateTitle(file, title: t)
                    print("Title set: '\(t)'")
                    changed = true
                }
                if let n = parseFlag("--notes", from: args) {
                    VaultFileStorage.shared.updateNotes(file, notes: n)
                    print("Notes set for: \(file.displayTitle)")
                    changed = true
                }
                if !changed {
                    print("No changes specified. Use --title or --notes")
                }
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "tag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli file tag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No file found with ID prefix: \(idPrefix)")
                return
            }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            for name in tagNames { VaultFileStorage.shared.addTag(file, tag: name) }
            let current = VaultFileStorage.shared.metadata(for: file.id)?.tags ?? []
            print("Tagged '\(file.displayTitle)' with \(tagNames.joined(separator: ", ")) — now: [\(current.joined(separator: ", "))]")

        case "untag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli file untag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No file found with ID prefix: \(idPrefix)")
                return
            }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            var removed = 0
            for name in tagNames where VaultFileStorage.shared.removeTag(file, tag: name) {
                removed += 1
            }
            let current = VaultFileStorage.shared.metadata(for: file.id)?.tags ?? []
            print("Removed \(removed) tag(s) from '\(file.displayTitle)' — now: [\(current.joined(separator: ", "))]")

        case "enrich":
            let enrichment = VaultFileEnrichment.shared
            if args.contains("--all") {
                enrichment.scheduleAll()
                print("Scheduled enrichment for all un-enriched files")
            } else {
                guard let idPrefix = args.first else {
                    print("Error: ID prefix required. Usage: cider-cli file enrich <id> | --all")
                    return
                }
                guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                    print("Error: No file found with ID prefix: \(idPrefix)")
                    return
                }
                enrichment.schedule(for: file)
                print("Scheduled enrichment for: \(file.displayTitle)")
            }

        default:
            printCLIError("Unknown file command: \(subcommand ?? "nil"). Commands: import, add, list, get, move, delete, update, tag, untag, enrich")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Folder Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleFolder(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "folder", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "list", "ls":
            // Component-wise sort so children always immediately follow their
            // parent. Lex-sorting by path puts "Restaurants 2" before
            // "Restaurants/Italian" (space < /), which previously caused the
            // text renderer to attribute children to the wrong sibling.
            let sorted = VaultFolderService.shared.folders.sorted { a, b in
                let aParts = a.relativePath.split(separator: "/").map(String.init)
                let bParts = b.relativePath.split(separator: "/").map(String.init)
                for i in 0..<min(aParts.count, bParts.count) {
                    let cmp = aParts[i].localizedCaseInsensitiveCompare(bParts[i])
                    if cmp != .orderedSame {
                        return cmp == .orderedAscending
                    }
                }
                return aParts.count < bParts.count
            }
            if jsonOutput {
                outputJSON(sorted.map(folderToDict))
            } else {
                print("Folders (\(sorted.count)):")
                // Print full relativePath on every row — no more depth-only
                // indentation that could imply the wrong parent. Agents can
                // grep `^  📁 Restaurants/` to find children of `Restaurants`.
                for folder in sorted {
                    print("  📁 \(folder.relativePath) (\(folder.id.uuidString.prefix(8)))")
                }
            }

        case "create":
            let name = args.first ?? "New Folder"
            let parentName = parseFlag("--parent", from: args)

            // If the name contains a slash, treat it as a vault-relative path
            // and auto-create every missing intermediate folder along the way.
            // `Food/Restaurants/Tacoma` → creates Food, Food/Restaurants,
            // Food/Restaurants/Tacoma as needed and returns the leaf.
            if name.contains("/") && parentName == nil {
                if let folder = findOrCreateFolderByPath(name) {
                    print("Created folder: \(folder.relativePath) (\(folder.id.uuidString.prefix(8)))")
                } else {
                    print("Error: Could not create nested folder path '\(name)'")
                }
                return
            }

            // If --parent was given, refuse to silently fall back to the root
            // when it doesn't resolve. Previously a typo'd parent name would
            // create the folder at the vault root with no warning.
            let parentID: UUID?
            if let parentName {
                guard let parent = findFolder(named: parentName) else {
                    print("Error: Parent folder '\(parentName)' not found")
                    return
                }
                parentID = parent.id
            } else {
                parentID = nil
            }
            if let folder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) {
                // The folder service auto-suffixes name collisions
                // ("Restaurants" → "Restaurants 2"). Surface that loudly so
                // agents don't assume their requested name was honored.
                if folder.name != name {
                    print("Note: name '\(name)' was already taken — created as '\(folder.name)' instead")
                }
                print("Created folder: \(folder.relativePath) (\(folder.id.uuidString.prefix(8)))")
            } else {
                print("Error: Could not create folder: \(name)")
            }

        case "rename":
            guard let oldName = args.first, let newName = parseFlag("--to", from: args) else {
                print("Error: Usage: cider-cli folder rename <name|path> --to <new-name>")
                return
            }
            // Strict lookup: path-match first, ambiguity-errors on bare names.
            // Prevents renaming the wrong folder when two share a leaf name.
            guard let folder = findFolderStrict(oldName) else { return }
            let oldPath = folder.relativePath
            let success = VaultFolderService.shared.renameFolder(folder.id, to: newName)
            if success {
                // Re-read to capture the post-rename name; the service
                // auto-suffixes collisions, so the requested newName may
                // not match the actual one.
                let actualName = VaultFolderService.shared.folder(for: folder.id)?.name ?? newName
                if actualName != newName {
                    print("Note: name '\(newName)' was already taken — renamed to '\(actualName)' instead")
                }
                print("Renamed: \(oldPath) → \(actualName)")
            } else {
                print("Error: Could not rename folder")
            }

        case "move", "mv":
            guard let nameOrID = args.first else {
                print("Error: Usage: cider-cli folder move <name|path|id-prefix> --to <parent-path>")
                print("  Use --to \"\" or --to / to move to the vault root.")
                return
            }
            guard let toPath = parseFlag("--to", from: args) else {
                print("Error: Missing --to <parent-path>. Use --to \"\" to move to the root.")
                return
            }
            // Strict lookup: path-match first, ambiguity-errors on bare names.
            guard let folder = findFolderStrict(nameOrID) else { return }

            // Resolve the destination parent. Empty string or "/" means root;
            // any other value is a vault-relative path that will be auto-created
            // if it doesn't exist yet.
            let trimmedPath = toPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            let newParentID: UUID?
            if trimmedPath.isEmpty {
                newParentID = nil
            } else {
                guard let parent = findOrCreateFolderByPath(trimmedPath) else {
                    print("Error: Could not resolve or create destination parent '\(toPath)'")
                    return
                }
                newParentID = parent.id
            }

            let success = VaultFolderService.shared.moveFolder(folder.id, toParentID: newParentID)
            if success {
                if let updated = VaultFolderService.shared.folder(for: folder.id) {
                    print("Moved folder: \(folder.name) → \(updated.relativePath)")
                } else {
                    print("Moved folder: \(folder.name)")
                }
            } else {
                print("Error: Could not move folder '\(folder.name)' to '\(toPath)'")
            }

        case "delete", "rm":
            guard let name = args.first else {
                print("Error: Folder name required.")
                return
            }
            // Strict lookup: path-match first, ambiguity-errors on bare names.
            // Prevents deleting the wrong folder when two share a leaf name.
            guard let folder = findFolderStrict(name) else { return }

            // Receipt: enumerate descendants + items that are about to be
            // affected BEFORE executing the delete, so the agent (or user)
            // gets a clear record of the blast radius. Covers ALL seven
            // folder-aware item types (not just bookmarks/notes/files —
            // the earlier version under-reported todos/events/contacts/
            // sessions and the user couldn't see them in the receipt).
            let allFolders = VaultFolderService.shared.folders
            let prefix = folder.relativePath + "/"
            let descendants = allFolders.filter { $0.relativePath.hasPrefix(prefix) }
            let affectedFolderIDs = Set([folder.id] + descendants.map(\.id))

            func isInAffected(_ fid: UUID?, _ set: Set<UUID>) -> Bool {
                guard let fid else { return false }
                return set.contains(fid)
            }
            let affectedBookmarks = VaultBookmarkService.shared.bookmarks.filter { isInAffected($0.folderID, affectedFolderIDs) }
            let affectedNotes = NotesStorage.shared.notes.filter { isInAffected($0.folderID, affectedFolderIDs) }
            let affectedFiles = VaultFileService.shared.files.filter { isInAffected($0.folderID, affectedFolderIDs) }
            let affectedTodos = TodoCardStorage.shared.todoCards.filter { isInAffected($0.folderID, affectedFolderIDs) }
            let affectedEvents = DateCardStorage.shared.dateCards.filter { isInAffected($0.folderID, affectedFolderIDs) }
            let affectedContacts = ContactStorage.shared.contacts.filter { isInAffected($0.folderID, affectedFolderIDs) }

            print("About to delete folder: \(folder.relativePath)")
            if !descendants.isEmpty {
                print("  Subfolders (\(descendants.count)):")
                for sub in descendants {
                    print("    - \(sub.relativePath)")
                }
            }
            let totalItems = affectedBookmarks.count + affectedNotes.count + affectedFiles.count
                + affectedTodos.count + affectedEvents.count + affectedContacts.count
            if totalItems > 0 {
                print("  Items (\(totalItems), will relocate to Inbox):")
                print("    bookmarks: \(affectedBookmarks.count), notes: \(affectedNotes.count), files: \(affectedFiles.count),")
                print("    todos: \(affectedTodos.count), events: \(affectedEvents.count), contacts: \(affectedContacts.count)")
            }

            if let result = VaultFolderService.shared.deleteFolder(folder.id) {
                _ = result
                print("Deleted folder: \(folder.relativePath) (moved to trash)")
            } else {
                // deleteFolder returns nil on abort (failed drain, failed trash
                // move, or missing index entry). The service logs the specific
                // cause via os.Logger at .error level — the agent should check
                // Console.app or `log show` for details.
                print("Error: deleteFolder aborted — check os log for details. Folder and items preserved.")
            }

        case "restore":
            guard let pathArg = args.first else {
                print("Error: Usage: cider-cli folder restore <vault-relative-path>")
                print("  e.g. cider-cli folder restore Food/Restaurants/Lynnwood")
                return
            }
            guard let breadcrumb = VaultFolderService.shared.readLatestDeleteBreadcrumb(forFolderPath: pathArg) else {
                print("Error: No delete breadcrumb found for '\(pathArg)'")
                print("  Breadcrumbs are written by `folder delete` and live in .cider/folders/.trash/")
                return
            }
            print("Restoring '\(breadcrumb.folderPath)' (deleted \(breadcrumb.deletedAt.formatted())):")
            print("  Items to restore: \(breadcrumb.items.count)")

            var restored = 0
            var misses: [VaultFolderService.BreadcrumbItem] = []
            var skippedRefiled: [VaultFolderService.BreadcrumbItem] = []

            // Unique destination paths to recreate. findOrCreateFolderByPath
            // walks the components and reuses existing folders so we don't
            // collide with siblings that happen to share a name.
            let targetPaths = Set(breadcrumb.items.map(\.previousFolderPath))
            for path in targetPaths {
                _ = findOrCreateFolderByPath(path)
            }

            for item in breadcrumb.items {
                guard let targetFolder = VaultFolderService.shared.folders.first(where: {
                    $0.relativePath == item.previousFolderPath
                }) else {
                    misses.append(item)
                    continue
                }
                switch item.itemType {
                case "note":
                    guard let note = NotesStorage.shared.notes.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    // Staleness check: if the user/agent manually re-filed
                    // this item after the delete, don't yank it back.
                    if note.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if NotesStorage.shared.assignNote(note.id, toFolder: targetFolder.id) {
                        print("  ↺ note: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                case "bookmark":
                    guard let bm = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    if bm.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if VaultBookmarkService.shared.assignBookmark(bm.id, toFolder: targetFolder.id) {
                        print("  ↺ bookmark: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                case "vaultFile":
                    guard let file = VaultFileService.shared.files.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    if file.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if VaultFileService.shared.assignFile(file.id, toFolder: targetFolder.id) {
                        print("  ↺ file: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                case "todo":
                    guard let todo = TodoCardStorage.shared.todoCards.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    if todo.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if TodoCardStorage.shared.assignTodoCard(todo.id, toFolder: targetFolder.id) {
                        print("  ↺ todo: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                case "event":
                    guard let dc = DateCardStorage.shared.dateCards.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    if dc.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if DateCardStorage.shared.assignDateCard(dc.id, toFolder: targetFolder.id) {
                        print("  ↺ event: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                case "contact":
                    guard let contact = ContactStorage.shared.contacts.first(where: { $0.id == item.itemID }) else {
                        misses.append(item); continue
                    }
                    if contact.folderID != nil {
                        skippedRefiled.append(item); continue
                    }
                    if ContactStorage.shared.assignContact(contact.id, toFolder: targetFolder.id) {
                        print("  ↺ contact: \(item.title) → \(item.previousFolderPath)")
                        restored += 1
                    } else {
                        misses.append(item)
                    }
                default:
                    misses.append(item)
                }
            }

            print("Restored \(restored)/\(breadcrumb.items.count) item(s) to \(targetPaths.count) folder(s)")
            if !skippedRefiled.isEmpty {
                print("Skipped \(skippedRefiled.count) item(s) already re-filed to a different folder:")
                for s in skippedRefiled {
                    print("  - \(s.itemType) \(s.itemID.uuidString.prefix(8)) '\(s.title)'")
                }
            }
            if !misses.isEmpty {
                print("Could not restore \(misses.count) item(s) — likely deleted separately or trashed:")
                for m in misses {
                    print("  - \(m.itemType) \(m.itemID.uuidString.prefix(8)) '\(m.title)'")
                }
            }

        case "doctor":
            // Vault health audit. Default: scan and report findings
            // (read-only). --fix applies fixes with interactive confirm.
            // --yes skips confirm (for scripted / agent runs). --json
            // emits machine-readable output.
            let shouldFix = args.contains("--fix") || args.contains("--yes")
            let assumeYes = args.contains("--yes")

            let report = VaultDoctor.shared.scan()

            if jsonOutput {
                if !shouldFix {
                    outputJSON(doctorReportToDict(report))
                    return
                }
                // --json + --fix: apply all fixable findings (no prompt
                // because JSON mode implies non-interactive).
                var results: [[String: Any]] = []
                for finding in report.findings where finding.isFixable {
                    let ok = VaultDoctor.shared.fix(finding)
                    var entry = doctorFindingToDict(finding)
                    entry["fixApplied"] = ok
                    results.append(entry)
                }
                outputJSON([
                    "report": doctorReportToDict(report),
                    "fixResults": results,
                ] as [String: Any])
                return
            }

            // Human-readable output.
            let counts = report.counts
            let errors = counts[.error] ?? 0
            let warnings = counts[.warning] ?? 0
            let infos = counts[.info] ?? 0
            print("Vault doctor — \(report.findings.count) finding(s)")
            print("  errors: \(errors), warnings: \(warnings), info: \(infos)")
            print("  fixable: \(report.fixableCount)")

            if report.findings.isEmpty {
                print("\nVault is healthy. Nothing to report.")
                return
            }

            // Print findings grouped by severity, errors first.
            let ordering: [VaultDoctor.Severity] = [.error, .warning, .info]
            for sev in ordering {
                let group = report.findings.filter { $0.severity == sev }
                if group.isEmpty { continue }
                let label: String = {
                    switch sev {
                    case .error: return "ERRORS"
                    case .warning: return "WARNINGS"
                    case .info: return "INFO"
                    }
                }()
                print("\n━━━ \(label) (\(group.count)) ━━━")
                for finding in group {
                    let fixTag = finding.isFixable ? " [fixable]" : " [manual]"
                    print("  • \(finding.summary)\(fixTag)")
                    print("    \(finding.detail)")
                    if let label = finding.fixLabel {
                        print("    → fix: \(label)")
                    }
                }
            }

            // Optional fix pass
            if shouldFix {
                print("\n━━━ APPLYING FIXES ━━━")
                var applied = 0
                var failed = 0
                for finding in report.findings where finding.isFixable {
                    if !assumeYes {
                        print("Fix '\(finding.summary)'? [y/N] ", terminator: "")
                        let line = readLine() ?? ""
                        if line.lowercased() != "y" && line.lowercased() != "yes" {
                            print("  skipped")
                            continue
                        }
                    }
                    if VaultDoctor.shared.fix(finding) {
                        print("  ✓ \(finding.fixLabel ?? finding.summary)")
                        applied += 1
                    } else {
                        print("  ✗ failed: \(finding.summary)")
                        failed += 1
                    }
                }
                print("\nApplied \(applied) fix(es), \(failed) failure(s).")
                if report.fixableCount > applied + failed {
                    let skipped = report.fixableCount - applied - failed
                    print("Skipped \(skipped) fix(es) declined by the user.")
                }
            } else if report.fixableCount > 0 {
                print("\nRun with --fix to apply fixes interactively, or --yes for scripted mode.")
            }

        case "get", "show", "info":
            guard let nameOrPath = args.first else {
                print("Error: Folder name or path required.")
                return
            }
            guard let folder = findFolderStrict(nameOrPath) else { return }
            let service = VaultFolderService.shared
            let parentName = service.parentID(for: folder)
                .flatMap { service.folder(for: $0)?.relativePath } ?? "(root)"
            let childCount = service.children(of: folder.id).count
            let itemCounts = countItemsInFolder(folder.id)
            if jsonOutput {
                var dict = folderToDict(folder)
                dict["parent"] = parentName
                dict["childFolderCount"] = childCount
                dict["itemCount"] = itemCounts
                outputJSON(dict)
            } else {
                print("Folder: \(folder.relativePath)")
                print("  ID:       \(folder.id.uuidString)")
                print("  Parent:   \(parentName)")
                print("  Children: \(childCount) subfolder(s)")
                print("  Items:    \(itemCounts)")
                print("  Icon:     \(folder.icon ?? "(none)")")
                print("  Cover:    \(folder.coverImagePath ?? "(none)")")
                print("  Created:  \(folder.createdAt.formatted())")
            }

        case "children":
            guard let nameOrPath = args.first else {
                print("Error: Folder name or path required. Use '/' for root-level folders.")
                return
            }
            let service = VaultFolderService.shared
            let parentID: UUID?
            if nameOrPath == "/" || nameOrPath == "root" {
                parentID = nil
            } else {
                guard let folder = findFolderStrict(nameOrPath) else { return }
                parentID = folder.id
            }
            let children = service.children(of: parentID)
            if jsonOutput {
                outputJSON(children.map(folderToDict))
            } else {
                let label = parentID.flatMap { service.folder(for: $0)?.relativePath } ?? "Root"
                print("Children of \(label) (\(children.count)):")
                for child in children {
                    print("  📁 \(child.relativePath) (\(child.id.uuidString.prefix(8)))")
                }
            }

        case "ancestors", "path":
            guard let nameOrPath = args.first else {
                print("Error: Folder name or path required.")
                return
            }
            guard let folder = findFolderStrict(nameOrPath) else { return }
            let chain = VaultFolderService.shared.path(to: folder.id)
            if jsonOutput {
                outputJSON(chain.map(folderToDict))
            } else {
                print("Path to \(folder.relativePath):")
                for (i, ancestor) in chain.enumerated() {
                    let indent = String(repeating: "  ", count: i)
                    print("  \(indent)📁 \(ancestor.name) (\(ancestor.id.uuidString.prefix(8)))")
                }
            }

        case "set-icon":
            guard let folderArg = args.first else {
                print("Error: Usage: cider-cli folder set-icon <name|path> <emoji>")
                return
            }
            guard let folder = findFolderStrict(folderArg) else { return }
            guard args.count > 1 else {
                print("Error: Emoji/icon required. Usage: cider-cli folder set-icon <name|path> <emoji>")
                return
            }
            let icon = args[1]
            if VaultFolderService.shared.setIcon(icon, for: folder.id) {
                print("Set icon '\(icon)' for folder '\(folder.name)'")
            } else {
                print("Error: Failed to set icon")
            }

        case "remove-icon":
            guard let folderArg = args.first else {
                print("Error: Usage: cider-cli folder remove-icon <name|path>")
                return
            }
            guard let folder = findFolderStrict(folderArg) else { return }
            if VaultFolderService.shared.setIcon(nil, for: folder.id) {
                print("Removed icon from folder '\(folder.name)'")
            } else {
                print("Error: Failed to remove icon")
            }

        case "set-cover":
            guard let folderArg = args.first else {
                print("Error: Usage: cider-cli folder set-cover <name|path> <image-path>")
                return
            }
            guard let folder = findFolderStrict(folderArg) else { return }
            guard args.count > 1 else {
                print("Error: Image path required")
                return
            }
            let imagePath = NSString(string: args[1]).expandingTildeInPath
            let imageURL = URL(fileURLWithPath: imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                print("Error: File not found: \(imageURL.path)")
                return
            }
            guard let data = try? Data(contentsOf: imageURL) else {
                print("Error: Could not read file: \(imageURL.path)")
                return
            }
            if VaultFolderService.shared.setCoverImage(data, for: folder.id) {
                print("Set cover image for '\(folder.name)' from \(imageURL.lastPathComponent)")
            } else {
                print("Error: Failed to set cover image")
            }

        case "remove-cover":
            guard let folderArg = args.first else {
                print("Error: Usage: cider-cli folder remove-cover <name|path>")
                return
            }
            guard let folder = findFolderStrict(folderArg) else { return }
            if VaultFolderService.shared.removeCoverImage(for: folder.id) {
                print("Removed cover image from folder '\(folder.name)'")
            } else {
                print("Error: Failed to remove cover image")
            }

        // ── Folder Kanban ──────────────────────────────────────

        case "kanban", "kanban-add-column", "kanban-rename-column", "kanban-delete-column", "kanban-assign", "kanban-unassign":
            printRemovedLegacyCommand(
                command: "folder \(subcommand ?? "kanban")",
                replacement: "Use board commands for development Kanban, or create a resistance card if folder-local work state is still needed.",
                reason: "folder kanban was a parallel folder-local YAML workflow outside the second-brain item surface."
            )

        default:
            printCLIError("Unknown folder command: \(subcommand ?? "nil"). Commands: list, create, rename, move, delete, restore, doctor, get, children, ancestors, set-icon, remove-icon, set-cover, remove-cover")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Board (Kanban) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleBoard(subcommand: String?, args: [String]) {
        let storage = KanbanStorage.shared
        switch subcommand {
        case "list", "ls":
            let boards = storage.boards
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.list",
                    payload: [
                        "count": boards.count,
                        "boards": boards.map { board in
                            var dict = boardIdentityDict(board)
                            dict["columns"] = board.columns.map(boardColumnSummaryToDict)
                            dict["cardCount"] = board.columns.reduce(0) { $0 + $1.cards.count }
                            return dict
                        },
                    ]
                ))
            } else {
                print("Boards (\(boards.count)):")
                for board in boards {
                    let cols = board.columns.map { "\($0.name)(\($0.cards.count))" }.joined(separator: ", ")
                    print("  [\(board.id)] \(board.name) — \(cols)")
                }
            }

        case "audit":
            let report = boardAuditReport(boards: storage.boards, loadIssues: storage.loadIssues())
            if !(report["ok"] as? Bool ?? false) {
                processExitCode = 1
            }
            if jsonOutput {
                outputJSON(report)
            } else {
                print("Board audit: \(report["boardCount"] ?? 0) board(s), \(report["cardCount"] ?? 0) card(s)")
                print("Issues: \(report["issueCount"] ?? 0)  Warnings: \(report["warningCount"] ?? 0)")
                if let issues = report["issues"] as? [[String: Any]], !issues.isEmpty {
                    print("\nIssues:")
                    for issue in issues {
                        print("  - \(issue["message"] ?? issue)")
                    }
                }
                if let warnings = report["warnings"] as? [[String: Any]], !warnings.isEmpty {
                    print("\nWarnings:")
                    for warning in warnings {
                        print("  - \(warning["message"] ?? warning)")
                    }
                }
            }

        case "show", "cards":
            guard let name = args.first else {
                print("Error: Board name required.")
                return
            }
            if let board = findBoardSilently(name, in: storage) {
                guard let tagFilters = parseBoardTagFilters(from: args) else { return }
                let visibleBoard = board.filteredByTags(tagFilters)
                if jsonOutput {
                    var payload: [String: Any] = [
                        "boardDetail": boardToDict(visibleBoard),
                        "tagFilters": tagFilters,
                    ]
                    payload["columns"] = visibleBoard.columns.map(boardColumnSummaryToDict)
                    outputJSON(boardReadEnvelope(command: "board.show", board: visibleBoard, payload: payload))
                } else {
                    print("Board: \(visibleBoard.name) (\(visibleBoard.id))")
                    if !tagFilters.isEmpty {
                        print("Filtered by tags: \(tagFilters.joined(separator: ", "))")
                    }
                    for col in visibleBoard.columns {
                        let done = col.isDoneColumn ? " ✅" : ""
                        print("\n  ── \(col.name)\(done) (\(col.cards.count)) ──")
                        for card in col.cards {
                            let priority = card.priority.map { " [\($0.rawValue)]" } ?? ""
                            let completed = card.completed.map { " done:\(dateFormatter.string(from: $0))" } ?? ""
                            print("    [\(card.id)] \(card.title)\(priority)\(completed)")
                            if let notes = card.notes, !notes.isEmpty {
                                print("      \(notes.prefix(80))")
                            }
                        }
                    }
                }
            } else {
                printBoardReadError(command: "board.show", message: "Board '\(name)' not found", boardRef: name)
            }

        case "tags":
            if jsonOutput {
                outputJSON([
                    "coreTags": KanbanCardTagTaxonomy.coreTags,
                    "usage": "Use cider-cli board show <board> --tag <tag> [--tag <tag>] [--tags <csv>] [--json] to filter cards by all requested tags.",
                ])
            } else {
                print("Core Kanban tags:")
                for tag in KanbanCardTagTaxonomy.coreTags {
                    print("  - \(tag)")
                }
                print("\nFilter cards: cider-cli board show <board> --tag bug --tag kanban [--tags qa,agent-handoff] [--json]")
            }

        case "workflow":
            guard let boardRef = args.first else {
                print("Error: Usage: cider-cli board workflow <board> [--json]")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.workflow", message: "Board '\(boardRef)' not found", boardRef: boardRef)
                return
            }
            let summary = KanbanAgentWorkflowSummary(board: board)
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.workflow",
                    board: board,
                    payload: ["workflow": kanbanAgentWorkflowSummaryToDict(summary)]
                ))
            } else {
                print("Agent workflow for: \(summary.boardName) [\(summary.boardID)]")
                if summary.laneSummaries.isEmpty {
                    print("  No standard workflow lanes found. Expected columns like Queued, In Progress, Testing, Needs Fix, Done.")
                } else {
                    for lane in summary.laneSummaries {
                        print("\n  ── \(lane.columnName) / \(lane.role.rawValue) (\(lane.count)) ──")
                        for card in lane.cards {
                            let agent = card.agent.map { " @\($0)" } ?? ""
                            let priority = card.priority.map { " [\($0.rawValue)]" } ?? ""
                            print("    [\(card.id)] \(card.title)\(agent)\(priority)")
                        }
                    }
                    if !summary.automationActions.isEmpty {
                        print("\n  Automation / review routing:")
                        for action in summary.automationActions {
                            let approval = action.requiresApproval ? " approval-required" : ""
                            print("    [\(action.cardID)] \(action.label) (\(action.action.rawValue))\(approval): \(action.reason)")
                            for command in action.safeCommands {
                                print("      \(command)")
                            }
                        }
                    }
                }
            }

        case "recent":
            guard let boardRef = args.first else {
                printCLIError("Usage: cider-cli board recent <board> [--limit <count>] [--json]")
                return
            }
            let limitValue = parseFlag("--limit", from: args).flatMap(Int.init) ?? 20
            guard limitValue > 0 else {
                printCLIError("Invalid --limit '\(parseFlag("--limit", from: args) ?? "")'. Use a positive number.")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.recent", message: "Board '\(boardRef)' not found", boardRef: boardRef)
                return
            }
            let recentCards = recentKanbanCards(in: board, limit: limitValue)
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.recent",
                    board: board,
                    payload: [
                    "limit": limitValue,
                    "cards": recentCards.map(boardRecentCardToDict),
                    ]
                ))
            } else if recentCards.isEmpty {
                print("No cards found for board: \(board.name)")
            } else {
                print("Recent cards for \(board.name):")
                for entry in recentCards {
                    let parent = entry.parent.map { " parent:\($0.id)" } ?? ""
                    let priority = entry.card.priority.map { " [\($0.rawValue)]" } ?? ""
                    print("  [\(entry.card.id)] \(entry.card.title)\(priority) — \(entry.column.name) \(entry.activityKind):\(dateFormatter.string(from: entry.activityAt))\(parent)")
                }
            }

        case "testing-summary":
            guard let boardRef = args.first else {
                printCLIError("Usage: cider-cli board testing-summary <board> [--json]")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.testing-summary", message: "Board '\(boardRef)' not found", boardRef: boardRef)
                return
            }
            let summary = KanbanTestingTriageSummary(board: board)
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.testing-summary",
                    board: board,
                    payload: ["testingSummary": kanbanTestingTriageSummaryToDict(summary)]
                ))
            } else {
                print("Testing summary for: \(summary.boardName) [\(summary.boardID)]")
                print("  Needs Erik: \(summary.needsErik.count)  Agent can verify: \(summary.agentCanVerify.count)  Mixed: \(summary.mixed.count)")
                printTestingTriageSection("Needs Erik", items: summary.needsErik)
                printTestingTriageSection("Agent can verify", items: summary.agentCanVerify)
                printTestingTriageSection("Mixed / needs triage", items: summary.mixed)
            }

        case "parent-summary":
            guard let boardRef = args.first,
                  let cardID = parseFlag("--card", from: args) else {
                printCLIError("Usage: cider-cli board parent-summary <board> --card <id> [--refresh --dry-run|--confirm] [--json]")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.parent-summary", message: "Board '\(boardRef)' not found", boardRef: boardRef)
                return
            }
            guard var parent = board.card(matching: cardID) else {
                printBoardReadError(command: "board.parent-summary", message: "Card '\(cardID)' not found in board '\(board.name)'", board: board, cardRef: cardID)
                return
            }
            guard let rollup = KanbanParentChildRollup(board: board, parentID: parent.id) else {
                printBoardReadError(command: "board.parent-summary", message: "Card '\(parent.title)' has no child cards.", board: board, card: parent)
                return
            }

            let refreshRequested = args.contains("--refresh")
            let confirmRefresh = args.contains("--confirm")
            let plan = parentRefreshPlan(board: board, parent: parent, rollup: rollup)
            var applied = false

            if refreshRequested && confirmRefresh {
                parent.notes = KanbanCardSectionParser.updatingSection(
                    in: parent.notes,
                    title: "Current State",
                    body: plan.currentState
                )
                parent.notes = KanbanCardSectionParser.updatingSection(
                    in: parent.notes,
                    title: "Next Step",
                    body: plan.nextStep
                )
                storage.updateCard(boardID: board.id, card: parent)
                refreshSecondBrainProjection(boardID: board.id, card: parent)
                applied = true
            }

            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.parent-summary",
                    board: board,
                    card: parent,
                    payload: ["parentSummary": parentSummaryToDict(
                    board: board,
                    parent: parent,
                    rollup: rollup,
                    plan: plan,
                    refreshRequested: refreshRequested,
                    applied: applied
                    )]
                ))
            } else {
                print("Parent summary: \(parent.title) [\(parent.id)]")
                print(rollup.statusLine)
                print(rollup.nextActionLine)
                if !plan.staleFindings.isEmpty {
                    print("Stale parent text: \(plan.staleFindings.count) finding(s)")
                }
                if refreshRequested {
                    print(applied ? "Refreshed Current State / Next Step." : "Dry run only. Add --confirm to apply.")
                }
            }

        case "milestone":
            handleBoardMilestone(subcommand: args.first, args: Array(args.dropFirst()), storage: storage)

        case "card":
            guard args.first == "inspect" else {
                printCLIError("Usage: cider-cli board card inspect <board> --card <id> [--json]")
                return
            }
            let inspectArgs = Array(args.dropFirst())
            guard let boardRef = inspectArgs.first,
                  let cardID = parseFlag("--card", from: inspectArgs) else {
                printCLIError("Usage: cider-cli board card inspect <board> --card <id> [--json]")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.card.inspect", message: "Board '\(boardRef)' not found", boardRef: boardRef, cardRef: cardID)
                return
            }
            guard let card = board.card(matching: cardID) else {
                printBoardReadError(command: "board.card.inspect", message: "Card '\(cardID)' not found in board '\(board.name)'", board: board, cardRef: cardID)
                return
            }
            let column = board.columns.first { column in
                column.cards.contains { $0.id == card.id }
            }
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.card.inspect",
                    board: board,
                    card: card,
                    payload: boardCardInspectToDict(board: board, column: column, card: card)
                ))
            } else {
                print("Card: \(card.title) [\(card.id)]")
                if let column {
                    print("Column: \(column.name)")
                }
                let model = KanbanCardDashboardModel(title: card.title, notes: card.notes)
                print("Sections: \(model.sections.count)")
                if let problem = model.problem { print("Problem: \(problem)") }
                if let goal = model.goal { print("Goal: \(goal)") }
                if let nextUp = KanbanRoadmapNextUpProjection(board: board, parentID: card.id) {
                    print("Next Up: \(nextUp.nextActionLine)")
                    print("Add child: \(nextUp.suggestedInsertion.command)")
                }
            }

        case "children":
            guard let boardRef = args.first,
                  let cardID = parseFlag("--card", from: args) else {
                printCLIError("Usage: cider-cli board children <board> --card <id>")
                return
            }
            guard let board = findBoardSilently(boardRef, in: storage) else {
                printBoardReadError(command: "board.children", message: "Board '\(boardRef)' not found", boardRef: boardRef, cardRef: cardID)
                return
            }
            guard let parent = board.card(matching: cardID) else {
                printBoardReadError(command: "board.children", message: "Card '\(cardID)' not found in board '\(board.name)'", board: board, cardRef: cardID)
                return
            }
            let children = board.childCards(of: parent.id)
            if jsonOutput {
                outputJSON(boardReadEnvelope(
                    command: "board.children",
                    board: board,
                    card: parent,
                    payload: [
                    "children": children.map { child in
                        var dict: [String: Any] = [
                            "id": child.id,
                            "title": child.title,
                            "created": ISO8601DateFormatter().string(from: child.created),
                            "parentCardID": parent.id,
                        ]
                        if let priority = child.priority { dict["priority"] = priority.rawValue }
                        if let completed = child.completed { dict["completed"] = ISO8601DateFormatter().string(from: completed) }
                        return dict
                    },
                    ]
                ))
            } else if children.isEmpty {
                print("No child cards for: \(parent.title) [\(parent.id)]")
            } else {
                print("Child cards for: \(parent.title) [\(parent.id)]")
                for child in children {
                    print("  [\(child.id)] \(child.title)")
                }
            }

        case "add-card":
            guard let boardName = args.first else {
                printCLIError("Usage: cider-cli board add-card <board> --column <col> --title <title> [--notes <text>] [--priority low|medium|high] [--parent <card-id>] [--after <sibling-id>] [--json]")
                return
            }
            guard let colName = parseFlag("--column", from: args),
                  let title = parseFlag("--title", from: args) else {
                printCLIError("--column and --title required")
                return
            }
            guard let board = findBoard(boardName, in: storage) else { return }
            guard let col = board.columns.first(where: { $0.name.localizedCaseInsensitiveCompare(colName) == .orderedSame || $0.id == colName }) else {
                printCLIError("Column '\(colName)' not found. Available: \(board.columns.map(\.name).joined(separator: ", "))")
                return
            }
            let parentCardID = parseFlag("--parent", from: args)
            let afterCardID = parseFlag("--after", from: args)
            let resolvedParentCardID = parentCardID.flatMap { board.card(matching: $0)?.id }
            if parentCardID != nil, resolvedParentCardID == nil {
                printCLIError("Parent card '\(parentCardID ?? "")' not found in board '\(board.name)'")
                return
            }
            let resolvedAfterCardID = afterCardID.flatMap { ref in
                col.cards.first { $0.id == ref || board.displayKey(for: $0).localizedCaseInsensitiveCompare(ref) == .orderedSame }?.id
            }
            let requestedPriority: KanbanPriority?
            if let priorityStr = parseFlag("--priority", from: args) {
                switch priorityStr.lowercased() {
                case "high": requestedPriority = .high
                case "medium": requestedPriority = .medium
                case "low": requestedPriority = .low
                default:
                    printCLIError("Invalid priority '\(priorityStr)'. Use low, medium, or high.")
                    return
                }
            } else {
                requestedPriority = nil
            }
            if let afterCardID {
                guard let resolvedAfterCardID,
                      let afterCard = col.cards.first(where: { $0.id == resolvedAfterCardID }) else {
                    printCLIError("After card '\(afterCardID)' not found in column '\(col.name)'")
                    return
                }
                if let resolvedParentCardID, afterCard.parentCardID != resolvedParentCardID {
                    printCLIError("After card '\(afterCardID)' is not a child of parent '\(parentCardID ?? "")'")
                    return
                }
            }
            if let card = storage.addCard(boardID: board.id, columnID: col.id, title: title, parentCardID: resolvedParentCardID, afterCardID: resolvedAfterCardID) {
                // Apply optional notes and priority via updateCard while preserving creation activity.
                var updated = card
                var changed = false
                if let notes = parseFlag("--notes", from: args) {
                    updated.notes = notes
                    changed = true
                }
                if let requestedPriority {
                    updated.priority = requestedPriority
                    changed = true
                }
                if changed {
                    updated.markActivity("created", at: card.created)
                    storage.updateCard(boardID: board.id, card: updated)
                }
                refreshSecondBrainProjection(boardID: board.id, card: updated)
                if jsonOutput {
                    var dict = boardMutationEnvelope(
                        command: "board.add-card",
                        action: "created",
                        board: board,
                        card: updated,
                        column: col
                    )
                    dict["projectionRefreshed"] = true
                    outputJSON(dict)
                } else {
                    print("Added card: \(updated.title) [\(updated.id)] to \(col.name)")
                }
            } else {
                printCLIError("Could not add card")
            }

        case "update-card":
            guard let boardRef = args.first,
                  let cardID = parseFlag("--card", from: args) else {
                printCLIError("Usage: cider-cli board update-card <board> --card <id> [--title <title>] [--notes <text>] [--clear-notes] [--priority low|medium|high|none] [--agent <name>] [--clear-agent] [--tags <csv>] [--clear-tags] [--color blue|green|orange|red|purple|none] [--parent <card-id>] [--clear-parent] [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard var card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }

            var changed = false

            if let title = parseFlag("--title", from: args) {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != card.title {
                    card.title = trimmed
                    changed = true
                }
            }

            if args.contains("--clear-notes") {
                if card.notes != nil {
                    card.notes = nil
                    changed = true
                }
            } else if let notes = parseFlag("--notes", from: args) {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.isEmpty ? nil : trimmed
                if normalized != card.notes {
                    card.notes = normalized
                    changed = true
                }
            }

            if let priorityValue = parseFlag("--priority", from: args) {
                let nextPriority: KanbanPriority?
                switch priorityValue.lowercased() {
                case "high": nextPriority = .high
                case "medium": nextPriority = .medium
                case "low": nextPriority = .low
                case "none", "clear": nextPriority = nil
                default:
                    printCLIError("Invalid priority '\(priorityValue)'. Use low, medium, high, or none.")
                    return
                }
                if nextPriority != card.priority {
                    card.priority = nextPriority
                    changed = true
                }
            }

            if args.contains("--clear-agent") {
                if card.agent != nil {
                    card.agent = nil
                    changed = true
                }
            } else if let agent = parseFlag("--agent", from: args) {
                let trimmed = agent.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.isEmpty ? nil : trimmed
                if normalized != card.agent {
                    card.agent = normalized
                    changed = true
                }
            }

            if args.contains("--clear-tags") {
                if !card.tags.isEmpty {
                    card.tags = []
                    changed = true
                }
            } else if let tagsValue = parseFlag("--tags", from: args) {
                let tags = tagsValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if tags != card.tags {
                    card.tags = tags
                    changed = true
                }
            }

            if let colorValue = parseFlag("--color", from: args) {
                let nextColor: KanbanCardColor?
                switch colorValue.lowercased() {
                case "blue": nextColor = .blue
                case "green": nextColor = .green
                case "orange": nextColor = .orange
                case "red": nextColor = .red
                case "purple": nextColor = .purple
                case "none", "clear": nextColor = nil
                default:
                    printCLIError("Invalid color '\(colorValue)'. Use blue, green, orange, red, purple, or none.")
                    return
                }
                if nextColor != card.color {
                    card.color = nextColor
                    changed = true
                }
            }

            if args.contains("--clear-parent") {
                if card.parentCardID != nil {
                    card.parentCardID = nil
                    changed = true
                }
            } else if let parentCardID = parseFlag("--parent", from: args) {
                guard let resolvedParent = board.card(matching: parentCardID) else {
                    printCLIError("Parent card '\(parentCardID)' not found in board '\(board.name)'")
                    return
                }
                guard board.canAssignParent(cardID: card.id, parentCardID: resolvedParent.id) else {
                    printCLIError("Cannot assign parent '\(parentCardID)' to card '\(card.id)'. Parent must exist in the same board and cannot create a cycle.")
                    return
                }
                if card.parentCardID != resolvedParent.id {
                    card.parentCardID = resolvedParent.id
                    changed = true
                }
            }

            guard changed else {
                if jsonOutput {
                    outputJSON(boardMutationEnvelope(
                        command: "board.update-card",
                        action: "noop",
                        board: board,
                        changed: false,
                        card: card
                    ))
                } else {
                    print("No card changes requested.")
                }
                return
            }

            storage.updateCard(boardID: board.id, card: card)
            refreshSecondBrainProjection(boardID: board.id, card: card)
            if jsonOutput {
                var dict = boardMutationEnvelope(
                    command: "board.update-card",
                    action: "updated",
                    board: board,
                    card: card
                )
                dict["projectionRefreshed"] = true
                outputJSON(dict)
            } else {
                print("Updated card: \(card.title) [\(card.id)]")
            }

        case "section":
            guard args.first == "update" else {
                printCLIError("Usage: cider-cli board section update <board> --card <id> --section <name> --value <text> [--json]")
                return
            }
            let sectionArgs = Array(args.dropFirst())
            guard let boardRef = sectionArgs.first,
                  let cardID = parseFlag("--card", from: sectionArgs),
                  let section = parseFlag("--section", from: sectionArgs),
                  let value = parseFlag("--value", from: sectionArgs) else {
                printCLIError("Usage: cider-cli board section update <board> --card <id> --section <name> --value <text> [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            guard let updatedCard = storage.updateCardSection(
                boardID: board.id,
                cardID: card.id,
                title: section,
                body: value
            ) else {
                printCLIError("Could not update section '\(section)' on card '\(cardID)'.")
                return
            }
            printBoardCardSectionResult(board: board, card: updatedCard)

        case "comment":
            guard args.first == "add" else {
                printCLIError("Usage: cider-cli board comment add <board> --card <id> --kind <note|handoff|decision|evidence|qa|final-report> --text <text> [--author <name>] [--source <source>] [--parent <comment-id>] [--json]")
                return
            }
            let commentArgs = Array(args.dropFirst())
            guard let boardRef = commentArgs.first,
                  let cardID = parseFlag("--card", from: commentArgs),
                  let text = parseFlag("--text", from: commentArgs) else {
                printCLIError("Usage: cider-cli board comment add <board> --card <id> --kind <note|handoff|decision|evidence|qa|final-report> --text <text> [--author <name>] [--source <source>] [--parent <comment-id>] [--json]")
                return
            }
            let kindValue = parseFlag("--kind", from: commentArgs) ?? "note"
            let kind: KanbanCardCommentKind?
            switch kindValue.lowercased().replacingOccurrences(of: "_", with: "-") {
            case "note": kind = .note
            case "handoff": kind = .handoff
            case "decision": kind = .decision
            case "evidence": kind = .evidence
            case "qa": kind = .qa
            case "final-report", "final", "report": kind = .finalReport
            default: kind = nil
            }
            guard let kind else {
                printCLIError("Invalid comment kind '\(kindValue)'. Use note, handoff, decision, evidence, qa, or final-report.")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let resolvedCard = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                printCLIError("Comment text cannot be blank.")
                return
            }
            let comment = KanbanCardComment(
                kind: kind,
                body: trimmedText,
                author: parseFlag("--author", from: commentArgs),
                source: parseFlag("--source", from: commentArgs),
                parentCommentID: parseFlag("--parent", from: commentArgs)
            )
            guard let appended = storage.addComment(boardID: board.id, cardID: resolvedCard.id, comment: comment) else {
                printCLIError("Could not append comment. Check that the card and optional parent comment exist.")
                return
            }
            if jsonOutput {
                let formatter = ISO8601DateFormatter()
                var commentDict: [String: Any] = [
                    "id": appended.id,
                    "permalinkID": appended.permalinkID,
                    "kind": appended.kind.rawValue,
                    "body": appended.body,
                    "createdAt": formatter.string(from: appended.createdAt),
                ]
                if let author = appended.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentDict["author"] = author
                }
                if let source = appended.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentDict["source"] = source
                }
                if let parentCommentID = appended.parentCommentID, !parentCommentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentDict["parentCommentID"] = parentCommentID
                }
                commentDict["isResolved"] = appended.isResolved
                if let resolvedAt = appended.resolvedAt {
                    commentDict["resolvedAt"] = formatter.string(from: resolvedAt)
                }
                if let resolvedBy = appended.resolvedBy, !resolvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentDict["resolvedBy"] = resolvedBy
                }
                var dict: [String: Any] = [
                    "ok": true,
                    "board": board.id,
                    "card": resolvedCard.id,
                    "comment": commentDict,
                ]
                if let refreshed = storage.findCard(id: resolvedCard.id)?.card {
                    dict["commentCount"] = refreshed.comments.count
                }
                outputJSON(dict)
            } else {
                print("Added comment: \(appended.kind.displayName) [\(appended.id)]")
            }

        case "evidence":
            guard args.first == "add" else {
                printCLIError("Usage: cider-cli board evidence add <board> --card <id> --text <text> [--source <source>] [--json]")
                return
            }
            let evidenceArgs = Array(args.dropFirst())
            guard let boardRef = evidenceArgs.first,
                  let cardID = parseFlag("--card", from: evidenceArgs),
                  let text = parseFlag("--text", from: evidenceArgs) else {
                printCLIError("Usage: cider-cli board evidence add <board> --card <id> --text <text> [--source <source>] [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            guard let updatedCard = storage.appendCardEvidence(
                boardID: board.id,
                cardID: card.id,
                text: text,
                source: parseFlag("--source", from: evidenceArgs)
            ) else {
                printCLIError("Could not append evidence to card '\(cardID)'.")
                return
            }
            printBoardCardSectionResult(board: board, card: updatedCard)

        case "history":
            guard args.first == "add" else {
                printCLIError("Usage: cider-cli board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text> [--source <source>] [--json]")
                return
            }
            let historyArgs = Array(args.dropFirst())
            guard let boardRef = historyArgs.first,
                  let cardID = parseFlag("--card", from: historyArgs),
                  let type = parseFlag("--type", from: historyArgs),
                  let text = parseFlag("--text", from: historyArgs) else {
                printCLIError("Usage: cider-cli board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text> [--source <source>] [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            guard let updatedCard = storage.appendCardHistory(
                boardID: board.id,
                cardID: card.id,
                type: type,
                text: text,
                source: parseFlag("--source", from: historyArgs)
            ) else {
                printCLIError("Invalid history type '\(type)'. Use \(KanbanCardSectionParser.supportedHistoryTypes.joined(separator: ", ")).")
                return
            }
            printBoardCardSectionResult(board: board, card: updatedCard)

        case "move-card":
            guard let boardName = args.first,
                  let cardID = parseFlag("--card", from: args),
                  let toCol = parseFlag("--to", from: args) else {
                printCLIError("Usage: cider-cli board move-card <board> --card <id> --to <column>")
                return
            }
            guard let board = findBoard(boardName, in: storage) else { return }
            guard let destCol = board.columns.first(where: { $0.name.localizedCaseInsensitiveCompare(toCol) == .orderedSame || $0.id == toCol }) else {
                printCLIError("Column '\(toCol)' not found")
                return
            }
            guard let card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            let sourceCol = board.columns.first { column in
                column.cards.contains { $0.id == card.id }
            }
            storage.moveCard(boardID: board.id, cardID: card.id, toColumnID: destCol.id, toIndex: 0)
            if jsonOutput {
                var dict = boardMutationEnvelope(
                    command: "board.move-card",
                    action: "moved",
                    board: board,
                    card: card
                )
                if let sourceCol {
                    dict["fromColumn"] = boardColumnSummaryToDict(sourceCol)
                }
                dict["toColumn"] = boardColumnSummaryToDict(destCol)
                outputJSON(dict)
            } else {
                print("Moved '\(card.title)' → \(destCol.name)")
            }

        case "delete-card":
            guard let boardName = args.first,
                  let cardID = parseFlag("--card", from: args) else {
                printCLIError("Usage: cider-cli board delete-card <board> --card <id>")
                return
            }
            guard let board = findBoard(boardName, in: storage) else { return }
            guard let card = board.card(matching: cardID) else {
                printCLIError("Card '\(cardID)' not found in board '\(board.name)'")
                return
            }
            storage.deleteCard(boardID: board.id, cardID: card.id)
            if jsonOutput {
                outputJSON(boardMutationEnvelope(
                    command: "board.delete-card",
                    action: "deleted",
                    board: board,
                    card: card
                ))
            } else {
                print("Deleted card: \(board.displayKey(for: card)) [\(card.id)]")
            }

        case "create":
            guard !args.contains("--help"), !args.contains("-h"),
                  let name = args.first,
                  !name.hasPrefix("--") else {
                printCLIError("Usage: cider-cli board create <name> [--project <project-id>]")
                return
            }
            let board = storage.createBoard(name: name)
            let projectID = ProjectBoardRegistrationService.normalizedProjectID(parseFlag("--project", from: args))
            ProjectBoardRegistrationService.register(board: board, projectID: projectID)
            if jsonOutput {
                var dict = boardMutationEnvelope(command: "board.create", action: "created", board: board)
                if let projectID {
                    dict["projectID"] = projectID
                }
                outputJSON(dict)
            } else {
                print("Created board: \(board.name) (\(board.id))")
                if let projectID {
                    print("Added to project: \(projectID)")
                }
            }

        case "rename":
            guard let nameOrID = args.first, let newName = parseFlag("--to", from: args) else {
                printCLIError("Usage: cider-cli board rename <name|id> --to <new-name>")
                return
            }
            guard let board = findBoard(nameOrID, in: storage) else { return }
            storage.renameBoard(id: board.id, name: newName)
            var renamedBoard = board
            renamedBoard.name = newName
            if jsonOutput {
                var dict = boardMutationEnvelope(command: "board.rename", action: "renamed", board: renamedBoard)
                dict["previousName"] = board.name
                outputJSON(dict)
            } else {
                print("Renamed: \(board.name) → \(newName)")
            }

        case "delete", "rm":
            guard let nameOrID = args.first else {
                printCLIError("Board name or ID required.")
                return
            }
            guard let board = findBoard(nameOrID, in: storage) else { return }
            if let trashItem = storage.deleteBoard(id: board.id) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .kanbanBoard, trashItem: trashItem))
                if jsonOutput {
                    var dict = boardMutationEnvelope(command: "board.delete", action: "deleted", board: board)
                    dict["trashItemID"] = trashItem.id.uuidString
                    outputJSON(dict)
                } else {
                    print("Deleted board: \(board.name) (moved to trash)")
                }
            } else {
                printCLIError("Could not delete board")
            }

        case "add-column":
            guard let boardRef = args.first,
                  let colName = parseFlag("--name", from: args) else {
                printCLIError("Usage: cider-cli board add-column <board> --name <column-name> [--done]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            let isDone = args.contains("--done")
            if let col = storage.addColumn(boardID: board.id, name: colName, isDoneColumn: isDone) {
                if jsonOutput {
                    outputJSON(boardMutationEnvelope(
                        command: "board.add-column",
                        action: "created",
                        board: board,
                        column: col
                    ))
                } else {
                    print("Added column: \(col.name) (\(col.id))\(isDone ? " [done column]" : "")")
                }
            } else {
                printCLIError("Could not add column")
            }

        case "set-column-done":
            guard let boardRef = args.first,
                  let colRef = parseFlag("--column", from: args) else {
                printCLIError("Usage: cider-cli board set-column-done <board> --column <col> (--done|--not-done)")
                return
            }
            let wantsDone = args.contains("--done")
            let wantsNotDone = args.contains("--not-done")
            guard wantsDone != wantsNotDone else {
                printCLIError("Pass exactly one of --done or --not-done")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let col = findColumn(colRef, in: board) else { return }
            storage.setColumnDone(boardID: board.id, columnID: col.id, isDone: wantsDone)
            if jsonOutput {
                let refreshed = storage.boards.first { $0.id == board.id }
                let refreshedColumn = refreshed?.columns.first { $0.id == col.id } ?? col
                outputJSON(boardMutationEnvelope(
                    command: "board.set-column-done",
                    action: "updated",
                    board: refreshed ?? board,
                    column: refreshedColumn
                ))
            } else {
                print("Updated column: \(col.name) \(wantsDone ? "[done column]" : "[not done column]")")
            }

        case "rename-column":
            guard let boardRef = args.first,
                  let colRef = parseFlag("--column", from: args),
                  let newName = parseFlag("--to", from: args) else {
                printCLIError("Usage: cider-cli board rename-column <board> --column <col> --to <new-name>")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let col = findColumn(colRef, in: board) else { return }
            storage.renameColumn(boardID: board.id, columnID: col.id, name: newName)
            var renamedColumn = col
            renamedColumn.name = newName
            if jsonOutput {
                var dict = boardMutationEnvelope(
                    command: "board.rename-column",
                    action: "renamed",
                    board: board,
                    column: renamedColumn
                )
                dict["previousName"] = col.name
                outputJSON(dict)
            } else {
                print("Renamed column: \(col.name) → \(newName)")
            }

        case "delete-column":
            guard let boardRef = args.first,
                  let colRef = parseFlag("--column", from: args) else {
                printCLIError("Usage: cider-cli board delete-column <board> --column <col>")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let col = findColumn(colRef, in: board) else { return }
            storage.deleteColumn(boardID: board.id, columnID: col.id)
            if jsonOutput {
                outputJSON(boardMutationEnvelope(
                    command: "board.delete-column",
                    action: "deleted",
                    board: board,
                    column: col
                ))
            } else {
                print("Deleted column: \(col.name)")
            }

        default:
            printCLIError("Unknown board command: \(subcommand ?? "nil"). Commands: list, audit, show, tags, workflow, recent, testing-summary, parent-summary, milestone create/list/inspect/attach-card, card inspect, create, rename, delete, add-card, update-card, section update, comment add, evidence add, history add, move-card, delete-card, children, add-column, set-column-done, rename-column, delete-column")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Label (Tag) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleLabel(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "label", subcommand: subcommand, args: args) else {
            return
        }
        let storage = CardLabelStorage.shared
        switch subcommand {
        case "list", "ls":
            let labels = storage.labels
            if jsonOutput {
                outputJSON(labels.map(labelToDict))
            } else {
                print("Labels (\(labels.count)):")
                for label in labels {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name) (\(label.colorHex))")
                }
            }

        case "create":
            let name = args.first ?? "New Label"
            let colorHex = parseFlag("--color", from: args)
            let label = storage.createLabel(name: name, colorHex: colorHex ?? CardLabelStorage.randomPresetColor())
            print("Created label: \(label.name) (\(label.id.uuidString.prefix(8)))")

        case "rename":
            guard let oldName = args.first, let newName = parseFlag("--to", from: args) else {
                print("Error: Usage: cider-cli label rename <name> --to <new-name>")
                return
            }
            if let label = storage.labels.first(where: { $0.name.localizedCaseInsensitiveCompare(oldName) == .orderedSame }) {
                var updated = label
                updated.name = newName
                _ = storage.updateLabel(updated)
                print("Renamed: \(oldName) → \(newName)")
            } else {
                print("Error: Label '\(oldName)' not found")
            }

        case "delete", "rm":
            guard let identifier = args.first else {
                print("Error: Usage: cider-cli label delete <id-prefix|name>")
                return
            }
            // Resolve 0/1/many for both the id-prefix and exact-name paths so
            // an ambiguous prefix (or duplicate name) never silently deletes
            // the wrong label.
            let lower = identifier.lowercased()
            let prefixMatches = storage.labels.filter { $0.id.uuidString.lowercased().hasPrefix(lower) }
            let nameMatches = storage.labels.filter { $0.name.localizedCaseInsensitiveCompare(identifier) == .orderedSame }

            let resolved: CardLabel?
            if prefixMatches.count == 1 {
                resolved = prefixMatches[0]
            } else if prefixMatches.count > 1 {
                print("Error: ID prefix '\(identifier)' is ambiguous — matches \(prefixMatches.count) labels:")
                for label in prefixMatches {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name)")
                }
                print("Use a longer id prefix to disambiguate.")
                return
            } else if nameMatches.count == 1 {
                resolved = nameMatches[0]
            } else if nameMatches.count > 1 {
                print("Error: Name '\(identifier)' is ambiguous — matches \(nameMatches.count) labels:")
                for label in nameMatches {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name)")
                }
                print("Use the id prefix to disambiguate.")
                return
            } else {
                resolved = nil
            }

            if let label = resolved {
                storage.deleteLabel(label.id)
                print("Deleted label: \(label.name) (\(label.id.uuidString.prefix(8)))")
            } else {
                print("Error: No label found matching '\(identifier)'")
            }

        case "merge":
            guard let firstArg = args.first,
                  let targetName = parseFlag("--into", from: args) else {
                print("Error: Usage: cider-cli label merge <source>[,<source>...] --into <target>")
                return
            }
            let lower = targetName.lowercased()
            let target = storage.labels.first(where: {
                $0.name.localizedCaseInsensitiveCompare(targetName) == .orderedSame ||
                $0.id.uuidString.lowercased().hasPrefix(lower)
            })
            guard let target else {
                print("Error: Target label '\(targetName)' not found")
                return
            }
            let sourceNames = firstArg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var sourceIDs: [UUID] = []
            for name in sourceNames {
                let srcLower = name.lowercased()
                if let src = storage.labels.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                    $0.id.uuidString.lowercased().hasPrefix(srcLower)
                }) {
                    sourceIDs.append(src.id)
                } else {
                    print("Error: Source label '\(name)' not found")
                    return
                }
            }
            storage.mergeLabels(sourceIDs: sourceIDs, into: target.id)
            print("Merged \(sourceIDs.count) label(s) into '\(target.name)'")

        default:
            print("Unknown label command: \(subcommand ?? "nil")")
            print("Commands: list, create, rename, delete, merge")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Search
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleSearch(args: [String]) async {
        let query = args.filter { $0 != "--json" }.joined(separator: " ")
        guard !query.isEmpty else {
            print("Usage: cider-cli search <query>")
            print("Supports scope modifiers: @bookmarks, @notes, @todos, @events, @images, @files, @folder:<name>, @tag:<name>")
            return
        }

        let results = await SearchService.search(
            query: query,
            bookmarks: VaultBookmarkService.shared.bookmarks,
            notes: NotesStorage.shared.notes
        )

        if jsonOutput {
            outputJSON(results.map(searchResultToDict))
        } else {
            print("Search '\(query)' (\(results.count) results):")
            for result in results {
                let icon: String
                switch result.type {
                case .bookmark: icon = "🔖"
                case .note: icon = "📝"
                case .dateCard: icon = "📅"
                case .contact: icon = "👤"
                case .todo: icon = "☑️"
                case .vaultFile: icon = "📎"
                }
                let subtitle = result.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(result.id.uuidString.prefix(8))] \(result.title)\(subtitle)")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Trash Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleTrash(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "trash", subcommand: subcommand, args: args) else {
            return
        }
        switch subcommand {
        case "list", "ls":
            var items = TrashStorage.shared.allTrashItems()
            if let typeFilter = parseFlag("--type", from: args) {
                items = items.filter { $0.itemType.rawValue.localizedCaseInsensitiveCompare(typeFilter) == .orderedSame }
            }
            if jsonOutput {
                outputJSON(items.map(trashItemToDict))
            } else {
                print("Trash (\(items.count) items):")
                for item in items {
                    let age = item.deletedAt.formatted(.relative(presentation: .named))
                    print("  [\(item.id.uuidString.prefix(8))] \(item.title) (\(item.itemType.rawValue)) — deleted \(age)")
                }
            }

        case "restore":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            // Match against BOTH the trash entry id (what `trash list` shows)
            // and the original item id (what `bookmark delete` etc. echo back).
            // Lets the agent paste back whichever id they have on hand.
            let lower = idPrefix.lowercased()
            let items = TrashStorage.shared.allTrashItems()
            let matches = items.filter {
                $0.id.uuidString.lowercased().hasPrefix(lower) ||
                $0.itemID.uuidString.lowercased().hasPrefix(lower)
            }
            if matches.count == 1 {
                TrashStorage.shared.restore(matches[0])
                print("Restored: \(matches[0].title)")
            } else if matches.count > 1 {
                print("Error: ID prefix '\(idPrefix)' matches \(matches.count) trash items:")
                for item in matches {
                    print("  [\(item.id.uuidString.prefix(8))] \(item.title) (\(item.itemType.rawValue))")
                }
                print("Use a longer id prefix to disambiguate.")
            } else {
                print("Error: No trash item found with ID prefix: \(idPrefix)")
            }

        case "empty":
            let count = TrashStorage.shared.allTrashItems().count
            TrashStorage.shared.emptyTrash()
            print("Emptied trash (\(count) items permanently deleted)")

        case "purge":
            let days = Int(parseFlag("--days", from: args) ?? "30") ?? 30
            // The underlying purge guards `days > 0` (so AppDelegate's
            // periodic purge can't accidentally wipe everything when the
            // retention setting is 0). Mirror that here with an explicit
            // error so the agent doesn't think `--days 0` purged things.
            if days <= 0 {
                print("Error: --days must be > 0. Use 'cider-cli trash empty' to delete everything.")
                return
            }
            TrashStorage.shared.purgeExpired(olderThan: days)
            print("Purged items older than \(days) days")

        default:
            print("Unknown trash command: \(subcommand ?? "nil")")
            print("Commands: list, restore, empty, purge")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Status
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleStatus() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files
        let folders = VaultFolderService.shared.folders
        let labels = CardLabelStorage.shared.labels
        let boards = KanbanStorage.shared.boards
        let trash = TrashStorage.shared.allTrashItems()

        if jsonOutput {
            outputJSON(statusToDict())
        } else {
            print("Cider Vault Status")
            print("──────────────────")
            print("  Bookmarks:    \(bookmarks.count)")
            print("  Notes:        \(notes.count)")
            print("  Todos:        \(todos.count) (\(todos.filter { !$0.isCompleted }.count) active)")
            print("  Events:       \(events.count)")
            print("  Contacts:     \(contacts.count)")
            print("  Vault Files:  \(files.count) (\(files.filter { $0.fileType == .image }.count) images)")
            print("  Folders:      \(folders.count)")
            print("  Labels:       \(labels.count)")
            print("  Boards:       \(boards.count) (\(boards.flatMap(\.columns).flatMap(\.cards).count) cards)")
            print("  Trash:        \(trash.count) items")
            print("  Vault Root:   \(StoragePaths.cachedVaultDirectoryURL.path)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Recent
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleRecent(args: [String]) {
        let hoursStr = parseFlag("--hours", from: args) ?? "24"
        let hours = Double(hoursStr) ?? 24
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let typeFilter = parseFlag("--type", from: args)?.lowercased()
        let limitStr = parseFlag("--limit", from: args)
        let limit = Int(limitStr ?? "") ?? 50

        struct RecentItem {
            let type: String
            let id: String
            let title: String
            let date: Date
            let subtitle: String?
            func toDict() -> [String: Any] {
                var d: [String: Any] = ["type": type, "id": id, "title": title,
                    "date": ISO8601DateFormatter().string(from: date)]
                if let s = subtitle { d["subtitle"] = s }
                return d
            }
        }

        var items: [RecentItem] = []

        if typeFilter == nil || typeFilter == "bookmark" {
            for bm in VaultBookmarkService.shared.bookmarks where bm.createdAt >= cutoff {
                items.append(RecentItem(type: "bookmark", id: bm.id.uuidString,
                    title: bm.title, date: bm.createdAt, subtitle: bm.hostDisplay))
            }
        }
        if typeFilter == nil || typeFilter == "note" {
            for note in NotesStorage.shared.notes where note.createdAt >= cutoff {
                items.append(RecentItem(type: "note", id: note.id.uuidString,
                    title: note.title, date: note.createdAt, subtitle: nil))
            }
        }
        if typeFilter == nil || typeFilter == "todo" {
            for todo in TodoCardStorage.shared.todoCards where todo.createdAt >= cutoff {
                items.append(RecentItem(type: "todo", id: todo.id.uuidString,
                    title: todo.title, date: todo.createdAt,
                    subtitle: todo.isCompleted ? "completed" : "active"))
            }
        }
        if typeFilter == nil || typeFilter == "event" {
            for card in DateCardStorage.shared.dateCards where card.createdAt >= cutoff {
                items.append(RecentItem(type: "event", id: card.id.uuidString,
                    title: card.title, date: card.createdAt,
                    subtitle: dateFormatter.string(from: card.startAt)))
            }
        }
        if typeFilter == nil || typeFilter == "contact" {
            for c in ContactStorage.shared.contacts where c.createdAt >= cutoff {
                items.append(RecentItem(type: "contact", id: c.id.uuidString,
                    title: c.displayName, date: c.createdAt, subtitle: nil))
            }
        }
        if typeFilter == nil || typeFilter == "file" || typeFilter == "image" {
            for f in VaultFileService.shared.files where f.createdAt >= cutoff {
                if typeFilter == "image" && f.fileType != .image { continue }
                items.append(RecentItem(type: "file", id: f.id.uuidString,
                    title: f.displayTitle, date: f.createdAt,
                    subtitle: f.fileType.rawValue))
            }
        }

        items.sort { $0.date > $1.date }
        let results = Array(items.prefix(limit))

        if jsonOutput {
            outputJSON(results.map { $0.toDict() })
        } else {
            let label = hours >= 24 ? "\(Int(hours / 24)) day\(hours >= 48 ? "s" : "")" : "\(Int(hours)) hour\(hours > 1 ? "s" : "")"
            print("Recent items (last \(label), \(results.count) found):")
            let icons = ["bookmark": "🔖", "note": "📝", "todo": "☑️", "event": "📅",
                         "contact": "👤", "file": "📎"]
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            for item in results {
                let icon = icons[item.type] ?? "📦"
                let ago = relFormatter.localizedString(for: item.date, relativeTo: Date())
                let sub = item.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(item.id.prefix(8))] \(item.title)\(sub) (\(ago))")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Snapshot
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleSnapshot() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files
        let folders = VaultFolderService.shared.folders
        let labels = CardLabelStorage.shared.labels
        let trash = TrashStorage.shared.allTrashItems()

        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)
        let weekAgo = now.addingTimeInterval(-604800)

        // Count recent items
        let recentBookmarks24h = bookmarks.filter { $0.createdAt >= dayAgo }.count
        let recentBookmarks7d = bookmarks.filter { $0.createdAt >= weekAgo }.count
        let recentNotes24h = notes.filter { $0.createdAt >= dayAgo }.count
        let recentNotes7d = notes.filter { $0.createdAt >= weekAgo }.count

        // Tag frequency
        var tagCounts: [String: Int] = [:]
        for label in labels {
            let count = bookmarks.filter { $0.labelIDs.contains(label.id) }.count
                + notes.filter { $0.labelIDs.contains(label.id) }.count
            if count > 0 { tagCounts[label.name] = count }
        }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(15)

        // Folder item counts
        var folderCounts: [(String, Int)] = []
        let inboxCount = bookmarks.filter { $0.folderID == nil }.count
            + notes.filter { $0.folderID == nil }.count
        folderCounts.append(("Inbox", inboxCount))
        for folder in folders {
            let bmCount = bookmarks.filter { $0.folderID == folder.id }.count
            let noteCount = notes.filter { $0.folderID == folder.id }.count
            let todoCount = todos.filter { $0.folderID == folder.id }.count
            let fileCount = files.filter { $0.folderID == folder.id }.count
            let count = bmCount + noteCount + todoCount + fileCount
            if count > 0 { folderCounts.append((folder.name, count)) }
        }
        folderCounts.sort { $0.1 > $1.1 }

        if jsonOutput {
            var d: [String: Any] = statusToDict()
            d["recentBookmarks24h"] = recentBookmarks24h
            d["recentBookmarks7d"] = recentBookmarks7d
            d["recentNotes24h"] = recentNotes24h
            d["recentNotes7d"] = recentNotes7d
            d["topTags"] = topTags.map { ["name": $0.key, "count": $0.value] as [String: Any] }
            d["folderCounts"] = folderCounts.map { ["name": $0.0, "count": $0.1] as [String: Any] }
            d["activeTodos"] = todos.filter { !$0.isCompleted }.map {
                ["id": $0.id.uuidString, "title": $0.title,
                 "priority": $0.priority?.rawValue ?? "none"] as [String: Any]
            }
            outputJSON(d)
        } else {
            print("Cider Vault Snapshot")
            print("════════════════════════════════════════")
            print("")
            print("  ITEMS")
            print("  ─────")
            print("  Bookmarks:    \(bookmarks.count)  (+\(recentBookmarks24h) today, +\(recentBookmarks7d) this week)")
            print("  Notes:        \(notes.count)  (+\(recentNotes24h) today, +\(recentNotes7d) this week)")
            print("  Todos:        \(todos.filter { !$0.isCompleted }.count) active / \(todos.count) total")
            print("  Events:       \(events.count)")
            print("  Contacts:     \(contacts.count)")
            print("  Files:        \(files.count) (\(files.filter { $0.fileType == .image }.count) images)")
            print("  Trash:        \(trash.count)")
            print("")
            print("  FOLDERS (\(folders.count))")
            print("  ───────")
            for (name, count) in folderCounts.prefix(20) {
                print("  📁 \(name): \(count) items")
            }
            if !topTags.isEmpty {
                print("")
                print("  TOP TAGS")
                print("  ────────")
                for (name, count) in topTags {
                    print("  🏷️  \(name): \(count)")
                }
            }
            let activeTodos = todos.filter { !$0.isCompleted }
            if !activeTodos.isEmpty {
                print("")
                print("  ACTIVE TODOS")
                print("  ────────────")
                for todo in activeTodos.prefix(10) {
                    let priority = todo.priority.map { " [\($0.rawValue)]" } ?? ""
                    let due = todo.dueDate.map { " due:\(formattedTodoDueDate($0))" } ?? ""
                    print("  ☑️  \(todo.title)\(priority)\(due)")
                }
            }
            print("")
            print("  Vault: \(StoragePaths.cachedVaultDirectoryURL.path)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Query (natural language search)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleQuery(args: [String]) async {
        let raw = args.filter { $0 != "--json" }.joined(separator: " ")
        guard !raw.isEmpty else {
            print("Usage: cider-cli query \"restaurants I saved last week\"")
            print("Parses natural language time ranges and searches across all fields.")
            return
        }

        // Parse time expressions from the query
        let (keywords, dateRange) = parseNaturalQuery(raw)

        // Search across all types
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files

        struct QueryResult {
            let type: String; let id: String; let title: String
            let date: Date; let subtitle: String?; let score: Int
            func toDict() -> [String: Any] {
                var d: [String: Any] = ["type": type, "id": id, "title": title,
                    "date": ISO8601DateFormatter().string(from: date), "score": score]
                if let s = subtitle { d["subtitle"] = s }
                return d
            }
        }

        var results: [QueryResult] = []
        let query = keywords.lowercased()

        // Search bookmarks (title, URL, notes, tags, AI summary, OCR)
        for bm in bookmarks {
            if let range = dateRange, bm.createdAt < range.start || bm.createdAt > range.end { continue }
            var score = 0
            if bm.title.lowercased().contains(query) { score += 10 }
            if bm.urlString.lowercased().contains(query) { score += 5 }
            if bm.notes.lowercased().contains(query) { score += 8 }
            if bm.tags.contains(where: { $0.lowercased().contains(query) }) { score += 7 }
            if let summary = bm.aiSummary, summary.lowercased().contains(query) { score += 6 }
            if let ocr = bm.ocrText, ocr.lowercased().contains(query) { score += 3 }
            // Check label names
            let labelNames = bm.labelIDs.compactMap { id in
                CardLabelStorage.shared.labels.first(where: { $0.id == id })?.name.lowercased()
            }
            if labelNames.contains(where: { $0.contains(query) }) { score += 7 }
            // If no keywords but date range matched, include it
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "bookmark", id: bm.id.uuidString,
                    title: bm.title, date: bm.createdAt,
                    subtitle: bm.hostDisplay, score: score))
            }
        }

        // Search notes
        for note in notes {
            if let range = dateRange, note.createdAt < range.start || note.createdAt > range.end { continue }
            var score = 0
            if note.title.lowercased().contains(query) { score += 10 }
            if note.content.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "note", id: note.id.uuidString,
                    title: note.title, date: note.createdAt, subtitle: nil, score: score))
            }
        }

        // Search todos
        for todo in todos {
            if let range = dateRange, todo.createdAt < range.start || todo.createdAt > range.end { continue }
            var score = 0
            if todo.title.lowercased().contains(query) { score += 10 }
            if todo.details.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "todo", id: todo.id.uuidString,
                    title: todo.title, date: todo.createdAt,
                    subtitle: todo.isCompleted ? "completed" : "active", score: score))
            }
        }

        // Search events
        for card in events {
            if let range = dateRange, card.createdAt < range.start || card.createdAt > range.end { continue }
            var score = 0
            if card.title.lowercased().contains(query) { score += 10 }
            if card.details.lowercased().contains(query) { score += 6 }
            if !card.location.isEmpty && card.location.lowercased().contains(query) { score += 8 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "event", id: card.id.uuidString,
                    title: card.title, date: card.createdAt,
                    subtitle: dateFormatter.string(from: card.startAt), score: score))
            }
        }

        // Search contacts
        for c in contacts {
            if let range = dateRange, c.createdAt < range.start || c.createdAt > range.end { continue }
            var score = 0
            if c.displayName.lowercased().contains(query) { score += 10 }
            if c.email.lowercased().contains(query) { score += 8 }
            if c.notes.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "contact", id: c.id.uuidString,
                    title: c.displayName, date: c.createdAt,
                    subtitle: c.email.isEmpty ? nil : c.email, score: score))
            }
        }

        // Search vault files
        for f in files {
            if let range = dateRange, f.createdAt < range.start || f.createdAt > range.end { continue }
            var score = 0
            if f.displayTitle.lowercased().contains(query) { score += 10 }
            if f.notes.lowercased().contains(query) { score += 6 }
            if let ocr = f.ocrText, ocr.lowercased().contains(query) { score += 3 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "file", id: f.id.uuidString,
                    title: f.displayTitle, date: f.createdAt,
                    subtitle: f.fileType.rawValue, score: score))
            }
        }

        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.date > $1.date }

        if jsonOutput {
            outputJSON(results.map { $0.toDict() })
        } else {
            var desc = "Query: \(raw)"
            if let range = dateRange {
                desc += " (date: \(dateFormatter.string(from: range.start)) to \(dateFormatter.string(from: range.end)))"
            }
            if !keywords.isEmpty { desc += " (keywords: \(keywords))" }
            print("\(desc)")
            print("\(results.count) results:")
            let icons = ["bookmark": "🔖", "note": "📝", "todo": "☑️", "event": "📅",
                         "contact": "👤", "file": "📎"]
            for result in results.prefix(30) {
                let icon = icons[result.type] ?? "📦"
                let sub = result.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(result.id.prefix(8))] \(result.title)\(sub)")
            }
        }
    }

    static func handleDatabase(subcommand: String?, args: [String]) {
        let database = CiderDatabase.shared
        guard let databaseURL = database.databaseURL else {
            printDatabaseError(
                command: databaseCommandName(subcommand),
                message: "SQLite database is not open.",
                readOnly: !isDatabaseMutationSubcommand(subcommand)
            )
            return
        }

        let safety = DatabaseSafetyService.shared

        switch subcommand {
        case "backups", "list":
            let backups = safety.listRollingBackups(databaseURL: databaseURL)
            if jsonOutput {
                outputJSON(databaseEnvelope(
                    command: "db.backups",
                    readOnly: true,
                    changed: false,
                    payload: [
                        "count": backups.count,
                        "backups": backups.enumerated().map { index, backup in
                            databaseBackupToDict(backup, index: index)
                        },
                    ]
                ))
            } else if backups.isEmpty {
                print("No rolling SQLite backups found.")
            } else {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                print("SQLite rolling backups (\(backups.count)):")
                for (index, backup) in backups.enumerated() {
                    let size = formatter.string(fromByteCount: backup.byteSize)
                    print("  [\(index)] \(backup.url.lastPathComponent) — \(backup.createdAt.formatted()) — \(size)")
                }
            }

        case "backup", "create":
            do {
                let backupURL = try safety.createManualBackup(database: database)
                if jsonOutput {
                    outputJSON(databaseEnvelope(
                        command: "db.backup",
                        readOnly: false,
                        changed: true,
                        payload: [
                            "backup": databaseBackupURLToDict(backupURL),
                            "verification": databaseBackupVerificationDict(backupURL),
                        ]
                    ))
                } else {
                    print("Created SQLite backup at \(backupURL.path)")
                }
            } catch {
                printDatabaseError(
                    command: "db.backup",
                    message: "Error creating SQLite backup: \(error.localizedDescription)",
                    readOnly: false
                )
            }

        case "integrity", "check":
            do {
                let status = try database.integrityCheck()
                if jsonOutput {
                    outputJSON(databaseEnvelope(
                        command: "db.integrity",
                        readOnly: true,
                        changed: false,
                        payload: ["integrity": databaseIntegrityToDict(status)]
                    ))
                } else if status.isHealthy {
                    print("SQLite integrity check passed.")
                } else {
                    print("SQLite integrity check failed:")
                    for message in status.messages {
                        print("  - \(message)")
                    }
                }
            } catch {
                printDatabaseError(
                    command: "db.integrity",
                    message: "Error running SQLite integrity check: \(error.localizedDescription)",
                    readOnly: true
                )
            }

        case "audit", "log":
            let limit = parseFlag("--limit", from: args).flatMap(Int.init) ?? 50
            let itemTypeFilter = parseFlag("--type", from: args)?.lowercased()
            let actionFilter = parseFlag("--action", from: args)?.lowercased()
            let sourceFilter = parseFlag("--source", from: args)?.lowercased()
            let itemPrefixFilter = parseFlag("--item", from: args)?.lowercased()

            let auditService = MutationAuditService.shared
            let sourceSet = Set(MutationAuditSource.allCases.map(\.rawValue))
            if let sourceFilter, !sourceSet.contains(sourceFilter) {
                printDatabaseError(
                    command: "db.audit",
                    message: "Unknown source '\(sourceFilter)'. Valid sources: \(MutationAuditSource.allCases.map(\.rawValue).joined(separator: ", "))",
                    readOnly: true
                )
                return
            }

            let entries = auditService.loadEntries().filter { entry in
                if let itemTypeFilter, entry.itemType.lowercased() != itemTypeFilter {
                    return false
                }
                if let actionFilter, entry.action.lowercased() != actionFilter {
                    return false
                }
                if let sourceFilter, entry.source.rawValue != sourceFilter {
                    return false
                }
                if let itemPrefixFilter, !entry.itemID.uuidString.lowercased().hasPrefix(itemPrefixFilter) {
                    return false
                }
                return true
            }

            let limitedEntries = limit > 0 ? Array(entries.prefix(limit)) : entries
            if jsonOutput {
                outputJSON(databaseEnvelope(
                    command: "db.audit",
                    readOnly: true,
                    changed: false,
                    payload: [
                        "limit": limit,
                        "count": limitedEntries.count,
                        "totalMatching": entries.count,
                        "entries": limitedEntries.map(mutationAuditEntryToDict),
                    ]
                ))
            } else if limitedEntries.isEmpty {
                print("No mutation audit entries found.")
            } else {
                print("Mutation audit entries (\(limitedEntries.count)\(entries.count > limitedEntries.count ? " of \(entries.count)" : "")):")
                for entry in limitedEntries {
                    let timestamp = entry.occurredAt.formatted(date: .abbreviated, time: .standard)
                    let itemID = String(entry.itemID.uuidString.prefix(8))
                    print("  [\(timestamp)] \(entry.source.rawValue) \(entry.action) \(entry.itemType) \(itemID)")
                    if !entry.beforeState.isEmpty {
                        print("    before: \(formatAuditState(entry.beforeState))")
                    }
                    if !entry.afterState.isEmpty {
                        print("    after:  \(formatAuditState(entry.afterState))")
                    }
                    if !entry.metadata.isEmpty {
                        print("    meta:   \(formatAuditState(entry.metadata))")
                    }
                }
            }

        case "restore":
            guard let selector = args.first else {
                printDatabaseError(
                    command: "db.restore",
                    message: "Usage: cider-cli db restore <index|filename|latest> [--dry-run|--yes]",
                    readOnly: true,
                    payload: ["requiresConfirmation": true]
                )
                return
            }

            let ciderRunning = isCiderAppRunning()
            let dryRun = args.contains("--dry-run")

            let backups = safety.listRollingBackups(databaseURL: databaseURL)
            guard !backups.isEmpty else {
                printDatabaseError(
                    command: "db.restore",
                    message: "No rolling SQLite backups are available to restore.",
                    readOnly: true,
                    payload: ["selector": selector, "requiresConfirmation": true]
                )
                return
            }

            guard let backup = resolveDatabaseBackup(selector, in: backups) else {
                printDatabaseError(
                    command: "db.restore",
                    message: "Could not find a backup matching '\(selector)'. Run 'cider-cli db backups' first.",
                    readOnly: true,
                    payload: [
                        "selector": selector,
                        "requiresConfirmation": true,
                        "safeNextCommands": ["cider-cli db backups --json"],
                    ]
                )
                return
            }
            let backupIndex = backups.firstIndex { candidate in
                candidate.url.standardizedFileURL == backup.url.standardizedFileURL
            } ?? 0

            if dryRun {
                outputJSON(databaseEnvelope(
                    command: "db.restore",
                    readOnly: true,
                    changed: false,
                    payload: databaseRestorePlanPayload(
                        selector: selector,
                        backup: backup,
                        databaseURL: databaseURL,
                        ciderRunning: ciderRunning
                    )
                ))
                return
            }

            if ciderRunning {
                printDatabaseError(
                    command: "db.restore",
                    message: "Quit Cider before restoring the SQLite database.",
                    readOnly: false,
                    payload: databaseRestorePlanPayload(
                        selector: selector,
                        backup: backup,
                        databaseURL: databaseURL,
                        ciderRunning: true
                    )
                )
                return
            }

            guard args.contains("--yes") else {
                printDatabaseError(
                    command: "db.restore",
                    message: "Refusing to restore without --yes. This will replace \(databaseURL.path) with \(backup.url.lastPathComponent).",
                    readOnly: true,
                    payload: databaseRestorePlanPayload(
                        selector: selector,
                        backup: backup,
                        databaseURL: databaseURL,
                        ciderRunning: false
                    )
                )
                return
            }

            do {
                let result = try safety.restoreRollingBackup(
                    from: backup.url,
                    into: databaseURL,
                    database: database,
                    reopenDatabase: true
                )
                let status = try database.integrityCheck()
                if jsonOutput {
                    var payload: [String: Any] = [
                        "selector": selector,
                        "restoredBackup": databaseBackupToDict(result.restoredBackup, index: backupIndex),
                        "integrity": databaseIntegrityToDict(status),
                        "partialFailure": false,
                        "rollbackGuidance": "If restore results are wrong, run cider-cli db restore <pre-restore-snapshot-name> --dry-run --json, then confirm with --yes only after review.",
                    ]
                    if let snapshotURL = result.preRestoreSnapshotURL {
                        payload["preRestoreSnapshot"] = databaseBackupURLToDict(snapshotURL)
                    }
                    outputJSON(databaseEnvelope(
                        command: "db.restore",
                        readOnly: false,
                        changed: true,
                        payload: payload
                    ))
                } else {
                    print("Restored SQLite database from \(result.restoredBackup.url.lastPathComponent)")
                    if let snapshotURL = result.preRestoreSnapshotURL {
                        print("Pre-restore snapshot: \(snapshotURL.path)")
                    }
                    print(status.isHealthy ? "Integrity check passed after restore." : "Integrity check reported issues after restore.")
                    if !status.isHealthy {
                        for message in status.messages {
                            print("  - \(message)")
                        }
                    }
                }
            } catch {
                printDatabaseError(
                    command: "db.restore",
                    message: "Error restoring SQLite backup: \(error.localizedDescription)",
                    readOnly: false,
                    payload: [
                        "selector": selector,
                        "partialFailure": true,
                        "safeNextCommands": [
                            "cider-cli db backups --json",
                            "cider-cli db integrity --json",
                        ],
                    ]
                )
            }

        default:
            printDatabaseError(
                command: databaseCommandName(subcommand),
                message: "Unknown db command: \(subcommand ?? "nil"). Commands: backups, backup, integrity, audit, restore",
                readOnly: true
            )
        }
    }

    /// Parses natural language time expressions from a query string.
    /// Returns (remaining keywords, optional date range).
    static func parseNaturalQuery(_ input: String) -> (String, (start: Date, end: Date)?) {
        let lower = input.lowercased()
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        var dateRange: (start: Date, end: Date)?
        var keywords = input

        // Time patterns — order matters (longest match first)
        let patterns: [(String, (start: Date, end: Date))] = [
            ("last 2 weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("last two weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("past 2 weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("last week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("past week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("this week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("last month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("past month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("this month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("last 3 days", (calendar.date(byAdding: .day, value: -3, to: startOfToday)!, now)),
            ("last 3 months", (calendar.date(byAdding: .month, value: -3, to: startOfToday)!, now)),
            ("last 6 months", (calendar.date(byAdding: .month, value: -6, to: startOfToday)!, now)),
            ("last year", (calendar.date(byAdding: .year, value: -1, to: startOfToday)!, now)),
            ("yesterday", (calendar.date(byAdding: .day, value: -1, to: startOfToday)!,
                           startOfToday)),
            ("today", (startOfToday, now)),
            ("this year", (calendar.date(from: calendar.dateComponents([.year], from: now))!, now)),
            ("recently", (calendar.date(byAdding: .day, value: -3, to: startOfToday)!, now)),
        ]

        for (phrase, range) in patterns {
            if lower.contains(phrase) {
                dateRange = range
                // Remove the time phrase from keywords
                let keywordRange = lower.range(of: phrase)!
                var cleaned = input
                cleaned.removeSubrange(keywordRange)
                keywords = cleaned
                break
            }
        }

        // Also match "N days ago", "N weeks ago"
        if dateRange == nil {
            let daysAgoPattern = try? NSRegularExpression(pattern: "(\\d+)\\s+days?\\s+ago", options: .caseInsensitive)
            if let match = daysAgoPattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let numRange = Range(match.range(at: 1), in: input),
               let days = Int(input[numRange]) {
                dateRange = (calendar.date(byAdding: .day, value: -days, to: startOfToday)!, now)
                let fullRange = Range(match.range, in: input)!
                keywords = input.replacingCharacters(in: fullRange, with: "")
            }
            let weeksAgoPattern = try? NSRegularExpression(pattern: "(\\d+)\\s+weeks?\\s+ago", options: .caseInsensitive)
            if dateRange == nil, let match = weeksAgoPattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let numRange = Range(match.range(at: 1), in: input),
               let weeks = Int(input[numRange]) {
                dateRange = (calendar.date(byAdding: .day, value: -weeks * 7, to: startOfToday)!, now)
                let fullRange = Range(match.range, in: input)!
                keywords = input.replacingCharacters(in: fullRange, with: "")
            }
        }

        // Clean up keywords
        keywords = keywords
            .replacingOccurrences(of: "I saved", with: "")
            .replacingOccurrences(of: "i saved", with: "")
            .replacingOccurrences(of: "I added", with: "")
            .replacingOccurrences(of: "i added", with: "")
            .replacingOccurrences(of: "saved", with: "")
            .replacingOccurrences(of: "from", with: "")
            .replacingOccurrences(of: "about", with: "")
            .replacingOccurrences(of: "related to", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (keywords, dateRange)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Memory Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleMemory(subcommand: String?, args: [String]) {
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        let memoryDir = vaultRoot.appendingPathComponent(".cider/memory")
        let fm = FileManager.default

        switch subcommand {
        case "show":
            let target = args.first ?? "core"
            switch target {
            case "user":
                let url = memoryDir.appendingPathComponent("user.md")
                if jsonOutput {
                    outputJSON(memoryFileDict(url: url, name: "user"))
                } else {
                    printMemoryFile(url: url, label: "user.md")
                }

            case "agent":
                let url = memoryDir.appendingPathComponent("agent.md")
                if jsonOutput {
                    outputJSON(memoryFileDict(url: url, name: "agent"))
                } else {
                    printMemoryFile(url: url, label: "agent.md")
                }

            case "core":
                let userURL = memoryDir.appendingPathComponent("user.md")
                let agentURL = memoryDir.appendingPathComponent("agent.md")
                if jsonOutput {
                    outputJSON([
                        "user": memoryFileDict(url: userURL, name: "user"),
                        "agent": memoryFileDict(url: agentURL, name: "agent"),
                    ])
                } else {
                    printMemoryFile(url: userURL, label: "user.md")
                    print("")
                    printMemoryFile(url: agentURL, label: "agent.md")
                }

            case "daily":
                let dateStr = parseFlag("--date", from: args) ?? todayDateString()
                let url = memoryDir.appendingPathComponent("daily/\(dateStr).md")
                if jsonOutput {
                    outputJSON(memoryFileDict(url: url, name: "daily/\(dateStr)"))
                } else {
                    printMemoryFile(url: url, label: "daily/\(dateStr).md")
                }

            case "index":
                let url = memoryDir.appendingPathComponent("index.md")
                if jsonOutput {
                    outputJSON(memoryFileDict(url: url, name: "index"))
                } else {
                    printMemoryFile(url: url, label: "index.md")
                }

            default:
                print("Unknown target: \(target). Options: user, agent, core, daily, index")
            }

        case "add-daily":
            // Strip flags (--json, --vault <path>, etc.) from observation text
            var textParts: [String] = []
            var i = 0
            while i < args.count {
                if args[i].hasPrefix("--") {
                    // Skip flag; if it takes a value (--vault, --date), skip that too
                    let flagsWithValues: Set<String> = ["--vault", "--date", "--limit"]
                    if flagsWithValues.contains(args[i]), i + 1 < args.count {
                        i += 2
                    } else {
                        i += 1
                    }
                } else {
                    textParts.append(args[i])
                    i += 1
                }
            }
            let observation = textParts.joined(separator: " ")
            guard !observation.isEmpty else {
                print("Error: Usage: cider-cli memory add-daily <observation>")
                return
            }
            let dailyDir = memoryDir.appendingPathComponent("daily")
            try? fm.createDirectory(at: dailyDir, withIntermediateDirectories: true)

            let dateStr = todayDateString()
            let fileURL = dailyDir.appendingPathComponent("\(dateStr).md")

            if fm.fileExists(atPath: fileURL.path) {
                // Append to existing daily note
                guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                    print("Error: Could not open daily note for writing")
                    return
                }
                handle.seekToEndOfFile()
                let entry = "\n- \(observation)\n"
                handle.write(Data(entry.utf8))
                handle.closeFile()
            } else {
                // Create new daily note with frontmatter
                let content = """
                ---
                date: '\(dateStr)'
                ---

                ## Observations

                - \(observation)
                """
                try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            if jsonOutput {
                outputJSON([
                    "date": dateStr,
                    "observation": observation,
                    "path": fileURL.path,
                ] as [String: Any])
            } else {
                print("Added to daily/\(dateStr).md: \(observation)")
            }

        case "list-daily":
            let dailyDir = memoryDir.appendingPathComponent("daily")
            guard fm.fileExists(atPath: dailyDir.path) else {
                if jsonOutput {
                    outputJSON([] as [Any])
                } else {
                    print("No daily notes yet.")
                }
                return
            }
            let files = (try? fm.contentsOfDirectory(atPath: dailyDir.path))?
                .filter { $0.hasSuffix(".md") }
                .sorted()
                .reversed() ?? []

            let limitStr = parseFlag("--limit", from: args)
            let limit = limitStr.flatMap(Int.init) ?? 10
            let listed = Array(files.prefix(limit))

            if jsonOutput {
                let dicts = listed.map { filename -> [String: Any] in
                    let date = String(filename.dropLast(3)) // remove .md
                    let url = dailyDir.appendingPathComponent(filename)
                    let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    return ["date": date, "filename": filename, "sizeBytes": size]
                }
                outputJSON(dicts)
            } else {
                if listed.isEmpty {
                    print("No daily notes yet.")
                } else {
                    print("Daily notes (\(files.count) total, showing \(listed.count)):")
                    for filename in listed {
                        let date = String(filename.dropLast(3))
                        let url = dailyDir.appendingPathComponent(filename)
                        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                        print("  \(date)  (\(size) bytes)")
                    }
                }
            }

        default:
            print("Unknown memory command: \(subcommand ?? "nil")")
            print("Commands: show [user|agent|core|daily|index], add-daily, list-daily")
        }
    }

    private static func todayDateString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    private static func printMemoryFile(url: URL, label: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\(label): (not found)")
            return
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("\(label): (could not read)")
            return
        }
        print("── \(label) ──")
        print(content)
    }

    private static func memoryFileDict(url: URL, name: String) -> [String: Any] {
        let fm = FileManager.default
        var d: [String: Any] = [
            "name": name,
            "path": url.path,
            "exists": fm.fileExists(atPath: url.path),
        ]
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            d["content"] = content
            d["sizeBytes"] = content.utf8.count
        }
        return d
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Duplicate Check
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleDuplicateCheck(args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "duplicate-check", subcommand: args.first, args: Array(args.dropFirst())) else {
            return
        }
        guard let url = args.first else {
            print("Usage: cider-cli duplicate-check <url>")
            return
        }

        let normalized = url.lowercased()
            .replacingOccurrences(of: "https://www.", with: "https://")
            .replacingOccurrences(of: "http://www.", with: "http://")
            .replacingOccurrences(of: "http://", with: "https://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let matches = VaultBookmarkService.shared.bookmarks.filter { bm in
            let bmNorm = bm.urlString.lowercased()
                .replacingOccurrences(of: "https://www.", with: "https://")
                .replacingOccurrences(of: "http://www.", with: "http://")
                .replacingOccurrences(of: "http://", with: "https://")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return bmNorm == normalized || bmNorm.hasPrefix(normalized) || normalized.hasPrefix(bmNorm)
        }

        if jsonOutput {
            outputJSON([
                "url": url,
                "isDuplicate": !matches.isEmpty,
                "matches": matches.map(bookmarkToDict),
            ] as [String: Any])
        } else {
            if matches.isEmpty {
                print("No duplicates found for: \(url)")
            } else {
                print("⚠️  Found \(matches.count) duplicate\(matches.count > 1 ? "s" : ""):")
                for bm in matches {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) (\(folder))")
                    print("    \(bm.urlString)")
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Clipboard Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleClipboard(subcommand: String?, args: [String]) {
        guard !printHiddenLegacyCommandIfRemoved(command: "clipboard", subcommand: subcommand, args: args) else {
            return
        }
        let storage = ClipboardStorage.shared

        switch subcommand {
        case "list", "ls":
            let limitStr = parseFlag("--limit", from: args)
            let limit = limitStr.flatMap(Int.init) ?? 20
            let items = Array(storage.items.prefix(limit))
            if jsonOutput {
                outputJSON(items.map(clipboardItemToDict))
            } else {
                print("Clipboard history (\(storage.items.count) total, showing \(items.count)):")
                for item in items {
                    let preview = item.textContent?.prefix(60) ?? "(no text)"
                    let saved = item.isSaved ? " [saved]" : ""
                    print("  [\(item.id.uuidString.prefix(8))] \(item.type.rawValue) \(item.timestamp.formatted())\(saved)")
                    print("    \(preview)")
                }
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required")
                return
            }
            guard let item = storage.items.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No clipboard item found with ID prefix: \(idPrefix)")
                return
            }
            if jsonOutput {
                outputJSON(clipboardItemToDict(item))
            } else {
                print("Clipboard item:")
                print("  ID:        \(item.id.uuidString)")
                print("  Type:      \(item.type.rawValue)")
                print("  Timestamp: \(item.timestamp.formatted())")
                if let app = item.sourceAppName { print("  Source:    \(app)") }
                print("  Saved:     \(item.isSaved)")
                if let text = item.textContent {
                    print("  Content:")
                    print(text)
                }
            }

        case "dismiss", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required")
                return
            }
            guard let item = storage.items.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No clipboard item found with ID prefix: \(idPrefix)")
                return
            }
            storage.dismiss(item)
            let preview = item.textContent.map { String($0.prefix(40)) } ?? item.type.rawValue
            print("Dismissed: \(preview)")

        case "clear":
            let count = storage.items.count
            storage.clearAll()
            print("Cleared \(count) clipboard items")

        case "stats":
            let totalBytes = storage.totalStorageBytes()
            let imageBytes = storage.imageStorageBytes()
            if jsonOutput {
                outputJSON([
                    "totalItems": storage.items.count,
                    "totalStorageBytes": totalBytes,
                    "imageStorageBytes": imageBytes,
                ] as [String: Any])
            } else {
                print("Clipboard stats:")
                print("  Items:         \(storage.items.count)")
                print("  Total storage: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                print("  Image storage: \(ByteCountFormatter.string(fromByteCount: imageBytes, countStyle: .file))")
            }

        default:
            print("Unknown clipboard command: \(subcommand ?? "nil")")
            print("Commands: list, get, dismiss, clear, stats")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    struct BookmarkNativeCaptureWaitResult {
        let bookmark: Bookmark?
        let elapsedSeconds: TimeInterval
        let timeoutSeconds: TimeInterval
        let timedOut: Bool
    }

    static let defaultBookmarkNativeCaptureWaitSeconds: TimeInterval = 20

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    static let localTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    static let twentyFourHourTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    static func todoHasExplicitTime(_ date: Date) -> Bool {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }

    static func formattedTodoDueDate(_ date: Date) -> String {
        if todoHasExplicitTime(date) {
            return "\(localDateFormatter.string(from: date)) \(localTimeFormatter.string(from: date))"
        }
        return dateFormatter.string(from: date)
    }

    static func parseFlag(_ flag: String, from args: [String]) -> String? {
        guard let flagIndex = args.firstIndex(of: flag),
              flagIndex + 1 < args.count else { return nil }
        return args[flagIndex + 1]
    }

    static func firstPositionalArgument(from args: [String], valueFlags: Set<String> = []) -> String? {
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("--") {
                continue
            }
            return arg
        }
        return nil
    }

    enum CaptureAddSource {
        case inferred(String)
        case note(String)
        case todo(String)
        case bookmark(String)
        case file(String)
        case event(CaptureAddEventInput)
        case contact(CaptureAddContactInput)
        case journal(String)

        var originalText: String {
            switch self {
            case .inferred(let raw), .note(let raw), .todo(let raw), .bookmark(let raw), .file(let raw):
                raw
            case .event(let event):
                event.sourceText
            case .contact(let contact):
                contact.sourceText
            case .journal(let raw):
                raw
            }
        }
    }

    struct CaptureAddEventInput {
        var title: String
        var sourceText: String
        var startAt: Date
        var allDay: Bool
        var location: String?
    }

    struct CaptureAddContactInput {
        var displayName: String
        var sourceText: String
        var relationship: String?
        var email: String?
        var phone: String?
    }

    enum CaptureAddArgumentError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message): message
            }
        }
    }

    struct GeneratedArtifactSummaryFile {
        var relativePath: String
        var byteCount: Int64
        var omitted: Bool

        func toDictionary() -> [String: Any] {
            [
                "path": relativePath,
                "bytes": byteCount,
                "omitted": omitted,
            ] as [String: Any]
        }
    }

    struct GeneratedArtifactSummary {
        var sourceURL: URL
        var files: [GeneratedArtifactSummaryFile]

        var fileCount: Int { files.count }
        var totalBytes: Int64 { files.reduce(0) { $0 + $1.byteCount } }
        var omittedArtifactCount: Int { files.filter(\.omitted).count }
        var omittedBytes: Int64 { files.filter(\.omitted).reduce(0) { $0 + $1.byteCount } }
        var representativeFiles: [GeneratedArtifactSummaryFile] {
            Array(files.sorted { lhs, rhs in
                if lhs.omitted != rhs.omitted { return lhs.omitted && !rhs.omitted }
                if lhs.byteCount != rhs.byteCount { return lhs.byteCount > rhs.byteCount }
                return lhs.relativePath < rhs.relativePath
            }.prefix(10))
        }
    }

    static func archiveGeneratedArtifacts(
        args: [String],
        bookmarkService: VaultBookmarkService
    ) throws -> [String: Any] {
        guard let sourcePath = firstPositionalArgument(
            from: args,
            valueFlags: [
                "--title", "--card", "--commit", "--cleanup", "--large-threshold-bytes",
            ]
        ) else {
            throw CaptureAddArgumentError.message("Source path required. Usage: cider-cli capture archive-artifacts <path> [--title <title>] [--card <id>] [--commit <sha>] [--cleanup none|trash] [--large-threshold-bytes <bytes>] [--json]")
        }

        let sourceURL = URL(fileURLWithPath: NSString(string: sourcePath).expandingTildeInPath)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CaptureAddArgumentError.message("Artifact source not found: \(sourcePath)")
        }

        let threshold = parseFlag("--large-threshold-bytes", from: args).flatMap(Int64.init) ?? 1_048_576
        guard threshold >= 0 else {
            throw CaptureAddArgumentError.message("--large-threshold-bytes must be zero or greater.")
        }

        let cleanupMode = (parseFlag("--cleanup", from: args) ?? "none").lowercased()
        guard ["none", "trash"].contains(cleanupMode) else {
            throw CaptureAddArgumentError.message("--cleanup must be none or trash.")
        }

        let title = parseFlag("--title", from: args) ?? "Generated artifact archive"
        let relatedCards = parseFlagAll("--card", from: args)
        let commits = parseFlagAll("--commit", from: args)
        let summary = try summarizeGeneratedArtifacts(at: sourceURL, largeThresholdBytes: threshold)
        let noteContent = generatedArtifactArchiveNote(
            title: title,
            summary: summary,
            relatedCards: relatedCards,
            commits: commits,
            cleanupMode: cleanupMode
        )

        let database = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
        let service = CiderCaptureService(bookmarkService: bookmarkService, database: database)
        let sourceContext = CaptureSourceContext(
            surface: "cli",
            channel: nil,
            channelID: nil,
            threadID: nil,
            messageID: nil,
            senderID: nil,
            senderName: nil,
            originalText: sourceURL.path,
            attachments: [],
            metadata: [
                "command": "capture.archive-artifacts",
                "sourcePath": sourceURL.path,
                "summaryOnly": "true",
            ]
        )
        let capture = try service.addNoteCapture(
            title: title,
            content: noteContent,
            folderID: nil,
            sourceContext: sourceContext
        )

        let cleanup = try performGeneratedArtifactCleanupIfNeeded(
            sourceURL: sourceURL,
            mode: cleanupMode
        )

        return [
            "ok": true,
            "command": "capture.archive-artifacts",
            "backendCommand": "capture.add",
            "changed": true,
            "readOnly": false,
            "title": title,
            "sourcePath": sourceURL.path,
            "summaryOnly": true,
            "fileCount": summary.fileCount,
            "totalBytes": summary.totalBytes,
            "omittedArtifactCount": summary.omittedArtifactCount,
            "omittedBytes": summary.omittedBytes,
            "representativeFiles": summary.representativeFiles.map { $0.toDictionary() },
            "relatedCards": relatedCards,
            "commits": commits,
            "cleanup": cleanup,
            "capture": capture.toDictionary(finalBookmark: nil),
        ] as [String: Any]
    }

    static func summarizeGeneratedArtifacts(
        at sourceURL: URL,
        largeThresholdBytes: Int64
    ) throws -> GeneratedArtifactSummary {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let fileURLs: [URL]
        if (try sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            fileURLs = [sourceURL]
        } else {
            let enumerator = FileManager.default.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
            fileURLs = (enumerator?.compactMap { $0 as? URL } ?? []).filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
        }

        let files = try fileURLs.map { url -> GeneratedArtifactSummaryFile in
            let values = try url.resourceValues(forKeys: resourceKeys)
            let size = Int64(values.fileSize ?? 0)
            return GeneratedArtifactSummaryFile(
                relativePath: relativeArtifactPath(for: url, sourceURL: sourceURL),
                byteCount: size,
                omitted: size > largeThresholdBytes
            )
        }.sorted { $0.relativePath < $1.relativePath }

        return GeneratedArtifactSummary(sourceURL: sourceURL, files: files)
    }

    static func relativeArtifactPath(for fileURL: URL, sourceURL: URL) -> String {
        let sourcePath = sourceURL.resolvingSymlinksInPath().path
        let filePath = fileURL.resolvingSymlinksInPath().path
        guard filePath.hasPrefix(sourcePath) else { return fileURL.lastPathComponent }
        let suffix = String(filePath.dropFirst(sourcePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? fileURL.lastPathComponent : suffix
    }

    static func generatedArtifactArchiveNote(
        title: String,
        summary: GeneratedArtifactSummary,
        relatedCards: [String],
        commits: [String],
        cleanupMode: String
    ) -> String {
        let files = summary.representativeFiles.map { file in
            "- \(file.relativePath) (\(file.byteCount) bytes)\(file.omitted ? " omitted from raw archive" : "")"
        }.joined(separator: "\n")
        let cardLine = relatedCards.isEmpty ? "None" : relatedCards.joined(separator: ", ")
        let commitLine = commits.isEmpty ? "None" : commits.joined(separator: ", ")
        let cleanupLine = cleanupMode == "trash"
            ? "Trash source directory after successful capture."
            : "Leave source artifacts in place; remove manually after review."

        return """
        # \(title)

        Source path: \(summary.sourceURL.path)
        Summary only: true
        File count: \(summary.fileCount)
        Total bytes: \(summary.totalBytes)
        Omitted artifact count: \(summary.omittedArtifactCount)
        Omitted bytes: \(summary.omittedBytes)
        Related cards: \(cardLine)
        Commits: \(commitLine)
        Cleanup recommendation: \(cleanupLine)

        ## Representative Files
        \(files.isEmpty ? "- No files found." : files)
        """
    }

    static func performGeneratedArtifactCleanupIfNeeded(
        sourceURL: URL,
        mode: String
    ) throws -> [String: Any] {
        switch mode {
        case "none":
            return [
                "mode": mode,
                "performed": false,
                "safeNextCommands": ["rm -rf \(shellQuoted(sourceURL.path))"],
            ] as [String: Any]
        case "trash":
            let trashRoot = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent(".cider/artifact-trash", isDirectory: true)
            try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
            let destination = trashRoot
                .appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            return [
                "mode": mode,
                "performed": true,
                "trashPath": destination.path,
                "safeNextCommands": ["rm -rf \(shellQuoted(destination.path))"],
            ] as [String: Any]
        default:
            throw CaptureAddArgumentError.message("--cleanup must be none or trash.")
        }
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func resolveCaptureAddSource(from args: [String]) throws -> CaptureAddSource {
        let kind = parseFlag("--kind", from: args)?.lowercased()
        let rawText = try rawCaptureText(from: args)
        let url = parseFlag("--url", from: args)
        let path = parseFlag("--path", from: args)
        let positionalArgs = capturePositionalArguments(from: args)
        let positional = positionalArgs.first
        let positionalText = positionalArgs.isEmpty ? nil : positionalArgs.joined(separator: " ")

        switch kind {
        case nil:
            if let url { return .inferred(url) }
            if let path { return .inferred(path) }
            if let rawText { return .note(rawText) }
            if let positionalText {
                if positionalArgs.count == 1 { return .inferred(positionalText) }
                return .note(positionalText)
            }
        case "note":
            if let rawText { return .note(rawText) }
            if let positionalText { return .note(positionalText) }
        case "todo":
            if let rawText { return .todo(rawText) }
            if let positionalText { return .todo(positionalText) }
        case "bookmark", "url":
            if let url { return .bookmark(url) }
            if let positional { return .bookmark(positional) }
        case "file":
            if let path { return .file(path) }
            if let positional { return .file(positional) }
        case "event":
            return try .event(resolveCaptureAddEventInput(from: args, rawText: rawText))
        case "contact":
            return try .contact(resolveCaptureAddContactInput(from: args, rawText: rawText))
        case "journal", "daily", "daily-journal":
            if let rawText { return .journal(rawText) }
            if let content = parseFlag("--content", from: args) {
                return .journal(content
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\t", with: "\t"))
            }
            if let positionalText { return .journal(positionalText) }
        case let unsupported?:
            throw CaptureAddArgumentError.message("Unsupported --kind '\(unsupported)'. Use note, todo, bookmark, file, event, contact, or journal.")
        }

        throw CaptureAddArgumentError.message("Source required. Usage: cider-cli capture add [--kind note|todo|bookmark|file|event|contact|journal] (--stdin|--text-file <text-file-path>|--content <text>|--url <url>|--path <source-file-path>|<url|text|file-path>) [--title <title>] [--folder <target-folder-path>] [--surface <surface>] [--channel <channel>] [--message-id <id>] [--sender-id <id>] [--timeout <seconds>|--no-wait] [--json]")
    }

    static func capturePositionalArguments(from args: [String]) -> [String] {
        let valueFlags: Set<String> = [
            "--kind", "--title", "--folder", "--path", "--text-file", "--content", "--url",
            "--surface", "--channel", "--channel-id", "--thread-id", "--message-id",
            "--sender-id", "--sender-name", "--timeout", "--wait-timeout", "--capture-timeout",
            "--source-meta", "--date", "--time", "--location", "--details", "--name",
            "--relationship", "--email", "--phone",
        ]
        let booleanFlags: Set<String> = [
            "--stdin", "--json", "--no-wait", "--all-day", "--help", "-h",
        ]
        var values: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(arg) {
                skipNext = true
                continue
            }
            if booleanFlags.contains(arg) || arg.hasPrefix("--") {
                continue
            }
            values.append(arg)
        }
        return values
    }

    static func resolveCaptureAddEventInput(from args: [String], rawText: String?) throws -> CaptureAddEventInput {
        guard let title = normalizedRequiredCaptureFlag("--title", from: args) else {
            throw CaptureAddArgumentError.message("--kind event requires --title.")
        }
        guard let dateString = normalizedRequiredCaptureFlag("--date", from: args) else {
            throw CaptureAddArgumentError.message("--kind event requires --date yyyy-MM-dd.")
        }
        let timeString = parseFlag("--time", from: args)
        guard let startAt = resolveEventStartAt(dateString: dateString, timeString: timeString) else {
            throw CaptureAddArgumentError.message("Invalid event date/time. Use --date yyyy-MM-dd and optional --time \"h:mm a\" or \"HH:mm\".")
        }
        let details = parseFlag("--details", from: args)
        let sourceText = rawText ?? details ?? title
        let allDay = args.contains("--all-day") || (timeString == nil)
        return CaptureAddEventInput(
            title: title,
            sourceText: sourceText,
            startAt: allDay ? Calendar.autoupdatingCurrent.startOfDay(for: startAt) : startAt,
            allDay: allDay,
            location: parseFlag("--location", from: args)
        )
    }

    static func resolveCaptureAddContactInput(from args: [String], rawText: String?) throws -> CaptureAddContactInput {
        guard let displayName = normalizedRequiredCaptureFlag("--name", from: args)
            ?? normalizedRequiredCaptureFlag("--title", from: args) else {
            throw CaptureAddArgumentError.message("--kind contact requires --name or --title.")
        }
        return CaptureAddContactInput(
            displayName: displayName,
            sourceText: rawText ?? displayName,
            relationship: parseFlag("--relationship", from: args),
            email: parseFlag("--email", from: args),
            phone: parseFlag("--phone", from: args)
        )
    }

    static func normalizedRequiredCaptureFlag(_ flag: String, from args: [String]) -> String? {
        guard let value = parseFlag(flag, from: args)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static func rawCaptureText(from args: [String]) throws -> String? {
        let wantsStdin = args.contains("--stdin")
        let textFile = parseFlag("--text-file", from: args)
        if wantsStdin, textFile != nil {
            throw CaptureAddArgumentError.message("Use only one raw text source: --stdin or --text-file.")
        }
        if wantsStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else {
                throw CaptureAddArgumentError.message("Could not read UTF-8 text from stdin.")
            }
            guard !raw.isEmpty else { throw CiderCaptureError.missingSource }
            return raw
        }
        if let textFile {
            do {
                let raw = try String(contentsOfFile: NSString(string: textFile).expandingTildeInPath, encoding: .utf8)
                guard !raw.isEmpty else { throw CiderCaptureError.missingSource }
                return raw
            } catch {
                throw CaptureAddArgumentError.message("Could not read UTF-8 text file: \(textFile)")
            }
        }
        return nil
    }

    static func bookmarkNativeCaptureWaitTimeout(from args: [String]) -> TimeInterval? {
        if args.contains("--no-wait") { return nil }

        let rawValue = parseFlag("--timeout", from: args)
            ?? parseFlag("--wait-timeout", from: args)
            ?? parseFlag("--capture-timeout", from: args)
        guard let rawValue else { return defaultBookmarkNativeCaptureWaitSeconds }
        guard let seconds = TimeInterval(rawValue), seconds >= 0 else {
            return defaultBookmarkNativeCaptureWaitSeconds
        }
        return seconds
    }

    static func reviewBatchWaitTimeout(from args: [String]) -> TimeInterval? {
        if args.contains("--no-wait") { return nil }
        let rawValue = parseFlag("--timeout", from: args)
            ?? parseFlag("--wait-timeout", from: args)
        guard let rawValue else { return nil }
        guard let seconds = TimeInterval(rawValue), seconds >= 0 else { return nil }
        return seconds
    }

    static func recordReviewBatchEnrichmentResults(
        _ result: CiderReviewQueueBatchEnrichmentResult,
        candidates: [CiderReviewQueueItem],
        actor: String,
        timeout: TimeInterval,
        bookmarkService: VaultBookmarkService
    ) async {
        let audit = MutationAuditService(database: CiderDatabase.shared)
        for candidate in candidates {
            let waitResult = await waitForBookmarkEnrichmentCompletion(
                candidate.itemID,
                in: bookmarkService,
                timeout: timeout
            )
            audit.record(
                action: "review.enrich.batch.result",
                itemType: candidate.itemType,
                itemID: candidate.itemID,
                after: [
                    "reviewAction": "enrich",
                    "status": waitResult.completed ? "completed" : "timed_out",
                    "elapsedSeconds": String(format: "%.1f", waitResult.elapsedSeconds),
                ],
                metadata: [
                    "batchID": result.batchID.uuidString,
                    "candidateCount": String(result.candidateCount),
                    "excludedCount": String(result.excludedCount),
                    "actor": actor,
                ],
                source: reviewMutationAuditSource(for: actor)
            )
        }
    }

    struct BookmarkEnrichmentCompletionWaitResult {
        var completed: Bool
        var elapsedSeconds: TimeInterval
    }

    static func waitForBookmarkEnrichmentCompletion(
        _ bookmarkID: UUID,
        in service: VaultBookmarkService,
        timeout: TimeInterval
    ) async -> BookmarkEnrichmentCompletionWaitResult {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)

        while Date() <= deadline {
            service.reconcileLegacyIndexCacheIntoCanonicalBookmarks()
            if isBookmarkEnrichmentComplete(bookmarkID, in: service)
                || isBookmarkEnrichmentCompleteInDatabase(bookmarkID) {
                return BookmarkEnrichmentCompletionWaitResult(
                    completed: true,
                    elapsedSeconds: Date().timeIntervalSince(startedAt)
                )
            }

            if timeout == 0 { break }
            try? await Task.sleep(for: .milliseconds(250))
        }

        return BookmarkEnrichmentCompletionWaitResult(
            completed: isBookmarkEnrichmentComplete(bookmarkID, in: service)
                || isBookmarkEnrichmentCompleteInDatabase(bookmarkID),
            elapsedSeconds: Date().timeIntervalSince(startedAt)
        )
    }

    static func isBookmarkEnrichmentComplete(_ bookmarkID: UUID, in service: VaultBookmarkService) -> Bool {
        guard let bookmark = service.bookmarks.first(where: { $0.id == bookmarkID }) else {
            return false
        }
        return bookmark.enrichmentStatus == "complete" && bookmark.lastEnrichedAt != nil
    }

    static func isBookmarkEnrichmentCompleteInDatabase(_ bookmarkID: UUID) -> Bool {
        guard CiderDatabase.shared.isOpen else { return false }
        do {
            let stmt = try CiderDatabase.shared.prepare("""
                SELECT enrichment_status, last_enriched_at IS NOT NULL
                FROM bookmarks
                WHERE item_id = ?
                LIMIT 1;
            """)
            stmt.bind(bookmarkID.uuidString, at: 1)
            guard try stmt.step() else { return false }
            return stmt.string(at: 0) == "complete" && stmt.bool(at: 1)
        } catch {
            return false
        }
    }

    static func isReviewEnrichmentResolved(_ bookmarkID: UUID) -> Bool {
        do {
            let service = CiderReviewQueueService()
            return try service.list(
                limit: Int.max,
                kind: "enrichment",
                itemType: "bookmark",
                requiredSafeAction: "enrich"
            ).items.contains { $0.itemID == bookmarkID } == false
        } catch {
            return false
        }
    }

    static func reviewMutationAuditSource(for actor: String) -> MutationAuditSource {
        switch actor.lowercased() {
        case "agent": return .agent
        case "cli": return .cli
        default: return .ui
        }
    }

    static func waitForNativeBookmarkCapture(
        _ bookmarkID: UUID,
        in service: VaultBookmarkService,
        timeout: TimeInterval
    ) async -> BookmarkNativeCaptureWaitResult {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)
        var state = BookmarkNativeCaptureWaitState()

        while Date() <= deadline {
            service.reconcileLegacyIndexCacheIntoCanonicalBookmarks()
            if let bookmark = service.bookmarks.first(where: { $0.id == bookmarkID }) {
                let now = Date()
                if shouldReturnNativeBookmarkCapture(
                    bookmark: bookmark,
                    state: &state,
                    startedAt: startedAt,
                    now: now,
                    timeout: timeout
                ) {
                    return BookmarkNativeCaptureWaitResult(
                        bookmark: bookmark,
                        elapsedSeconds: now.timeIntervalSince(startedAt),
                        timeoutSeconds: timeout,
                        timedOut: false
                    )
                }
            }

            if timeout == 0 { break }
            state.polls += 1
            try? await Task.sleep(for: .milliseconds(250))
        }

        return BookmarkNativeCaptureWaitResult(
            bookmark: service.bookmarks.first(where: { $0.id == bookmarkID }),
            elapsedSeconds: Date().timeIntervalSince(startedAt),
            timeoutSeconds: timeout,
            timedOut: true
        )
    }

    struct BookmarkNativeCaptureWaitState {
        var sawEnrichmentRunning = false
        var polls = 0
        var lastCandidateFingerprint: String?
        var candidateFirstSeenAt: Date?
    }

    static func shouldReturnNativeBookmarkCapture(
        bookmark: Bookmark,
        state: inout BookmarkNativeCaptureWaitState,
        startedAt: Date,
        now: Date,
        timeout: TimeInterval
    ) -> Bool {
        let minimumSettleDelay = min(timeout, 1.5)
        let stableSettleWindow: TimeInterval = 0.25

        if bookmark.isEnriching {
            state.sawEnrichmentRunning = true
            state.lastCandidateFingerprint = nil
            state.candidateFirstSeenAt = nil
            return false
        }

        guard state.sawEnrichmentRunning
            || bookmark.metadataUpdatedAt != nil
            || bookmark.thumbnailRelativePath != nil
            || bookmark.thumbnailRemoteURLString != nil
            || state.polls >= 2 else {
            return false
        }
        guard bookmark.enrichmentStatus == "complete",
              bookmark.lastEnrichedAt != nil else {
            return false
        }

        let fingerprint = nativeCaptureFingerprint(for: bookmark)
        if fingerprint != state.lastCandidateFingerprint {
            state.lastCandidateFingerprint = fingerprint
            state.candidateFirstSeenAt = now
        }

        let waitedLongEnough = now.timeIntervalSince(startedAt) >= minimumSettleDelay
        let candidateStableLongEnough = now.timeIntervalSince(state.candidateFirstSeenAt ?? now) >= stableSettleWindow
        return waitedLongEnough && candidateStableLongEnough
    }

    static func nativeCaptureFingerprint(for bookmark: Bookmark) -> String {
        [
            bookmark.title,
            bookmark.notes,
            bookmark.tags.joined(separator: "\u{1f}"),
            bookmark.thumbnailRelativePath ?? "",
            bookmark.thumbnailRemoteURLString ?? "",
            bookmark.metadataUpdatedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            bookmark.lastEnrichedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "",
            String(bookmark.updatedAt.timeIntervalSinceReferenceDate),
        ].joined(separator: "\u{1e}")
    }

    static func dashboardNowMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    static func dashboardTopics(storage: DashboardStorage) -> [DashboardTopic] {
        let storedTopics = storage.topics
            .filter { $0.deleted != true }
        let storedIDs = Set(storedTopics.map(\.ciderSyncId))
        let defaultTopics = DashboardDefaultTopics.topics.filter { storedIDs.contains($0.ciderSyncId) == false }
        return (defaultTopics + storedTopics).sorted { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.position < rhs.position
        }
    }

    static func resolveDashboardTopic(_ ref: String, storage: DashboardStorage) -> DashboardTopic? {
        let lower = ref.lowercased()
        let topics = dashboardTopics(storage: storage)
        let idMatches = topics.filter { $0.ciderSyncId.hasPrefix(lower) }
        if idMatches.count == 1 { return idMatches[0] }
        if idMatches.count > 1 {
            print("Error: Dashboard topic ID prefix '\(ref)' is ambiguous:")
            idMatches.forEach { print("  [\($0.ciderSyncId.prefix(8))] \($0.title)") }
            return nil
        }
        let titleMatches = topics.filter { $0.title.localizedCaseInsensitiveCompare(ref) == .orderedSame }
        if titleMatches.count == 1 { return titleMatches[0] }
        if titleMatches.count > 1 {
            print("Error: Dashboard topic title '\(ref)' is ambiguous. Use an ID prefix.")
            titleMatches.forEach { print("  [\($0.ciderSyncId.prefix(8))] \($0.title)") }
            return nil
        }
        print("Error: No dashboard topic found for '\(ref)'")
        return nil
    }

    static func resolveDashboardTopicIDs(from args: [String], storage: DashboardStorage) -> [String] {
        let topicRefs = parseFlagAll("--topic", from: args)
        let topicIDs = parseFlagAll("--topic-id", from: args).map { $0.lowercased() }
        var resolved = topicIDs
        for ref in topicRefs {
            guard let topic = resolveDashboardTopic(ref, storage: storage) else { continue }
            resolved.append(topic.ciderSyncId)
        }
        return Array(Set(resolved)).sorted()
    }

    static func resolveDashboardCard(_ ref: String, storage: DashboardStorage) -> DashboardCard? {
        let lower = ref.lowercased()
        let matches = storage.cards.filter { $0.ciderSyncId.hasPrefix(lower) }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            print("Error: Dashboard card ID prefix '\(ref)' is ambiguous:")
            matches.forEach { print("  [\($0.ciderSyncId.prefix(8))] \($0.title)") }
            return nil
        }
        print("Error: No dashboard card found for '\(ref)'")
        return nil
    }

    static func readDashboardCardPayload(from args: [String]) -> DashboardCardUpsertPayload? {
        if let inline = parseFlag("--json-payload", from: args) {
            return decodeDashboardCardPayload(inline, source: "--json-payload")
        }
        if let path = parseFlag("--json-file", from: args) {
            if path == "-" {
                guard let string = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) else {
                    print("Error: Could not read dashboard card JSON from stdin.")
                    return nil
                }
                return decodeDashboardCardPayload(string, source: "stdin")
            }
            let expanded = NSString(string: path).expandingTildeInPath
            do {
                let string = try String(contentsOfFile: expanded, encoding: .utf8)
                return decodeDashboardCardPayload(string, source: expanded)
            } catch {
                print("Error: Could not read dashboard card JSON file '\(expanded)': \(error.localizedDescription)")
                return nil
            }
        }

        let topicRefs = parseFlagAll("--topic", from: args)
        let topicIDs = parseFlagAll("--topic-id", from: args)
        if parseFlag("--title", from: args) != nil || parseFlag("--summary", from: args) != nil || !topicRefs.isEmpty || !topicIDs.isEmpty {
            return DashboardCardUpsertPayload(
                ciderSyncId: parseFlag("--id", from: args),
                topicSyncIds: topicIDs.isEmpty ? nil : topicIDs,
                topics: topicRefs.isEmpty ? nil : topicRefs,
                title: parseFlag("--title", from: args),
                subtitle: parseFlag("--subtitle", from: args),
                summary: parseFlag("--summary", from: args),
                whyItMatters: parseFlag("--why", from: args),
                sourceKind: parseFlag("--source-kind", from: args),
                sourceURL: parseFlag("--source-url", from: args),
                sourceTitle: parseFlag("--source-title", from: args),
                relatedItemSyncId: parseFlag("--related-item-id", from: args),
                relatedItemType: parseFlag("--related-item-type", from: args),
                status: parseFlag("--status", from: args),
                priority: parseFlag("--priority", from: args),
                score: parseFlag("--score", from: args).flatMap(Double.init),
                rating: parseFlag("--rating", from: args).flatMap(Int.init),
                moreLikeThis: parseOptionalBoolFlag("--more-like-this", from: args),
                lessLikeThis: parseOptionalBoolFlag("--less-like-this", from: args)
            )
        }

        print("Error: Usage: cider-cli dashboard card upsert --json-file <path|-> OR --title <title> --summary <summary> --topic <id|title>")
        return nil
    }

    static func decodeDashboardCardPayload(_ string: String, source: String) -> DashboardCardUpsertPayload? {
        guard let data = string.data(using: .utf8) else {
            print("Error: Dashboard card JSON from \(source) was not valid UTF-8.")
            return nil
        }
        do {
            return try JSONDecoder().decode(DashboardCardUpsertPayload.self, from: data)
        } catch {
            print("Error: Could not decode dashboard card JSON from \(source): \(error.localizedDescription)")
            return nil
        }
    }

    static func dashboardCard(from payload: DashboardCardUpsertPayload, storage: DashboardStorage) -> DashboardCard? {
        let existing = payload.ciderSyncId.flatMap { id in
            storage.cards.first { $0.ciderSyncId == id.lowercased() }
        }
        let now = dashboardNowMilliseconds()
        let resolvedTopicIDs = {
            var ids = payload.topicSyncIds?.map { $0.lowercased() } ?? []
            for ref in payload.topics ?? [] {
                guard let topic = resolveDashboardTopic(ref, storage: storage) else { continue }
                ids.append(topic.ciderSyncId)
            }
            return Array(Set(ids)).sorted()
        }()

        guard let title = payload.title ?? existing?.title, !title.isEmpty else {
            print("Error: Dashboard card title is required for new cards.")
            return nil
        }
        guard let summary = payload.summary ?? existing?.summary, !summary.isEmpty else {
            print("Error: Dashboard card summary is required for new cards.")
            return nil
        }
        let topicIDs = resolvedTopicIDs.isEmpty ? (existing?.topicSyncIds ?? []) : resolvedTopicIDs
        guard !topicIDs.isEmpty else {
            print("Error: At least one dashboard topic is required for new cards.")
            return nil
        }

        let feedback: DashboardCardFeedback?
        if payload.rating != nil || payload.moreLikeThis != nil || payload.lessLikeThis != nil {
            var moreLikeThis = payload.moreLikeThis ?? existing?.feedback?.moreLikeThis
            var lessLikeThis = payload.lessLikeThis ?? existing?.feedback?.lessLikeThis
            if payload.moreLikeThis == true {
                lessLikeThis = false
            }
            if payload.lessLikeThis == true {
                moreLikeThis = false
            }
            feedback = DashboardCardFeedback(
                rating: payload.rating ?? existing?.feedback?.rating,
                moreLikeThis: moreLikeThis,
                lessLikeThis: lessLikeThis,
                notInterested: existing?.feedback?.notInterested,
                note: existing?.feedback?.note,
                updatedAt: now
            )
        } else {
            feedback = existing?.feedback
        }

        return DashboardCard(
            ciderSyncId: payload.ciderSyncId ?? existing?.ciderSyncId,
            topicSyncIds: topicIDs,
            title: title,
            subtitle: payload.subtitle ?? existing?.subtitle,
            summary: summary,
            whyItMatters: payload.whyItMatters ?? existing?.whyItMatters,
            sourceKind: payload.sourceKind.map(DashboardCardSourceKind.init(rawValue:)) ?? existing?.sourceKind ?? .manual,
            sourceURL: payload.sourceURL ?? existing?.sourceURL,
            sourceTitle: payload.sourceTitle ?? existing?.sourceTitle,
            relatedItemSyncId: payload.relatedItemSyncId ?? existing?.relatedItemSyncId,
            relatedItemType: payload.relatedItemType ?? existing?.relatedItemType,
            status: payload.status.map(DashboardCardStatus.init(rawValue:)) ?? existing?.status ?? .new,
            priority: payload.priority.map(DashboardCardPriority.init(rawValue:)) ?? existing?.priority ?? .normal,
            score: payload.score ?? existing?.score,
            feedback: feedback,
            actionState: existing?.actionState,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            lastSeenAt: existing?.lastSeenAt,
            dismissedAt: existing?.dismissedAt,
            deleted: existing?.deleted,
            deletedAt: existing?.deletedAt
        )
    }

    static func mutateDashboardCard(
        _ ref: String?,
        storage: DashboardStorage,
        usage: String,
        mutation: (DashboardCard) -> Bool
    ) {
        guard let ref else {
            print("Error: Usage: \(usage)")
            return
        }
        guard let card = resolveDashboardCard(ref, storage: storage) else { return }
        guard mutation(card) else {
            print("Error: Could not update dashboard card '\(ref)'")
            return
        }
        printDashboardCardResult(resolveDashboardCard(card.ciderSyncId, storage: storage) ?? card)
    }

    static func printDashboardTopicResult(_ topic: DashboardTopic) {
        if jsonOutput {
            outputJSON(dashboardTopicToDict(topic))
        } else {
            print("Dashboard topic: \(topic.title) (\(topic.ciderSyncId.prefix(8)))")
        }
    }

    static func printDashboardCardResult(_ card: DashboardCard) {
        if jsonOutput {
            outputJSON(dashboardCardToDict(card))
        } else {
            print("Dashboard card: \(card.title) (\(card.ciderSyncId.prefix(8)))")
        }
    }

    static func resolveDatabaseBackup(
        _ selector: String,
        in backups: [DatabaseSafetyService.SQLiteBackupInfo]
    ) -> DatabaseSafetyService.SQLiteBackupInfo? {
        if selector == "latest" {
            return backups.first
        }
        if let index = Int(selector), backups.indices.contains(index) {
            return backups[index]
        }
        return backups.first {
            $0.url.lastPathComponent == selector
                || $0.url.lastPathComponent.lowercased().hasPrefix(selector.lowercased())
        }
    }

    static func databaseBackupToDict(
        _ backup: DatabaseSafetyService.SQLiteBackupInfo,
        index: Int
    ) -> [String: Any] {
        [
            "index": index,
            "kind": backup.kind.rawValue,
            "name": backup.url.lastPathComponent,
            "path": backup.url.path,
            "createdAt": backup.createdAt.timeIntervalSince1970,
            "byteSize": backup.byteSize,
        ]
    }

    static func databaseBackupURLToDict(_ url: URL) -> [String: Any] {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        var dict: [String: Any] = [
            "name": url.lastPathComponent,
            "path": url.path,
            "exists": FileManager.default.fileExists(atPath: url.path),
            "byteSize": attrs[.size] as? Int64 ?? 0,
        ]
        if let createdAt = attrs[.creationDate] as? Date {
            dict["createdAt"] = ISO8601DateFormatter().string(from: createdAt)
        }
        if let modifiedAt = attrs[.modificationDate] as? Date {
            dict["modifiedAt"] = ISO8601DateFormatter().string(from: modifiedAt)
        }
        return dict
    }

    static func databaseBackupVerificationDict(_ url: URL) -> [String: Any] {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let byteSize = attrs[.size] as? Int64 ?? 0
        return [
            "exists": FileManager.default.fileExists(atPath: url.path),
            "nonEmpty": byteSize > 0,
            "byteSize": byteSize,
        ]
    }

    static func databaseIntegrityToDict(_ status: DatabaseIntegrityStatus) -> [String: Any] {
        [
            "healthy": status.isHealthy,
            "messages": status.messages,
        ]
    }

    static func databaseRestorePlanPayload(
        selector: String,
        backup: DatabaseSafetyService.SQLiteBackupInfo,
        databaseURL: URL,
        ciderRunning: Bool
    ) -> [String: Any] {
        [
            "selector": selector,
            "targetDatabase": databaseURL.path,
            "selectedBackup": databaseBackupToDict(backup, index: 0),
            "requiresConfirmation": true,
            "requiredConfirmationFlag": "--yes",
            "activeAppBlocker": ciderRunning,
            "blockers": ciderRunning ? ["cider_app_running"] : [],
            "preRestoreSnapshotPlanned": true,
            "rollbackGuidance": "Confirmed restore creates a pre-restore snapshot. Use db backups and db restore --dry-run before any rollback.",
            "safeNextCommands": [
                "cider-cli db backups --json",
                "cider-cli db restore \(selector) --dry-run --json",
            ],
        ]
    }

    static func databaseEnvelope(
        command: String,
        readOnly: Bool,
        changed: Bool,
        payload: [String: Any] = [:]
    ) -> [String: Any] {
        var dict = payload
        dict["ok"] = true
        dict["command"] = command
        dict["readOnly"] = readOnly
        dict["changed"] = changed
        if dict["safeNextCommands"] == nil {
            dict["safeNextCommands"] = readOnly
                ? ["cider-cli db integrity --json"]
                : ["cider-cli db integrity --json", "cider-cli db backups --json"]
        }
        return dict
    }

    static func printDatabaseError(
        command: String,
        message: String,
        readOnly: Bool,
        payload: [String: Any] = [:]
    ) {
        processExitCode = 1
        if jsonOutput {
            var dict = payload
            dict["ok"] = false
            dict["command"] = command
            dict["readOnly"] = readOnly
            dict["changed"] = false
            dict["error"] = message
            if dict["safeNextCommands"] == nil {
                dict["safeNextCommands"] = ["cider-cli db backups --json", "cider-cli db integrity --json"]
            }
            outputJSON(dict)
        } else {
            print("Error: \(message)")
        }
    }

    static func databaseCommandName(_ subcommand: String?) -> String {
        switch subcommand {
        case "backups", "list": return "db.backups"
        case "backup", "create": return "db.backup"
        case "integrity", "check": return "db.integrity"
        case "audit", "log": return "db.audit"
        case "restore": return "db.restore"
        default: return "db"
        }
    }

    static func isDatabaseMutationSubcommand(_ subcommand: String?) -> Bool {
        switch subcommand {
        case "backup", "create", "restore":
            return true
        default:
            return false
        }
    }

    static func mutationAuditEntryToDict(_ entry: MutationAuditEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "occurredAt": entry.occurredAt.timeIntervalSince1970,
            "itemType": entry.itemType,
            "itemID": entry.itemID.uuidString,
            "action": entry.action,
            "source": entry.source.rawValue,
            "before": entry.beforeState,
            "after": entry.afterState,
            "metadata": entry.metadata,
        ]
    }

    static func formatAuditState(_ state: [String: String]) -> String {
        state.keys.sorted().map { "\($0)=\(state[$0] ?? "")" }.joined(separator: ", ")
    }

    static func isCiderAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.cider.app").isEmpty
    }

    static func resolveEventStartAt(dateString: String, timeString: String?) -> Date? {
        let calendar = Calendar.autoupdatingCurrent

        guard let baseDate = localDateFormatter.date(from: dateString) else {
            return nil
        }

        guard let timeString, !timeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return calendar.startOfDay(for: baseDate)
        }

        let supportedFormats = ["h:mm a", "h:mma", "H:mm", "HH:mm"]
        let timeFormatters: [DateFormatter] = supportedFormats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            return formatter
        }

        guard let parsedTime = timeFormatters.compactMap({ $0.date(from: timeString) }).first else {
            return nil
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second ?? 0
        combined.timeZone = .autoupdatingCurrent
        return calendar.date(from: combined)
    }

    static func countItemsInFolder(_ folderID: UUID) -> Int {
        let bm = VaultBookmarkService.shared.bookmarks.filter { $0.folderID == folderID }.count
        let notes = NotesStorage.shared.notes.filter { $0.folderID == folderID }.count
        let todos = TodoCardStorage.shared.todoCards.filter { $0.folderID == folderID }.count
        let events = DateCardStorage.shared.dateCards.filter { $0.folderID == folderID }.count
        let contacts = ContactStorage.shared.contacts.filter { $0.folderID == folderID }.count
        let files = VaultFileService.shared.files.filter { $0.folderID == folderID }.count
        return bm + notes + todos + events + contacts + files
    }

    static func findBoard(_ nameOrID: String, in storage: KanbanStorage) -> KanbanBoard? {
        if let board = findBoardSilently(nameOrID, in: storage) {
            return board
        }
        printCLIError("Board '\(nameOrID)' not found")
        return nil
    }

    static func findBoardSilently(_ nameOrID: String, in storage: KanbanStorage) -> KanbanBoard? {
        storage.boards.first(where: {
            $0.name.localizedCaseInsensitiveCompare(nameOrID) == .orderedSame || $0.id == nameOrID
        })
    }

    static func printTestingTriageSection(_ title: String, items: [KanbanTestingTriageSummary.Item]) {
        print("\n  ── \(title) (\(items.count)) ──")
        if items.isEmpty {
            print("    None")
            return
        }
        for item in items {
            let priority = item.card.priority.map { " [\($0.rawValue)]" } ?? ""
            let parent = item.parentTitle.map { " — parent: \($0)" } ?? ""
            print("    [\(item.card.id)] \(item.card.title)\(priority) — \(item.reason)\(parent)")
            if !item.whatChanged.isEmpty {
                print("      What changed:")
                for change in item.whatChanged.prefix(2) {
                    print("        • \(change)")
                }
            }
            if !item.testEvidence.isEmpty {
                print("      Test evidence:")
                for evidence in item.testEvidence.prefix(2) {
                    print("        • \(evidence)")
                }
            }
            if !item.agentVerificationSteps.isEmpty {
                print("      Agent can verify:")
                for step in item.agentVerificationSteps.prefix(2) {
                    print("        • \(step)")
                }
            }
            if !item.failedQASteps.isEmpty {
                print("      Failed QA:")
                for step in item.failedQASteps.prefix(3) {
                    print("        • \(step)")
                }
            }
            if !item.manualQASteps.isEmpty {
                print("      Manual QA:")
                for step in item.manualQASteps.prefix(3) {
                    print("        • \(step)")
                }
            }
        }
    }

    static func printRoutingExplanation(_ explanation: CiderRoutingExplanation) {
        if jsonOutput {
            outputJSON(explanation.toDictionary())
            return
        }

        print("Item: \(explanation.item.title) [\(explanation.item.type)] \(explanation.item.id.uuidString.prefix(8))")
        guard let decision = explanation.latestDecision else {
            print("  Routing: none recorded")
            print("  Review needed: true")
            print("  Next safe action: \(explanation.nextSafeAction)")
            return
        }

        print("  Target: \(decision.target.relativePath)")
        print("  Confidence: \(decision.confidence)")
        print("  Review state: \(decision.reviewState)")
        print("  Actor: \(decision.actor)")
        print("  Source: \(decision.source)")
        print("  Reason: \(decision.reason)")
        print("  Decision: \(decision.id.uuidString)")
        if let supersedes = decision.supersedesDecisionID {
            print("  Supersedes: \(supersedes.uuidString)")
        }
        print("  History entries: \(explanation.history.count)")
        print("  Next safe action: \(explanation.nextSafeAction)")
    }

    static func printReviewQueueResult(_ result: CiderReviewQueueResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        guard !result.items.isEmpty else {
            print("No review items.")
            return
        }

        print("Review queue (\(result.items.count)):")
        for item in result.items {
            let id = item.itemID.uuidString.prefix(8)
            print("  [\(id)] \(item.title)")
            print("    Kind: \(item.kind)")
            print("    State: \(item.reviewState)")
            if let relativePath = item.relativePath {
                print("    Path: \(relativePath)")
            }
            if let target = item.target {
                print("    Candidate target: \(target.relativePath)")
            }
            if let confidence = item.confidence {
                print("    Confidence: \(confidence)")
            }
            print("    Reason: \(item.reason)")
            if !item.reasonCodes.isEmpty {
                print("    Reason codes: \(item.reasonCodes.joined(separator: ", "))")
            }
            print("    Suggested action: \(item.suggestedAction)")
            print("    Safe actions: \(item.safeActions.joined(separator: ", "))")
        }
    }

    static func printReviewQueueSummaryResult(_ result: CiderReviewQueueSummaryResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review summary: \(result.totalCount) item(s)")
        print("  By kind: \(formatCounts(result.countsByKind))")
        print("  By item type: \(formatCounts(result.countsByItemType))")
        print("  By state: \(formatCounts(result.countsByReviewState))")
        print("  By safe action: \(formatCounts(result.countsBySafeAction))")
        if !result.groups.isEmpty {
            print("  Groups:")
            for group in result.groups {
                print("    \(group.kind) state=\(group.reviewState) action=\(group.requiredSafeAction) type=\(group.itemType) count=\(group.count)")
            }
        }
        let preview = result.batchEnrichmentPreview
        print("  Batch enrichment preview: \(preview.candidateCount) candidate(s), \(preview.excludedCount) excluded, mutating=\(preview.isMutating)")
    }

    static func printReviewEnrichmentDiagnosisResult(_ result: CiderReviewEnrichmentDiagnosisResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review enrichment diagnosis: \(result.totalCandidateCount) candidate(s)")
        print("  Mutating: \(result.isMutating)")
        print("  Sample limit: \(result.sampleLimit)")
        for group in result.groups {
            print("  \(group.id): \(group.count)")
            print("    \(group.summary)")
            for item in group.sampleItems {
                print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
                if let relativePath = item.relativePath {
                    print("      Path: \(relativePath)")
                }
                if let enrichmentStatus = item.enrichmentStatus {
                    print("      Status: \(enrichmentStatus)")
                }
                if let lastEnrichedAt = item.lastEnrichedAt {
                    print("      Last enriched: \(ISO8601DateFormatter().string(from: lastEnrichedAt))")
                }
            }
        }
    }

    static func printReviewEnrichmentReconciliationPlanResult(_ result: CiderReviewEnrichmentReconciliationPlanResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review enrichment reconciliation plan: \(result.totalCandidateCount) candidate(s)")
        print("  Mutating: \(result.isMutating)")
        print("  Approval required: \(result.approvalRequired)")
        print("  Proposed changes: \(result.proposedChangeCount)")
        print("  Blocked: \(result.blockedCount)")
        print("  Sample limit: \(result.sampleLimit)")
        for group in result.groups {
            print("  \(group.id): \(group.count)")
            print("    \(group.summary)")
            print("    Proposed: \(group.proposedChangeCount), blocked: \(group.blockedCount)")
            for item in group.sampleItems {
                print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
                if let relativePath = item.relativePath {
                    print("      Path: \(relativePath)")
                }
                if !item.evidence.isEmpty {
                    print("      Evidence: \(item.evidence.joined(separator: ", "))")
                }
                if let proposedStatus = item.proposedStatus {
                    print("      Proposed status: \(proposedStatus)")
                }
                if let proposedLastEnrichedAt = item.proposedLastEnrichedAt {
                    print("      Proposed last enriched: \(ISO8601DateFormatter().string(from: proposedLastEnrichedAt))")
                }
            }
        }
    }

    static func printReviewEnrichmentReconciliationSampleResult(_ result: CiderReviewEnrichmentReconciliationSampleResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review enrichment reconciliation samples: \(result.matchingCandidateCount) matching of \(result.totalCandidateCount) candidate(s)")
        print("  Mutating: \(result.isMutating)")
        print("  Approval required: \(result.approvalRequired)")
        if let groupID = result.groupID {
            print("  Group: \(groupID)")
        }
        print("  Limit: \(result.limit)")
        for item in result.sampleItems {
            print("  [\(item.itemID.uuidString.prefix(8))] \(item.title)")
            print("    Group: \(item.groupID)")
            print("    URL: \(item.url)")
            if let relativePath = item.relativePath {
                print("    Path: \(relativePath)")
            }
            if !item.evidence.isEmpty {
                print("    Evidence: \(item.evidence.joined(separator: ", "))")
            }
            if let proposedStatus = item.proposedStatus {
                print("    Proposed status: \(proposedStatus)")
            }
            if let proposedLastEnrichedAt = item.proposedLastEnrichedAt {
                print("    Proposed last enriched: \(ISO8601DateFormatter().string(from: proposedLastEnrichedAt))")
            }
        }
    }

    static func printReviewEnrichmentReconciliationApplyResult(_ result: CiderReviewEnrichmentReconciliationApplyResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review enrichment reconciliation apply")
        print("  Status: \(result.status)")
        print("  Mutating: \(result.isMutating)")
        print("  Approval required: \(result.approvalRequired)")
        print("  Required approval token: \(result.requiredApprovalToken)")
        if let groupID = result.groupID {
            print("  Group: \(groupID)")
        }
        print("  Limit: \(result.limit)")
        print("  Candidates: \(result.matchingCandidateCount) matching of \(result.totalCandidateCount)")
        print("  Proposed changes: \(result.proposedChangeCount)")
        print("  Selected: \(result.selectedCount)")
        print("  Projected remaining candidates: \(result.projectedRemainingCandidateCount)")
        print("  Applied: \(result.appliedCount)")
        print("  Skipped: \(result.skippedCount)")
        if !result.blockers.isEmpty {
            print("  Blockers:")
            for blocker in result.blockers {
                print("    \(blocker)")
            }
        }
        if !result.selectedItems.isEmpty {
            print("  Selected items:")
        }
        for item in result.selectedItems {
            print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
            print("    Group: \(item.groupID)")
            if let proposedStatus = item.proposedStatus {
                print("    Proposed status: \(proposedStatus)")
            }
            if !item.evidence.isEmpty {
                print("    Evidence: \(item.evidence.joined(separator: ", "))")
            }
        }
        if !result.appliedItems.isEmpty {
            print("  Applied items:")
        }
        for item in result.appliedItems {
            print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
            print("    Group: \(item.groupID)")
            if let proposedStatus = item.proposedStatus {
                print("    Proposed status: \(proposedStatus)")
            }
            if !item.evidence.isEmpty {
                print("    Evidence: \(item.evidence.joined(separator: ", "))")
            }
        }
    }

    static func printReviewQueueDrilldownResult(_ result: CiderReviewQueueDrilldownResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review lane \(result.groupID): \(result.items.count)/\(result.totalCount) item(s)")
        print("  Offset: \(result.offset)")
        print("  Limit: \(result.limit)")
        print("  Has more: \(result.hasMore)")
        for item in result.items {
            print("  [\(item.itemID.uuidString.prefix(8))] \(item.title)")
            print("    Kind: \(item.kind)")
            print("    State: \(item.reviewState)")
            if let relativePath = item.relativePath {
                print("    Path: \(relativePath)")
            }
            if let target = item.target {
                print("    Candidate target: \(target.relativePath)")
            }
            print("    Reason: \(item.reason)")
            print("    Safe actions: \(item.safeActions.joined(separator: ", "))")
        }
    }

    private static func formatCounts(_ counts: [String: Int]) -> String {
        if counts.isEmpty { return "none" }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    static func printReviewQueueActionResult(_ result: CiderReviewQueueActionResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("\(result.status.capitalized): \(result.title) (\(result.itemID.uuidString.prefix(8)))")
        print("  Action: \(result.action)")
        print("  Type: \(result.itemType)")
        print("  Actor: \(result.actor)")
        print("  Message: \(result.message)")
        print("  Safe actions: \(result.safeActions.joined(separator: ", "))")
    }

    static func printReviewEnrichmentLifecycleResult(
        scheduledResult: CiderReviewQueueActionResult,
        before: Bookmark?,
        after: Bookmark?,
        waitResult: BookmarkNativeCaptureWaitResult,
        reviewResolved: Bool
    ) {
        let status = waitResult.timedOut ? "timed_out" : "completed"
        let changedFields = changedBookmarkMetadataFields(before: before, after: after)
        let safeActions = reviewEnrichmentLifecycleSafeActions(
            itemID: scheduledResult.itemID,
            status: status,
            reviewResolved: reviewResolved
        )

        if jsonOutput {
            outputJSON([
                "action": scheduledResult.action,
                "itemID": scheduledResult.itemID.uuidString,
                "itemType": scheduledResult.itemType,
                "title": after?.title ?? scheduledResult.title,
                "actor": scheduledResult.actor,
                "status": status,
                "message": reviewEnrichmentLifecycleMessage(
                    status: status,
                    changedFields: changedFields,
                    reviewResolved: reviewResolved
                ),
                "waited": true,
                "elapsedSeconds": waitResult.elapsedSeconds,
                "timeoutSeconds": waitResult.timeoutSeconds,
                "before": bookmarkLifecycleSnapshot(before),
                "after": bookmarkLifecycleSnapshot(after),
                "changedFields": changedFields,
                "reviewResolved": reviewResolved,
                "safeActions": safeActions,
            ])
            return
        }

        print("\(status.replacingOccurrences(of: "_", with: " ").capitalized): \(after?.title ?? scheduledResult.title) (\(scheduledResult.itemID.uuidString.prefix(8)))")
        print("  Action: \(scheduledResult.action)")
        print("  Type: \(scheduledResult.itemType)")
        print("  Actor: \(scheduledResult.actor)")
        print("  Waited: \(String(format: "%.1f", waitResult.elapsedSeconds))s / \(String(format: "%.1f", waitResult.timeoutSeconds))s")
        print("  Changed: \(changedFields.isEmpty ? "none" : changedFields.joined(separator: ", "))")
        print("  Review resolved: \(reviewResolved ? "yes" : "no")")
        print("  Message: \(reviewEnrichmentLifecycleMessage(status: status, changedFields: changedFields, reviewResolved: reviewResolved))")
        print("  Safe actions: \(safeActions.joined(separator: ", "))")
    }

    static func reviewEnrichmentLifecycleMessage(
        status: String,
        changedFields: [String],
        reviewResolved: Bool
    ) -> String {
        switch status {
        case "completed":
            if reviewResolved {
                return changedFields.isEmpty
                    ? "Bookmark enrichment completed; no visible metadata fields changed."
                    : "Bookmark enrichment completed and updated \(changedFields.joined(separator: ", "))."
            }
            return "Bookmark enrichment completed, but the review item still needs attention."
        case "timed_out":
            return "Bookmark enrichment was scheduled, but did not reach a final complete state before the timeout."
        default:
            return "Bookmark enrichment finished with status \(status)."
        }
    }

    static func reviewEnrichmentLifecycleSafeActions(
        itemID: UUID,
        status: String,
        reviewResolved: Bool
    ) -> [String] {
        var actions = [
            "item get \(itemID.uuidString)",
            "review list --kind enrichment",
        ]
        if status == "timed_out" || !reviewResolved {
            actions.insert("review enrich \(itemID.uuidString) --timeout 20", at: 0)
        }
        return actions
    }

    static func bookmarkLifecycleSnapshot(_ bookmark: Bookmark?) -> [String: Any] {
        guard let bookmark else { return [:] }
        var snapshot: [String: Any] = [
            "id": bookmark.id.uuidString,
            "title": bookmark.title,
            "url": bookmark.urlString,
            "relativePath": bookmark.relativePath ?? NSNull(),
            "thumbnailRelativePath": bookmark.thumbnailRelativePath ?? NSNull(),
            "thumbnailRemoteURL": bookmark.thumbnailRemoteURLString ?? NSNull(),
            "originalImagePath": bookmark.originalImageRelativePath ?? NSNull(),
            "enrichmentStatus": bookmark.enrichmentStatus ?? NSNull(),
            "isEnriching": bookmark.isEnriching,
            "titleManuallySet": bookmark.titleManuallySet,
            "notesManuallySet": bookmark.notesManuallySet,
        ]
        if let metadataUpdatedAt = bookmark.metadataUpdatedAt {
            snapshot["metadataUpdatedAt"] = ISO8601DateFormatter().string(from: metadataUpdatedAt)
        } else {
            snapshot["metadataUpdatedAt"] = NSNull()
        }
        if let lastEnrichedAt = bookmark.lastEnrichedAt {
            snapshot["lastEnrichedAt"] = ISO8601DateFormatter().string(from: lastEnrichedAt)
        } else {
            snapshot["lastEnrichedAt"] = NSNull()
        }
        if let aiSummary = bookmark.aiSummary { snapshot["aiSummary"] = aiSummary }
        if let ocrText = bookmark.ocrText { snapshot["ocrText"] = ocrText }
        if let dominantColors = bookmark.dominantColors { snapshot["dominantColors"] = dominantColors }
        return snapshot
    }

    static func changedBookmarkMetadataFields(before: Bookmark?, after: Bookmark?) -> [String] {
        guard let before, let after else {
            return after == nil ? [] : ["bookmark"]
        }
        var fields: [String] = []
        if before.title != after.title { fields.append("title") }
        if before.notes != after.notes { fields.append("notes") }
        if before.relativePath != after.relativePath { fields.append("relativePath") }
        if before.thumbnailRelativePath != after.thumbnailRelativePath { fields.append("thumbnailRelativePath") }
        if before.thumbnailRemoteURLString != after.thumbnailRemoteURLString { fields.append("thumbnailRemoteURL") }
        if before.originalImageRelativePath != after.originalImageRelativePath { fields.append("originalImagePath") }
        if before.metadataUpdatedAt != after.metadataUpdatedAt { fields.append("metadataUpdatedAt") }
        if before.enrichmentStatus != after.enrichmentStatus { fields.append("enrichmentStatus") }
        if before.lastEnrichedAt != after.lastEnrichedAt { fields.append("lastEnrichedAt") }
        if before.aiSummary != after.aiSummary { fields.append("aiSummary") }
        if before.ocrText != after.ocrText { fields.append("ocrText") }
        if before.dominantColors != after.dominantColors { fields.append("dominantColors") }
        return fields
    }

    static func printReviewRoutingActionResult(_ result: CiderReviewRoutingActionResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("\(result.status.capitalized): \(result.title) (\(result.itemID.uuidString.prefix(8)))")
        print("  Action: \(result.action)")
        print("  Type: \(result.itemType)")
        print("  Actor: \(result.actor)")
        print("  Review state: \(result.reviewState)")
        print("  Target: \(result.target.relativePath)")
        print("  Decision: \(result.routingDecisionID.uuidString)")
        if let supersedes = result.supersedesDecisionID {
            print("  Supersedes: \(supersedes.uuidString)")
        }
        print("  Remaining routing reviews: \(result.remainingActiveRoutingReviewCount)")
        print("  Message: \(result.message)")
        print("  Safe actions: \(result.safeActions.joined(separator: ", "))")
    }

    static func printReviewQueueBatchEnrichmentResult(_ result: CiderReviewQueueBatchEnrichmentResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Batch enrichment: \(result.scheduledCount)/\(result.candidateCount) scheduled")
        print("  Batch: \(result.batchID.uuidString)")
        print("  Actor: \(result.actor)")
        print("  Excluded: \(result.excludedCount)")
        print("  Failed: \(result.failedCount)")
        if !result.exclusionsByReason.isEmpty {
            print("  Exclusions: \(formatCounts(result.exclusionsByReason))")
        }
        if !result.failures.isEmpty {
            print("  Failure samples:")
            for failure in result.failures {
                print("    \(failure.title): \(failure.reason)")
            }
        }
        print("  Safe actions: \(result.safeActions.joined(separator: ", "))")
    }

    static func printReviewActionJobHistoryResult(_ result: CiderReviewActionJobHistoryResult) {
        if jsonOutput {
            outputJSON(result.toDictionary())
            return
        }

        print("Review action jobs: \(result.jobs.count)")
        for job in result.jobs {
            print("\(job.action): \(job.jobID)")
            print("  Family: \(job.actionFamily)")
            print("  Scheduled: \(job.scheduledCount)/\(job.candidateCount)")
            print("  Result: \(job.resultState)")
            print("  Excluded: \(job.excludedCount)")
            print("  Failed: \(job.failedCount)")
            print("  Actor: \(job.actor)")
            if !job.itemSamples.isEmpty {
                print("  Item samples:")
                for item in job.itemSamples {
                    print("    \(item.title) (\(item.itemID.uuidString.prefix(8))) - \(item.status)")
                }
            }
            print("  Safe actions: \(job.safeActions.joined(separator: ", "))")
        }
    }

    static func printSpaceCaptureDashboard(_ dashboard: CiderSpaceCaptureDashboard) {
        if jsonOutput {
            outputJSON(dashboard.toDictionary())
            return
        }

        print("Space captures: \(dashboard.spaceName) — \(dashboard.rootRelativePath)")

        if dashboard.needsReview.isEmpty {
            print("  Needs review: none")
        } else {
            print("  Needs review:")
            for item in dashboard.needsReview {
                print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
                print("      State: \(item.reviewState) confidence=\(item.confidence)")
                print("      Reason: \(item.reason)")
                print("      Explain: \(item.routingExplanationCommand)")
            }
        }

        if dashboard.recentRouted.isEmpty {
            print("  Recent routed: none")
        } else {
            print("  Recent routed:")
            for item in dashboard.recentRouted {
                print("    [\(item.itemID.uuidString.prefix(8))] \(item.title)")
                print("      Target: \(item.target.relativePath)")
                print("      Reason: \(item.reason)")
                if let sourceURL = item.sourceURL {
                    print("      Source: \(sourceURL)")
                }
            }
        }
    }

    static func resolveSpace(_ ref: String, storage: CiderSpaceStorage) -> CiderSpace? {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()
        let idMatches = storage.spaces.filter {
            $0.id.lowercased().hasPrefix(lowercased)
        }
        if idMatches.count == 1 { return idMatches[0] }
        if idMatches.count > 1 {
            printCLIError("Space ID prefix '\(ref)' is ambiguous.")
            return nil
        }

        let nameMatches = storage.spaces.filter {
            $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }
        if nameMatches.count == 1 { return nameMatches[0] }
        if nameMatches.count > 1 {
            printCLIError("Space name '\(ref)' is ambiguous. Use an ID prefix.")
            return nil
        }

        printCLIError("No Space found for '\(ref)'")
        return nil
    }

    static func resolveOptionalSpaceFlag(from args: [String]) -> CiderSpace? {
        guard let ref = parseFlag("--space", from: args) else { return nil }
        return resolveSpace(ref, storage: CiderSpaceStorage.shared)
    }

    static func resolveSpaceTarget(targetID: String?, targetPath: String?) -> CiderSpace? {
        let storage = CiderSpaceStorage.shared
        for ref in [targetID, targetPath].compactMap({ $0 }) {
            let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = storage.spaces.first(where: {
                $0.id == normalized
                    || $0.id.lowercased().hasPrefix(normalized.lowercased())
                    || $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame
                    || $0.rootRelativePath.localizedCaseInsensitiveCompare(normalized) == .orderedSame
            }) {
                return match
            }
        }
        return nil
    }

    static func findColumn(_ nameOrID: String, in board: KanbanBoard) -> KanbanColumn? {
        if let col = board.columns.first(where: {
            $0.name.localizedCaseInsensitiveCompare(nameOrID) == .orderedSame || $0.id == nameOrID
        }) {
            return col
        }
        printCLIError("Column '\(nameOrID)' not found in board '\(board.name)'. Available: \(board.columns.map(\.name).joined(separator: ", "))")
        return nil
    }

    static func handleBoardMilestone(subcommand: String?, args: [String], storage: KanbanStorage) {
        switch subcommand {
        case "create":
            guard let boardRef = args.first,
                  let title = parseFlag("--title", from: args) else {
                printCLIError("Usage: cider-cli board milestone create <board> --title <title> [--description <text>] [--column <column>] [--source-artifact <note-id>] [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            let sourceArtifactRef = parseFlag("--source-artifact", from: args) ?? parseFlag("--source-note", from: args)
            let sourceArtifact: Note?
            if let sourceArtifactRef {
                guard let note = findNote(sourceArtifactRef, in: NotesStorage.shared) else { return }
                sourceArtifact = note
            } else {
                sourceArtifact = nil
            }
            let columnRef = parseFlag("--column", from: args)
            guard let column = columnRef.flatMap({ findColumn($0, in: board) }) ?? defaultMilestoneColumn(in: board) else {
                printCLIError("Board '\(board.name)' has no column for milestone creation.")
                return
            }
            let milestoneTitle = normalizedMilestoneTitle(title)
            guard let created = storage.addCard(boardID: board.id, columnID: column.id, title: milestoneTitle) else {
                printCLIError("Could not create milestone card on board '\(board.name)'.")
                return
            }
            var milestone = created
            milestone.tags = normalizedTags(created.tags + ["milestone", "milestone-object"])
            milestone.color = .purple
            if let description = parseFlag("--description", from: args) {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    milestone.notes = KanbanCardSectionParser.updatingSection(in: milestone.notes, title: "Goal", body: trimmed)
                }
            }
            milestone.markActivity("created", at: created.created)
            storage.updateCard(boardID: board.id, card: milestone)
            refreshSecondBrainProjection(boardID: board.id, card: milestone)
            if let sourceArtifact {
                _ = ProjectArtifactRelationService.recordArtifactRelations(
                    note: sourceArtifact,
                    targets: [
                        ProjectArtifactRelationService.ArtifactRelationTarget(
                            owner: SecondBrainKanbanProjectionService.owner(boardID: board.id, cardID: milestone.id),
                            relationType: ProjectArtifactRelationType.documents,
                            title: milestone.title,
                            evidence: "Project artifact \(sourceArtifact.title) documents milestone \(milestone.title) [\(milestone.id)]."
                        ),
                    ],
                    actor: parseFlag("--source-agent", from: args) ?? "cider-cli",
                    source: ProjectArtifactRelationService.cliSource
                )
            }
            printMilestoneResult(boardID: board.id, boardName: board.name, milestone: milestone, children: [], action: "created")

        case "list", "ls":
            guard let boardRef = args.first else {
                printCLIError("Usage: cider-cli board milestone list <board> [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            let milestones = boardMilestoneCards(in: board)
            if jsonOutput {
                outputJSON([
                    "ok": true,
                    "board": ["id": board.id, "name": board.name],
                    "milestones": milestones.map { milestoneToDict(board: board, milestone: $0) },
                ])
            } else if milestones.isEmpty {
                print("No milestones found on board: \(board.name)")
            } else {
                print("Milestones for \(board.name):")
                for milestone in milestones {
                    let children = board.childCards(of: milestone.id)
                    print("  [\(milestone.id)] \(milestone.title) — \(children.count) card(s)")
                }
            }

        case "inspect":
            guard let boardRef = args.first,
                  let milestoneRef = parseFlag("--milestone", from: args) else {
                printCLIError("Usage: cider-cli board milestone inspect <board> --milestone <id|display-key|title> [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let milestone = resolveMilestone(milestoneRef, in: board) else { return }
            let children = board.childCards(of: milestone.id)
            printMilestoneResult(boardID: board.id, boardName: board.name, milestone: milestone, children: children, action: "inspected")

        case "attach-card", "attach":
            guard let boardRef = args.first,
                  let milestoneRef = parseFlag("--milestone", from: args),
                  let cardRef = parseFlag("--card", from: args) else {
                printCLIError("Usage: cider-cli board milestone attach-card <board> --milestone <id|display-key|title> --card <id|display-key> [--json]")
                return
            }
            guard let board = findBoard(boardRef, in: storage) else { return }
            guard let milestone = resolveMilestone(milestoneRef, in: board) else { return }
            guard var card = board.card(matching: cardRef) else {
                printCLIError("Card '\(cardRef)' not found in board '\(board.name)'")
                return
            }
            guard card.id != milestone.id else {
                printCLIError("A milestone cannot be attached to itself.")
                return
            }
            guard board.canAssignParent(cardID: card.id, parentCardID: milestone.id) else {
                printCLIError("Cannot attach card '\(card.id)' to milestone '\(milestone.id)'. The milestone must be in the same board and cannot create a cycle.")
                return
            }
            let previousParentID = card.parentCardID
            card.parentCardID = milestone.id
            let text: String
            if let previousParentID, previousParentID != milestone.id {
                text = "Moved from parent/milestone \(previousParentID) to milestone \(milestone.title) [\(milestone.id)]."
            } else if previousParentID == milestone.id {
                text = "Confirmed card is attached to milestone \(milestone.title) [\(milestone.id)]."
            } else {
                text = "Attached to milestone \(milestone.title) [\(milestone.id)]."
            }
            card.notes = KanbanCardSectionParser.appendingHistory(
                to: card.notes,
                type: "decision",
                text: text,
                source: parseFlag("--source", from: args) ?? "cider-cli milestone"
            )
            card.markActivity("milestone_attached")
            storage.updateCard(boardID: board.id, card: card)
            refreshSecondBrainProjection(boardID: board.id, card: card)
            let refreshedBoard = findBoard(board.id, in: storage) ?? board
            let refreshedMilestone = refreshedBoard.card(matching: milestone.id) ?? milestone
            let children = refreshedBoard.childCards(of: refreshedMilestone.id)
            if jsonOutput {
                outputJSON([
                    "ok": true,
                    "action": "attached",
                    "board": ["id": refreshedBoard.id, "name": refreshedBoard.name],
                    "milestone": milestoneToDict(board: refreshedBoard, milestone: refreshedMilestone),
                    "card": milestoneAttachedCardToDict(card),
                    "children": children.map(minimalCardToDict),
                ])
            } else {
                print("Attached '\(card.title)' to milestone '\(refreshedMilestone.title)'")
            }

        default:
            printCLIError("Unknown board milestone command: \(subcommand ?? "nil"). Commands: create, list, inspect, attach-card")
        }
    }

    static func normalizedMilestoneTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.localizedCaseInsensitiveContains("milestone:") else { return trimmed }
        return "Milestone: \(trimmed)"
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    static func defaultMilestoneColumn(in board: KanbanBoard) -> KanbanColumn? {
        board.columns.first { $0.name.localizedCaseInsensitiveCompare("Backlog") == .orderedSame }
            ?? board.columns.first { !$0.isDoneColumn }
            ?? board.columns.first
    }

    static func boardMilestoneCards(in board: KanbanBoard) -> [KanbanCard] {
        board.allCards.filter(isMilestoneCard)
    }

    static func isMilestoneCard(_ card: KanbanCard) -> Bool {
        card.tags.contains { $0.localizedCaseInsensitiveCompare("milestone-object") == .orderedSame }
            || card.title.localizedCaseInsensitiveContains("milestone:")
    }

    static func resolveMilestone(_ ref: String, in board: KanbanBoard) -> KanbanCard? {
        let milestones = boardMilestoneCards(in: board)
        if let milestone = milestones.first(where: {
            $0.id == ref
                || board.displayKey(for: $0).localizedCaseInsensitiveCompare(ref) == .orderedSame
                || $0.title.localizedCaseInsensitiveCompare(ref) == .orderedSame
        }) {
            return milestone
        }
        printCLIError("Milestone '\(ref)' not found in board '\(board.name)'")
        return nil
    }

    static func printMilestoneResult(
        boardID: String,
        boardName: String,
        milestone: KanbanCard,
        children: [KanbanCard],
        action: String
    ) {
        if jsonOutput {
            outputJSON([
                "ok": true,
                "action": action,
                "board": ["id": boardID, "name": boardName],
                "milestone": milestoneToDict(boardID: boardID, milestone: milestone, children: children),
                "children": children.map(minimalCardToDict),
            ])
        } else {
            print("\(action.capitalized) milestone: \(milestone.title) [\(milestone.id)] — \(children.count) card(s)")
        }
    }

    static func milestoneToDict(board: KanbanBoard, milestone: KanbanCard) -> [String: Any] {
        var dict = milestoneToDict(boardID: board.id, milestone: milestone, children: board.childCards(of: milestone.id))
        let doneCount = board.columns.reduce(0) { count, column in
            let children = column.cards.filter { $0.parentCardID == milestone.id }
            return count + (column.isDoneLikeColumn ? children.count : children.filter { $0.completed != nil }.count)
        }
        let childCount = board.childCards(of: milestone.id).count
        dict["childCount"] = childCount
        dict["completedChildCount"] = doneCount
        dict["progressFraction"] = childCount == 0 ? 0 : Double(doneCount) / Double(childCount)
        return dict
    }

    static func milestoneToDict(boardID: String, milestone: KanbanCard, children: [KanbanCard]) -> [String: Any] {
        let doneCount = children.filter { $0.completed != nil }.count
        var dict: [String: Any] = [
            "id": milestone.id,
            "boardID": boardID,
            "title": milestone.title,
            "tags": milestone.tags,
            "childCount": children.count,
            "completedChildCount": doneCount,
            "progressFraction": children.isEmpty ? 0 : Double(doneCount) / Double(children.count),
            "created": ISO8601DateFormatter().string(from: milestone.created),
        ]
        if let displayKey = milestone.displayKey { dict["displayKey"] = displayKey }
        if let color = milestone.color { dict["color"] = color.rawValue }
        if let notes = milestone.notes { dict["notes"] = notes }
        if let updatedAt = milestone.updatedAt { dict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt) }
        dict["artifactLinks"] = milestoneArtifactLinks(boardID: boardID, milestoneID: milestone.id)
        return dict
    }

    static func milestoneArtifactLinks(boardID: String, milestoneID: String) -> [[String: Any]] {
        let owner = SecondBrainKanbanProjectionService.owner(boardID: boardID, cardID: milestoneID)
        let relations = (try? SecondBrainStore(database: .shared).relatedRelations(for: owner)) ?? []
        let notesByID = Dictionary(uniqueKeysWithValues: NotesStorage.shared.notes.map { ($0.id.uuidString, $0) })
        let allowedArtifactTypes: Set<String> = ["plan", "qa", "audit", "decision", "handoff", "note"]
        return relations.compactMap { relation -> [String: Any]? in
            guard relation.sourceOwner.ownerType == "note" || relation.targetOwner.ownerType == "note" else { return nil }
            guard relation.sourceOwner == owner || relation.targetOwner == owner else { return nil }
            let noteOwner = relation.sourceOwner.ownerType == "note" ? relation.sourceOwner : relation.targetOwner
            let note = notesByID[noteOwner.ownerID]
            let artifactType = (relation.metadata["artifactType"] ?? note?.artifactType ?? "note").localizedLowercase
            guard allowedArtifactTypes.contains(artifactType) else { return nil }
            let title = relation.metadata["title"] ?? note?.title ?? noteOwner.ownerID
            var dict: [String: Any] = [
                "owner": ownerToDict(noteOwner),
                "title": title,
                "artifactType": artifactType,
                "displayType": projectArtifactDisplayType(artifactType),
                "relationType": relation.relationType,
                "relationLabel": ProjectArtifactRelationType.displayName(for: relation.relationType),
            ]
            if let path = relation.metadata["path"] ?? note?.relativePath {
                dict["path"] = path
            }
            return dict
        }
    }

    static func projectArtifactDisplayType(_ artifactType: String) -> String {
        switch artifactType.localizedLowercase {
        case "qa", "audit":
            return "QA"
        case "plan":
            return "Plan"
        case "decision":
            return "Decision"
        case "handoff":
            return "Handoff"
        default:
            return "Note"
        }
    }

    static func milestoneAttachedCardToDict(_ card: KanbanCard) -> [String: Any] {
        var dict = minimalCardToDict(card)
        if let parentCardID = card.parentCardID { dict["parentCardID"] = parentCardID }
        if let notes = card.notes { dict["notes"] = notes }
        return dict
    }

    static func refreshSecondBrainProjection(boardID: String, card: KanbanCard) {
        guard CiderDatabase.shared.isOpen else { return }
        do {
            try SecondBrainKanbanProjectionService().refreshCard(boardID: boardID, card: card)
        } catch {
            FileHandle.standardError.write(Data("Warning: failed to refresh item graph projection for card \(card.id): \(error.localizedDescription)\n".utf8))
        }
    }

    static func printBoardCardSectionResult(board: KanbanBoard, card: KanbanCard) {
        if jsonOutput {
            outputJSON(boardCardInspectToDict(board: board, column: board.columns.first { $0.cards.contains { $0.id == card.id } }, card: card))
        } else {
            print("Updated card sections: \(card.title) [\(card.id)]")
        }
    }

    struct BoardRecentCard {
        let board: KanbanBoard
        let column: KanbanColumn
        let card: KanbanCard
        let parent: KanbanCard?
        let activityAt: Date
        let activityKind: String
        let traversalOrder: Int
    }

    struct BoardTestingSummaryEntry {
        let board: KanbanBoard
        let column: KanbanColumn
        let card: KanbanCard
        let parent: KanbanCard?
        let reason: String
        let activityAt: Date
        let traversalOrder: Int
    }

    struct BoardTestingSummary {
        let needsErik: [BoardTestingSummaryEntry]
        let agentCanVerify: [BoardTestingSummaryEntry]
    }

    static func recentKanbanCards(in board: KanbanBoard, limit: Int) -> [BoardRecentCard] {
        var entries: [BoardRecentCard] = []
        var traversalOrder = 0
        for column in board.columns {
            for card in column.cards {
                traversalOrder += 1
                let activityAt = card.updatedAt ?? card.completed ?? card.created
                let activityKind = card.lastActivityKind ?? (card.completed == nil ? "created" : "completed")
                entries.append(BoardRecentCard(
                    board: board,
                    column: column,
                    card: card,
                    parent: board.parentCard(for: card.id),
                    activityAt: activityAt,
                    activityKind: activityKind,
                    traversalOrder: traversalOrder
                ))
            }
        }

        return Array(entries.sorted { lhs, rhs in
            if lhs.activityAt != rhs.activityAt {
                return lhs.activityAt > rhs.activityAt
            }
            return lhs.traversalOrder > rhs.traversalOrder
        }.prefix(limit))
    }

    static func testingQueueSummary(in board: KanbanBoard) -> BoardTestingSummary {
        var needsErik: [BoardTestingSummaryEntry] = []
        var agentCanVerify: [BoardTestingSummaryEntry] = []
        var traversalOrder = 0

        for column in board.columns where isTestingQueueColumn(column) {
            for card in column.cards where card.completed == nil {
                traversalOrder += 1
                let entry = BoardTestingSummaryEntry(
                    board: board,
                    column: column,
                    card: card,
                    parent: board.parentCard(for: card.id),
                    reason: testingQueueOwnerReason(for: card),
                    activityAt: card.updatedAt ?? card.created,
                    traversalOrder: traversalOrder
                )
                if entry.reason == "manual" {
                    needsErik.append(entry)
                } else {
                    agentCanVerify.append(entry)
                }
            }
        }

        return BoardTestingSummary(
            needsErik: sortTestingQueueEntries(needsErik),
            agentCanVerify: sortTestingQueueEntries(agentCanVerify)
        )
    }

    static func isTestingQueueColumn(_ column: KanbanColumn) -> Bool {
        let normalized = column.name.lowercased()
        return normalized == "testing"
            || normalized == "ready to test"
            || normalized.contains("testing")
            || normalized.contains("ready to test")
    }

    static func testingQueueOwnerReason(for card: KanbanCard) -> String {
        let model = KanbanCardDashboardModel(title: card.title, notes: card.notes)
        if !failedQASteps(in: card.notes).isEmpty {
            return "agent"
        }
        let haystack = [
            card.title,
            card.notes ?? "",
            model.currentState ?? "",
            model.nextStep ?? "",
            model.fallbackSummary,
        ].joined(separator: "\n").lowercased()
        let manualSignals = [
            "manual qa",
            "manual test",
            "manual testing",
            "needs erik",
            "erik should",
            "user test",
            "user should",
            "visual",
            "ui",
            "open the app",
            "approval",
            "approve",
        ]
        return manualSignals.contains { haystack.contains($0) } ? "manual" : "agent"
    }

    static func failedQASteps(in notes: String?) -> [String] {
        KanbanCardSectionParser.sections(from: notes)
            .filter { ["qa_results", "qa_findings", "testing_results", "manual_qa_results"].contains($0.key) }
            .flatMap { section in
                section.body.components(separatedBy: .newlines).compactMap { rawLine -> String? in
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
                    guard isFailedQAResultLine(stripped) else { return nil }
                    return stripped.isEmpty ? nil : stripped
                }
            }
    }

    static func isFailedQAResultLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            .lowercased()
        if normalized == "failed steps:" || normalized == "failed steps" {
            return false
        }
        if normalized.range(of: #"^step\s+\d+\s+failed:"#, options: .regularExpression) != nil {
            return true
        }
        return normalized.hasPrefix("failed:") || normalized.hasPrefix("failed ")
    }

    static func sortTestingQueueEntries(_ entries: [BoardTestingSummaryEntry]) -> [BoardTestingSummaryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.activityAt != rhs.activityAt {
                return lhs.activityAt > rhs.activityAt
            }
            return lhs.traversalOrder > rhs.traversalOrder
        }
    }

    static func boardRecentCardToDict(_ entry: BoardRecentCard) -> [String: Any] {
        let model = KanbanCardDashboardModel(title: entry.card.title, notes: entry.card.notes)
        var dict: [String: Any] = [
            "id": entry.card.id,
            "title": entry.card.title,
            "board": ["id": entry.board.id, "name": entry.board.name],
            "column": ["id": entry.column.id, "name": entry.column.name, "isDoneColumn": entry.column.isDoneColumn, "isDoneLikeColumn": entry.column.isDoneLikeColumn],
            "created": ISO8601DateFormatter().string(from: entry.card.created),
            "activityAt": ISO8601DateFormatter().string(from: entry.activityAt),
            "activityKind": entry.activityKind,
            "tags": entry.card.tags,
            "summary": model.currentState ?? model.nextStep ?? model.fallbackSummary,
        ]
        if let completed = entry.card.completed {
            dict["completed"] = ISO8601DateFormatter().string(from: completed)
        }
        if let updatedAt = entry.card.updatedAt {
            dict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt)
        }
        if let priority = entry.card.priority {
            dict["priority"] = priority.rawValue
        }
        if let agent = entry.card.agent {
            dict["agent"] = agent
        }
        if let color = entry.card.color {
            dict["color"] = color.rawValue
        }
        if let parentCardID = entry.card.parentCardID {
            dict["parentCardID"] = parentCardID
        }
        if let currentState = model.currentState {
            dict["currentState"] = currentState
        }
        if let nextStep = model.nextStep {
            dict["nextStep"] = nextStep
        }
        let failedSteps = failedQASteps(in: entry.card.notes)
        if !failedSteps.isEmpty {
            dict["failedQASteps"] = failedSteps
        }
        if let parent = entry.parent {
            dict["parent"] = minimalCardToDict(parent)
        }
        return dict
    }

    static func boardAuditReport(
        boards: [KanbanBoard],
        loadIssues: [KanbanBoardLoadIssue] = []
    ) -> [String: Any] {
        var issues: [[String: Any]] = []
        var warnings: [[String: Any]] = []
        var columnCount = 0
        var cardCount = 0

        for loadIssue in loadIssues {
            issues.append([
                "type": "board_yaml_decode_failed",
                "severity": "error",
                "boardID": loadIssue.boardID,
                "fileName": loadIssue.fileName,
                "message": loadIssue.message,
            ])
        }

        for board in boards {
            columnCount += board.columns.count
            var cardLocations: [String: [(column: KanbanColumn, card: KanbanCard)]] = [:]
            var parentByCardID: [String: String] = [:]

            for column in board.columns {
                let archiveLike = [column.id, column.name]
                    .contains { $0.localizedCaseInsensitiveContains("archive") }
                if archiveLike && !column.isHiddenColumn {
                    warnings.append(boardAuditFinding(
                        type: "archive_column_not_hidden",
                        severity: "warning",
                        board: board,
                        column: column,
                        card: nil,
                        message: "Archive-like column '\(column.name)' is not explicitly marked hidden; layout compatibility may still hide it."
                    ))
                }

                for card in column.cards {
                    cardCount += 1
                    cardLocations[card.id, default: []].append((column, card))
                    if let parentCardID = card.parentCardID,
                       !parentCardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parentByCardID[card.id] = parentCardID
                    }
                }
            }

            for (cardID, locations) in cardLocations where locations.count > 1 {
                issues.append(boardAuditFinding(
                    type: "duplicate_card_id",
                    severity: "error",
                    board: board,
                    column: locations[0].column,
                    card: locations[0].card,
                    message: "Card id '\(cardID)' appears in \(locations.count) columns on board '\(board.name)'."
                ))
            }

            for (cardID, parentCardID) in parentByCardID {
                guard let location = cardLocations[cardID]?.first else { continue }
                if cardID == parentCardID {
                    issues.append(boardAuditFinding(
                        type: "self_parent",
                        severity: "error",
                        board: board,
                        column: location.column,
                        card: location.card,
                        parentCardID: parentCardID,
                        message: "Card '\(location.card.title)' points to itself as parent."
                    ))
                } else if cardLocations[parentCardID] == nil {
                    issues.append(boardAuditFinding(
                        type: "missing_parent",
                        severity: "error",
                        board: board,
                        column: location.column,
                        card: location.card,
                        parentCardID: parentCardID,
                        message: "Card '\(location.card.title)' references missing parent '\(parentCardID)' on board '\(board.name)'."
                    ))
                }
            }

            for cardID in parentByCardID.keys {
                var seen: Set<String> = []
                var cursor: String? = cardID
                while let current = cursor, let nextParent = parentByCardID[current] {
                    if seen.contains(current) {
                        if let location = cardLocations[cardID]?.first {
                            issues.append(boardAuditFinding(
                                type: "parent_cycle",
                                severity: "error",
                                board: board,
                                column: location.column,
                                card: location.card,
                                message: "Card '\(location.card.title)' participates in a parent cycle on board '\(board.name)'."
                            ))
                        }
                        break
                    }
                    seen.insert(current)
                    cursor = nextParent
                }
            }
        }

        return [
            "ok": issues.isEmpty,
            "boardCount": boards.count,
            "columnCount": columnCount,
            "cardCount": cardCount,
            "issueCount": issues.count,
            "warningCount": warnings.count,
            "issues": issues,
            "warnings": warnings,
        ]
    }

    static func boardAuditFinding(
        type: String,
        severity: String,
        board: KanbanBoard,
        column: KanbanColumn?,
        card: KanbanCard?,
        parentCardID: String? = nil,
        message: String
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "severity": severity,
            "boardID": board.id,
            "boardName": board.name,
            "message": message,
        ]
        if let column {
            dict["columnID"] = column.id
            dict["columnName"] = column.name
        }
        if let card {
            dict["cardID"] = card.id
            dict["cardTitle"] = card.title
            dict["created"] = ISO8601DateFormatter().string(from: card.created)
        }
        if let parentCardID {
            dict["parentCardID"] = parentCardID
        }
        return dict
    }

    static func boardTestingSummaryToDict(board: KanbanBoard, summary: BoardTestingSummary) -> [String: Any] {
        [
            "ok": true,
            "board": ["id": board.id, "name": board.name],
            "counts": [
                "total": summary.needsErik.count + summary.agentCanVerify.count,
                "needsErik": summary.needsErik.count,
                "agentCanVerify": summary.agentCanVerify.count,
            ],
            "needsErik": summary.needsErik.map(boardTestingSummaryEntryToDict),
            "agentCanVerify": summary.agentCanVerify.map(boardTestingSummaryEntryToDict),
        ]
    }

    static func boardTestingSummaryEntryToDict(_ entry: BoardTestingSummaryEntry) -> [String: Any] {
        let model = KanbanCardDashboardModel(title: entry.card.title, notes: entry.card.notes)
        var dict: [String: Any] = [
            "id": entry.card.id,
            "title": entry.card.title,
            "board": ["id": entry.board.id, "name": entry.board.name],
            "column": ["id": entry.column.id, "name": entry.column.name, "isDoneColumn": entry.column.isDoneColumn, "isDoneLikeColumn": entry.column.isDoneLikeColumn],
            "created": ISO8601DateFormatter().string(from: entry.card.created),
            "activityAt": ISO8601DateFormatter().string(from: entry.activityAt),
            "reason": entry.reason,
            "summary": model.currentState ?? model.nextStep ?? model.fallbackSummary,
        ]
        if let priority = entry.card.priority {
            dict["priority"] = priority.rawValue
        }
        if let agent = entry.card.agent {
            dict["agent"] = agent
        }
        if let parentCardID = entry.card.parentCardID {
            dict["parentCardID"] = parentCardID
        }
        if let currentState = model.currentState {
            dict["currentState"] = currentState
        }
        if let nextStep = model.nextStep {
            dict["nextStep"] = nextStep
        }
        let failedSteps = failedQASteps(in: entry.card.notes)
        if !failedSteps.isEmpty {
            dict["failedQASteps"] = failedSteps
        }
        if let parent = entry.parent {
            dict["parent"] = minimalCardToDict(parent)
        }
        return dict
    }

    static func boardCardInspectToDict(board: KanbanBoard, column: KanbanColumn?, card: KanbanCard) -> [String: Any] {
        let owner = SecondBrainKanbanProjectionService.owner(boardID: board.id, cardID: card.id)
        let model = KanbanCardDashboardModel(title: card.title, notes: card.notes)
        let store = SecondBrainStore(database: .shared)
        try? SecondBrainKanbanProjectionService(store: store).refreshCard(boardID: board.id, card: card)
        let projectedSections = (try? store.sections(for: owner)) ?? []
        let routes = (try? store.routingDecisions(for: owner)) ?? []
        let actions = (try? store.agentActions(for: owner)) ?? []
        let relations = (try? store.outgoingRelations(for: owner)) ?? []
        let backlinks = (try? store.backlinks(for: owner)) ?? []

        var cardDict: [String: Any] = [
            "id": card.id,
            "displayKey": board.displayKey(for: card),
            "title": card.title,
            "notes": card.notes ?? "",
            "created": ISO8601DateFormatter().string(from: card.created),
            "tags": card.tags,
            "linkedEntities": card.linkedEntities.map(libraryEntityRefToDict),
            "relatedCardIDs": card.relatedCardIDs,
        ]
        if let priority = card.priority { cardDict["priority"] = priority.rawValue }
        if let agent = card.agent { cardDict["agent"] = agent }
        if let color = card.color { cardDict["color"] = color.rawValue }
        if let parentCardID = card.parentCardID { cardDict["parentCardID"] = parentCardID }
        if let completed = card.completed { cardDict["completed"] = ISO8601DateFormatter().string(from: completed) }
        if let updatedAt = card.updatedAt { cardDict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt) }
        if let lastActivityKind = card.lastActivityKind { cardDict["lastActivityKind"] = lastActivityKind }
        appendKanbanCommentFields(card, to: &cardDict)

        let parent = board.parentCard(for: card.id)
        var dict: [String: Any] = [
            "ok": true,
            "board": ["id": board.id, "name": board.name, "displayKeyPrefix": board.displayKeyPrefix],
            "card": cardDict,
            "owner": ownerToDict(owner),
            "dashboard": dashboardModelToDict(model, board: board.id, cardID: card.id),
            "sections": model.sections.map(kanbanSectionToDict),
            "projectedSections": projectedSections.map(secondBrainSectionToDict),
            "children": board.childCards(of: card.id).map(minimalCardToDict),
            "relatedCards": board.relatedCards(for: card.id).map(minimalCardToDict),
            "linkedEntities": card.linkedEntities.map(libraryEntityRefToDict),
            "ownerRelations": relations.map(ownerRelationToDict),
            "backlinks": backlinks.map(ownerRelationToDict),
            "routingDecisions": routes.map(routingDecisionToDict),
            "agentActions": actions.map(agentActionToDict),
        ]
        if let column {
            dict["column"] = ["id": column.id, "name": column.name, "isDoneColumn": column.isDoneColumn, "isDoneLikeColumn": column.isDoneLikeColumn]
        }
        dict["hasFailedQA"] = model.hasFailedQA
        let failedSteps = failedQASteps(in: card.notes)
        if !failedSteps.isEmpty {
            dict["failedQASteps"] = failedSteps
        }
        if let parent {
            dict["parent"] = minimalCardToDict(parent)
        }
        if let rollup = KanbanParentChildRollup(board: board, parentID: card.id) {
            dict["childRollup"] = parentChildRollupToDict(rollup)
        }
        if let nextUp = KanbanRoadmapNextUpProjection(board: board, parentID: card.id) {
            dict["roadmapNextUp"] = roadmapNextUpToDict(nextUp)
        }
        return dict
    }

    static func printCLIError(_ message: String) {
        printCLIError(message, details: nil)
    }

    static func printCLIError(_ message: String, details: [String: Any]?) {
        processExitCode = 1
        if jsonOutput {
            var dict: [String: Any] = ["ok": false, "error": message]
            if let details {
                dict["details"] = details
            }
            outputJSON(dict)
        } else {
            print("Error: \(message)")
        }
    }

    static func normalizedOwner(type rawType: String, ref rawRef: String) -> SecondBrainOwnerRef {
        let normalizedType = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        if normalizedType == "kanban" || normalizedType == "kanban_card" || normalizedType == "card" {
            if rawRef.contains("/") {
                return SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: rawRef)
            }
            if let detail = KanbanStorage.shared.findCard(id: rawRef) {
                return SecondBrainKanbanProjectionService.owner(boardID: detail.board.id, cardID: detail.card.id)
            }
            return SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: rawRef)
        }

        if let entityType = try? ItemLinkService.entityType(from: rawType),
           let ref = try? ItemLinkService.shared.resolve(type: entityType, ref: rawRef) {
            return SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
        }

        return SecondBrainOwnerRef(ownerType: normalizedType, ownerID: rawRef)
    }

    static func itemApplySpaceIntentPayload(
        type rawType: String,
        ref rawRef: String,
        actor: String,
        source: String
    ) throws -> [String: Any] {
        let entityType = try ItemLinkService.entityType(from: rawType)
        guard entityType == .bookmark else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Staged Space intent approval currently supports bookmark items only."]
            )
        }
        let resolved = try ItemLinkService.shared.resolve(type: entityType, ref: rawRef)
        guard let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == resolved.entityID }) else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No bookmark found matching '\(rawRef)'."]
            )
        }
        let stagedSpaceIntent = CiderCaptureIntentStagingService
            .stagedIntents(for: bookmark)
            .first { $0.isSpaceIntent }
        guard let stagedSpaceIntent else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No staged Space intent is available for this item."]
            )
        }
        guard case let .space(spaceName, area) = stagedSpaceIntent.kind else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No staged Space intent is available for this item."]
            )
        }

        let existingSpace = resolveSpaceTarget(targetID: nil, targetPath: spaceName)
        let finalSpaceID = existingSpace?.id ?? normalizedIntentSpaceID(spaceName)
        let finalSpaceName = existingSpace?.name ?? spaceName
        let areaClause = area.map { " / \($0)" } ?? ""
        let reason = "\(stagedSpaceIntent.reason) Approved staged capture intent for \(finalSpaceName)\(areaClause)."
        let explanation = try CiderRoutingDecisionService().recordSpaceAssignment(
            itemID: resolved.entityID,
            spaceID: finalSpaceID,
            spaceName: finalSpaceName,
            reason: reason,
            confidence: stagedSpaceIntent.confidence,
            actor: actor,
            source: source
        )

        let owner = SecondBrainOwnerRef(ownerType: resolved.type.rawValue, ownerID: resolved.entityID.uuidString)
        try SecondBrainStore(database: .shared).recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: resolved.entityID.uuidString,
                toolName: "item.apply-intent",
                actionType: "apply.space_intent",
                source: source,
                status: "succeeded",
                summary: reason
            )
        )

        let storageDestination = bookmark.relativePath?.hasPrefix("Inbox/") == true
            ? bookmark.relativePath?.components(separatedBy: "/").prefix(2).joined(separator: "/")
            : bookmark.relativePath
        var approvedIntent = stagedSpaceIntent.toDictionary(storageDestination: storageDestination)
        approvedIntent["spaceID"] = finalSpaceID
        approvedIntent["spaceName"] = finalSpaceName
        if let area { approvedIntent["area"] = area }
        var item: [String: Any] = [
            "id": resolved.entityID.uuidString,
            "type": resolved.type.rawValue,
            "title": bookmark.title,
        ]
        if let relativePath = bookmark.relativePath {
            item["relativePath"] = relativePath
        }

        return [
            "ok": true,
            "command": "item.apply-intent",
            "changed": true,
            "intent": "space",
            "item": item,
            "approvedIntent": approvedIntent,
            "routing": explanation.toDictionary(),
            "safeNextCommands": [
                "cider-cli item context \(resolved.type.rawValue) \(resolved.entityID.uuidString) --json",
                "cider-cli item get \(resolved.type.rawValue) \(resolved.entityID.uuidString) --json",
            ],
        ]
    }

    static func itemApplyProjectIntentPayload(
        type rawType: String,
        ref rawRef: String,
        actor: String,
        source: String
    ) throws -> [String: Any] {
        let entityType = try ItemLinkService.entityType(from: rawType)
        guard entityType == .bookmark else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Staged project intent approval currently supports bookmark items only."]
            )
        }
        let resolved = try ItemLinkService.shared.resolve(type: entityType, ref: rawRef)
        guard let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == resolved.entityID }) else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No bookmark found matching '\(rawRef)'."]
            )
        }
        let stagedProjectIntent = CiderCaptureIntentStagingService
            .stagedIntents(for: bookmark)
            .first { $0.isProjectIntent }
        guard let stagedProjectIntent,
              case let .project(projectName) = stagedProjectIntent.kind else {
            throw NSError(
                domain: "CiderCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No staged project intent is available for this item."]
            )
        }

        let projectService = SecondBrainProjectGraphService(database: .shared)
        let project = try projectService.upsertProject(
            id: projectName,
            title: projectName,
            metadata: ["intentSource": stagedProjectIntent.source]
        )
        let owner = SecondBrainOwnerRef(ownerType: resolved.type.rawValue, ownerID: resolved.entityID.uuidString)
        let reason = "\(stagedProjectIntent.reason) Approved staged capture intent for project \(project.title)."
        let relation = SecondBrainRelation(
            sourceOwner: owner,
            targetOwner: project.owner,
            relationType: "artifact_of",
            evidence: reason,
            source: source,
            actor: actor,
            confidence: stagedProjectIntent.confidence,
            metadata: ["intent": "project", "projectName": projectName]
        )
        let store = SecondBrainStore(database: .shared)
        try store.recordRelation(relation)
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: resolved.entityID.uuidString,
                toolName: "item.apply-intent",
                actionType: "apply.project_intent",
                source: source,
                status: "succeeded",
                summary: reason
            )
        )

        let storageDestination = bookmark.relativePath?.hasPrefix("Inbox/") == true
            ? bookmark.relativePath?.components(separatedBy: "/").prefix(2).joined(separator: "/")
            : bookmark.relativePath
        var approvedIntent = stagedProjectIntent.toDictionary(storageDestination: storageDestination)
        approvedIntent["projectID"] = project.id
        approvedIntent["projectName"] = project.title
        var item: [String: Any] = [
            "id": resolved.entityID.uuidString,
            "type": resolved.type.rawValue,
            "title": bookmark.title,
        ]
        if let relativePath = bookmark.relativePath {
            item["relativePath"] = relativePath
        }

        return [
            "ok": true,
            "command": "item.apply-intent",
            "changed": true,
            "intent": "project",
            "item": item,
            "approvedIntent": approvedIntent,
            "project": projectToDict(project),
            "relation": ownerRelationToDict(relation),
            "safeNextCommands": [
                "cider-cli item project-context \(project.id) --json",
                "cider-cli item context \(resolved.type.rawValue) \(resolved.entityID.uuidString) --json",
                "cider-cli item get \(resolved.type.rawValue) \(resolved.entityID.uuidString) --json",
            ],
        ]
    }

    static func normalizedIntentSpaceID(_ name: String) -> String {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return normalized.isEmpty ? "space" : normalized
    }

    static func projectWorkspace(ref: String, catalog: ProjectWorkspaceCatalog) -> ProjectWorkspace? {
        catalog.workspace(id: SecondBrainProjectGraphService.normalizedProjectID(ref))
            ?? catalog.activeProjects.first { $0.title.localizedCaseInsensitiveCompare(ref) == .orderedSame }
    }

    static let itemGetLegacyOwnerDeprecationMessage = "item get with non-library owner refs is deprecated; use cider-cli item owner-get <owner-type> <owner-id-or-ref> --json for legacy owner-section inspection."

    enum FolderOwnerResolution {
        case inbox
        case folder(VaultFolder)
        case ambiguous([VaultFolder])
        case missing
    }

    static func itemOpenPayload(
        type rawType: String,
        ref rawRef: String,
        store: SecondBrainStore
    ) throws -> (payload: [String: Any], notificationUserInfo: [String: String]) {
        let requestID = UUID().uuidString
        let requestedAt = ISO8601DateFormatter().string(from: Date())
        let normalizedType = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
            .replacingOccurrences(of: "-", with: "_")

        let target: [String: String]
        if isKanbanCardItemType(rawType) {
            let detail = try resolveKanbanCardDetail(ref: rawRef)
            try? SecondBrainKanbanProjectionService(store: store).refreshCard(boardID: detail.board.id, card: detail.card)
            target = [
                "type": "card",
                "id": detail.card.id,
                "title": detail.card.title,
                "boardID": detail.board.id,
                "boardName": detail.board.name,
            ]
        } else if normalizedType == "board" || normalizedType == "boards" || normalizedType == "kanban_board" {
            guard let board = KanbanStorage.shared.boards.first(where: {
                $0.id == rawRef || $0.name.localizedCaseInsensitiveCompare(rawRef) == .orderedSame
            }) else {
                throw NSError(
                    domain: "CiderCLI",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No board found matching '\(rawRef)'."]
                )
            }
            target = [
                "type": "board",
                "id": board.id,
                "title": board.name,
                "boardID": board.id,
                "boardName": board.name,
            ]
        } else {
            let entityType = try ItemLinkService.entityType(from: rawType)
            let resolved = try ItemLinkService.shared.resolve(type: entityType, ref: rawRef)
            let summary = ItemLinkService.shared.summary(for: resolved)
            target = [
                "type": resolved.type.rawValue,
                "id": resolved.entityID.uuidString,
                "title": summary?.title ?? resolved.entityID.uuidString,
            ]
        }

        var notificationUserInfo = target.reduce(into: [
            CiderExternalOpenBridge.Key.requestID: requestID,
            CiderExternalOpenBridge.Key.targetType: target["type"] ?? rawType,
            CiderExternalOpenBridge.Key.targetID: target["id"] ?? rawRef,
            CiderExternalOpenBridge.Key.sourceType: rawType,
            CiderExternalOpenBridge.Key.sourceRef: rawRef,
            CiderExternalOpenBridge.Key.requestedAt: requestedAt,
        ]) { partial, pair in
            switch pair.key {
            case "type":
                partial[CiderExternalOpenBridge.Key.targetType] = pair.value
            case "id":
                partial[CiderExternalOpenBridge.Key.targetID] = pair.value
            case "title":
                partial[CiderExternalOpenBridge.Key.title] = pair.value
            case "boardID":
                partial[CiderExternalOpenBridge.Key.boardID] = pair.value
            case "boardName":
                partial[CiderExternalOpenBridge.Key.boardName] = pair.value
            default:
                break
            }
        }

        if notificationUserInfo[CiderExternalOpenBridge.Key.title] == nil {
            notificationUserInfo[CiderExternalOpenBridge.Key.title] = target["id"] ?? rawRef
        }

        var targetDict: [String: Any] = [
            "type": target["type"] ?? rawType,
            "id": target["id"] ?? rawRef,
            "title": target["title"] ?? "",
        ]
        if let boardID = target["boardID"] { targetDict["boardID"] = boardID }
        if let boardName = target["boardName"] { targetDict["boardName"] = boardName }

        return ([
            "ok": true,
            "command": "item.open",
            "readOnly": true,
            "changed": false,
            "notificationName": CiderExternalOpenBridge.notificationName.rawValue,
            "requestID": requestID,
            "requestedAt": requestedAt,
            "target": targetDict,
            "sourceRef": [
                "type": rawType,
                "ref": rawRef,
            ],
            "safeNextCommands": [
                "cider-cli item get \(targetDict["type"] ?? rawType) \(targetDict["id"] ?? rawRef) --json",
            ],
            "message": "Posted a request for the running Cider app to open the resolved target. This confirms notification delivery was attempted, not that a human saw the item.",
        ] as [String: Any], notificationUserInfo)
    }

    static func ownerInspectionPayload(
        type rawType: String,
        ref rawRef: String,
        store: SecondBrainStore,
        command: String,
        deprecated: Bool
    ) throws -> (
        owner: SecondBrainOwnerRef,
        sections: [SecondBrainSection],
        routes: [SecondBrainRoutingDecision],
        actions: [SecondBrainAgentAction],
        dict: [String: Any]
    ) {
        let owner = normalizedOwner(type: rawType, ref: rawRef)
        let ownerResolved = ownerExists(type: rawType, ref: rawRef, owner: owner)
        let sections = try store.sections(for: owner)
        let routes = try store.routingDecisions(for: owner)
        let actions = try store.agentActions(for: owner)
        let relations = try store.outgoingRelations(for: owner)
        let backlinks = try store.backlinks(for: owner)
        var dict: [String: Any] = [
            "ok": true,
            "command": command,
            "exists": ownerResolved,
            "ownerResolved": ownerResolved,
            "legacyOwnerInspection": true,
            "sourceRef": [
                "type": rawType,
                "ref": rawRef,
            ],
            "owner": ownerToDict(owner),
            "sections": sections.map(secondBrainSectionToDict),
            "ownerRelations": relations.map(ownerRelationToDict),
            "backlinks": backlinks.map(ownerRelationToDict),
            "routingDecisions": routes.map(routingDecisionToDict),
            "agentActions": actions.map(agentActionToDict),
        ]
        if deprecated {
            dict["deprecated"] = true
            dict["deprecationMessage"] = itemGetLegacyOwnerDeprecationMessage
        }
        return (owner, sections, routes, actions, dict)
    }

    static func printFolderOwnerInspection(ref rawRef: String) {
        let ref = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        switch resolveFolderOwner(ref: ref) {
        case .folder(let folder):
            let payload = folderOwnerInspectionPayload(folder: folder, sourceRef: ref)
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("\(folder.relativePath) (\(folder.id.uuidString))")
            }
        case .inbox:
            let payload = inboxFolderOwnerInspectionPayload(sourceRef: ref)
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("Inbox")
            }
        case .ambiguous(let matches):
            processExitCode = 1
            let payload: [String: Any] = [
                "ok": false,
                "command": "item.owner-get.folder",
                "readOnly": true,
                "changed": false,
                "error": "Ambiguous folder reference '\(ref)'. Use one of the returned relativePath or id values.",
                "sourceRef": [
                    "type": "folder",
                    "ref": ref,
                ],
                "matches": matches
                    .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                    .map(folderOwnerMatchDict),
                "safeNextCommands": [
                    "cider-cli item owner-get folder <relative-path-or-id> --json",
                    "cider-cli item search <query> --json",
                ],
            ]
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("Error: Ambiguous folder reference '\(ref)'.")
                for match in matches.sorted(by: { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) {
                    print("  \(match.relativePath) (\(match.id.uuidString))")
                }
            }
        case .missing:
            processExitCode = 1
            let payload: [String: Any] = [
                "ok": false,
                "command": "item.owner-get.folder",
                "readOnly": true,
                "changed": false,
                "error": "No folder found matching '\(ref)'.",
                "sourceRef": [
                    "type": "folder",
                    "ref": ref,
                ],
                "matches": [],
                "safeNextCommands": [
                    "cider-cli item search <query> --json",
                    "cider-cli storage audit --json",
                ],
            ]
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("Error: No folder found matching '\(ref)'.")
            }
        }
    }

    static func resolveFolderOwner(ref: String) -> FolderOwnerResolution {
        let service = VaultFolderService.shared
        let normalizedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedRef.isEmpty || normalizedRef.localizedCaseInsensitiveCompare("Inbox") == .orderedSame {
            return .inbox
        }

        if let uuid = UUID(uuidString: normalizedRef),
           let folder = service.folder(for: uuid) {
            return .folder(folder)
        }

        let lowerRef = normalizedRef.lowercased()
        let idPrefixMatches = service.folders.filter { $0.id.uuidString.lowercased().hasPrefix(lowerRef) }
        if idPrefixMatches.count == 1 {
            return .folder(idPrefixMatches[0])
        } else if idPrefixMatches.count > 1 {
            return .ambiguous(idPrefixMatches)
        }

        let pathMatches = service.folders.filter {
            $0.relativePath.localizedCaseInsensitiveCompare(normalizedRef) == .orderedSame
        }
        if pathMatches.count == 1 {
            return .folder(pathMatches[0])
        } else if pathMatches.count > 1 {
            return .ambiguous(pathMatches)
        }

        let nameMatches = service.folders.filter {
            $0.name.localizedCaseInsensitiveCompare(normalizedRef) == .orderedSame
        }
        if nameMatches.count == 1 {
            return .folder(nameMatches[0])
        } else if nameMatches.count > 1 {
            return .ambiguous(nameMatches)
        }
        return .missing
    }

    static func folderRouteResolutionFailurePayload(
        sourceRef: String,
        targetType: String,
        targetPath: String?,
        error: String,
        matches: [VaultFolder]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "ok": false,
            "command": "item.route",
            "readOnly": false,
            "changed": false,
            "targetType": targetType,
            "error": error,
            "sourceRef": [
                "type": "folder",
                "ref": sourceRef,
            ],
            "matches": matches
                .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                .map(folderOwnerMatchDict),
            "safeNextCommands": [
                "cider-cli item owner-get folder \"\(sourceRef)\" --json",
                "cider-cli capture review-queue --json",
            ],
        ]
        if let targetPath {
            payload["targetPath"] = targetPath
        }
        CiderAgentDecisionContract.merge(
            CiderAgentDecisionContract.dictionary(
                saved: false,
                needsReview: true,
                needsRouting: true,
                confidence: 0,
                blockingIssues: ["folder_target_unresolved"],
                recommendedNextAction: "review_route",
                safeNextCommands: payload["safeNextCommands"] as? [String] ?? []
            ),
            into: &payload
        )
        return payload
    }

    static func folderOwnerInspectionPayload(folder: VaultFolder, sourceRef: String) -> [String: Any] {
        let service = VaultFolderService.shared
        let childFolders = service.children(of: folder.id)
        let descendants = service.folders.filter { candidate in
            candidate.relativePath.hasPrefix(folder.relativePath + "/")
        }
        let directCounts = itemCounts { $0 == folder.id }
        let descendantFolderIDs = Set(([folder] + descendants).map(\.id))
        let descendantCounts = itemCounts { folderID in
            guard let folderID else { return false }
            return descendantFolderIDs.contains(folderID)
        }
        let parentID = service.parentID(for: folder)
        let parent = parentID.flatMap { service.folder(for: $0) }
        let existsOnDisk = folderDirectoryExists(folder)
        var folderDict = folderOwnerFolderDict(
            id: folder.id.uuidString,
            name: folder.name,
            relativePath: folder.relativePath,
            parentID: parentID?.uuidString,
            parentRelativePath: parent?.relativePath,
            isRoot: parentID == nil,
            isInbox: false,
            icon: folder.icon,
            iconIsEmoji: folder.iconIsEmoji,
            coverImagePath: folder.coverImagePath,
            coverImageOffsetY: folder.coverImageOffsetY,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt
        )
        folderDict["breadcrumb"] = service.path(to: folder.id).map(folderOwnerMatchDict)

        return [
            "ok": true,
            "command": "item.owner-get.folder",
            "readOnly": true,
            "changed": false,
            "exists": true,
            "ownerResolved": true,
            "sourceRef": [
                "type": "folder",
                "ref": sourceRef,
            ],
            "owner": ownerToDict(SecondBrainOwnerRef(ownerType: "folder", ownerID: folder.id.uuidString)),
            "folder": folderDict,
            "counts": folderOwnerCountsDict(
                directCounts: directCounts,
                descendantCounts: descendantCounts,
                directChildFolderCount: childFolders.count,
                descendantFolderCount: descendants.count
            ),
            "health": [
                "existsInIndex": true,
                "existsInDatabase": true,
                "existsOnDisk": existsOnDisk,
                "isGhost": !existsOnDisk,
                "missingDirectory": !existsOnDisk,
            ],
            "safeNextCommands": folderOwnerSafeNextCommands(
                relativePath: folder.relativePath,
                folderID: folder.id.uuidString
            ),
        ]
    }

    static func inboxFolderOwnerInspectionPayload(sourceRef: String) -> [String: Any] {
        let service = VaultFolderService.shared
        let directCounts = itemCounts { $0 == nil }
        let allFolderIDs = Set(service.folders.map(\.id))
        let descendantCounts = itemCounts { folderID in
            guard let folderID else { return true }
            return allFolderIDs.contains(folderID)
        }
        let inboxURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("Inbox")
        var isDirectory = ObjCBool(false)
        let inboxExistsOnDisk = FileManager.default.fileExists(atPath: inboxURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let now = Date()
        return [
            "ok": true,
            "command": "item.owner-get.folder",
            "readOnly": true,
            "changed": false,
            "exists": true,
            "ownerResolved": true,
            "sourceRef": [
                "type": "folder",
                "ref": sourceRef,
            ],
            "owner": ownerToDict(SecondBrainOwnerRef(ownerType: "folder", ownerID: "Inbox")),
            "folder": folderOwnerFolderDict(
                id: "Inbox",
                name: "Inbox",
                relativePath: "Inbox",
                parentID: nil,
                parentRelativePath: nil,
                isRoot: true,
                isInbox: true,
                icon: "tray",
                iconIsEmoji: false,
                coverImagePath: nil,
                coverImageOffsetY: nil,
                createdAt: now,
                updatedAt: now
            ),
            "counts": folderOwnerCountsDict(
                directCounts: directCounts,
                descendantCounts: descendantCounts,
                directChildFolderCount: service.children(of: nil).count,
                descendantFolderCount: service.folders.count
            ),
            "health": [
                "existsInIndex": true,
                "existsInDatabase": true,
                "existsOnDisk": inboxExistsOnDisk,
                "isGhost": false,
                "missingDirectory": !inboxExistsOnDisk,
            ],
            "safeNextCommands": folderOwnerSafeNextCommands(relativePath: "Inbox", folderID: "Inbox"),
        ]
    }

    static func folderOwnerFolderDict(
        id: String,
        name: String,
        relativePath: String,
        parentID: String?,
        parentRelativePath: String?,
        isRoot: Bool,
        isInbox: Bool,
        icon: String?,
        iconIsEmoji: Bool,
        coverImagePath: String?,
        coverImageOffsetY: Double?,
        createdAt: Date,
        updatedAt: Date
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "relativePath": relativePath,
            "isRoot": isRoot,
            "isInbox": isInbox,
            "iconIsEmoji": iconIsEmoji,
            "created": ISO8601DateFormatter().string(from: createdAt),
            "updated": ISO8601DateFormatter().string(from: updatedAt),
        ]
        if let parentID { dict["parentID"] = parentID }
        if let parentRelativePath { dict["parentRelativePath"] = parentRelativePath }
        if let icon { dict["icon"] = icon }
        if let coverImagePath { dict["coverImagePath"] = coverImagePath }
        if let coverImageOffsetY { dict["coverImageOffsetY"] = coverImageOffsetY }
        return dict
    }

    static func folderOwnerMatchDict(_ folder: VaultFolder) -> [String: Any] {
        var dict: [String: Any] = [
            "id": folder.id.uuidString,
            "name": folder.name,
            "relativePath": folder.relativePath,
        ]
        if let parentID = VaultFolderService.shared.parentID(for: folder) {
            dict["parentID"] = parentID.uuidString
        }
        if let parentPath = folder.parentRelativePath {
            dict["parentRelativePath"] = parentPath
        }
        return dict
    }

    static func folderOwnerCountsDict(
        directCounts: [String: Int],
        descendantCounts: [String: Int],
        directChildFolderCount: Int,
        descendantFolderCount: Int
    ) -> [String: Any] {
        [
            "directItemsByType": directCounts,
            "descendantItemsByType": descendantCounts,
            "directItemCount": directCounts.values.reduce(0, +),
            "descendantItemCount": descendantCounts.values.reduce(0, +),
            "directChildFolderCount": directChildFolderCount,
            "descendantFolderCount": descendantFolderCount,
        ]
    }

    static func itemCounts(matching predicate: (UUID?) -> Bool) -> [String: Int] {
        [
            "bookmark": VaultBookmarkService.shared.bookmarks.filter { predicate($0.folderID) }.count,
            "note": NotesStorage.shared.notes.filter { predicate($0.folderID) }.count,
            "todo": TodoCardStorage.shared.todoCards.filter { predicate($0.folderID) }.count,
            "event": DateCardStorage.shared.dateCards.filter { predicate($0.folderID) }.count,
            "contact": ContactStorage.shared.contacts.filter { predicate($0.folderID) }.count,
            "file": VaultFileService.shared.files.filter { predicate($0.folderID) }.count,
        ]
    }

    static func folderDirectoryExists(_ folder: VaultFolder) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: VaultFolderService.shared.absoluteURL(for: folder).path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    static func folderOwnerSafeNextCommands(relativePath: String, folderID: String? = nil) -> [String] {
        var commands = ["cider-cli item search <query> --json"]
        let artifactLooking = looksLikeVaultArtifactPath(relativePath)
        if !artifactLooking && relativePath != "Inbox" {
            commands.append("cider-cli item move <type> <id-or-ref> --folder \"\(folderID ?? relativePath)\" --json")
            commands.append("cider-cli item move <type> <id-or-ref> --path \"\(relativePath)\" --json")
        }
        if !artifactLooking {
            if let folderID, !folderID.isEmpty {
                commands.append("cider-cli item route <type> <id-or-ref> --target-type folder --target-id \(folderID) --target-path \"\(relativePath)\" --reason <reason> --json")
            } else {
                commands.append("cider-cli item route <type> <id-or-ref> --target-type folder --target-path \"\(relativePath)\" --reason <reason> --json")
            }
        }
        commands.append("cider-cli storage audit --json")
        commands.append("cider-cli storage doctor-plan --json")
        return commands
    }

    static func printOwnerInspection(
        type rawType: String,
        ref rawRef: String,
        store: SecondBrainStore,
        command: String,
        deprecated: Bool
    ) throws {
        let payload = try ownerInspectionPayload(
            type: rawType,
            ref: rawRef,
            store: store,
            command: command,
            deprecated: deprecated
        )
        if jsonOutput {
            outputJSON(payload.dict)
            return
        }
        if deprecated {
            print("Warning: \(itemGetLegacyOwnerDeprecationMessage)")
        }
        print("\(payload.owner.ownerType):\(payload.owner.ownerID)")
        if payload.sections.isEmpty {
            print("  No structured sections.")
        } else {
            for section in payload.sections {
                print("  ## \(section.title)")
                print("  \(section.body.replacingOccurrences(of: "\n", with: "\n  "))")
            }
        }
        if !payload.routes.isEmpty {
            print("  Routing decisions: \(payload.routes.count)")
        }
        if !payload.actions.isEmpty {
            print("  Agent actions: \(payload.actions.count)")
        }
        let relations = payload.dict["ownerRelations"] as? [[String: Any]] ?? []
        let backlinks = payload.dict["backlinks"] as? [[String: Any]] ?? []
        if !relations.isEmpty {
            print("  Owner relations: \(relations.count)")
        }
        if !backlinks.isEmpty {
            print("  Backlinks: \(backlinks.count)")
        }
    }

    static func ownerExists(type rawType: String, ref rawRef: String, owner: SecondBrainOwnerRef) -> Bool {
        let normalizedType = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        if normalizedType == "kanban" || normalizedType == "kanban_card" || normalizedType == "card" {
            if rawRef.contains("/") {
                let parts = rawRef.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let board = KanbanStorage.shared.boards.first(where: { $0.id == parts[0] || $0.name == parts[0] }) else {
                    return false
                }
                return board.card(id: parts[1]) != nil
            }
            return KanbanStorage.shared.findCard(id: rawRef) != nil
                || KanbanStorage.shared.boards.contains { board in
                    SecondBrainKanbanProjectionService.owner(boardID: board.id, cardID: rawRef) == owner
                        && board.card(matching: rawRef) != nil
                }
        }
        if let entityType = try? ItemLinkService.entityType(from: rawType) {
            return (try? ItemLinkService.shared.resolve(type: entityType, ref: rawRef)) != nil
        }
        return true
    }

    static func isKanbanCardItemType(_ rawType: String) -> Bool {
        let normalizedType = rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return normalizedType == "kanban"
            || normalizedType == "kanban_card"
            || normalizedType == "card"
            || normalizedType == "cards"
    }

    static func resolveKanbanCardDetail(ref rawRef: String) throws -> (board: KanbanBoard, column: KanbanColumn, card: KanbanCard) {
        let trimmed = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2,
               let board = KanbanStorage.shared.boards.first(where: { $0.id == parts[0] || $0.name.localizedCaseInsensitiveCompare(parts[0]) == .orderedSame }),
               let column = board.columns.first(where: { column in column.cards.contains { $0.id == parts[1] } }),
               let card = column.cards.first(where: { $0.id == parts[1] }) {
                return (board, column, card)
            }
        }

        if let detail = KanbanStorage.shared.findCard(id: trimmed) {
            return detail
        }

        throw NSError(
            domain: "CiderCLI",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No kanban card found matching '\(rawRef)'."]
        )
    }

    static func kanbanCardItemPayload(ref rawRef: String, store: SecondBrainStore) throws -> [String: Any] {
        let detail = try resolveKanbanCardDetail(ref: rawRef)
        let owner = SecondBrainKanbanProjectionService.owner(boardID: detail.board.id, cardID: detail.card.id)
        try SecondBrainKanbanProjectionService(store: store).refreshCard(boardID: detail.board.id, card: detail.card)

        let sections = try store.sections(for: owner)
        let routes = try store.routingDecisions(for: owner)
        let actions = try store.agentActions(for: owner)
        let related = try relatedKanbanCardItems(ref: "\(detail.board.id)/\(detail.card.id)")
        let ownerRelations = try store.outgoingRelations(for: owner)
        let backlinks = try store.backlinks(for: owner)

        return [
            "ok": true,
            "exists": true,
            "ownerResolved": true,
            "sourceRef": [
                "type": "card",
                "ref": rawRef,
            ],
            "owner": ownerToDict(owner),
            "item": kanbanCardItemToDict(board: detail.board, column: detail.column, card: detail.card),
            "sections": sections.map(secondBrainSectionToDict),
            "ownerRelations": ownerRelations.map(ownerRelationToDict),
            "backlinks": backlinks.map(ownerRelationToDict),
            "routingDecisions": routes.map(routingDecisionToDict),
            "agentActions": actions.map(agentActionToDict),
            "related": related,
            "safeCommands": [
                "cider-cli item get card \(detail.card.id) --json",
                "cider-cli item context card \(detail.card.id) --json",
                "cider-cli item related card \(detail.card.id) --json",
                "cider-cli item relations card \(detail.card.id) --json",
                "cider-cli item backlinks card \(detail.card.id) --json",
                "cider-cli board card inspect \(detail.board.id) --card \(detail.card.id) --json",
            ],
        ]
    }

    static func kanbanCardAgentContextPayload(ref rawRef: String, args: [String], store: SecondBrainStore) throws -> [String: Any] {
        let detail = try resolveKanbanCardDetail(ref: rawRef)
        let owner = SecondBrainKanbanProjectionService.owner(boardID: detail.board.id, cardID: detail.card.id)
        try SecondBrainKanbanProjectionService(store: store).refreshCard(boardID: detail.board.id, card: detail.card)

        let limits = itemAgentContextLimits(from: args)
        let sections = try store.sections(for: owner)
        let related = try relatedKanbanCardItems(ref: "\(detail.board.id)/\(detail.card.id)")
        let ownerRelations = try store.outgoingRelations(for: owner)
        let backlinks = try store.backlinks(for: owner)
        let summary = kanbanCardSummary(card: detail.card, sections: sections, limit: limits.maxBodyCharacters)
        let contentBlocks = sections
            .prefix(max(0, limits.maxSections))
            .map { section in
                [
                    "id": "section-\(section.id)",
                    "kind": "section",
                    "title": section.title,
                    "body": clippedText(section.body, limit: limits.maxBodyCharacters),
                    "source": section.source,
                ]
            }
        let recentHistory = kanbanCardRecentHistory(
            card: detail.card,
            sections: sections,
            limit: limits.maxHistory,
            bodyLimit: limits.maxBodyCharacters
        )
        let safeCommands = [
            "cider-cli item get card \(detail.card.id) --json",
            "cider-cli item context card \(detail.card.id) --json",
            "cider-cli item related card \(detail.card.id) --json",
            "cider-cli item relations card \(detail.card.id) --json",
            "cider-cli item backlinks card \(detail.card.id) --json",
            "cider-cli board card inspect \(detail.board.id) --card \(detail.card.id) --json",
            "cider-cli board section update \(detail.board.id) --card \(detail.card.id) --section \"Current State\" --value \"...\" --json",
            "cider-cli board comment add \(detail.board.id) --card \(detail.card.id) --kind note --text \"...\" --author \"...\" --source \"...\" --json",
            "cider-cli board history add \(detail.board.id) --card \(detail.card.id) --type implementation --text \"...\" --source \"...\" --json",
            "cider-cli board evidence add \(detail.board.id) --card \(detail.card.id) --text \"...\" --source \"...\" --json",
        ]

        return [
            "ok": true,
            "sourceRef": [
                "type": "card",
                "ref": rawRef,
            ],
            "item": kanbanCardItemToDict(board: detail.board, column: detail.column, card: detail.card),
            "owner": ownerToDict(owner),
            "summary": summary,
            "provenance": kanbanCardProvenance(board: detail.board, card: detail.card, sections: sections),
            "contentBlocks": contentBlocks,
            "related": related,
            "ownerRelations": ownerRelations.map(ownerRelationToDict),
            "backlinks": backlinks.map(ownerRelationToDict),
            "surfacing": [
                "reason": summary,
                "urgency": detail.column.isDoneLikeColumn ? "done" : "normal",
                "sourceSignal": "kanban_context",
                "reviewState": detail.column.name.localizedCaseInsensitiveContains("testing") ? "needs_review" : "ok",
                "suggestedAction": detail.column.isDoneLikeColumn ? "Archive or reference" : "Open card",
            ],
            "recentHistory": recentHistory,
            "safeCommands": safeCommands,
            "limits": [
                "maxSections": limits.maxSections,
                "maxChunks": limits.maxChunks,
                "maxRelated": limits.maxRelated,
                "maxHistory": limits.maxHistory,
                "maxBodyCharacters": limits.maxBodyCharacters,
            ],
        ]
    }

    static func kanbanCardSummary(card: KanbanCard, sections: [SecondBrainSection], limit: Int) -> String {
        let preferredKeys = ["current_state", "summary", "overview", "next_step", "goal"]
        for key in preferredKeys {
            if let section = sections.first(where: { $0.sectionKey == key }),
               !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return clippedText(section.body, limit: limit)
            }
        }
        if let section = sections.first(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return clippedText(section.body, limit: limit)
        }
        if let aiSummary = card.aiSummary, !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return clippedText(aiSummary, limit: limit)
        }
        return clippedText(card.title, limit: limit)
    }

    static func kanbanCardRecentHistory(
        card: KanbanCard,
        sections: [SecondBrainSection],
        limit: Int,
        bodyLimit: Int
    ) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        let explicitEntries: [[String: Any]] = card.historyEntries
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
            .map { entry in
                [
                    "id": entry.id,
                    "kind": entry.type.rawValue,
                    "summary": clippedText(entry.body, limit: bodyLimit),
                    "source": entry.author ?? "kanban",
                    "status": "recorded",
                    "createdAt": formatter.string(from: entry.createdAt),
                ]
            }
        let commentEntries: [[String: Any]] = card.comments
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
            .map { comment in
                var dict: [String: Any] = [
                    "id": comment.id,
                    "kind": "comment_\(comment.kind.rawValue)",
                    "summary": clippedText(comment.body, limit: bodyLimit),
                    "source": comment.source ?? comment.author ?? "kanban_comment",
                    "status": comment.isResolved ? "resolved" : "recorded",
                    "createdAt": formatter.string(from: comment.createdAt),
                ]
                if let parentCommentID = comment.parentCommentID {
                    dict["parentCommentID"] = parentCommentID
                }
                return dict
            }

        let sectionHistoryKeys: [String: String] = [
            "failed_attempts": "failed_attempt",
            "implementation_history": "implementation",
            "test_evidence": "test_evidence",
            "decisions": "decision",
            "agent_handoff": "handoff",
            "handoff": "handoff",
            "final_summary": "final_summary",
            "commits": "commit",
        ]
        let sectionEntries: [[String: Any]] = sections.compactMap { section in
            guard let kind = sectionHistoryKeys[section.sectionKey],
                  !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return [
                "id": "section-\(section.id)",
                "kind": kind,
                "summary": clippedText(section.body, limit: bodyLimit),
                "source": section.source,
                "status": "recorded",
                "createdAt": ISO8601DateFormatter().string(from: section.updatedAt),
            ]
        }
        return Array((explicitEntries + commentEntries + sectionEntries).prefix(max(0, limit)))
    }

    static func kanbanCardProvenance(board: KanbanBoard, card: KanbanCard, sections: [SecondBrainSection]) -> [String] {
        var values = [
            "item:kanban_card",
            "board:\(board.id)",
            "card:\(card.id)",
        ]
        values += sections.map { "section:\($0.source)" }
        if !card.historyEntries.isEmpty {
            values.append("history:\(card.historyEntries.count)")
        }
        if !card.linkedEntities.isEmpty {
            values.append("linked_items:\(card.linkedEntities.count)")
        }
        return orderedUniqueStrings(values)
    }

    static func secondBrainCapabilityMapPayload() -> [String: Any] {
        let areas: [[String: Any]] = [
            [
                "id": "capture",
                "title": "Capture accurately",
                "status": "usable",
                "affordanceTargets": ["capture add", "bookmark add", "note create", "todo create", "file capture"],
                "agentGuidance": "Capture first, then verify stored identity, enrichment, route, and review state.",
                "nextImplementationSlice": "Broaden typed capture coverage only when a concrete workflow is missing.",
            ],
            [
                "id": "route_and_organize",
                "title": "Route and organize safely",
                "status": "usable",
                "affordanceTargets": ["routing explain/approve/correct", "review list/approve/correct/defer", "folder doctor"],
                "agentGuidance": "Treat unclear routing as review, not a guess.",
                "nextImplementationSlice": "Improve correction UX and confidence explanations as dogfooding reveals gaps.",
            ],
            [
                "id": "retrieve",
                "title": "Retrieve reliably",
                "status": "usable",
                "affordanceTargets": ["item get/search/related/context/why-surfaced"],
                "agentGuidance": "Use item APIs before reading files or scraping folders.",
                "nextImplementationSlice": "Add richer related-item reasons as new item types join the graph.",
            ],
            [
                "id": "resurface",
                "title": "Resurface at the right time",
                "status": "partial",
                "affordanceTargets": ["dashboard/home relevance", "item why-surfaced", "reminder relevance"],
                "agentGuidance": "Show why now and next action; avoid noisy lists.",
                "nextImplementationSlice": "Unify dashboard, notification, and agent briefing projections.",
            ],
            [
                "id": "track_ongoing_state",
                "title": "Track ongoing life and project state",
                "status": "partial",
                "affordanceTargets": ["todos", "date cards", "Kanban parent rollups", "recent activity"],
                "agentGuidance": "Prefer explicit commitments, waiting-on, deadlines, and review state over memory.",
                "nextImplementationSlice": "Add waiting-on and stale commitment projections.",
            ],
            [
                "id": "reduce_adhd_burden",
                "title": "Reduce ADHD burden",
                "status": "partial",
                "affordanceTargets": ["review queues", "why-surfaced", "safe commands", "dashboard next actions"],
                "agentGuidance": "Offer the smallest safe next action, keep prompts low-noise, and do not require perfect manual organization.",
                "nextImplementationSlice": "Turn capability gaps into concrete one-step dashboard or CLI affordances.",
            ],
            [
                "id": "explain_and_build_trust",
                "title": "Explain and build trust",
                "status": "usable",
                "affordanceTargets": ["routing decisions", "mutation audit", "item why-surfaced", "card history"],
                "agentGuidance": "State source, confidence, and side effects before acting.",
                "nextImplementationSlice": "Expose mutation previews for higher-risk actions.",
            ],
            [
                "id": "agent_context",
                "title": "Agent context and handoff",
                "status": "usable",
                "affordanceTargets": ["item context", "board card inspect", "card history", "safe commands"],
                "agentGuidance": "Start from compact bundles and recent failed attempts before changing state.",
                "nextImplementationSlice": "Add per-action previews and richer handoff compression.",
            ],
        ]

        return [
            "ok": true,
            "purpose": "second_brain_agent_capability_map",
            "generatedBy": "cider-cli item capability-map",
            "areas": areas,
            "nextActions": [
                "Use item search/get/context/why-surfaced before reading files or scraping folders.",
                "Treat low-confidence routing or unclear side effects as review prompts.",
                "Prefer one concrete next action over long task lists.",
                "Update this map when dogfooding reveals a missing second-brain affordance.",
            ],
            "relatedRoadmapCards": ["64cca3", "e4f102", "a07189", "c5b6cb", "288e23"],
        ]
    }

    static func clippedText(_ value: String, limit: Int) -> String {
        let normalizedLimit = max(40, limit)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > normalizedLimit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: normalizedLimit)
        return String(trimmed[..<end])
    }

    static func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values where !value.isEmpty && seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }

    static func kanbanCardItemToDict(board: KanbanBoard, column: KanbanColumn, card: KanbanCard) -> [String: Any] {
        var dict: [String: Any] = [
            "id": card.id,
            "type": "kanban_card",
            "title": card.title,
            "boardID": board.id,
            "boardName": board.name,
            "columnID": column.id,
            "columnName": column.name,
            "relativePath": "\(board.name)/\(card.id)",
            "createdAt": ISO8601DateFormatter().string(from: card.created),
            "tags": card.tags,
        ]
        if let updatedAt = card.updatedAt {
            dict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt)
        } else {
            dict["updatedAt"] = ISO8601DateFormatter().string(from: card.created)
        }
        if let priority = card.priority {
            dict["priority"] = priority.rawValue
        }
        if let parentCardID = card.parentCardID {
            dict["parentCardID"] = parentCardID
        }
        if !card.relatedCardIDs.isEmpty {
            dict["relatedCardIDs"] = card.relatedCardIDs
        }
        appendKanbanCommentFields(card, to: &dict)
        return dict
    }

    static func appendKanbanCommentFields(_ card: KanbanCard, to dict: inout [String: Any]) {
        dict["commentCount"] = card.comments.count
        guard !card.comments.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        dict["comments"] = card.comments.map { comment in
            var commentDict: [String: Any] = [
                "id": comment.id,
                "permalinkID": comment.permalinkID,
                "kind": comment.kind.rawValue,
                "body": comment.body,
                "createdAt": formatter.string(from: comment.createdAt),
                "isResolved": comment.isResolved,
            ]
            if let author = comment.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["author"] = author
            }
            if let source = comment.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["source"] = source
            }
            if let parentCommentID = comment.parentCommentID, !parentCommentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["parentCommentID"] = parentCommentID
            }
            if let resolvedAt = comment.resolvedAt {
                commentDict["resolvedAt"] = formatter.string(from: resolvedAt)
            }
            if let resolvedBy = comment.resolvedBy, !resolvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["resolvedBy"] = resolvedBy
            }
            return commentDict
        }
    }

    static func relatedKanbanCardItems(ref rawRef: String) throws -> [[String: Any]] {
        let detail = try resolveKanbanCardDetail(ref: rawRef)
        let board = detail.board
        let card = detail.card
        var seen = Set<String>()
        var output: [[String: Any]] = []

        func append(_ relatedCard: KanbanCard, relationship: String) {
            guard seen.insert("\(relationship):\(relatedCard.id)").inserted,
                  let relatedColumn = board.columns.first(where: { column in column.cards.contains { $0.id == relatedCard.id } }) else {
                return
            }
            var dict = kanbanCardItemToDict(board: board, column: relatedColumn, card: relatedCard)
            dict["relationship"] = relationship
            output.append(dict)
        }

        if let parent = board.parentCard(for: card.id) {
            append(parent, relationship: "parent")
        }
        for child in board.childCards(of: card.id) {
            append(child, relationship: "child")
        }
        for related in board.relatedCards(for: card.id) {
            append(related, relationship: "related_card")
        }
        for linked in ItemLinkService.shared.summaries(for: card.linkedEntities) {
            var dict = itemLinkSummaryToDict(linked)
            dict["relationship"] = "linked_item"
            output.append(dict)
        }
        return output
    }

    static func ownerToDict(_ owner: SecondBrainOwnerRef) -> [String: Any] {
        [
            "ownerType": owner.ownerType,
            "ownerID": owner.ownerID,
            "ref": owner.canonicalRef,
        ]
    }

    static func ownerRelationToDict(_ relation: SecondBrainRelation) -> [String: Any] {
        var dict: [String: Any] = [
            "id": relation.id,
            "sourceOwner": ownerToDict(relation.sourceOwner),
            "targetOwner": ownerToDict(relation.targetOwner),
            "relationType": relation.relationType,
            "evidence": relation.evidence,
            "source": relation.source,
            "actor": relation.actor,
            "metadata": relation.metadata,
            "createdAt": ISO8601DateFormatter().string(from: relation.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: relation.updatedAt),
        ]
        if let confidence = relation.confidence {
            dict["confidence"] = confidence
        }
        return dict
    }

    static func printOwnerRelations(
        _ relations: [SecondBrainRelation],
        command: String,
        sourceType: String,
        sourceRef: String,
        owner: SecondBrainOwnerRef
    ) {
        if jsonOutput {
            outputJSON([
                "ok": true,
                "command": command,
                "sourceRef": [
                    "type": sourceType,
                    "ref": sourceRef,
                ],
                "owner": ownerToDict(owner),
                "relations": relations.map(ownerRelationToDict),
            ])
            return
        }
        if relations.isEmpty {
            print("No owner relations.")
            return
        }
        for relation in relations {
            print("  [\(relation.relationType)] \(relation.sourceOwner.canonicalRef) -> \(relation.targetOwner.canonicalRef) (\(relation.source))")
        }
    }

    static func printReferenceExtractionResults(
        _ results: [SecondBrainReferenceExtractionResult],
        command: String,
        sourceType: String,
        sourceRef: String
    ) {
        let relationCount = results.reduce(0) { $0 + $1.relations.count }
        if jsonOutput {
            outputJSON([
                "ok": true,
                "command": command,
                "sourceRef": [
                    "type": sourceType,
                    "ref": sourceRef,
                ],
                "sources": results.map { result in
                    [
                        "owner": ownerToDict(result.sourceOwner),
                        "surface": result.surface,
                        "relationCount": result.relations.count,
                        "relations": result.relations.map(ownerRelationToDict),
                    ] as [String: Any]
                },
                "sourceCount": results.count,
                "relationCount": relationCount,
            ])
            return
        }

        print("Rebuilt extracted references for \(results.count) source\(results.count == 1 ? "" : "s") (\(relationCount) relation\(relationCount == 1 ? "" : "s")).")
        for result in results {
            print("  \(result.sourceOwner.canonicalRef): \(result.relations.count)")
        }
    }

    static func projectToDict(_ project: SecondBrainProject) -> [String: Any] {
        [
            "id": project.id,
            "title": project.title,
            "subtitle": project.subtitle,
            "status": project.status,
            "metadata": project.metadata,
            "createdAt": ISO8601DateFormatter().string(from: project.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: project.updatedAt),
            "owner": ownerToDict(project.owner),
        ]
    }

    struct ProjectContextOutputLimits {
        var mode: String
        var maxSamples: Int

        static let full = ProjectContextOutputLimits(mode: "full", maxSamples: Int.max)

        static func summary(maxSamples: Int) -> ProjectContextOutputLimits {
            ProjectContextOutputLimits(mode: "summary", maxSamples: max(0, maxSamples))
        }

        var isSummary: Bool { mode == "summary" }
    }

    static func projectContextOutputLimits(from args: [String]) -> ProjectContextOutputLimits {
        if args.contains("--full") {
            return .full
        }
        if args.contains("--summary") || parseFlag("--limit", from: args) != nil {
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? 25
            return .summary(maxSamples: limit)
        }
        return .full
    }

    static func projectContextToDict(
        _ context: SecondBrainProjectContext,
        command: String,
        sourceRef: String,
        limits: ProjectContextOutputLimits = .full
    ) -> [String: Any] {
        var safeCommands = context.safeCommands
        let fullCommand = "cider-cli item project-context \(context.project.id) --full --json"
        if limits.isSummary, !safeCommands.contains(fullCommand) {
            safeCommands.append(fullCommand)
        }

        var dict: [String: Any] = [
            "ok": true,
            "command": command,
            "readOnly": context.readOnly,
            "changed": context.changed,
            "sourceRef": [
                "type": "project",
                "ref": sourceRef,
            ],
            "project": projectToDict(context.project),
            "owner": ownerToDict(context.owner),
            "sections": context.sections.prefix(limits.maxSamples).map(secondBrainSectionToDict),
            "ownerRelations": context.outgoingRelations.prefix(limits.maxSamples).map(ownerRelationToDict),
            "backlinks": context.backlinks.prefix(limits.maxSamples).map(ownerRelationToDict),
            "artifactRelations": context.artifactRelations.prefix(limits.maxSamples).map(ownerRelationToDict),
            "artifactOwners": context.artifactOwners.prefix(limits.maxSamples).map(ownerToDict),
            "boardOwners": context.boardOwners.prefix(limits.maxSamples).map(ownerToDict),
            "cardOwners": context.cardOwners.prefix(limits.maxSamples).map(ownerToDict),
            "safeCommands": safeCommands,
        ]
        if let mutationReason = context.mutationReason {
            dict["mutationReason"] = mutationReason
        }
        if limits.isSummary {
            dict["mode"] = limits.mode
            dict["limits"] = ["maxSamples": limits.maxSamples]
            dict["counts"] = [
                "sections": context.sections.count,
                "ownerRelations": context.outgoingRelations.count,
                "backlinks": context.backlinks.count,
                "artifactRelations": context.artifactRelations.count,
                "artifactOwners": context.artifactOwners.count,
                "boardOwners": context.boardOwners.count,
                "cardOwners": context.cardOwners.count,
            ]
            dict["truncation"] = [
                "sections": context.sections.count > limits.maxSamples,
                "ownerRelations": context.outgoingRelations.count > limits.maxSamples,
                "backlinks": context.backlinks.count > limits.maxSamples,
                "artifactRelations": context.artifactRelations.count > limits.maxSamples,
                "artifactOwners": context.artifactOwners.count > limits.maxSamples,
                "boardOwners": context.boardOwners.count > limits.maxSamples,
                "cardOwners": context.cardOwners.count > limits.maxSamples,
            ]
        }
        return dict
    }

    static func printProjectContext(
        _ context: SecondBrainProjectContext,
        command: String,
        sourceRef: String,
        limits: ProjectContextOutputLimits = .full
    ) {
        if jsonOutput {
            outputJSON(projectContextToDict(context, command: command, sourceRef: sourceRef, limits: limits))
            return
        }
        print("Project: \(context.project.title) [\(context.project.id)]")
        if !context.project.subtitle.isEmpty {
            print("  \(context.project.subtitle)")
        }
        print("  Owner: \(context.owner.canonicalRef)")
        print("  Boards: \(context.boardOwners.count)")
        print("  Cards: \(context.cardOwners.count)")
        print("  Artifacts: \(context.artifactOwners.count)")
        print("  Relations: \(context.outgoingRelations.count)")
        if !context.safeCommands.isEmpty {
            print("  Safe commands:")
            for command in context.safeCommands {
                print("    \(command)")
            }
        }
    }

    static func kanbanSectionToDict(_ section: KanbanCardSection) -> [String: Any] {
        [
            "key": section.key,
            "title": section.title,
            "body": section.body,
            "sortOrder": section.sortOrder,
        ]
    }

    static func dashboardModelToDict(_ model: KanbanCardDashboardModel, board: String, cardID: String) -> [String: Any] {
        var dict: [String: Any] = [
            "title": model.title,
            "hasStructuredContent": model.hasStructuredContent,
            "currentState": model.currentState ?? "",
            "problem": model.problem ?? "",
            "goal": model.goal ?? "",
            "scope": model.scope ?? "",
            "nextStep": model.nextStep ?? "",
            "openLoops": model.openLoops.map(dashboardEntryToDict),
            "decisions": model.decisions.map(dashboardEntryToDict),
            "historyEntries": model.historyEntries.map(dashboardEntryToDict),
            "evidenceEntries": model.evidenceEntries.map(dashboardEntryToDict),
            "qaFindingsEntries": model.qaFindingsEntries.map(dashboardEntryToDict),
            "hasFailedQA": model.hasFailedQA,
            "relatedItems": model.relatedItems.map(dashboardEntryToDict),
            "missingCoreSections": model.missingCoreSections,
            "fallbackSummary": model.fallbackSummary,
            "agentContext": [
                "notes": model.agentContext.notes,
                "updateTargets": model.agentContext.updateTargets,
                "commands": model.agentContext.commands(board: board, cardID: cardID),
            ],
        ]
        if model.currentState == nil { dict.removeValue(forKey: "currentState") }
        if model.problem == nil { dict.removeValue(forKey: "problem") }
        if model.goal == nil { dict.removeValue(forKey: "goal") }
        if model.scope == nil { dict.removeValue(forKey: "scope") }
        if model.nextStep == nil { dict.removeValue(forKey: "nextStep") }
        return dict
    }

    static func dashboardEntryToDict(_ entry: KanbanCardDashboardEntry) -> [String: Any] {
        var dict: [String: Any] = [
            "id": entry.id,
            "title": entry.title,
            "body": entry.body,
        ]
        if let dateLabel = entry.dateLabel { dict["dateLabel"] = dateLabel }
        if let source = entry.source { dict["source"] = source }
        return dict
    }

    static func parentChildRollupToDict(_ rollup: KanbanParentChildRollup) -> [String: Any] {
        var dict: [String: Any] = [
            "parentID": rollup.parentID,
            "totalChildCount": rollup.totalChildCount,
            "isComplete": rollup.isComplete,
            "statusLine": rollup.statusLine,
            "nextActionLine": rollup.nextActionLine,
            "counts": [
                "backlog": rollup.counts.backlog,
                "queued": rollup.counts.queued,
                "inProgress": rollup.counts.inProgress,
                "testing": rollup.counts.testing,
                "needsFix": rollup.counts.needsFix,
                "done": rollup.counts.done,
                "other": rollup.counts.other,
            ],
            "children": rollup.children.map(parentChildRollupChildToDict),
        ]

        if let currentGate = rollup.currentGate {
            dict["currentGate"] = parentChildRollupChildToDict(currentGate)
        }
        if let nextActionableChild = rollup.nextActionableChild {
            dict["nextActionableChild"] = parentChildRollupChildToDict(nextActionableChild)
        }
        if let failedQAChild = rollup.failedQAChild {
            dict["failedQAChild"] = parentChildRollupChildToDict(failedQAChild)
        }
        if let nextQueuedChild = rollup.nextQueuedChild {
            dict["nextQueuedChild"] = parentChildRollupChildToDict(nextQueuedChild)
        }

        return dict
    }

    struct KanbanParentRefreshPlan {
        var currentState: String
        var nextStep: String
        var staleFindings: [[String: String]]
        var safeCommands: [String]
    }

    static func parentRefreshPlan(
        board: KanbanBoard,
        parent: KanbanCard,
        rollup: KanbanParentChildRollup
    ) -> KanbanParentRefreshPlan {
        let currentState = "\(rollup.statusLine) Next gate: \(rollup.nextActionLine)"
        let nextStep = rollup.nextActionLine
        let boardRef = quoted(board.name)
        let safeCommands = [
            "cider-cli board parent-summary \(boardRef) --card \(parent.id) --refresh --dry-run --json",
            "cider-cli board parent-summary \(boardRef) --card \(parent.id) --refresh --confirm --json",
        ]

        return KanbanParentRefreshPlan(
            currentState: currentState,
            nextStep: nextStep,
            staleFindings: staleParentTextFindings(parent: parent, rollup: rollup),
            safeCommands: safeCommands
        )
    }

    static func parentSummaryToDict(
        board: KanbanBoard,
        parent: KanbanCard,
        rollup: KanbanParentChildRollup,
        plan: KanbanParentRefreshPlan,
        refreshRequested: Bool,
        applied: Bool
    ) -> [String: Any] {
        [
            "ok": true,
            "board": [
                "id": board.id,
                "name": board.name,
            ],
            "parent": minimalCardToDict(parent),
            "childRollup": parentChildRollupToDict(rollup),
            "staleParentText": [
                "isStale": !plan.staleFindings.isEmpty,
                "findings": plan.staleFindings,
            ],
            "proposedSections": [
                "Current State": plan.currentState,
                "Next Step": plan.nextStep,
            ],
            "refreshRequested": refreshRequested,
            "applied": applied,
            "safeCommands": plan.safeCommands,
        ]
    }

    private static func staleParentTextFindings(
        parent: KanbanCard,
        rollup: KanbanParentChildRollup
    ) -> [[String: String]] {
        let model = KanbanCardDashboardModel(title: parent.title, notes: parent.notes)
        let sections: [(String, String)] = [
            ("Current State", model.currentState ?? ""),
            ("Next Step", model.nextStep ?? ""),
        ]
        let doneChildren = rollup.children.filter { $0.role == .done }
        let actionWords = ["next", "remaining", "finish", "start", "queue", "continue", "waiting", "open", "todo", "to do"]

        var findings: [[String: String]] = []
        for (section, body) in sections {
            let normalizedBody = body.lowercased()
            guard actionWords.contains(where: { normalizedBody.contains($0) }) else { continue }
            for child in doneChildren where normalizedBody.contains(child.title.lowercased()) {
                findings.append([
                    "section": section,
                    "referencedDoneChildID": child.id,
                    "referencedDoneChildTitle": child.title,
                    "reason": "Parent section appears to name a completed child as remaining or next work.",
                ])
            }
        }
        return findings
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func parentChildRollupChildToDict(_ child: KanbanParentChildRollup.Child) -> [String: Any] {
        var dict: [String: Any] = [
            "id": child.id,
            "title": child.title,
            "columnID": child.columnID,
            "columnName": child.columnName,
            "role": child.role.rawValue,
            "hasFailedQA": child.hasFailedQA,
            "failedQASteps": child.failedQASteps,
        ]
        if child.failedQASteps.isEmpty {
            dict.removeValue(forKey: "failedQASteps")
        }
        return dict
    }

    static func roadmapNextUpToDict(_ nextUp: KanbanRoadmapNextUpProjection) -> [String: Any] {
        var dict: [String: Any] = [
            "parentID": nextUp.parentID,
            "nextActionLine": nextUp.nextActionLine,
            "sequence": nextUp.sequence.map(roadmapNextUpSequenceItemToDict),
            "groups": nextUp.groups.map(roadmapNextUpGroupToDict),
            "suggestedInsertion": roadmapNextUpSuggestedInsertionToDict(nextUp.suggestedInsertion),
        ]
        if let currentGate = nextUp.currentGate {
            dict["currentGate"] = roadmapNextUpSequenceItemToDict(currentGate)
        }
        if let nextActionableChild = nextUp.nextActionableChild {
            dict["nextActionableChild"] = roadmapNextUpSequenceItemToDict(nextActionableChild)
        }
        return dict
    }

    static func roadmapNextUpGroupToDict(_ group: KanbanRoadmapNextUpProjection.Group) -> [String: Any] {
        [
            "id": group.id,
            "kind": group.kind.rawValue,
            "label": group.label,
            "items": group.items.map(roadmapNextUpSequenceItemToDict),
        ]
    }

    static func roadmapNextUpSequenceItemToDict(_ item: KanbanRoadmapNextUpProjection.SequenceItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "title": item.title,
            "columnID": item.columnID,
            "columnName": item.columnName,
            "role": item.role.rawValue,
            "stepNumber": item.stepNumber,
            "stepCount": item.stepCount,
            "isCurrentGate": item.isCurrentGate,
            "isNextActionable": item.isNextActionable,
            "hasFailedQA": item.hasFailedQA,
            "failedQASteps": item.failedQASteps,
        ]
        if item.failedQASteps.isEmpty {
            dict.removeValue(forKey: "failedQASteps")
        }
        return dict
    }

    static func roadmapNextUpSuggestedInsertionToDict(_ insertion: KanbanRoadmapNextUpProjection.SuggestedInsertion) -> [String: Any] {
        var dict: [String: Any] = [
            "parentID": insertion.parentID,
            "columnID": insertion.columnID,
            "columnName": insertion.columnName,
            "command": insertion.command,
            "reason": insertion.reason,
        ]
        if let afterChildID = insertion.afterChildID {
            dict["afterChildID"] = afterChildID
        }
        return dict
    }

    static func minimalCardToDict(_ card: KanbanCard) -> [String: Any] {
        var dict: [String: Any] = [
            "id": card.id,
            "title": card.title,
            "created": ISO8601DateFormatter().string(from: card.created),
        ]
        if let priority = card.priority { dict["priority"] = priority.rawValue }
        if let completed = card.completed { dict["completed"] = ISO8601DateFormatter().string(from: completed) }
        return dict
    }

    static func boardCardSummaryToDict(board: KanbanBoard, card: KanbanCard) -> [String: Any] {
        var dict = minimalCardToDict(card)
        dict["displayKey"] = board.displayKey(for: card)
        dict["tags"] = card.tags
        dict["linkedEntities"] = card.linkedEntities.map(libraryEntityRefToDict)
        dict["relatedCardIDs"] = card.relatedCardIDs
        if let parentCardID = card.parentCardID { dict["parentCardID"] = parentCardID }
        if let notes = card.notes { dict["notes"] = notes }
        if let agent = card.agent { dict["agent"] = agent }
        if let color = card.color { dict["color"] = color.rawValue }
        if let updatedAt = card.updatedAt { dict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt) }
        return dict
    }

    static func boardIdentityDict(_ board: KanbanBoard) -> [String: Any] {
        [
            "id": board.id,
            "name": board.name,
            "displayKeyPrefix": board.displayKeyPrefix
        ]
    }

    static func boardColumnSummaryToDict(_ column: KanbanColumn) -> [String: Any] {
        [
            "id": column.id,
            "name": column.name,
            "isDoneColumn": column.isDoneColumn,
            "isDoneLikeColumn": column.isDoneLikeColumn
        ]
    }

    static func boardVerificationCommands(board: KanbanBoard, card: KanbanCard? = nil) -> [String] {
        var commands = [
            "cider-cli board show \(board.id) --json"
        ]
        if let card {
            commands.append("cider-cli board card inspect \(board.id) --card \(card.id) --json")
        }
        return commands
    }

    static func boardReadEnvelope(
        command: String,
        board: KanbanBoard? = nil,
        card: KanbanCard? = nil,
        payload: [String: Any] = [:]
    ) -> [String: Any] {
        var dict = payload
        dict["ok"] = true
        dict["command"] = command
        dict["readOnly"] = true
        dict["changed"] = false
        if let board {
            dict["board"] = boardIdentityDict(board)
            dict["safeVerificationCommands"] = boardVerificationCommands(board: board, card: card)
        } else {
            dict["safeVerificationCommands"] = ["cider-cli board list --json"]
        }
        if let card, dict["card"] == nil {
            dict["card"] = board.map { boardCardSummaryToDict(board: $0, card: card) } ?? minimalCardToDict(card)
        }
        return dict
    }

    static func printBoardReadError(
        command: String,
        message: String,
        boardRef: String? = nil,
        board: KanbanBoard? = nil,
        cardRef: String? = nil,
        card: KanbanCard? = nil
    ) {
        processExitCode = 1
        if jsonOutput {
            var dict: [String: Any] = [
                "ok": false,
                "command": command,
                "readOnly": true,
                "changed": false,
                "error": message,
                "safeVerificationCommands": ["cider-cli board list --json"]
            ]
            if let board {
                dict["board"] = boardIdentityDict(board)
                dict["safeVerificationCommands"] = boardVerificationCommands(board: board, card: card)
            } else if let boardRef {
                dict["boardRef"] = boardRef
            }
            if let card {
                dict["card"] = board.map { boardCardSummaryToDict(board: $0, card: card) } ?? minimalCardToDict(card)
            } else if let cardRef {
                dict["cardRef"] = cardRef
            }
            outputJSON(dict)
        } else {
            print("Error: \(message)")
        }
    }

    static func boardMutationEnvelope(
        command: String,
        action: String,
        board: KanbanBoard,
        changed: Bool = true,
        card: KanbanCard? = nil,
        column: KanbanColumn? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "ok": true,
            "command": command,
            "action": action,
            "board": boardIdentityDict(board),
            "readOnly": false,
            "changed": changed,
            "safeVerificationCommands": boardVerificationCommands(board: board, card: card)
        ]
        if let card {
            dict["card"] = boardCardSummaryToDict(board: board, card: card)
        }
        if let column {
            dict["column"] = boardColumnSummaryToDict(column)
        }
        return dict
    }

    static func libraryEntityRefToDict(_ ref: LibraryEntityRef) -> [String: Any] {
        [
            "id": ref.id,
            "type": ref.type.rawValue,
            "entityID": ref.entityID.uuidString,
        ]
    }

    static func secondBrainSectionToDict(_ section: SecondBrainSection) -> [String: Any] {
        var dict: [String: Any] = [
            "id": section.id,
            "owner": ownerToDict(section.owner),
            "sectionKey": section.sectionKey,
            "title": section.title,
            "body": section.body,
            "source": section.source,
            "metadata": section.metadata,
            "sortOrder": section.sortOrder,
            "createdAt": ISO8601DateFormatter().string(from: section.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: section.updatedAt),
        ]
        if let itemID = section.itemID { dict["itemID"] = itemID }
        if let confidence = section.confidence { dict["confidence"] = confidence }
        return dict
    }

    static func secondBrainSearchResultToDict(_ result: SecondBrainChunkSearchResult) -> [String: Any] {
        [
            "id": result.id,
            "owner": ownerToDict(result.owner),
            "title": result.title,
            "snippet": result.snippet,
            "rank": result.rank,
        ]
    }

    static func itemSummaryToDict(_ item: CiderItemSummary) -> [String: Any] {
        itemSummaryToDict(item, ownerRelations: [])
    }

    static func itemSummaryToDict(_ item: CiderItemSummary, ownerRelations: [SecondBrainRelation]) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id.uuidString,
            "type": item.type.rawValue,
            "title": item.title,
            "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
            "isProjectArtifact": false,
        ]
        if let relativePath = item.relativePath { dict["relativePath"] = relativePath }
        if let folderID = item.folderID { dict["folderID"] = folderID.uuidString }
        if let projectRelation = ownerRelations.first(where: {
            $0.relationType == "artifact_of" &&
            $0.sourceOwner.ownerType == item.type.rawValue &&
            $0.sourceOwner.ownerID.caseInsensitiveCompare(item.id.uuidString) == .orderedSame &&
            $0.targetOwner.ownerType == "project"
        }) {
            dict["isProjectArtifact"] = true
            dict["projectID"] = projectRelation.targetOwner.ownerID
            dict["artifactType"] = projectRelation.metadata["artifactType"] ?? item.type.rawValue
        }
        return dict
    }

    static func itemChunkToDict(_ chunk: CiderItemChunk) -> [String: Any] {
        var dict: [String: Any] = [
            "id": chunk.id,
            "owner": ownerToDict(chunk.owner),
            "source": chunk.source,
            "title": chunk.title,
            "body": chunk.body,
            "chunkIndex": chunk.chunkIndex,
            "metadata": chunk.metadata,
            "createdAt": ISO8601DateFormatter().string(from: chunk.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: chunk.updatedAt),
        ]
        if let itemID = chunk.itemID { dict["itemID"] = itemID.uuidString }
        return dict
    }

    static func itemContentIndexResultToDict(_ result: SecondBrainItemContentIndexResult) -> [String: Any] {
        [
            "owner": ownerToDict(result.owner),
            "title": result.title,
            "itemType": result.itemType,
            "chunkCount": result.chunkCount,
            "sources": result.sources,
        ]
    }

    static func printItemContentIndexResults(
        _ results: [SecondBrainItemContentIndexResult],
        command: String,
        sourceType: String,
        sourceRef: String?
    ) {
        if jsonOutput {
            var payload: [String: Any] = [
                "ok": true,
                "command": command,
                "sourceType": sourceType,
                "count": results.count,
                "results": results.map(itemContentIndexResultToDict),
            ]
            if let sourceRef {
                payload["sourceRef"] = sourceRef
            }
            outputJSON(payload)
            return
        }

        print("Rebuilt content chunks for \(results.count) item(s).")
        for result in results {
            print("  \(result.owner.canonicalRef) - \(result.chunkCount) chunk(s) - \(result.title)")
        }
    }

    static func itemLinkSummaryToDict(_ summary: ItemLinkSummary) -> [String: Any] {
        [
            "type": summary.ref.type.rawValue,
            "id": summary.ref.entityID.uuidString,
            "title": summary.title,
            "subtitle": summary.subtitle,
            "symbol": summary.symbol,
        ]
    }

    static func itemContextBundleToDict(_ bundle: CiderItemContextBundle) -> [String: Any] {
        [
            "item": itemSummaryToDict(bundle.item, ownerRelations: bundle.ownerRelations),
            "owner": ownerToDict(bundle.owner),
            "sections": bundle.sections.map(secondBrainSectionToDict),
            "chunks": bundle.chunks.map(itemChunkToDict),
            "related": bundle.related.map(itemLinkSummaryToDict),
            "ownerRelations": bundle.ownerRelations.map(ownerRelationToDict),
            "backlinks": bundle.backlinks.map(ownerRelationToDict),
            "routingDecisions": bundle.routingDecisions.map(routingDecisionToDict),
            "agentActions": bundle.agentActions.map(agentActionToDict),
            "enrichmentOutputs": bundle.enrichmentOutputs.map(enrichmentOutputToDict),
            "captureProvenance": bundle.captureProvenance.map(captureProvenanceToDict),
        ]
    }

    static func captureProvenanceToDict(_ provenance: CiderItemCaptureProvenance) -> [String: Any] {
        var dict: [String: Any] = [
            "eventID": provenance.eventID,
            "owner": ownerToDict(provenance.owner),
            "sourceKind": provenance.sourceKind,
            "attachmentCount": provenance.attachmentCount,
            "metadata": provenance.metadata,
            "createdAt": ISO8601DateFormatter().string(from: provenance.createdAt),
            "relation": ownerRelationToDict(provenance.relation),
        ]
        if let surface = provenance.surface { dict["surface"] = surface }
        if let channel = provenance.channel { dict["channel"] = channel }
        if let channelID = provenance.channelID { dict["channelID"] = channelID }
        if let threadID = provenance.threadID { dict["threadID"] = threadID }
        if let messageID = provenance.messageID { dict["messageID"] = messageID }
        if let senderID = provenance.senderID { dict["senderID"] = senderID }
        if let senderName = provenance.senderName { dict["senderName"] = senderName }
        if let sourceURL = provenance.sourceURL { dict["sourceURL"] = sourceURL }
        if let sourceFile = provenance.sourceFile { dict["sourceFile"] = sourceFile }
        if let sourceText = provenance.sourceText { dict["sourceText"] = sourceText }
        return dict
    }

    static func enrichmentOutputToDict(_ output: SecondBrainEnrichmentOutput) -> [String: Any] {
        var dict: [String: Any] = [
            "id": output.id,
            "owner": ownerToDict(output.owner),
            "kind": output.kind,
            "value": output.value,
            "normalizedValue": output.normalizedValue,
            "label": output.label,
            "evidence": output.evidence,
            "source": output.source,
            "reviewState": output.reviewState,
            "metadata": output.metadata,
            "createdAt": ISO8601DateFormatter().string(from: output.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: output.updatedAt),
        ]
        if let chunkID = output.chunkID { dict["chunkID"] = chunkID }
        if let confidence = output.confidence { dict["confidence"] = confidence }
        return dict
    }

    static func memoryCandidateResultToDict(
        _ result: SecondBrainMemoryCandidateResult,
        sourceType: String,
        sourceRef: String
    ) -> [String: Any] {
        let safeCommands = memoryCandidateSafeCommands(owner: result.owner)
        return [
            "ok": true,
            "command": "item.memory-suggest",
            "readOnly": false,
            "changed": true,
            "mutationReason": "Recorded a reviewable memory candidate; no permanent memory was promoted.",
            "sourceRef": [
                "type": sourceType,
                "ref": sourceRef,
            ],
            "owner": ownerToDict(result.owner),
            "candidate": enrichmentOutputToDict(result.candidate),
            "agentAction": agentActionToDict(result.agentAction),
            "safeNextCommands": safeCommands,
            "safeCommands": safeCommands,
        ]
    }

    static func memoryCandidateSafeCommands(owner: SecondBrainOwnerRef) -> [String] {
        var commands: [String] = []
        switch owner.ownerType {
        case "project":
            commands.append("cider-cli item project-context \(owner.ownerID) --json")
        case "kanban_card":
            commands.append("cider-cli item context card \(owner.ownerID) --json")
        case "bookmark", "note", "dateCard", "contact", "todo", "vaultFile":
            commands.append("cider-cli item context \(owner.ownerType) \(owner.ownerID) --json")
        default:
            commands.append("cider-cli item owner-get \(owner.ownerType) \(owner.ownerID) --json")
        }
        commands.append("cider-cli capture review-queue --json")
        commands.append("cider-cli item owner-get \(owner.ownerType) \(owner.ownerID) --json")
        var seen = Set<String>()
        return commands.filter { seen.insert($0).inserted }
    }

    static func handleItemDelete(
        args: [String],
        contextService: CiderItemContextService,
        store: SecondBrainStore
    ) {
        let positional = leadingPositionalArgs(from: args)
        guard positional.count >= 2, let reason = parseFlag("--reason", from: args)?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            printCLIError("Usage: cider-cli item delete <type> <id-or-ref> --reason <text> [--approve <token> --execute] [--actor <name>] [--source <source>] [--json]")
            return
        }
        do {
            let entityType = try ItemLinkService.entityType(from: positional[0])
            guard LibraryEntityType.activeCases.contains(entityType) else {
                printCLIError("item delete does not support \(entityType.rawValue).")
                return
            }
            let ref = try ItemLinkService.shared.resolve(type: entityType, ref: positional[1])
            let before = try contextService.context(for: ref).item
            let token = itemDeleteApprovalToken(ref: ref, reason: reason)
            let execute = args.contains("--execute")
            let approval = parseFlag("--approve", from: args)
            let actor = parseFlag("--actor", from: args) ?? "agent"
            let source = parseFlag("--source", from: args) ?? "cli.item.delete"

            if !execute || approval != token {
                let payload = itemDeleteEnvelope(
                    ref: ref,
                    before: before,
                    reason: reason,
                    readOnly: true,
                    changed: false,
                    approvalToken: token,
                    actor: actor,
                    source: source
                )
                if jsonOutput {
                    outputJSON(payload)
                } else {
                    print("About to trash \(before.type.rawValue): \(before.title)")
                    print("  Path: \(before.relativePath ?? "(none)")")
                    print("  Reason: \(reason)")
                    print("  Approve with: cider-cli item delete \(ref.type.rawValue) \(ref.entityID.uuidString) --reason \"\(reason)\" --approve \(token) --execute")
                }
                return
            }

            let trashItem = try trashItem(ref: ref)
            CiderUndoManager.shared.record(.deletedToTrash(itemType: trashItem.itemType, trashItem: trashItem))

            let auditEntry = MutationAuditService(database: .shared).record(
                action: "item_delete",
                itemType: ref.type.rawValue,
                itemID: ref.entityID,
                before: itemDeleteSummarySnapshot(before),
                after: MutationAuditSnapshots.trashItem(trashItem),
                metadata: [
                    "command": "item.delete",
                    "actor": actor,
                    "source": source,
                    "reason": reason,
                    "trashItemID": trashItem.id.uuidString,
                ],
                source: source == "cli" || source.hasPrefix("cli.") ? .cli : .agent
            )

            let actionID = UUID().uuidString
            try store.recordAgentAction(
                SecondBrainAgentAction(
                    id: actionID,
                    owner: SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString),
                    itemID: nil,
                    toolName: "item.delete",
                    actionType: "item.delete",
                    source: source,
                    status: "succeeded",
                    summary: "Trashed \(ref.type.rawValue):\(ref.entityID.uuidString) through approved item delete.",
                    argumentsJSON: DatabaseHelpers.encodeJSON([
                        "actor": actor,
                        "reason": reason,
                    ]),
                    resultJSON: DatabaseHelpers.encodeJSON([
                        "trashItemID": trashItem.id.uuidString,
                        "mutationAuditEntryID": auditEntry?.id.uuidString ?? "",
                    ])
                )
            )

            var payload = itemDeleteEnvelope(
                ref: ref,
                before: before,
                reason: reason,
                readOnly: false,
                changed: true,
                approvalToken: token,
                actor: actor,
                source: source
            )
            payload["trashItemID"] = trashItem.id.uuidString
            payload["mutationAuditEntryID"] = auditEntry?.id.uuidString
            payload["agentActionID"] = actionID
            payload["nextSafeAction"] = "inspect_trash"
            payload["safeNextCommands"] = [
                "cider-cli item search \"\(before.title)\" --limit 5 --json",
                "cider-cli storage audit --json",
            ]
            if jsonOutput {
                outputJSON(payload)
            } else {
                print("Deleted: \(before.title) (moved to trash)")
            }
        } catch {
            printCLIError(error.localizedDescription)
        }
    }

    static func itemDeleteApprovalToken(ref: LibraryEntityRef, reason: String) -> String {
        let seed = "\(ref.type.rawValue)|\(ref.entityID.uuidString)|\(reason)"
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "DELETE_ITEM_" + String(hash, radix: 16).uppercased()
    }

    static func itemDeleteEnvelope(
        ref: LibraryEntityRef,
        before: CiderItemSummary,
        reason: String,
        readOnly: Bool,
        changed: Bool,
        approvalToken: String,
        actor: String,
        source: String
    ) -> [String: Any] {
        [
            "ok": true,
            "command": "item.delete",
            "readOnly": readOnly,
            "changed": changed,
            "approvalRequired": readOnly,
            "requiredApprovalToken": approvalToken,
            "item": [
                "type": ref.type.rawValue,
                "id": ref.entityID.uuidString,
            ],
            "before": itemSummaryToDict(before),
            "reason": reason,
            "actor": actor,
            "source": source,
            "nextSafeAction": readOnly ? "approve_delete" : "inspect_trash",
            "safeNextCommands": [
                "cider-cli item delete \(ref.type.rawValue) \(ref.entityID.uuidString) --reason \"\(reason)\" --approve \(approvalToken) --execute --json",
            ],
            "rollbackGuidance": readOnly
                ? "No mutation has happened. Execute only after verifying the item is safe to trash."
                : "The item was moved to Cider trash and can be restored through Cider trash flows while retained.",
        ]
    }

    static func trashItem(ref: LibraryEntityRef) throws -> TrashItem {
        switch ref.type {
        case .bookmark:
            guard let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == ref.entityID }),
                  let item = VaultBookmarkService.shared.removeAll([bookmark]).first else {
                throw CaptureAddArgumentError.message("No bookmark found for \(ref.entityID.uuidString).")
            }
            return item
        case .note:
            guard let note = NotesStorage.shared.notes.first(where: { $0.id == ref.entityID }) else {
                throw CaptureAddArgumentError.message("No note found for \(ref.entityID.uuidString).")
            }
            return NotesStorage.shared.delete(note: note)
        case .todo:
            guard let item = TodoCardStorage.shared.deleteTodoCard(ref.entityID) else {
                throw CaptureAddArgumentError.message("No todo found for \(ref.entityID.uuidString).")
            }
            return item
        case .dateCard:
            guard let item = DateCardStorage.shared.deleteDateCard(ref.entityID) else {
                throw CaptureAddArgumentError.message("No event found for \(ref.entityID.uuidString).")
            }
            return item
        case .contact:
            guard let item = ContactStorage.shared.deleteContact(ref.entityID) else {
                throw CaptureAddArgumentError.message("No contact found for \(ref.entityID.uuidString).")
            }
            return item
        case .vaultFile:
            guard let file = VaultFileService.shared.file(for: ref.entityID) else {
                throw CaptureAddArgumentError.message("No vaultFile found for \(ref.entityID.uuidString).")
            }
            return TrashStorage.shared.trashVaultFile(file)
        case .externalFile, .session:
            throw CaptureAddArgumentError.message("item delete does not support \(ref.type.rawValue).")
        }
    }

    static func itemDeleteSummarySnapshot(_ item: CiderItemSummary) -> [String: String] {
        var snapshot: [String: String] = [
            "id": item.id.uuidString,
            "type": item.type.rawValue,
            "title": item.title,
            "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
        ]
        if let folderID = item.folderID {
            snapshot["folderID"] = folderID.uuidString
        }
        if let relativePath = item.relativePath {
            snapshot["relativePath"] = relativePath
        }
        return snapshot
    }

    static func similarityCandidateToDict(_ candidate: SecondBrainSimilarityCandidate) -> [String: Any] {
        var dict: [String: Any] = [
            "id": candidate.id,
            "sourceOwner": ownerToDict(candidate.sourceOwner),
            "targetOwner": ownerToDict(candidate.targetOwner),
            "candidateType": candidate.candidateType,
            "signal": candidate.signal,
            "score": candidate.score,
            "reason": candidate.reason,
            "evidence": candidate.evidence,
            "source": candidate.source,
            "reviewState": candidate.reviewState,
            "metadata": candidate.metadata,
            "createdAt": ISO8601DateFormatter().string(from: candidate.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: candidate.updatedAt),
        ]
        if let reviewedAt = candidate.reviewedAt {
            dict["reviewedAt"] = ISO8601DateFormatter().string(from: reviewedAt)
        }
        return dict
    }

    static func intelligenceDogfoodOwnerResultToDict(_ result: SecondBrainIntelligenceDogfoodOwnerResult) -> [String: Any] {
        [
            "owner": ownerToDict(result.owner),
            "chunkCount": result.chunkCount,
            "enrichmentOutputCount": result.enrichmentOutputCount,
            "enrichmentKindCounts": result.enrichmentKindCounts,
            "enrichmentReviewStates": result.enrichmentReviewStates,
            "similarityCandidateCount": result.similarityCandidateCount,
            "similarityReviewStates": result.similarityReviewStates,
        ]
    }

    static func intelligenceDogfoodResultToDict(_ result: SecondBrainIntelligenceDogfoodResult) -> [String: Any] {
        [
            "ok": true,
            "command": "item.dogfood-intelligence",
            "changed": result.enrichmentOutputCount > 0 || result.similarityCandidateCount > 0,
            "reviewRequired": result.reviewRequired,
            "ownerCount": result.ownerCount,
            "limit": result.limit,
            "threshold": result.threshold,
            "candidateLimit": result.candidateLimit,
            "enrichmentOutputCount": result.enrichmentOutputCount,
            "similarityCandidateCount": result.similarityCandidateCount,
            "owners": result.owners.map(intelligenceDogfoodOwnerResultToDict),
        ]
    }

    static func printIntelligenceDogfoodResult(_ result: SecondBrainIntelligenceDogfoodResult) {
        if jsonOutput {
            outputJSON(intelligenceDogfoodResultToDict(result))
            return
        }

        print("Dogfooded intelligence stores for \(result.ownerCount) owner(s).")
        print("  Enrichment outputs: \(result.enrichmentOutputCount)")
        print("  Similarity candidates: \(result.similarityCandidateCount)")
        if result.reviewRequired {
            print("  Review required before applying generated suggestions.")
        }
        for owner in result.owners {
            print("  \(owner.owner.canonicalRef): \(owner.chunkCount) chunk(s), \(owner.enrichmentOutputCount) output(s), \(owner.similarityCandidateCount) candidate(s)")
        }
    }

    static func printSimilarityCandidates(
        _ candidates: [SecondBrainSimilarityCandidate],
        command: String,
        owner: SecondBrainOwnerRef,
        extra: [String: Any] = [:]
    ) {
        if jsonOutput {
            var payload: [String: Any] = [
                "ok": true,
                "command": command,
                "owner": ownerToDict(owner),
                "candidates": candidates.map(similarityCandidateToDict),
            ]
            for (key, value) in extra {
                payload[key] = value
            }
            outputJSON(payload)
            return
        }

        if candidates.isEmpty {
            print("No similarity candidates for \(owner.canonicalRef).")
            return
        }
        print("Similarity candidates for \(owner.canonicalRef):")
        for candidate in candidates {
            let score = String(format: "%.2f", candidate.score)
            print("  [\(candidate.id)] \(candidate.candidateType) \(score) \(candidate.targetOwner.canonicalRef) - \(candidate.reviewState)")
            print("    \(candidate.evidence)")
        }
    }

    static func itemAgentContextLimits(from args: [String]) -> CiderItemAgentContextLimits {
        CiderItemAgentContextLimits(
            maxSections: Int(parseFlag("--max-sections", from: args) ?? "") ?? CiderItemAgentContextLimits.default.maxSections,
            maxChunks: Int(parseFlag("--max-chunks", from: args) ?? "") ?? CiderItemAgentContextLimits.default.maxChunks,
            maxRelated: Int(parseFlag("--max-related", from: args) ?? "") ?? CiderItemAgentContextLimits.default.maxRelated,
            maxHistory: Int(parseFlag("--max-history", from: args) ?? "") ?? CiderItemAgentContextLimits.default.maxHistory,
            maxBodyCharacters: Int(parseFlag("--max-body", from: args) ?? "") ?? CiderItemAgentContextLimits.default.maxBodyCharacters
        )
    }

    static func itemAgentContextPacketToDict(_ packet: CiderItemAgentContextPacket) -> [String: Any] {
        var dict: [String: Any] = [
            "ok": true,
            "command": "item.context",
            "readOnly": true,
            "changed": false,
            "item": itemSummaryToDict(packet.item),
            "owner": ownerToDict(packet.owner),
            "summary": packet.summary,
            "provenance": packet.provenance,
            "spaceMemberships": packet.spaceMemberships.map(itemSpaceMembershipToDict),
            "contentBlocks": packet.contentBlocks.map(itemAgentContextBlockToDict),
            "related": packet.related.map(itemLinkSummaryToDict),
            "ownerRelations": packet.ownerRelations.map(ownerRelationToDict),
            "backlinks": packet.backlinks.map(ownerRelationToDict),
            "captureProvenance": packet.captureProvenance.map(captureProvenanceToDict),
            "surfacing": surfacingExplanationToDict(packet.surfacing),
            "recentHistory": packet.recentHistory.map(itemAgentContextHistoryToDict),
            "safeCommands": packet.safeCommands,
            "limits": [
                "maxSections": packet.limits.maxSections,
                "maxChunks": packet.limits.maxChunks,
                "maxRelated": packet.limits.maxRelated,
                "maxHistory": packet.limits.maxHistory,
                "maxBodyCharacters": packet.limits.maxBodyCharacters,
            ],
        ]
        CiderAgentDecisionContract.merge(itemAgentDecisionDictionary(for: packet), into: &dict)
        if let review = packet.review {
            dict["review"] = itemAgentReviewStateToDict(review)
        }
        return dict
    }

    static func itemAgentDecisionDictionary(for packet: CiderItemAgentContextPacket) -> [String: Any] {
        let reviewStatus = packet.review?.status ?? packet.surfacing.reviewState
        let needsReview = reviewStatus == "needs_review"
        let needsRouting = needsReview || packet.review?.targetPath != nil
        var blockingIssues: [String] = []
        if needsReview {
            blockingIssues.append("routing_needs_review")
        }
        return CiderAgentDecisionContract.dictionary(
            saved: true,
            needsReview: needsReview,
            needsEnrichment: false,
            needsRouting: needsRouting,
            confidence: packet.review?.confidence,
            blockingIssues: blockingIssues,
            recommendedNextAction: needsReview ? "review_route" : packet.surfacing.suggestedAction,
            safeNextCommands: packet.safeCommands
        )
    }

    static func itemSpaceMembershipToDict(_ membership: CiderSpaceMembership) -> [String: Any] {
        var dict: [String: Any] = [
            "id": membership.id,
            "spaceID": membership.spaceID,
            "spaceName": membership.spaceName,
            "item": [
                "type": membership.item.type.rawValue,
                "id": membership.item.entityID.uuidString,
            ],
            "reason": membership.reason,
            "source": membership.source,
            "actor": membership.actor,
            "createdAt": ISO8601DateFormatter().string(from: membership.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: membership.updatedAt),
        ]
        if let confidence = membership.confidence {
            dict["confidence"] = confidence
        }
        return dict
    }

    static func surfacingExplanationToDict(_ explanation: CiderSurfacingExplanation) -> [String: Any] {
        var dict: [String: Any] = [
            "reason": explanation.reason,
            "urgency": explanation.urgency,
            "sourceSignal": explanation.sourceSignal,
            "reviewState": explanation.reviewState,
            "suggestedAction": explanation.suggestedAction,
        ]
        if let actionURLString = explanation.actionURLString {
            dict["actionURLString"] = actionURLString
        }
        return dict
    }

    static func itemAgentContextBlockToDict(_ block: CiderItemAgentContextBlock) -> [String: Any] {
        [
            "id": block.id,
            "kind": block.kind,
            "title": block.title,
            "body": block.body,
            "source": block.source,
        ]
    }

    static func itemAgentReviewStateToDict(_ review: CiderItemAgentReviewState) -> [String: Any] {
        var dict: [String: Any] = [
            "status": review.status,
            "reason": review.reason,
            "targetType": review.targetType,
            "source": review.source,
            "createdAt": ISO8601DateFormatter().string(from: review.createdAt),
        ]
        if let confidence = review.confidence { dict["confidence"] = confidence }
        if let targetPath = review.targetPath { dict["targetPath"] = targetPath }
        return dict
    }

    static func itemAgentContextHistoryToDict(_ entry: CiderItemAgentContextHistoryEntry) -> [String: Any] {
        [
            "id": entry.id,
            "kind": entry.kind,
            "summary": entry.summary,
            "source": entry.source,
            "status": entry.status,
            "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
        ]
    }

    static func itemSearchResultToDict(_ result: CiderItemSearchResult) -> [String: Any] {
        var dict: [String: Any] = [
            "id": result.id,
            "kind": result.kind.rawValue,
            "owner": ownerToDict(result.owner),
            "title": result.title,
            "snippet": result.snippet,
            "rank": result.rank,
        ]
        if let item = result.item {
            dict["item"] = itemSummaryToDict(item)
        }
        if let stage = result.stage {
            dict["stage"] = stage
        }
        if let matchedQuery = result.matchedQuery {
            dict["matchedQuery"] = matchedQuery
        }
        if !result.rankFactors.isEmpty {
            dict["rankFactors"] = result.rankFactors
        }
        return dict
    }

    static func itemSearchDiagnosticsReportToDict(_ report: CiderItemSearchDiagnosticsReport) -> [String: Any] {
        let rankedResults = report.exactMatches.map(itemSearchResultToDict)
        return [
            "ok": report.errors.isEmpty,
            "command": report.command,
            "readOnly": true,
            "changed": false,
            "query": report.query,
            "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
            "rankedResults": rankedResults,
            "exactMatches": rankedResults,
            "fallbackStages": report.fallbackStages.map(itemSearchFallbackStageToDict),
            "matchedChunks": report.matchedChunks.map(itemSearchDiagnosticsChunkMatchToDict),
            "candidateItems": report.candidateItems.map(itemSummaryToDict),
            "excludedItems": report.excludedItems.map(itemSearchDiagnosticsWarningToDict),
            "indexWarnings": report.indexWarnings.map(itemSearchIndexWarningToDict),
            "semanticStatus": itemSearchSemanticStatusToDict(report.semanticStatus),
            "warnings": report.warnings.map(itemSearchDiagnosticsWarningToDict),
            "errors": report.errors.map(itemSearchDiagnosticsWarningToDict),
            "safeNextCommands": report.safeNextCommands,
        ]
    }

    static func itemSearchFallbackStageToDict(_ stage: CiderItemSearchFallbackStage) -> [String: Any] {
        [
            "name": stage.name,
            "query": stage.query,
            "resultCount": stage.resultCount,
            "explanation": stage.explanation,
        ]
    }

    static func itemSearchDiagnosticsChunkMatchToDict(_ match: CiderItemSearchDiagnosticsChunkMatch) -> [String: Any] {
        var dict: [String: Any] = [
            "id": match.id,
            "searchResult": itemSearchResultToDict(match.searchResult),
            "chunk": itemChunkToDict(match.chunk),
            "routingDecisions": match.routingDecisions.map(routingDecisionToDict),
            "captureProvenance": match.captureProvenance.map(captureProvenanceToDict),
            "indexFreshness": itemSearchIndexFreshnessToDict(match.indexFreshness),
        ]
        if let item = match.item {
            dict["item"] = itemSummaryToDict(item)
        }
        return dict
    }

    static func itemSearchIndexFreshnessToDict(_ freshness: CiderItemSearchIndexFreshness) -> [String: Any] {
        var dict: [String: Any] = [
            "status": freshness.status,
            "chunkCount": freshness.chunkCount,
        ]
        if let itemUpdatedAt = freshness.itemUpdatedAt {
            dict["itemUpdatedAt"] = ISO8601DateFormatter().string(from: itemUpdatedAt)
        }
        if let newestChunkUpdatedAt = freshness.newestChunkUpdatedAt {
            dict["newestChunkUpdatedAt"] = ISO8601DateFormatter().string(from: newestChunkUpdatedAt)
        }
        return dict
    }

    static func itemSearchIndexWarningToDict(_ warning: CiderItemSearchIndexWarning) -> [String: Any] {
        var dict: [String: Any] = [
            "id": warning.id,
            "kind": warning.kind,
            "message": warning.message,
            "owner": ownerToDict(warning.owner),
            "chunkCount": warning.chunkCount,
            "safeRepairCommand": warning.safeRepairCommand,
        ]
        if let item = warning.item {
            dict["item"] = itemSummaryToDict(item)
        }
        if let itemUpdatedAt = warning.itemUpdatedAt {
            dict["itemUpdatedAt"] = ISO8601DateFormatter().string(from: itemUpdatedAt)
        }
        if let newestChunkUpdatedAt = warning.newestChunkUpdatedAt {
            dict["newestChunkUpdatedAt"] = ISO8601DateFormatter().string(from: newestChunkUpdatedAt)
        }
        return dict
    }

    static func itemSearchDiagnosticsWarningToDict(_ warning: CiderItemSearchDiagnosticsWarning) -> [String: Any] {
        var dict: [String: Any] = [
            "id": warning.id,
            "kind": warning.kind,
            "message": warning.message,
        ]
        if let owner = warning.owner {
            dict["owner"] = ownerToDict(owner)
        }
        if let item = warning.item {
            dict["item"] = itemSummaryToDict(item)
        }
        return dict
    }

    static func itemSearchSemanticStatusToDict(_ status: CiderItemSearchSemanticStatus) -> [String: Any] {
        [
            "available": status.available,
            "status": status.status,
            "reason": status.reason,
            "mode": status.mode,
            "candidateCount": status.candidateCount,
            "candidates": status.candidates.map(itemSearchSemanticCandidateToDict),
            "requiresRebuild": status.requiresRebuild,
            "safeNextCommands": status.safeNextCommands,
        ]
    }

    static func itemSearchSemanticCandidateToDict(_ candidate: CiderItemSearchSemanticCandidate) -> [String: Any] {
        var dict: [String: Any] = [
            "id": candidate.id,
            "score": candidate.score,
            "rationale": candidate.rationale,
            "rankFactors": candidate.rankFactors,
        ]
        if let item = candidate.item {
            dict["item"] = itemSummaryToDict(item)
        }
        if let owner = candidate.owner {
            dict["owner"] = ownerToDict(owner)
        }
        return dict
    }

    static func routingDecisionToDict(_ decision: SecondBrainRoutingDecision) -> [String: Any] {
        var dict: [String: Any] = [
            "id": decision.id,
            "owner": ownerToDict(decision.owner),
            "targetType": decision.targetType,
            "confidence": decision.confidence,
            "reason": decision.reason,
            "status": decision.status,
            "actor": decision.actor,
            "source": decision.source,
            "createdAt": ISO8601DateFormatter().string(from: decision.createdAt),
        ]
        if let itemID = decision.itemID { dict["itemID"] = itemID }
        if let targetID = decision.targetID { dict["targetID"] = targetID }
        if let targetPath = decision.targetPath { dict["targetPath"] = targetPath }
        if let candidatesJSON = decision.candidatesJSON { dict["candidatesJSON"] = candidatesJSON }
        if let reviewedAt = decision.reviewedAt { dict["reviewedAt"] = ISO8601DateFormatter().string(from: reviewedAt) }
        return dict
    }

    static func agentActionToDict(_ action: SecondBrainAgentAction) -> [String: Any] {
        var dict: [String: Any] = [
            "id": action.id,
            "owner": ownerToDict(action.owner),
            "toolName": action.toolName,
            "actionType": action.actionType,
            "source": action.source,
            "status": action.status,
            "summary": action.summary,
            "createdAt": ISO8601DateFormatter().string(from: action.createdAt),
        ]
        if let itemID = action.itemID { dict["itemID"] = itemID }
        if let argumentsJSON = action.argumentsJSON { dict["argumentsJSON"] = argumentsJSON }
        if let resultJSON = action.resultJSON { dict["resultJSON"] = resultJSON }
        return dict
    }

    static func spaceToDict(_ space: CiderSpace) -> [String: Any] {
        [
            "id": space.id,
            "name": space.name,
            "systemImage": space.systemImage,
            "purpose": space.purpose,
            "preset": space.preset.rawValue,
            "isPinned": space.isPinned,
            "aiInstructions": space.aiInstructions,
            "routingHints": space.routingHints,
            "defaultViews": space.defaultViews.map(\.rawValue),
            "rootRelativePath": space.rootRelativePath,
            "authority": spaceAuthorityToDict(),
            "nativeCutover": spaceNativeCutoverToDict(),
            "createdAt": ISO8601DateFormatter().string(from: space.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: space.updatedAt),
        ]
    }

    private static func spaceAuthorityToDict() -> [String: Any] {
        [
            "status": "hybrid_yaml_bridge",
            "metadataSource": ".cider-space.yaml",
            "semanticMembershipSource": "space_memberships",
            "rootPathRole": "storage_projection",
            "pathContainmentIsSemantic": false,
        ]
    }

    private static func spaceNativeCutoverToDict() -> [String: Any] {
        [
            "plannedTable": "spaces",
            "compatibilityProjection": ".cider-space.yaml",
            "nextGate": "39a15a",
        ]
    }

    static func secondBrainGraphHealthStatus() throws -> [String: Any] {
        let db = CiderDatabase.shared

        func tableExists(_ table: String) throws -> Bool {
            let stmt = try db.prepare("""
                SELECT count(*)
                FROM sqlite_master
                WHERE type = 'table' AND name = ?;
                """)
            stmt.bind(table, at: 1)
            try stmt.step()
            return stmt.int(at: 0) == 1
        }

        func rowCount(_ table: String) throws -> Int? {
            guard try tableExists(table), table != "content_chunks_fts" else { return nil }
            let stmt = try db.prepare("SELECT count(*) FROM \(table);")
            try stmt.step()
            return Int(stmt.int64(at: 0))
        }

        let itemCount = try rowCount("items") ?? 0
        let ownerRelationCount = try rowCount("owner_relations") ?? 0
        let projectCount = try rowCount("projects") ?? 0
        let captureEventCount = try rowCount("capture_events") ?? 0
        let captureAttachmentCount = try rowCount("capture_attachments") ?? 0
        let chunkCount = try rowCount("content_chunks") ?? 0
        let enrichmentCount = try rowCount("enrichment_outputs") ?? 0
        let similarityCount = try rowCount("similarity_candidates") ?? 0
        let knownWorkspaceCount = ProjectWorkspaceCatalog.defaultCatalog(
            boards: KanbanStorage.shared.boards,
            boardAssociations: ProjectWorkspaceAssociationStore.shared.associations
        ).activeProjects.count

        var suggestedCommands: [String] = []
        var suggestedActions: [[String: Any]] = []
        func addSuggestedCommand(_ command: String) {
            guard !suggestedCommands.contains(command) else { return }
            suggestedCommands.append(command)
            suggestedActions.append(graphHealthSuggestedAction(for: command))
        }
        func component(
            id: String,
            table: String,
            label: String,
            count: Int?,
            emptyState: String = "implemented_empty",
            emptyDetail: String,
            healthyDetail: String,
            emptyReason: String? = nil,
            suggestedCommand: String? = nil,
            needsWorkWhenEmpty: Bool = false,
            needsWorkState: String = "needs_rebuild"
        ) throws -> [String: Any] {
            guard try tableExists(table) else {
                let command = "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
                addSuggestedCommand(command)
                return [
                    "id": id,
                    "label": label,
                    "table": table,
                    "exists": false,
                    "state": "not_implemented",
                    "detail": "Required graph table \(table) is missing.",
                    "safeNextCommands": [command],
                    "safeNextActions": [graphHealthSuggestedAction(for: command)],
                ]
            }

            let resolvedCount = count ?? 0
            if resolvedCount > 0 {
                return [
                    "id": id,
                    "label": label,
                    "table": table,
                    "exists": true,
                    "count": resolvedCount,
                    "state": "healthy",
                    "detail": healthyDetail,
                    "safeNextCommands": [],
                    "safeNextActions": [],
                ]
            }

            let state = needsWorkWhenEmpty ? needsWorkState : emptyState
            let commandList = suggestedCommand.map { [$0] } ?? []
            if let suggestedCommand {
                addSuggestedCommand(suggestedCommand)
            }
            var payload: [String: Any] = [
                "id": id,
                "label": label,
                "table": table,
                "exists": true,
                "count": resolvedCount,
                "state": state,
                "detail": emptyDetail,
                "safeNextCommands": commandList,
                "safeNextActions": commandList.map(graphHealthSuggestedAction),
            ]
            if let emptyReason {
                payload["emptyReason"] = emptyReason
            }
            return payload
        }

        let components = try [
            component(
                id: "owner_relations",
                table: "owner_relations",
                label: "Owner relations",
                count: ownerRelationCount,
                emptyDetail: "Owner relation graph is implemented but has no edges yet.",
                healthyDetail: "Typed owner relations are populated.",
                suggestedCommand: "cider-cli item rebuild-references board \"Second-Brain Roadmap v1\" --json",
                needsWorkWhenEmpty: itemCount > 0 || captureEventCount > 0 || projectCount > 0
            ),
            component(
                id: "projects",
                table: "projects",
                label: "Project graph",
                count: projectCount,
                emptyDetail: knownWorkspaceCount > 0
                    ? "Project graph is implemented but project workspace rows have not been synced."
                    : "Project graph is implemented but no project workspaces are currently known.",
                healthyDetail: "Project graph rows are populated.",
                suggestedCommand: knownWorkspaceCount > 0 ? "cider-cli item sync-project <project-id-or-name> --json" : nil,
                needsWorkWhenEmpty: knownWorkspaceCount > 0,
                needsWorkState: "needs_sync"
            ),
            component(
                id: "capture_events",
                table: "capture_events",
                label: "Capture events",
                count: captureEventCount,
                emptyDetail: "Capture provenance is implemented but no captures have been recorded yet.",
                healthyDetail: "Capture event provenance is populated."
            ),
            component(
                id: "capture_attachments",
                table: "capture_attachments",
                label: "Capture attachments",
                count: captureAttachmentCount,
                emptyDetail: captureEventCount > 0
                    ? "Capture attachment provenance is empty despite existing capture events."
                    : "Attachment-level provenance is implemented but no attachment captures have been recorded yet.",
                healthyDetail: "Capture attachment provenance is populated.",
                suggestedCommand: captureEventCount > 0 ? "cider-cli item backlinks capture_event <capture-event-id> --json" : nil,
                needsWorkWhenEmpty: captureEventCount > 0,
                needsWorkState: "needs_review"
            ),
            component(
                id: "content_chunks",
                table: "content_chunks",
                label: "Content chunks",
                count: chunkCount,
                emptyDetail: itemCount > 0
                    ? "Content chunking is implemented but indexed chunks are empty."
                    : "Content chunking is implemented but no items are available to index yet.",
                healthyDetail: "Content chunks are populated.",
                suggestedCommand: "cider-cli item rebuild-chunks all --json",
                needsWorkWhenEmpty: itemCount > 0
            ),
            component(
                id: "enrichment_outputs",
                table: "enrichment_outputs",
                label: "Enrichment outputs",
                count: enrichmentCount,
                emptyDetail: chunkCount > 0
                    ? "Enrichment output storage is implemented but no extracted outputs exist."
                    : "Enrichment output storage is implemented but waits for content chunks.",
                healthyDetail: "Structured enrichment outputs are populated.",
                emptyReason: chunkCount > 0 ? "unseeded" : "waiting_for_content_chunks",
                suggestedCommand: chunkCount > 0 ? "cider-cli item dogfood-intelligence --limit 5 --json" : nil,
                needsWorkWhenEmpty: chunkCount > 0
            ),
            component(
                id: "similarity_candidates",
                table: "similarity_candidates",
                label: "Similarity candidates",
                count: similarityCount,
                emptyDetail: chunkCount > 1
                    ? "Similarity candidate storage is implemented but no reviewable candidates exist."
                    : "Similarity candidate storage is implemented but waits for enough chunks to compare.",
                healthyDetail: "Reviewable similarity/grouping candidates are populated.",
                emptyReason: chunkCount > 1 ? "unseeded" : "waiting_for_comparable_chunks",
                suggestedCommand: chunkCount > 1 ? "cider-cli item dogfood-intelligence --limit 5 --json" : nil,
                needsWorkWhenEmpty: chunkCount > 1
            ),
        ]

        let states = Set(components.compactMap { $0["state"] as? String })
        let status: String
        if states.contains("not_implemented") {
            status = "not_implemented"
        } else if states.contains("needs_sync") {
            status = "needs_sync"
        } else if states.contains("needs_rebuild") {
            status = "needs_rebuild"
        } else if states.contains("needs_review") {
            status = "needs_review"
        } else if states.contains("implemented_empty") {
            status = "implemented_empty"
        } else {
            status = "healthy"
        }

        let integrity = try db.integrityCheck()
        return [
            "ok": integrity.isHealthy && !states.contains("not_implemented"),
            "command": "item.graph-health",
            "readOnly": true,
            "status": status,
            "schemaVersion": DatabaseMigrations.latestVersion,
            "integrity": [
                "healthy": integrity.isHealthy,
                "messages": integrity.messages,
            ],
            "counts": [
                "items": itemCount,
                "knownProjectWorkspaces": knownWorkspaceCount,
            ],
            "components": components,
            "suggestedCommands": suggestedCommands,
            "suggestedActions": suggestedActions,
        ]
    }

    private static func graphHealthSuggestedAction(for command: String) -> [String: Any] {
        var action: [String: Any] = [
            "command": command,
            "readOnly": false,
            "requiresApproval": true,
        ]

        if command.contains(" backfill-kanban ") {
            action["mutationReason"] = "rebuild_kanban_projection"
        } else if command.contains(" rebuild-references ") {
            action["mutationReason"] = "rebuild_owner_relations"
        } else if command.contains(" sync-project ") {
            action["mutationReason"] = "sync_project_graph"
        } else if command.contains(" rebuild-chunks ") {
            action["mutationReason"] = "rebuild_content_chunks"
        } else if command.contains(" dogfood-intelligence ") {
            action["mutationReason"] = "seed_reviewable_intelligence"
        } else if command.contains(" repair-schema ") {
            action["mutationReason"] = "repair_schema"
        } else if command.contains(" backlinks ") {
            action["readOnly"] = true
            action["requiresApproval"] = false
            action["mutationReason"] = "inspect_capture_backlinks"
        } else {
            action["mutationReason"] = "follow_up"
        }
        return action
    }

    static func secondBrainDoctorStatus() throws -> [String: Any] {
        let expected = [
            "item_sections",
            "content_chunks",
            "content_chunks_fts",
            "routing_decisions",
            "agent_actions",
            "owner_relations",
            "projects",
            "capture_events",
            "enrichment_outputs",
            "similarity_candidates",
        ]
        let tableRows = try expected.map { table -> [String: Any] in
            let existsStmt = try CiderDatabase.shared.prepare(
                "SELECT count(*) FROM sqlite_master WHERE name = ?;"
            )
            existsStmt.bind(table, at: 1)
            try existsStmt.step()
            let exists = existsStmt.int(at: 0) == 1

            var row: [String: Any] = [
                "name": table,
                "exists": exists,
            ]
            if exists, table != "content_chunks_fts" {
                let countStmt = try CiderDatabase.shared.prepare("SELECT count(*) FROM \(table);")
                try countStmt.step()
                row["count"] = countStmt.int(at: 0)
            }
            return row
        }
        let integrity = try CiderDatabase.shared.integrityCheck()
        return [
            "ok": tableRows.allSatisfy { $0["exists"] as? Bool == true } && integrity.isHealthy,
            "schemaVersion": DatabaseMigrations.latestVersion,
            "integrity": integrity.messages,
            "tables": tableRows,
        ]
    }

    /// Split a CSV argument into individual ID prefixes, trimming whitespace
    /// and skipping empties. Returns an array even for a single value.
    /// Used by bulk move / tag commands: `cider-cli bookmark move a,b,c ...`.
    static func splitIDs(_ arg: String) -> [String] {
        arg.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseBoardTagFilters(from args: [String]) -> [String]? {
        var values: [String] = []
        var i = 0
        while i < args.count {
            let token = args[i]
            guard token == "--tag" || token == "--tags" else {
                i += 1
                continue
            }
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
                printCLIError("\(token) requires a tag value.\nUsage: cider-cli board show <board> [--tag <tag>] [--tags <csv>] [--json]")
                return nil
            }
            values.append(args[i + 1])
            i += 2
        }
        return KanbanCardTagTaxonomy.normalizedTags(from: values)
    }

    /// Parse every occurrence of `--flag <value>` in `args`. Used for
    /// subcommands that accept repeated flags (e.g. `--tag a --tag b`).
    static func parseFlagAll(_ flag: String, from args: [String]) -> [String] {
        var values: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == flag, i + 1 < args.count {
                values.append(args[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return values
    }

    static func findFolder(named name: String) -> VaultFolder? {
        VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        })
    }

    /// Strict folder lookup for destructive operations (delete/move/rename).
    /// Resolution order:
    ///   1. If the input contains '/', match by `relativePath` exact
    ///      (case-insensitive) — unique by schema
    ///   2. Else try leaf-name match. If multiple folders share the name,
    ///      return nil and print the ambiguity so the caller can retry with
    ///      a full path
    ///   3. Else fall back to id-prefix match
    /// Never creates folders, never touches disk.
    static func findFolderStrict(_ nameOrPath: String) -> VaultFolder? {
        let folders = VaultFolderService.shared.folders

        // 1. Path match (unambiguous — relative_path is UNIQUE in schema)
        if nameOrPath.contains("/") {
            if let exact = folders.first(where: {
                $0.relativePath.localizedCaseInsensitiveCompare(nameOrPath) == .orderedSame
            }) {
                return exact
            }
            print("Error: No folder found at path '\(nameOrPath)'")
            return nil
        }

        // 2. Name match with ambiguity check
        let nameMatches = folders.filter {
            $0.name.localizedCaseInsensitiveCompare(nameOrPath) == .orderedSame
        }
        if nameMatches.count == 1 {
            return nameMatches[0]
        }
        if nameMatches.count > 1 {
            print("Error: Name '\(nameOrPath)' is ambiguous — matches \(nameMatches.count) folders:")
            for f in nameMatches {
                print("  - \(f.relativePath)")
            }
            print("Pass the full vault-relative path to disambiguate (e.g. 'Food/Restaurants').")
            return nil
        }

        // 3. Fall back to id-prefix match
        let lower = nameOrPath.lowercased()
        let prefixMatches = folders.filter { $0.id.uuidString.lowercased().hasPrefix(lower) }
        if prefixMatches.count == 1 {
            return prefixMatches[0]
        }
        if prefixMatches.count > 1 {
            print("Error: ID prefix '\(nameOrPath)' is ambiguous — matches \(prefixMatches.count) folders:")
            for f in prefixMatches {
                print("  - [\(f.id.uuidString.prefix(8))] \(f.relativePath)")
            }
            return nil
        }

        print("Error: No folder found matching '\(nameOrPath)'")
        return nil
    }

    /// Result of resolving a `--folder` / `--path` flag from args.
    /// Distinguishes "user did not specify a folder" (caller may default to
    /// Inbox) from "user specified one but it didn't resolve" (caller MUST
    /// bail — error has already been printed). Eliminates the silent
    /// false-success where missing folders made write commands no-op to Inbox.
    enum FolderArgResolution {
        case unspecified
        case resolved(VaultFolder)
        case failed
    }

    static func folderArgFailurePayload(
        ref: String,
        error: String,
        matches: [VaultFolder] = [],
        blockingIssue: String = "folder_unresolved"
    ) -> [String: Any] {
        let safeNextCommands = [
            "cider-cli item owner-get folder \"\(ref)\" --json",
            "cider-cli item search <query> --json",
            "cider-cli storage audit --json",
        ]
        var payload: [String: Any] = [
            "ok": false,
            "command": "folder.resolve",
            "readOnly": false,
            "changed": false,
            "error": error,
            "sourceRef": [
                "type": "folder",
                "ref": ref,
            ],
            "matches": matches
                .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                .map(folderOwnerMatchDict),
            "safeNextCommands": safeNextCommands,
        ]
        CiderAgentDecisionContract.merge(
            CiderAgentDecisionContract.dictionary(
                saved: false,
                needsReview: true,
                needsRouting: true,
                confidence: 0,
                blockingIssues: [blockingIssue],
                recommendedNextAction: "review_route",
                safeNextCommands: safeNextCommands
            ),
            into: &payload
        )
        return payload
    }

    static func printFolderArgResolutionFailure(
        ref: String,
        error: String,
        matches: [VaultFolder] = [],
        blockingIssue: String = "folder_unresolved"
    ) {
        processExitCode = 1
        if jsonOutput {
            outputJSON(folderArgFailurePayload(
                ref: ref,
                error: error,
                matches: matches,
                blockingIssue: blockingIssue
            ))
        } else {
            print("Error: \(error)")
            for match in matches.sorted(by: { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) {
                print("  \(match.relativePath) (\(match.id.uuidString))")
            }
        }
    }

    /// Path-aware resolution of `--folder` / `--path`. `--path` intentionally
    /// creates missing components. `--folder` is read-only and only resolves
    /// folders already registered in canonical storage.
    static func resolveFolderArg(from args: [String]) -> FolderArgResolution {
        if let path = parseFlag("--path", from: args) {
            if looksLikeVaultArtifactPath(path) {
                let parentPath = parentFolderPath(forArtifactPath: path) ?? "<folder-path>"
                printCLIError(
                    "`--path \(path)` looks like a file path, but this command expects a target folder path. Use `--folder \(parentPath)` or `--path \(parentPath)` to move into the containing folder."
                )
                return .failed
            }
            if let folder = findOrCreateFolderByPath(path) {
                return .resolved(folder)
            }
            print("Error: Could not resolve or create folder path '\(path)'")
            return .failed
        }
        if let name = parseFlag("--folder", from: args) {
            switch resolveFolderOwner(ref: name) {
            case .folder(let folder):
                return .resolved(folder)
            case .inbox:
                printFolderArgResolutionFailure(
                    ref: name,
                    error: "`--folder \(name)` refers to Inbox. Use item unfile/review approve for Inbox workflows instead of moving to a synthetic Inbox folder.",
                    blockingIssue: "folder_ref_is_inbox"
                )
                return .failed
            case .ambiguous(let matches):
                printFolderArgResolutionFailure(
                    ref: name,
                    error: "Ambiguous folder reference '\(name)'. Use one of the returned relativePath or id values.",
                    matches: matches,
                    blockingIssue: "folder_ref_ambiguous"
                )
                return .failed
            case .missing:
                printFolderArgResolutionFailure(
                    ref: name,
                    error: "No folder found matching '\(name)'. Use --path to create a folder path, or pass an existing folder id/relativePath.",
                    blockingIssue: "folder_ref_missing"
                )
                return .failed
            }
        }
        return .unspecified
    }

    /// `capture add --path` is the canonical source-file flag, so capture target
    /// placement only honors `--folder`.
    static func resolveCaptureFolderArg(from args: [String], source: CaptureAddSource) -> FolderArgResolution {
        guard let name = parseFlag("--folder", from: args) else {
            return .unspecified
        }
        if name.contains("/") {
            if name.hasPrefix("Inbox/") || name.localizedCaseInsensitiveCompare("Inbox") == .orderedSame {
                let expectedPath = canonicalInboxPath(for: source)
                guard name.localizedCaseInsensitiveCompare(expectedPath) == .orderedSame else {
                    printCLIError("`--folder \(name)` is a canonical Inbox path for another item type. Use `--folder \(expectedPath)` for this capture, or choose a non-Inbox vault folder path.")
                    return .failed
                }
                return .unspecified
            }
            if let folder = findOrCreateFolderByPath(name) {
                return .resolved(folder)
            }
            printCLIError("Could not resolve or create capture target folder '\(name)'")
            return .failed
        }
        switch resolveFolderOwner(ref: name) {
        case .folder(let folder):
            return .resolved(folder)
        case .inbox:
            return .unspecified
        case .ambiguous(let matches):
            printFolderArgResolutionFailure(
                ref: name,
                error: "Ambiguous folder reference '\(name)'. Use one of the returned relativePath or id values.",
                matches: matches,
                blockingIssue: "folder_ref_ambiguous"
            )
            return .failed
        case .missing:
            printFolderArgResolutionFailure(
                ref: name,
                error: "No folder found matching '\(name)'. Pass an existing folder id/relativePath.",
                blockingIssue: "folder_ref_missing"
            )
            return .failed
        }
    }

    static func canonicalInboxPath(for source: CaptureAddSource) -> String {
        switch source {
        case .inferred(let raw):
            if looksLikeURL(raw) { return "Inbox/Bookmarks" }
            if FileManager.default.fileExists(atPath: NSString(string: raw).expandingTildeInPath) {
                return "Inbox/Files"
            }
            return "Inbox/Notes"
        case .note:
            return "Inbox/Notes"
        case .todo:
            return "Inbox/Todos"
        case .bookmark:
            return "Inbox/Bookmarks"
        case .file:
            return "Inbox/Files"
        case .event:
            return "Inbox/Date Cards"
        case .contact:
            return "Inbox/Contacts"
        case .journal:
            return "Inbox/Notes"
        }
    }

    static func looksLikeURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    static func looksLikeVaultArtifactPath(_ path: String) -> Bool {
        VaultFolder.looksLikeVaultArtifactPath(path)
    }

    static func parentFolderPath(forArtifactPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }

    static func routingTarget(for folder: VaultFolder?, inboxPath: String) -> CiderRoutingDecisionTarget {
        if let folder {
            return CiderRoutingDecisionTarget(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }
        return CiderRoutingDecisionTarget(
            kind: "inbox",
            name: inboxPath,
            relativePath: inboxPath,
            folderID: nil
        )
    }

    /// Resolves a vault-relative path (e.g. "People/Baine") to a registered VaultFolder.
    /// Creates the directory and registers each path component if needed.
    static func findOrCreateFolderByPath(_ relativePath: String) -> VaultFolder? {
        let vaultURL = StoragePaths.cachedVaultDirectoryURL

        // Ensure the full directory exists on disk
        let fullURL = vaultURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: fullURL, withIntermediateDirectories: true)

        // Check if this exact path is already registered
        if let existing = VaultFolderService.shared.folders.first(where: {
            $0.relativePath.localizedCaseInsensitiveCompare(relativePath) == .orderedSame
        }) {
            return existing
        }

        // Walk the path and register each component
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }

        var currentPath = ""
        var parentID: UUID?
        var lastFolder: VaultFolder?

        for component in components {
            currentPath = currentPath.isEmpty ? component : currentPath + "/" + component

            let existing = VaultFolderService.shared.folders.first(where: {
                $0.relativePath.localizedCaseInsensitiveCompare(currentPath) == .orderedSame
            })

            if let existing {
                parentID = existing.id
                lastFolder = existing
            } else {
                if let created = VaultFolderService.shared.createFolder(name: component, parentID: parentID) {
                    parentID = created.id
                    lastFolder = created
                } else {
                    return nil
                }
            }
        }
        return lastFolder
    }

    static func findBookmark(_ idPrefix: String, in service: VaultBookmarkService) -> Bookmark? {
        let bm = service.bookmarks.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) })
        if bm == nil { printCLIError("No bookmark found with ID prefix: \(idPrefix)") }
        return bm
    }

    static func findNote(_ idPrefix: String, in storage: NotesStorage) -> Note? {
        let note = storage.notes.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) })
        if note == nil { printCLIError("No note found with ID prefix: \(idPrefix)") }
        return note
    }

    static func findContact(_ ref: String, in storage: ContactStorage) -> ContactCard? {
        resolveContact(ref, in: storage, reportErrors: true)
    }

    static func resolveContact(_ ref: String, in storage: ContactStorage, reportErrors: Bool) -> ContactCard? {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let lowercased = normalized.lowercased()

        if let contact = storage.contacts.first(where: {
            $0.id.uuidString.lowercased().hasPrefix(lowercased)
        }) {
            return contact
        }

        let exactMatches = storage.contacts.filter {
            $0.displayName.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }
        if exactMatches.count > 1 {
            if reportErrors {
                print("Error: Multiple contacts named '\(normalized)'. Use an ID prefix.")
            }
            return nil
        }

        let containsMatches = storage.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(normalized)
        }
        if containsMatches.count == 1 {
            return containsMatches[0]
        }
        if containsMatches.count > 1 {
            if reportErrors {
                print("Error: Multiple contacts match '\(normalized)':")
                for contact in containsMatches {
                    print("  [\(contact.id.uuidString.prefix(8))] \(contact.displayName)")
                }
            }
            return nil
        }

        if reportErrors {
            print("Error: No contact found with ID prefix or name: \(normalized)")
        }
        return nil
    }

    static func leadingPositionalArgs(from args: [String]) -> [String] {
        var values: [String] = []
        for arg in args {
            if arg.hasPrefix("--") { break }
            values.append(arg)
        }
        return values
    }

    static func captureSourceContext(from args: [String], originalText: String?) -> CaptureSourceContext? {
        let surface = parseFlag("--surface", from: args)
        let channel = parseFlag("--channel", from: args)
        let channelID = parseFlag("--channel-id", from: args)
        let threadID = parseFlag("--thread-id", from: args)
        let messageID = parseFlag("--message-id", from: args)
        let senderID = parseFlag("--sender-id", from: args)
        let senderName = parseFlag("--sender-name", from: args)
        let metadataPairs = parseFlagAll("--source-meta", from: args)
        var metadata: [String: String] = [:]
        for pair in metadataPairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            metadata[parts[0]] = parts[1]
        }

        let hasStructuredContext = [
            surface, channel, channelID, threadID, messageID, senderID, senderName,
        ].contains { ($0 ?? "").isEmpty == false } || !metadata.isEmpty
        let hasOriginalText = (originalText ?? "").isEmpty == false
        guard hasStructuredContext || hasOriginalText else { return nil }

        return CaptureSourceContext(
            surface: surface,
            channel: channel,
            channelID: channelID,
            threadID: threadID,
            messageID: messageID,
            senderID: senderID,
            senderName: senderName,
            originalText: originalText,
            attachments: [],
            metadata: metadata
        )
    }

    static func hasHelpArg(_ args: [String]) -> Bool {
        args.contains("help") || args.contains("--help") || args.contains("-h")
    }

    static func nonFlagArgs(_ args: [String]) -> [String] {
        args.filter { !$0.hasPrefix("--") }
    }

    static func resolveLinkPair(
        from args: [String],
        service: ItemLinkService
    ) throws -> (source: LibraryEntityRef, target: LibraryEntityRef) {
        let positional = nonFlagArgs(args)
        guard positional.count >= 4 else {
            throw ItemLinkService.LinkError.unsupportedType(
                "Usage: cider-cli link add <source-type> <source-ref> <target-type> <target-ref>"
            )
        }
        let sourceType = try ItemLinkService.entityType(from: positional[0])
        let targetType = try ItemLinkService.entityType(from: positional[2])
        let source = try service.resolve(type: sourceType, ref: positional[1])
        let target = try service.resolve(type: targetType, ref: positional[3])
        return (source, target)
    }

    static func resolveSingleLinkRef(
        from args: [String],
        service: ItemLinkService
    ) throws -> LibraryEntityRef {
        let positional = nonFlagArgs(args)
        guard positional.count >= 2 else {
            throw ItemLinkService.LinkError.unsupportedType(
                "Usage: cider-cli link list <type> <ref>"
            )
        }
        let type = try ItemLinkService.entityType(from: positional[0])
        return try service.resolve(type: type, ref: positional[1])
    }

    static func printLinkMutation(
        action: String,
        source: LibraryEntityRef,
        target: LibraryEntityRef,
        service: ItemLinkService
    ) {
        if jsonOutput {
            outputJSON([
                "action": action,
                "source": linkRefToDict(source, service: service),
                "target": linkRefToDict(target, service: service)
            ])
        } else {
            let sourceTitle = service.summary(for: source)?.title ?? source.entityID.uuidString
            let targetTitle = service.summary(for: target)?.title ?? target.entityID.uuidString
            print("\(action.capitalized): \(source.type.rawValue) '\(sourceTitle)' <-> \(target.type.rawValue) '\(targetTitle)'")
        }
    }

    static func printLinkSummaries(_ refs: [LibraryEntityRef], service: ItemLinkService) {
        let rows = refs.map { linkRefToDict($0, service: service) }
        if jsonOutput {
            outputJSON(rows)
        } else if rows.isEmpty {
            print("No links found.")
        } else {
            for row in rows {
                let type = row["type"] as? String ?? "item"
                let id = row["id"] as? String ?? ""
                let title = row["title"] as? String ?? "(untitled)"
                let subtitle = row["subtitle"] as? String ?? ""
                print("  [\(id.prefix(8))] \(type): \(title)\(subtitle.isEmpty ? "" : " — \(subtitle)")")
            }
        }
    }

    static func linkRefToDict(_ ref: LibraryEntityRef, service: ItemLinkService) -> [String: Any] {
        let summary = service.summary(for: ref)
        var dict: [String: Any] = [
            "type": ref.type.rawValue,
            "id": ref.entityID.uuidString
        ]
        if let summary {
            dict["title"] = summary.title
            dict["subtitle"] = summary.subtitle
            dict["symbol"] = summary.symbol
        }
        return dict
    }

    static func readContactProfileJSON(from args: [String]) -> String? {
        if let inline = parseFlag("--profile-json", from: args) {
            if inline == "-" {
                return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
            }
            return inline
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
        }

        if let path = parseFlag("--profile-file", from: args) {
            let expanded = NSString(string: path).expandingTildeInPath
            do {
                return try String(contentsOfFile: expanded, encoding: .utf8)
            } catch {
                print("Error: Could not read profile file '\(expanded)': \(error.localizedDescription)")
                return nil
            }
        }

        print("Error: --profile-json <json> or --profile-file <path> required")
        return nil
    }

    static func contactProfileOutput(_ contact: ContactCard) -> [String: Any] {
        var dict = ContactProfileJSON.profileDictionary(for: contact)
        dict["folder"] = contact.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
        dict["folderID"] = contact.folderID?.uuidString as Any
        return dict
    }

    static func contactProfileEnvelope(
        _ contact: ContactCard,
        action: String,
        readOnly: Bool,
        changed: Bool
    ) -> [String: Any] {
        var dict = contactProfileOutput(contact)
        dict["ok"] = true
        dict["command"] = "contact.profile"
        dict["action"] = action
        dict["contact"] = contactIdentityDict(contact)
        dict["readOnly"] = readOnly
        dict["changed"] = changed
        dict["safeNextCommands"] = contactSafeNextCommands(contact)
        if !readOnly {
            dict["mutationSource"] = "contact.profile.apply"
        }
        return dict
    }

    static func contactFieldToDict(_ field: ContactCustomField) -> [String: Any] {
        [
            "id": field.id.uuidString,
            "section": field.section,
            "label": field.label,
            "value": field.value,
            "kind": field.kind.rawValue,
            "pinned": field.isPinned
        ]
    }

    static func contactFieldEnvelope(
        contact: ContactCard,
        action: String,
        readOnly: Bool,
        changed: Bool,
        field: ContactCustomField? = nil,
        fields: [[String: Any]]? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "ok": true,
            "command": "contact.field",
            "action": action,
            "contact": contactIdentityDict(contact),
            "readOnly": readOnly,
            "changed": changed,
            "safeNextCommands": contactSafeNextCommands(contact)
        ]
        if let field {
            dict["field"] = contactFieldToDict(field)
        }
        if let fields {
            dict["fields"] = fields
        }
        if !readOnly {
            dict["mutationSource"] = "contact.field.\(contactFieldMutationVerb(for: action))"
        }
        return dict
    }

    static func contactFieldMutationVerb(for action: String) -> String {
        switch action {
        case "added": return "add"
        case "updated": return "update"
        case "deleted": return "delete"
        default: return action
        }
    }

    static func contactIdentityDict(_ contact: ContactCard) -> [String: Any] {
        [
            "id": contact.id.uuidString,
            "displayName": contact.displayName
        ]
    }

    static func contactSafeNextCommands(_ contact: ContactCard) -> [String] {
        let id = String(contact.id.uuidString.prefix(8))
        return [
            "cider-cli contact profile show \(id) --json",
            "cider-cli contact field list \(id) --json"
        ]
    }

    static func resolveContactFieldIndex(_ ref: String, in contact: ContactCard) -> Int? {
        let lowercased = ref.lowercased()
        if let idx = contact.customFields.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(lowercased) }) {
            return idx
        }

        let exact = contact.customFields.indices.filter {
            contact.customFields[$0].label.localizedCaseInsensitiveCompare(ref) == .orderedSame
                || "\(contact.customFields[$0].section)/\(contact.customFields[$0].label)".localizedCaseInsensitiveCompare(ref) == .orderedSame
        }
        if exact.count == 1 { return exact[0] }

        let contains = contact.customFields.indices.filter {
            contact.customFields[$0].label.localizedCaseInsensitiveContains(ref)
                || contact.customFields[$0].section.localizedCaseInsensitiveContains(ref)
        }
        return contains.count == 1 ? contains[0] : nil
    }

    static func parseContactFieldKind(from args: [String]) -> ContactCustomFieldKind {
        guard let raw = parseFlag("--kind", from: args)?.lowercased() else { return .text }
        return ContactCustomFieldKind(rawValue: raw) ?? .text
    }

    static func parseOptionalBoolFlag(_ flag: String, from args: [String]) -> Bool? {
        guard let raw = parseFlag(flag, from: args)?.lowercased() else { return nil }
        switch raw {
        case "true", "yes", "1", "on":
            return true
        case "false", "no", "0", "off":
            return false
        default:
            return nil
        }
    }

    static func printContactProfile(_ contact: ContactCard) {
        let birthday = contact.birthday.map(ContactProfileJSON.formatBirthday) ?? "(none)"
        let folder = contact.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
        print("Contact Profile: \(contact.displayName)")
        print("  ID:           \(contact.id.uuidString)")
        print("  Folder:       \(folder)")
        print("  Relationship: \(contact.relationshipLabel.isEmpty ? "(none)" : contact.relationshipLabel)")
        print("  Birthday:     \(birthday)")
        print("  Email:        \(contact.email.isEmpty ? "(none)" : contact.email)")
        print("  Phone:        \(contact.phone.isEmpty ? "(none)" : contact.phone)")
        print("  Address:      \(contact.address.isEmpty ? "(none)" : contact.address)")
        print("  Linked:       \(contact.linkedEntities.count)")
        print("  Fields:       \(contact.customFields.count)")
        print("  Notes:")
        print(contact.notes.isEmpty ? "(empty)" : contact.notes)
    }

    static func printUsage() {
        print("""
        CiderCLI — Second Brain v1 agent API

        CAPTURE
          cider-cli capture add [--kind note|todo|bookmark|file|event|contact|journal] (--stdin|--text-file <text-file-path>|--url <url>|--path <source-file-path>|--content <text>) [--title <title>] [--date yyyy-MM-dd|today] [--details <text>] [--name <name>] [--folder <target-folder-path>] [--timeout <seconds>|--no-wait] [--json]
          cider-cli capture review-queue [--limit <n>] [--include-deferred] [--json]

        ITEM
          cider-cli item search <query> [--space <space-id|name>] [--limit <n>] [--json]
          cider-cli item search-debug <query> [--limit <n>] [--json]
          cider-cli item get <type> <id-or-ref> [--json]
          cider-cli item owner-get <owner-type> <owner-id-or-ref> [--json]
            Use owner-get folder <id|path|name|Inbox> for read-only folder metadata, counts, and health.
          cider-cli item open <type> <id-or-ref> [--json]
          cider-cli item context <type> <id-or-ref> [--max-sections <n>] [--max-chunks <n>] [--max-related <n>] [--max-history <n>] [--max-body <chars>] [--json]
          cider-cli item related <type> <id-or-ref> [--json]
          cider-cli item relations <owner-type> <owner-id-or-ref> [--json]
          cider-cli item backlinks <owner-type> <owner-id-or-ref> [--json]
          cider-cli item related-owners <owner-type> <owner-id-or-ref> [--json]
          cider-cli item why-surfaced <type> <id-or-ref> [--json]
          cider-cli item capability-map [--json]
          cider-cli item graph-health [--json]
          cider-cli item project-context <project-id-or-name> [--summary] [--limit <n>] [--full] [--json]
          cider-cli item link <source-type> <source-ref> <target-type> <target-ref>
          cider-cli item batch-plan --stdin [--json]
          cider-cli item batch-apply --stdin --approve <token> --execute [--actor <name>] [--json]
          cider-cli item move <type> <id-or-ref> (--folder <name|path>|--path <target-folder-path>) [--actor <name>] [--source <source>] [--json]
          cider-cli item unfile <type> <id-or-ref> [--actor <name>] [--source <source>] [--json]
          cider-cli item delete <type> <id-or-ref> --reason <text> [--approve <token> --execute] [--actor <name>] [--source <source>] [--json]
          cider-cli item route <type> <id-or-ref> --target-type <space|folder|board> [--target-id <id>] [--target-path <path>] --reason <text> [--confidence <0-1>] [--status accepted|needs_review] [--actor <name>] [--source <source>] [--json]
          cider-cli item doctor [--json]

        EXPORT
          cider-cli export folder <relative-path|id|Inbox> --format json|md [--limit <n>] [--json]
          cider-cli export item <type> <id-or-ref> --format json|md [--json]
          cider-cli export card <board-id/card-id|card-id> --format json|md [--json]
          cider-cli export project <project-id-or-name> --format json|md [--limit <n>] [--json]
            Whole-vault export is intentionally refused; export bounded scopes.

        REVIEW
          cider-cli review list [--include-deferred] [--limit <n>] [--json]
          cider-cli review summary [--include-deferred] [--json]
          cider-cli review drilldown <group-id> [--limit <n>] [--offset <n>] [--json]
          cider-cli review enrichment-diagnosis [--sample-limit <n>] [--json]
          cider-cli review enrichment-reconcile-plan [--sample-limit <n>] [--json]
          cider-cli review enrichment-reconcile-samples [--group <group-id>] [--limit <n>] [--json]
          cider-cli review enrichment-reconcile-apply [--group <group-id>] [--limit <n>] [--approve <token>] [--actor user|agent] [--execute] [--json]
          cider-cli review approve <item-id> [--actor user|agent] [--json]
          cider-cli review correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]
          cider-cli review defer <item-id> [--reason <text>] [--actor user|agent] [--json]
          cider-cli review enrich <item-id> [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]
          cider-cli review enrich-batch --confirm [--actor user|agent] [--timeout <seconds>|--no-wait] [--json]
          cider-cli review jobs [--limit <n>] [--json]

        ROUTE
          cider-cli route explain <item-id> [--json]
          cider-cli route approve <item-id> [--actor user|agent] [--json]
          cider-cli route correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) [--reason <text>] [--actor user|agent] [--json]
          cider-cli route rerun <item-id> [--actor user|agent] [--json]

        STORAGE
          cider-cli storage audit [--json]
          cider-cli storage doctor-plan [--limit <n>] [--json]
          cider-cli storage doctor-apply --finding <id> --canonical <path> --duplicate <path> --approve <token> [--execute] [--json]
          cider-cli storage bookmark-drift-audit [--limit <n>] [--json]
          cider-cli storage bookmark-drift-repair --item <id> --approve <token> [--execute] [--json]
          cider-cli storage repair-schema [--approve REPAIR_SCHEMA] [--execute] [--json]

        MIGRATE
          cider-cli item backfill-kanban [--board <name-or-id>] [--json]
          cider-cli item rebuild-references <note|card|board> <id-or-ref> [--json]
          cider-cli item rebuild-chunks <type|all> [id-or-ref] [--limit <n>] [--json]
          cider-cli item rebuild-enrichment <owner-type> <owner-id-or-ref> [--json]
          cider-cli item rebuild-similarity <owner-type> <owner-id-or-ref> [--threshold <0-1>] [--limit <n>] [--json]
          cider-cli item dogfood-intelligence [--limit <n>] [--threshold <0-1>] [--candidate-limit <n>] [--json]
          cider-cli item sync-project <project-id-or-name> [--json]

        DOCTOR
          cider-cli item doctor [--json]
          cider-cli item capability-map [--json]
          cider-cli item graph-health [--json]
          cider-cli storage audit [--json]
          cider-cli db integrity

        BOARD WORKFLOW
          cider-cli board list
          cider-cli board show <board-name-or-id> [--tag <tag>] [--tags <csv>] [--json]
          cider-cli board tags [--json]
          cider-cli board recent <board> [--limit <count>] [--json]
          cider-cli board testing-summary <board> [--json]
          cider-cli board parent-summary <board> --card <id> [--refresh --dry-run|--confirm] [--json]
          cider-cli board card inspect <board> --card <id> [--json]
          cider-cli board create <name> [--project <project-id-or-name>]
          cider-cli board rename <name|id> --to <new-name>
          cider-cli board delete <name|id>
          cider-cli board add-card <board> --column <col> --title <title> [--notes <text>] [--priority low|medium|high] [--parent <card-id>] [--after <sibling-id>]
          cider-cli board update-card <board> --card <id> [--title <title>] [--notes <text>] [--clear-notes]
                                         [--priority low|medium|high|none] [--agent <name>] [--clear-agent]
                                         [--tags <csv>] [--clear-tags] [--color blue|green|orange|red|purple|none]
                                         [--parent <card-id>] [--clear-parent]
          cider-cli board section update <board> --card <id> --section <name> --value <text> [--json]
          cider-cli board evidence add <board> --card <id> --text <text> [--source <source>] [--json]
          cider-cli board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text> [--source <source>] [--json]
          cider-cli board move-card <board> --card <id> --to <column>
          cider-cli board delete-card <board> --card <id>
          cider-cli board workflow <board> [--json]
          cider-cli board testing-summary <board> [--json]
          cider-cli board parent-summary <board> --card <id> [--refresh --dry-run|--confirm] [--json]
          cider-cli board children <board> --card <id> [--json]
          cider-cli board add-column <board> --name <col-name> [--done]
          cider-cli board rename-column <board> --column <col> --to <new-name>
          cider-cli board delete-column <board> --column <col>

        DATABASE
          cider-cli db backups
          cider-cli db backup
          cider-cli db integrity
          cider-cli db audit [--limit <n>] [--type <item-type>] [--action <action>] [--source <ui|cli|agent|migration|cleanup>] [--item <id-prefix>]
          cider-cli db restore <index|filename|latest> --yes

        GLOBAL FLAGS
          --vault <path>   Use a sandbox vault for this invocation. Bypasses
                           the user's saved CiderConfig vault path and any
                           per-type directory overrides. Prints
                           'Using sandbox vault: <path>' to stderr.
          --json           Emit machine-readable JSON output (most commands).
        """)
    }
}
