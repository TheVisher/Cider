import Foundation

enum LibraryHubNavigationTarget: Equatable {
    case query(String)
    case item(LibraryEntityRef)

    init?(command: String) {
        guard let tokens = HubCommandLexer.tokens(in: command),
              tokens.count >= 4,
              tokens[0] == "cider-cli",
              tokens[1] == "item",
              tokens[2] == "hub"
        else { return nil }

        var query: String?
        var itemRef: LibraryEntityRef?
        var index = 3

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "--json":
                index += 1
            case "--limit":
                guard index + 1 < tokens.count,
                      Int(tokens[index + 1]).map({ $0 > 0 }) == true
                else { return nil }
                index += 2
            case "--query":
                guard query == nil,
                      itemRef == nil,
                      index + 1 < tokens.count
                else { return nil }
                let value = tokens[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                query = value
                index += 2
            default:
                guard query == nil, itemRef == nil else { return nil }
                if let type = LibraryEntityType(rawValue: token) {
                    guard LibraryEntityType.activeCases.contains(type),
                          index + 1 < tokens.count,
                          let id = UUID(uuidString: tokens[index + 1])
                    else { return nil }
                    itemRef = LibraryEntityRef(type: type, entityID: id)
                    index += 2
                } else {
                    let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, !value.hasPrefix("-") else { return nil }
                    query = value
                    index += 1
                }
            }
        }

        if let itemRef {
            self = .item(itemRef)
        } else if let query {
            self = .query(query)
        } else {
            return nil
        }
    }

    var readOnly: Bool { true }

    var promotesTruth: Bool { false }

    var libraryRoute: LibraryRoute? {
        switch self {
        case .query(let query):
            return .search(query)
        case .item:
            return nil
        }
    }
}

private enum HubCommandLexer {
    static func tokens(in command: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in command {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if character.isWhitespace && !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        guard !isQuoted, !isEscaped else { return nil }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
