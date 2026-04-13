import Foundation
import os

// MARK: - Tool Definition

struct AgentToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: [AgentToolParameter]
    let categories: Set<ToolCategory>
    let requiresConfirmation: Bool
    let execute: @Sendable ([String: Any]) async throws -> String
}

struct AgentToolParameter: Sendable {
    let name: String
    let type: AgentToolParameterType
    let description: String
    let required: Bool
}

enum AgentToolParameterType: String, Sendable {
    case string
    case integer
    case boolean
    case number
}

enum ToolCategory: String, Sendable {
    case search
    case vaultRead
    case vaultWrite
    case vaultDelete
    case reminder
    case system
}

// MARK: - Tool Permission Level

enum ToolPermissionLevel: Sendable {
    case full        // All tools, no restrictions
    case standard    // Read + safe writes, destructive needs confirmation
    case limited     // Only tools in specific categories
}

// MARK: - Tool Registry

actor AgentToolRegistry {
    static let shared = AgentToolRegistry()
    private let logger = Logger(subsystem: "com.cider.app", category: "AgentToolRegistry")

    private(set) var tools: [AgentToolDefinition] = []

    func register(_ tool: AgentToolDefinition) {
        tools.append(tool)
        logger.debug("Registered tool: \(tool.name)")
    }

    func execute(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            logger.warning("Unknown tool requested: \(name)")
            return "Unknown tool: \(name)"
        }
        logger.info("Executing tool: \(name)")
        return try await tool.execute(arguments)
    }

    /// Return tools filtered by permission level.
    func tools(for permissionLevel: ToolPermissionLevel) -> [AgentToolDefinition] {
        switch permissionLevel {
        case .full:
            return tools
        case .standard:
            return tools.filter { !$0.categories.contains(.vaultDelete) || !$0.requiresConfirmation }
        case .limited:
            return tools.filter { $0.categories.contains(.reminder) || $0.categories.contains(.search) }
        }
    }

    /// Generate JSON schemas for all tools (used by MLX and API providers).
    func jsonSchemas(for permissionLevel: ToolPermissionLevel = .full) -> [[String: Any]] {
        tools(for: permissionLevel).map { tool in
            var schema: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]

            var properties: [String: Any] = [:]
            var required: [String] = []

            for param in tool.parameters {
                properties[param.name] = [
                    "type": param.type.rawValue,
                    "description": param.description,
                ]
                if param.required {
                    required.append(param.name)
                }
            }

            schema["parameters"] = [
                "type": "object",
                "properties": properties,
                "required": required,
            ]

            return schema
        }
    }
}
