import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os.log

/// Manages downloading, loading, and unloading the local MLX model.
@MainActor
final class MLXModelManager: ObservableObject {
    static let shared = MLXModelManager()

    /// Model options based on available RAM.
    enum ModelTier: String, CaseIterable {
        case small = "mlx-community/Qwen3.5-4B-MLX-4bit"   // ~2.5 GB, for 8GB Macs
        case large = "mlx-community/Qwen3.5-9B-MLX-4bit"   // ~5.5 GB, for 16GB+ Macs

        var displayName: String {
            switch self {
            case .small: "Qwen 3.5 4B (Recommended for 8GB)"
            case .large: "Qwen 3.5 9B (Recommended for 16GB+)"
            }
        }

        var downloadSizeGB: Double {
            switch self {
            case .small: 2.5
            case .large: 5.5
            }
        }
    }

    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var loadError: String?

    private let logger = Logger(subsystem: "com.cider.app", category: "MLXModelManager")
    private var modelContainer: ModelContainer?
    private var idleUnloadTask: Task<Void, Never>?

    /// Idle timeout before unloading model to free memory (5 minutes).
    private let idleTimeout: TimeInterval = 300

    // MARK: - Model Info

    /// Recommended model tier based on system RAM.
    var recommendedTier: ModelTier {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return ramGB >= 16 ? .large : .small
    }

    /// Currently selected model ID (from UserDefaults or recommended).
    var selectedModelID: String {
        get {
            UserDefaults.standard.string(forKey: "cider.mlxModelID") ?? recommendedTier.rawValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cider.mlxModelID")
        }
    }

    /// Whether the user has enabled the local model.
    var isLocalModelEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "cider.mlxModelEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "cider.mlxModelEnabled") }
    }

    // MARK: - Load / Unload

    /// Load the model into memory. Downloads on first use.
    func loadModel() async {
        guard !isModelLoaded, !isLoading else { return }
        isLoading = true
        isDownloading = true
        downloadProgress = 0
        loadError = nil

        // Set memory limits to prevent buffer bloat
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024) // 20 MB cache

        do {
            let modelID = selectedModelID
            logger.info("Loading model: \(modelID, privacy: .public)")

            let config = ModelConfiguration(id: modelID)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }

            modelContainer = container
            isModelLoaded = true
            isDownloading = false
            logger.info("Model loaded successfully")
            resetIdleTimer()
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
            isDownloading = false
        }

        isLoading = false
    }

    /// Unload the model to free memory.
    func unloadModel() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        modelContainer = nil
        isModelLoaded = false
        logger.info("Model unloaded")
    }

    // MARK: - Inference

    /// Generate a non-streaming response from the loaded model.
    nonisolated func generate(prompt: String, systemPrompt: String) async throws -> String {
        let container = await modelContainer
        guard let container else {
            throw MLXError.modelNotLoaded
        }

        await resetIdleTimer()

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]

        let output: String = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: .init(messages: messages)
            )
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.7, topP: 0.9),
                context: context
            ) { tokens in
                tokens.count < 2048 ? .more : .stop
            }
            return result.output
        }

        return output
    }

    // MARK: - Idle Timer

    /// Reset the idle timer — unloads model after `idleTimeout` of inactivity.
    private func resetIdleTimer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task {
            try? await Task.sleep(for: .seconds(idleTimeout))
            guard !Task.isCancelled else { return }
            logger.info("Idle timeout — unloading model to free memory")
            unloadModel()
        }
    }
}

enum MLXError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Local AI model is not loaded. Please enable it in Settings."
        case .generationFailed(let msg): "Generation failed: \(msg)"
        }
    }
}
