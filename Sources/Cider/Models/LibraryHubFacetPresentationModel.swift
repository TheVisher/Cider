import Foundation

struct LibraryHubFacetPresentationModel: Codable, Equatable {
    struct Chip: Identifiable, Codable, Equatable {
        enum Role: String, Codable, Equatable {
            case domain
            case entityType
            case alias
            case place
            case other
        }

        var id: String
        var role: Role
        var label: String
        var confidenceLabel: String
        var source: String
        var evidence: String
        var itemRefs: [String]
        var truthBoundary: String

        var accessibilityLabel: String {
            "\(role.accessibilityPrefix) facet \(label), \(confidenceLabel)"
        }
    }

    struct OpenHubAction: Identifiable, Codable, Equatable {
        var id: String
        var label: String
        var command: String
        var readOnly: Bool
        var promotesTruth: Bool
    }

    struct TruthBoundary: Codable, Equatable {
        var domainFacetsAreTruth: Bool
        var autoMutatedUserFields: Bool
        var note: String
    }

    var title: String
    var chips: [Chip]
    var openHubActions: [OpenHubAction]
    var truthBoundary: TruthBoundary

    init(hub: CiderLibraryHubReadModel, chipLimit: Int = 8, actionLimit: Int = 4) {
        title = hub.anchor.item.title
        chips = Array(
            hub.domainFacets
                .map(Self.chip)
                .sorted(by: Self.sortChips)
                .prefix(max(0, chipLimit))
        )
        openHubActions = Array(
            Self.openHubActions(from: hub.safeNextCommands)
                .prefix(max(0, actionLimit))
        )
        truthBoundary = TruthBoundary(
            domainFacetsAreTruth: false,
            autoMutatedUserFields: false,
            note: "Domain facets are interpretive metadata, not accepted truth."
        )
    }

    var isEmpty: Bool {
        chips.isEmpty && openHubActions.isEmpty
    }

    private static func chip(from facet: CiderLibraryHubDomainFacet) -> Chip {
        Chip(
            id: facet.id,
            role: Chip.Role(facetKind: facet.kind),
            label: facet.displayValue,
            confidenceLabel: facet.confidenceLabel,
            source: facet.source,
            evidence: facet.evidence,
            itemRefs: facet.itemRefs,
            truthBoundary: "interpretive_metadata_not_accepted_truth"
        )
    }

    private static func sortChips(_ lhs: Chip, _ rhs: Chip) -> Bool {
        let lhsRank = lhs.role.sortRank
        let rhsRank = rhs.role.sortRank
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
    }

    private static func openHubActions(from commands: [String]) -> [OpenHubAction] {
        var actions: [OpenHubAction] = []
        for command in commands where command.hasPrefix("cider-cli item hub ") {
            let label = openHubLabel(for: command, isFirst: actions.isEmpty)
            let id = command
            guard !actions.contains(where: { $0.id == id }) else { continue }
            actions.append(OpenHubAction(
                id: id,
                label: label,
                command: command,
                readOnly: true,
                promotesTruth: false
            ))
        }
        return actions
    }

    private static func openHubLabel(for command: String, isFirst: Bool) -> String {
        if isFirst {
            return "Open hub"
        }
        guard let query = quotedQuery(in: command), !query.isEmpty else {
            return "Open related hub"
        }
        return "Open \(query) hub"
    }

    private static func quotedQuery(in command: String) -> String? {
        guard let queryRange = command.range(of: "--query ") else { return nil }
        let tail = command[queryRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.first == "\"" else { return tail.split(separator: " ").first.map(String.init) }
        var result = ""
        var isEscaped = false
        for character in tail.dropFirst() {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }
        }
        return result
    }
}

extension LibraryHubFacetPresentationModel.Chip.Role {
    fileprivate init(facetKind: String) {
        switch facetKind {
        case "domain":
            self = .domain
        case "entity_type":
            self = .entityType
        case "alias":
            self = .alias
        case "place":
            self = .place
        default:
            self = .other
        }
    }

    fileprivate var sortRank: Int {
        switch self {
        case .domain: return 0
        case .entityType: return 1
        case .place: return 2
        case .alias: return 3
        case .other: return 4
        }
    }

    fileprivate var accessibilityPrefix: String {
        switch self {
        case .domain: return "Domain"
        case .entityType: return "Entity type"
        case .alias: return "Alias"
        case .place: return "Place"
        case .other: return "Domain"
        }
    }
}

extension CiderItemContextService {
    func libraryHubFacetPresentation(
        for ref: LibraryEntityRef,
        maxRelated: Int = 24
    ) throws -> LibraryHubFacetPresentationModel {
        let hub = try libraryHub(for: ref, maxRelated: maxRelated)
        return LibraryHubFacetPresentationModel(hub: hub)
    }
}
