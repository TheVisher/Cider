import Foundation
import Testing
@testable import Cider

struct PrivacyProjectionPolicyTests {
    @Test("private values are preserved canonically but redacted from outward projections")
    func privateValuesAreRedactedFromOutwardProjections() {
        let fixtures: [(CiderPrivateValue.Kind, String)] = [
            (.browserURL, "https://private.example/account?token=CID833_URL_SECRET#journal"),
            (.localPath, "/Users/private/CID833_PATH_SECRET/journal.md"),
            (.sourceText, "CID833_SOURCE_TEXT_SECRET private journal paragraph"),
            (.senderIdentity, "sender-CID833_IDENTITY_SECRET@example.invalid"),
            (.processStandardError, "CID833_STDERR_SECRET provider rejected private payload")
        ]

        for (kind, sentinel) in fixtures {
            let privateValue = CiderPrivateValue(kind: kind, rawValue: sentinel)
            #expect(privateValue.rawValue == sentinel)

            for context in CiderPrivacyProjectionContext.allCases {
                let projection = CiderPrivacyProjectionPolicy.project(privateValue, for: context)
                #expect(!projection.contains(sentinel))
                #expect(!projection.contains("CID833_"))
                #expect(projection.contains(kind.rawValue))
            }
        }
    }

    @MainActor
    @Test("browser capture success projection contains an event but no captured content")
    func browserCaptureSuccessProjectionIsContentFree() {
        let result = ActiveBrowserCaptureResult(
            urlString: "https://private.example/CID833_URL_SECRET?token=private",
            title: "CID833_SOURCE_TEXT_SECRET journal title"
        )

        let message = ActiveBrowserCaptureService.captureSucceededLogMessage(for: result)

        #expect(message == "browser_capture_succeeded")
        #expect(!message.contains(result.urlString))
        #expect(!message.contains(result.title!))
        #expect(!message.contains("CID833_"))
    }
}

struct HermesProcessPrivacyTests {
    @Test("Hermes process errors preserve exit status without exposing stderr")
    func processErrorRedactsStandardError() async throws {
        let stderrSentinel = "CID833_STDERR_SECRET private child failure"
        let runner = HermesProcessRunner(
            executablePath: "/bin/sh",
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            ambientEnvironment: minimalEnvironmentFixture()
        )

        do {
            _ = try await runner.runHermes(
                arguments: ["-c", "printf '%s' '\(stderrSentinel)' >&2; exit 42"],
                timeout: 2
            )
            Issue.record("Expected the child process to fail")
        } catch let error as HermesSessionClientError {
            #expect(error.classification == .commandExited)
            #expect(error.exitStatus == 42)
            #expect(error.timeoutSeconds == nil)
            #expect(!error.localizedDescription.contains(stderrSentinel))
            #expect(!error.localizedDescription.contains("CID833_"))
        }
    }

    @Test("Hermes child environment is deny-by-default and preserves launcher variables")
    func processEnvironmentDoesNotInheritAmbientSecrets() async throws {
        let secretKey = "CIDER_CID833_PRIVATE_ENV_SECRET"
        let secretValue = "CID833_ENV_SECRET_VALUE"
        var ambient = minimalEnvironmentFixture()
        ambient[secretKey] = secretValue
        ambient["OPENAI_API_KEY"] = "CID833_OPENAI_SECRET"
        ambient["SSH_AUTH_SOCK"] = "/private/CID833_AGENT_SOCKET"

        let runner = HermesProcessRunner(
            executablePath: "/usr/bin/env",
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            ambientEnvironment: ambient
        )

        #expect(Set(runner.environment.keys) == ["HOME", "LANG", "LC_ALL", "PATH", "SHELL", "TMPDIR", "USER"])
        for key in runner.environment.keys {
            #expect(runner.environment[key] == ambient[key])
        }

        let childOutput = try await runner.runHermes(arguments: [], timeout: 2)
        let childText = String(decoding: childOutput, as: UTF8.self)
        #expect(!childText.contains(secretKey))
        #expect(!childText.contains(secretValue))
        #expect(!childText.contains("CID833_"))
        #expect(childText.contains("PATH=\(ambient["PATH"]!)"))
        #expect(childText.contains("HOME=\(ambient["HOME"]!)"))
    }

    @Test("Hermes minimal environment preserves env-based script launch behavior")
    func minimalEnvironmentLaunchesEnvShebang() async throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid833-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let scriptURL = fixtureDirectory.appendingPathComponent("hermes-launch-fixture")
        try Data("#!/usr/bin/env bash\nprintf 'CID833_LAUNCH_OK'\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let runner = HermesProcessRunner(
            executablePath: scriptURL.path,
            workingDirectoryURL: fixtureDirectory,
            ambientEnvironment: minimalEnvironmentFixture()
        )
        let output = try await runner.runHermes(arguments: [], timeout: 2)

        #expect(String(decoding: output, as: UTF8.self) == "CID833_LAUNCH_OK")
    }

    @Test("Hermes timeout reports only stable timeout facts")
    func timeoutIsClassifiedWithoutProcessText() async throws {
        let runner = HermesProcessRunner(
            executablePath: "/bin/sleep",
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            ambientEnvironment: minimalEnvironmentFixture()
        )

        do {
            _ = try await runner.runHermes(arguments: ["2"], timeout: 0.05)
            Issue.record("Expected the child process to time out")
        } catch let error as HermesSessionClientError {
            #expect(error.classification == .commandTimedOut)
            #expect(error.timeoutSeconds == 0.05)
            #expect(error.exitStatus == nil)
        }
    }

    @Test("Hermes cancellation reports only stable cancellation facts")
    func cancellationIsClassified() async throws {
        let runner = HermesProcessRunner(
            executablePath: "/bin/sleep",
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            ambientEnvironment: minimalEnvironmentFixture()
        )
        let task = Task {
            try await runner.runHermes(arguments: ["2"], timeout: 5)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the child process to be cancelled")
        } catch let error as HermesSessionClientError {
            #expect(error.classification == .commandCancelled)
            #expect(error.exitStatus == nil)
            #expect(error.timeoutSeconds == nil)
        }
    }

    @Test("Hermes unavailable executable diagnostics do not reveal a private path")
    func unavailableExecutablePathIsRedacted() async throws {
        let privatePath = "/private/CID833_PATH_SECRET/hermes"
        let runner = HermesProcessRunner(
            executablePath: privatePath,
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            ambientEnvironment: minimalEnvironmentFixture()
        )

        do {
            _ = try await runner.runHermes(arguments: [], timeout: 1)
            Issue.record("Expected an unavailable executable error")
        } catch let error as HermesSessionClientError {
            #expect(error.classification == .executableUnavailable)
            #expect(!error.localizedDescription.contains(privatePath))
            #expect(!error.localizedDescription.contains("CID833_"))
        }
    }

    private func minimalEnvironmentFixture() -> [String: String] {
        [
            "HOME": "/tmp/cider-cid833-home",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "SHELL": "/bin/zsh",
            "TMPDIR": "/tmp",
            "USER": "cid833-test"
        ]
    }
}
