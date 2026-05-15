import SwiftUI

struct KanbanTestingGuideFloatingView: View {
    let payload: KanbanTestingGuidePanelPayload
    var onDock: CiderFloatingDockAction?
    var onReanchor: CiderFloatingReanchorAction?

    @ObservedObject private var progressStore = KanbanTestingGuideProgressStore.shared

    private var completedStepCount: Int {
        progressStore.completedCount(guideID: payload.id, steps: payload.steps)
    }

    private var failedStepCount: Int {
        progressStore.failedCount(guideID: payload.id, steps: payload.steps)
    }

    var body: some View {
        GenericItemDetailPanel(
            title: "What To Test",
            detailViewMode: .slideOut,
            showDragHandle: false,
            scrollsContent: false,
            onClose: { dock() },
            onModeChange: { _ in },
            trailingExtra: {
                Button {
                    reanchor()
                } label: {
                    Image(systemName: "rectangle.arrowtriangle.2.inward")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open card in Cider")
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if payload.steps.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(Array(payload.steps.enumerated()), id: \.element.id) { index, step in
                                guideStep(index: index, step: step)
                            }
                        }
                        .padding(.bottom, Spacing.md)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CiderColors.warning)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(payload.cardTitle)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.xs) {
                        guideBadge(payload.boardName)
                        guideBadge(payload.cardID)
                        guideBadge("\(payload.steps.count) steps")
                        if completedStepCount > 0 {
                            guideBadge("\(completedStepCount) passed")
                        }
                        if failedStepCount > 0 {
                            guideBadge("\(failedStepCount) failed")
                        }
                    }
                }
            }

            Text("Keep this open while you leave Kanban and test the app. Results sync back to this card.")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.warning.opacity(0.3), lineWidth: CiderBorder.thinStrokeWidth)
        )
    }

    private var emptyState: some View {
        Text("No What To Test steps were found on this card.")
            .font(CiderFont.body)
            .foregroundColor(CiderColors.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func guideStep(index: Int, step: KanbanTestingGuideStep) -> some View {
        KanbanTestingGuideStepRow(
            guideID: payload.id,
            payload: payload,
            step: step,
            stepIndex: index,
            label: "Step \(index + 1)",
            textFont: CiderFont.body,
            showsSelectionEnabledText: true
        )
    }

    private func guideBadge(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.microMedium)
            .foregroundColor(CiderColors.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(CiderColors.surfaceInput))
    }

    @MainActor
    private func dock() {
        let surface = CiderFloatableSurface.kanbanTestingGuide(payload)
        if let onDock {
            onDock()
        } else {
            NotificationCenter.default.post(name: .dockCiderSurface, object: surface)
        }
    }

    @MainActor
    private func reanchor() {
        let surface = CiderFloatableSurface.kanbanTestingGuide(payload)
        if let onReanchor {
            onReanchor(surface)
        } else {
            NotificationCenter.default.post(
                name: .reanchorCiderSurface,
                object: surface,
                userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
            )
        }
    }
}

struct KanbanTestingGuideStepRow: View {
    let guideID: String
    var payload: KanbanTestingGuidePanelPayload?
    let step: KanbanTestingGuideStep
    var stepIndex: Int = 0
    let label: String
    var textFont: Font = CiderFont.caption
    var showsSelectionEnabledText = false

    @ObservedObject private var progressStore = KanbanTestingGuideProgressStore.shared
    @State private var noteDraft = ""

    private var isCompleted: Bool {
        progressStore.isCompleted(guideID: guideID, stepID: step.id)
    }

    private var result: KanbanTestingGuideStepResult? {
        progressStore.result(guideID: guideID, stepID: step.id)
    }

    private var isFailed: Bool {
        result?.status == .failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button {
                    setStatus(isCompleted ? nil : .passed)
                } label: {
                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isCompleted ? CiderColors.success : CiderColors.tertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCompleted ? "Clear passed result" : "Mark passed")

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(label)
                        .font(CiderFont.microMedium)
                        .foregroundColor(CiderColors.tertiary)

                    Text(step.text)
                        .font(textFont)
                        .foregroundColor(isCompleted ? CiderColors.success : (isFailed ? CiderColors.destructive : CiderColors.secondary))
                        .strikethrough(isCompleted, color: CiderColors.success.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(KanbanTestingGuideTextSelection(enabled: showsSelectionEnabledText))
                }

                Spacer(minLength: Spacing.xs)

                Button {
                    setStatus(isFailed ? nil : .failed)
                } label: {
                    Image(systemName: isFailed ? "xmark.square.fill" : "xmark.square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isFailed ? CiderColors.destructive : CiderColors.tertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isFailed ? "Clear failed result" : "Mark failed")
            }

            if isFailed || !noteDraft.isEmpty {
                HStack(spacing: Spacing.xs) {
                    TextField("Failure note", text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                .fill(CiderColors.surfaceElevated)
                        )
                        .onSubmit {
                            setStatus(.failed, note: noteDraft)
                        }

                    Button {
                        setStatus(.failed, note: noteDraft)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Save failure note")
                }
                .padding(.leading, 28)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(rowStroke, lineWidth: CiderBorder.thinStrokeWidth)
        )
        .onAppear {
            noteDraft = result?.note ?? ""
        }
    }

    private var rowBackground: Color {
        if isCompleted { return CiderColors.success.opacity(0.08) }
        if isFailed { return CiderColors.destructive.opacity(0.08) }
        return CiderColors.surfaceInput
    }

    private var rowStroke: Color {
        if isCompleted { return CiderColors.success.opacity(0.25) }
        if isFailed { return CiderColors.destructive.opacity(0.25) }
        return CiderColors.separator.opacity(0.65)
    }

    @MainActor
    private func setStatus(_ status: KanbanTestingGuideStepStatus?, note: String? = nil) {
        if let status {
            progressStore.setResult(status, note: note, guideID: guideID, stepID: step.id)
            if let payload {
                KanbanTestingGuideCardResultSync.record(
                    payload: payload,
                    step: step,
                    stepIndex: stepIndex,
                    status: status,
                    note: note
                )
            }
        } else {
            progressStore.removeResult(guideID: guideID, stepID: step.id)
            if let payload {
                KanbanTestingGuideCardResultSync.record(
                    payload: payload,
                    step: step,
                    stepIndex: stepIndex,
                    status: nil,
                    note: nil
                )
            }
        }
    }
}

private struct KanbanTestingGuideTextSelection: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
