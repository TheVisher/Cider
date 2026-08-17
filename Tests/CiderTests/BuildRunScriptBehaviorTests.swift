import Foundation
import XCTest

final class BuildRunScriptBehaviorTests: XCTestCase {
    func testBuildRunStopsArchivedNativeButPreservesUniversalApp() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cider-launch-process-test-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let processTable = root.appendingPathComponent("processes.tsv")
        let initialProcesses = """
        4242\t/Users/test/Library/Developer/Xcode/Archives/Old.xcarchive/Products/Applications/Cider.app/Contents/MacOS/Cider
        4343\t/Users/test/Applications/Universal Cider.app/Contents/MacOS/Executable
        """ + "\n"
        try initialProcesses.write(to: processTable, atomically: true, encoding: .utf8)

        try writeExecutable(
            named: "pgrep",
            in: bin,
            contents: """
            #!/bin/zsh
            pattern="${@: -1}"
            matched=1
            while IFS=$'\\t' read -r pid path; do
              if [[ -n "$pid" ]] && /usr/bin/printf '%s\\n' "$path" | /usr/bin/grep -Eq "$pattern"; then
                /usr/bin/printf '%s\\n' "$pid"
                matched=0
              fi
            done < "$CIDER_TEST_PROCESS_FILE"
            exit "$matched"
            """
        )
        try writeExecutable(
            named: "pkill",
            in: bin,
            contents: """
            #!/bin/zsh
            pattern="${@: -1}"
            temporary="$CIDER_TEST_PROCESS_FILE.tmp"
            : > "$temporary"
            while IFS=$'\\t' read -r pid path; do
              if [[ -n "$pid" ]] && /usr/bin/printf '%s\\n' "$path" | /usr/bin/grep -Eq "$pattern"; then
                continue
              fi
              if [[ -n "$pid" ]]; then
                /usr/bin/printf '%s\\t%s\\n' "$pid" "$path" >> "$temporary"
              fi
            done < "$CIDER_TEST_PROCESS_FILE"
            /bin/mv "$temporary" "$CIDER_TEST_PROCESS_FILE"
            """
        )
        try writeExecutable(named: "sleep", in: bin, contents: "#!/bin/zsh\nexit 0\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            #"""
            source "$CIDER_LAUNCH_LIBRARY"
            stop_app_definition=$(/usr/bin/awk '/^stop_app\(\) \{/{capture=1} capture{print} capture && /^}/{exit}' "$CIDER_BUILD_RUN_SCRIPT")
            eval "$stop_app_definition"
            stop_app
            """#
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        environment["CIDER_LAUNCH_LIBRARY"] = "\(fileManager.currentDirectoryPath)/script/cider_process_control.sh"
        environment["CIDER_BUILD_RUN_SCRIPT"] = "\(fileManager.currentDirectoryPath)/script/build_and_run.sh"
        environment["CIDER_TEST_PROCESS_FILE"] = processTable.path
        environment["ROOT_DIR"] = "/Users/test/CurrentRepo"
        environment["APP_NAME"] = "Cider"
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let standardError = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, standardError)
        let remaining = try String(contentsOf: processTable, encoding: .utf8)
        XCTAssertFalse(remaining.contains("Archives/Old.xcarchive"))
        XCTAssertTrue(
            remaining.contains("Universal Cider.app/Contents/MacOS/Executable"),
            "Remaining process table: \(remaining.debugDescription)"
        )
    }

    func testLaunchCiderAppForcesNewInstanceOfExactBundle() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cider-launch-open-test-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let openLog = root.appendingPathComponent("open-arguments.txt")
        let fakeOpen = root.appendingPathComponent("open")
        try """
        #!/bin/zsh
        /usr/bin/printf '%s\\n' "$@" > "$CIDER_TEST_OPEN_LOG"
        """.write(to: fakeOpen, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOpen.path)

        let expectedApp = root.appendingPathComponent("Current Swift Cider.app", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            "source \"$CIDER_LAUNCH_LIBRARY\"; launch_cider_app \"$CIDER_TEST_APP_PATH\""
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["CIDER_LAUNCH_LIBRARY"] = "\(fileManager.currentDirectoryPath)/script/cider_process_control.sh"
        environment["CIDER_OPEN_COMMAND"] = fakeOpen.path
        environment["CIDER_TEST_APP_PATH"] = expectedApp.path
        environment["CIDER_TEST_OPEN_LOG"] = openLog.path
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let standardError = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            XCTFail("Launch helper failed with status \(process.terminationStatus): \(standardError)")
            return
        }
        let arguments = try String(contentsOf: openLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, ["-n", expectedApp.path])
    }

    private func writeExecutable(named name: String, in directory: URL, contents: String) throws {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
