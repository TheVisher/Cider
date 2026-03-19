import SwiftUI
import os

struct ConnectedDevicesView: View {
    @State private var devices: [ConnectedDevice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var deviceToRevoke: ConnectedDevice?

    private static let logger = Logger(subsystem: "com.cider", category: "ConnectedDevices")

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("Connected Devices")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                Spacer()

                Button {
                    Task { await loadDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("Refresh")
            }

            if isLoading && devices.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Loading devices...")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            } else if let error = errorMessage {
                Text(error)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
            } else if devices.isEmpty {
                Text("No connected devices")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
        .task { await loadDevices() }
        .alert("Remove Device?", isPresented: .init(
            get: { deviceToRevoke != nil },
            set: { if !$0 { deviceToRevoke = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToRevoke = nil }
            Button("Remove", role: .destructive) {
                if let device = deviceToRevoke {
                    Task { await revokeDevice(device) }
                }
            }
        } message: {
            if let device = deviceToRevoke {
                Text("'\(device.name)' will need to sign in again to sync.")
            }
        }
    }

    private func deviceRow(_ device: ConnectedDevice) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: device.icon)
                .font(CiderFont.bodyMedium)
                .foregroundColor(device.isCurrentDevice ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(width: SettingsDesign.deviceIconColumnWidth)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(spacing: Spacing.xs) {
                    Text(device.name)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.primary)

                    if device.isCurrentDevice {
                        Text("This device")
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.controlAccent)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.hairline)
                            .background(
                                Capsule()
                                    .fill(CiderColors.accentSubtle)
                            )
                    }
                }

                if let lastUsed = device.lastUsedAt {
                    Text("Last active \(lastUsed.formatted(.relative(presentation: .named)))")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                } else {
                    Text("Never synced")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
            }

            Spacer(minLength: 0)

            if !device.isCurrentDevice {
                Button {
                    deviceToRevoke = device
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove device")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    // MARK: - Network

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            let token = SyncService.loadSyncToken()
            let config = CiderConfig.load()
            let baseURL = config.syncURL.isEmpty
                ? "https://dashing-fennec-334.convex.site"
                : config.syncURL

            guard let url = URL(string: baseURL + "/api/auth/devices") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(DevicesResponse.self, from: data)

            let currentDeviceName = Host.current().localizedName ?? "Mac"

            devices = response.devices.map { d in
                ConnectedDevice(
                    id: d.id,
                    name: d.name,
                    lastUsedAt: d.lastUsedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                    createdAt: Date(timeIntervalSince1970: d.createdAt / 1000),
                    isCurrentDevice: d.name == currentDeviceName
                )
            }.sorted { lhs, rhs in
                if lhs.isCurrentDevice != rhs.isCurrentDevice { return lhs.isCurrentDevice }
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
        } catch {
            errorMessage = "Failed to load devices"
            Self.logger.error("Failed to load devices: \(error)")
        }

        isLoading = false
    }

    private func revokeDevice(_ device: ConnectedDevice) async {
        do {
            let token = SyncService.loadSyncToken()
            let config = CiderConfig.load()
            let baseURL = config.syncURL.isEmpty
                ? "https://dashing-fennec-334.convex.site"
                : config.syncURL

            guard let url = URL(string: baseURL + "/api/auth/devices/revoke") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["tokenId": device.id])

            let (_, _) = try await URLSession.shared.data(for: request)
            devices.removeAll { $0.id == device.id }
        } catch {
            Self.logger.error("Failed to revoke device: \(error)")
        }

        deviceToRevoke = nil
    }

    // MARK: - Models

    private struct DevicesResponse: Decodable {
        let devices: [DeviceDTO]
    }

    private struct DeviceDTO: Decodable {
        let id: String
        let name: String
        let createdAt: Double
        let lastUsedAt: Double?
    }
}

private struct ConnectedDevice: Identifiable {
    let id: String
    let name: String
    let lastUsedAt: Date?
    let createdAt: Date
    let isCurrentDevice: Bool

    var icon: String {
        let lower = name.lowercased()
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("phone") { return "iphone" }
        return "laptopcomputer"
    }
}
