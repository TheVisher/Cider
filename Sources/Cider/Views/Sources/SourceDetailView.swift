import SwiftUI

struct SourceDetailView: View {
    let source: ExternalSource
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double

    @ObservedObject private var registry = ExternalSourceRegistry.shared

    @State private var selectedFileID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var files: [ExternalFile] {
        registry.files(for: source.id)
    }

    private var cardMinWidth: CGFloat {
        LibraryCardSizing(scale: cardSizeScale).bookmarkSizing.cardMinWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Image(systemName: "folder.badge.gear")
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text(source.displayName)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Spacer(minLength: Spacing.sm)

                    Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)

                    Button {
                        createNewFile()
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "plus")
                                .font(CiderFont.captionSemibold)
                            Text("New File")
                                .font(CiderFont.captionMedium)
                        }
                        .foregroundColor(CiderColors.secondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.surfaceInput)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Create a new markdown file in this source")
                }

                Text(source.path)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)

            Divider()
                .background(CiderColors.separator)
                .padding(.horizontal, Spacing.md)

            if files.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - File List

    @ViewBuilder
    private var fileList: some View {
        GeometryReader { proxy in
            ScrollView {
                fileContent(containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .padding(Spacing.xxs)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    @ViewBuilder
    private func fileContent(containerWidth: CGFloat) -> some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(files) { file in
                    SourceCardView(
                        file: file,
                        width: containerWidth - Spacing.md * 2,
                        isSelected: selectedFileID == file.id,
                        onOpen: { openFile(file) },
                        onDelete: { deleteFile(file) }
                    )
                }
            }

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(files) { file in
                    SourceCardView(
                        file: file,
                        width: cardMinWidth,
                        isSelected: selectedFileID == file.id,
                        onOpen: { openFile(file) },
                        onDelete: { deleteFile(file) }
                    )
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(files) { file in
                    SourceCardView(
                        file: file,
                        width: cardMinWidth,
                        isSelected: selectedFileID == file.id,
                        onOpen: { openFile(file) },
                        onDelete: { deleteFile(file) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            Image(systemName: "folder.badge.gear")
                .font(CiderFont.heroDisplay(scale: 1.0))
                .foregroundColor(CiderColors.tertiary)

            Text("No markdown files")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)

            Text("This source folder contains no .md files yet. Click \"New File\" to create one.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openFile(_ file: ExternalFile) {
        selectedFileID = file.id
        NotificationCenter.default.post(
            name: .openExternalFile,
            object: nil,
            userInfo: ["fileURL": file.path]
        )
    }

    private func deleteFile(_ file: ExternalFile) {
        try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil)
    }

    private func createNewFile() {
        let dirURL = URL(fileURLWithPath: source.path)
        var name = "Untitled"
        var url = dirURL.appendingPathComponent("\(name).md")
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            name = "Untitled \(counter)"
            url = dirURL.appendingPathComponent("\(name).md")
            counter += 1
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
}
