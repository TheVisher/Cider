import SwiftUI

/// Root SwiftUI content for the canvas window.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var sidebarVisible = true
    @State private var isSearchVisible = false
    @State private var showNewItemPopover = false
    @State private var isCreateButtonHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                NativeCanvasView(viewModel: viewModel)
                    .frame(minWidth: 400, minHeight: 300)

                CanvasSidebarOverlay(
                    isVisible: $sidebarVisible,
                    zoomLevel: viewModel.viewport.zoom,
                    onCollapse: {
                        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                            sidebarVisible = false
                        }
                    },
                    onSelectFolder: { folderID in
                        guard let folderID else { return }
                        viewModel.panToFolder(folderID)
                    }
                )

                // Collapsed pill — shows when sidebar is hidden
                if !sidebarVisible {
                    collapsedPill
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                }

                // Search palette (below detail modal)
                if isSearchVisible {
                    CanvasSearchOverlay(
                        viewModel: viewModel,
                        canvasSize: geometry.size,
                        isSidebarVisible: sidebarVisible,
                        onDismiss: { isSearchVisible = false }
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

                // Detail modal (on top of search palette)
                if viewModel.selectedItemID != nil {
                    CanvasDetailOverlay(
                        viewModel: viewModel,
                        canvasSize: geometry.size,
                        isSidebarVisible: sidebarVisible,
                        onDismiss: { viewModel.deselectAll() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(3)
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.selectedItemIDs.count >= 2 {
                    bulkActionBar
                        .padding(.bottom, Spacing.xl)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                canvasCreateButton
                    .padding(Spacing.lg)
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: viewModel.selectedItemIDs)
            .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: sidebarVisible)
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: isSearchVisible)
        }
        .background {
            // Hidden button for Escape — dismiss detail first, then search, then deselect
            Button("") {
                if viewModel.selectedItemID != nil {
                    viewModel.deselectAll()
                } else if isSearchVisible {
                    isSearchVisible = false
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .background {
            // Hidden button for sidebar toggle
            Button("") {
                sidebarVisible.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .background {
            // Hidden button for fit all
            Button("") {
                NotificationCenter.default.post(name: .canvasFitAll, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .background {
            // Hidden button for search palette
            Button("") {
                isSearchVisible.toggle()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .onChange(of: sidebarVisible) { _, visible in
            // Sync sidebar state to the window for drag-region calculations
            (NSApp.keyWindow as? CanvasWindow)?.isSidebarVisible = visible
        }
    }

    // MARK: - Collapsed Pill

    /// Small floating pill in the top-left with traffic lights, zoom, and expand button.
    private var collapsedPill: some View {
        HStack(spacing: CiderPanelDesign.trafficLightSpacing) {
            // Traffic lights
            PanelTrafficLightButton(
                color: .systemRed,
                symbol: "xmark",
                help: "Close window"
            ) {
                NSApp.keyWindow?.close()
            }
            PanelTrafficLightButton(
                color: .systemYellow,
                symbol: "minus",
                help: "Minimize"
            ) {
                NSApp.keyWindow?.miniaturize(nil)
            }
            PanelTrafficLightButton(
                color: .systemGreen,
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Zoom"
            ) {
                NSApp.keyWindow?.zoom(nil)
            }

            Divider()
                .frame(height: CiderPanelDesign.trafficLightDiameter)
                .padding(.horizontal, Spacing.xxs)

            // Zoom level
            Button {
                NotificationCenter.default.post(name: .canvasResetZoom, object: nil)
            } label: {
                Text("\(Int(viewModel.viewport.zoom * 100))%")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(minWidth: 30)
            }
            .buttonStyle(.plain)
            .help("Reset to 100%")

            // Fit all
            Button {
                NotificationCenter.default.post(name: .canvasFitAll, object: nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("Fit All (⌘0)")

            Divider()
                .frame(height: CiderPanelDesign.trafficLightDiameter)
                .padding(.horizontal, Spacing.xxs)

            // Expand sidebar
            Button {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                    sidebarVisible = true
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("Show sidebar (⌘\\)")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowLight, radius: 6, x: 0, y: 2)
        .padding(.leading, Spacing.md)
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Bulk Action Bar

    /// Floating pill bar shown when 2+ items are selected.
    private var bulkActionBar: some View {
        HStack(spacing: Spacing.md) {
            Text("\(viewModel.selectedItemIDs.count) selected")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.primary)

            Divider()
                .frame(height: 16)

            Button {
                viewModel.deleteSelectedItems()
            } label: {
                Image(systemName: "trash")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete selected items")

            Menu {
                Button("Inbox (no folder)") {
                    viewModel.moveSelectedToFolder(nil)
                }
                Divider()
                ForEach(VaultFolderService.shared.folders) { folder in
                    Button(folder.name) {
                        viewModel.moveSelectedToFolder(folder.id)
                    }
                }
            } label: {
                Image(systemName: "folder")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move selected to folder")

            Divider()
                .frame(height: 16)

            Button {
                viewModel.deselectAll()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help("Deselect all")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
        }
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 2)
    }

    // MARK: - Create Button

    /// Floating "+" button in the bottom-right corner for creating new items.
    private var canvasCreateButton: some View {
        Button {
            showNewItemPopover = true
        } label: {
            Image(systemName: "plus")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .frame(width: 40, height: 40)
                .background(CiderColors.surfaceElevated)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
                )
                .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 4)
                .scaleEffect(isCreateButtonHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy(duration: 0.2)) {
                isCreateButtonHovered = hovering
            }
        }
        .help("Create new item")
        .popover(isPresented: $showNewItemPopover, arrowEdge: .top) {
            NewItemPopover(
                folders: VaultFolderService.shared.legacyFolders,
                onCreateBookmark: { urlString, title in
                    VaultBookmarkService.shared.add(urlString: urlString, title: title)
                },
                onCreateNote: { title, content in
                    var note = NotesStorage.shared.createNew(initialContent: content)
                    if !title.isEmpty { note.title = title; NotesStorage.shared.save(note: note) }
                },
                onCreateEvent: { title, date, allDay in
                    DateCardStorage.shared.createDateCard(
                        title: title,
                        startAt: date,
                        allDay: allDay
                    )
                },
                onCreateContact: { name, relationship in
                    var contact = ContactStorage.shared.createContact(displayName: name)
                    if !relationship.isEmpty {
                        contact.relationshipLabel = relationship
                        ContactStorage.shared.updateContact(contact)
                    }
                },
                onCreateTodo: { card in
                    TodoCardStorage.shared.addTodoCard(card)
                },
                onOpenTodoEditor: {
                    // No-op on canvas — todo editor is panel-specific
                },
                onCreateFolder: { name, parentID in
                    VaultFolderService.shared.createFolder(name: name, parentID: parentID)
                },
                onCreateTab: { _, _ in
                    // No-op on canvas — tabs are panel-specific
                },
                onCreateTag: { name, colorHex in
                    CardLabelStorage.shared.createLabel(name: name, colorHex: colorHex)
                },
                onCreateWhiteboard: { name in
                    WhiteboardStorage.shared.createCanvas(name: name)
                },
                onDismiss: {
                    showNewItemPopover = false
                }
            )
        }
    }
}
