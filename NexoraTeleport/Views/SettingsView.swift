import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: DeviceLocationService
    @State private var showingImporter = false
    @State private var importMessage: String?

    var body: some View {
        List {
            Section("Live & Location") {
                Toggle("Live when no route is active", isOn: $model.preferences.liveWhenIdle)
                    .onChange(of: model.preferences.liveWhenIdle) { _, _ in model.applyPreferences() }
                Picker("Battery mode", selection: $model.preferences.batteryMode) {
                    ForEach(BatteryMode.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: model.preferences.batteryMode) { _, _ in model.applyPreferences() }
                Picker("Map style", selection: $model.preferences.mapAppearance) {
                    ForEach(MapAppearance.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: model.preferences.mapAppearance) { _, _ in model.applyPreferences() }

                LabeledContent("Permission", value: permissionLabel)
                LabeledContent("Live", value: location.isLiveTracking ? "Active" : "Stopped")
                LabeledContent("Background", value: location.isBackgroundTracking ? "Active" : "Stopped")

                Button("Request Location Permission") { location.requestPermissions() }
                if let error = location.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section("Privacy") {
                Toggle("Keep route history", isOn: $model.preferences.historyEnabled)
                    .onChange(of: model.preferences.historyEnabled) { _, _ in model.applyPreferences() }
                Toggle("Local-only mode", isOn: $model.preferences.localOnlyMode)
                    .onChange(of: model.preferences.localOnlyMode) { _, value in
                        if value { model.preferences.cloudSyncEnabled = false }
                        model.applyPreferences()
                    }
                Label("Secrets use Keychain", systemImage: "key.fill")
                Label("Files use iOS Data Protection", systemImage: "lock.doc.fill")
                Label("Diagnostics exclude saved coordinates", systemImage: "eye.slash")
            }

            Section("Backup & Transfer") {
                if let backupURL = try? model.exportBackupURL() {
                    ShareLink(item: backupURL) { Label("Export Nexora backup", systemImage: "square.and.arrow.up") }
                }
                Button { showingImporter = true } label: { Label("Import backup or GPX", systemImage: "square.and.arrow.down") }
                if let importMessage { Text(importMessage).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("iCloud Sync") {
                Toggle("iCloud backup", isOn: $model.preferences.cloudSyncEnabled)
                    .disabled(model.preferences.localOnlyMode)
                    .onChange(of: model.preferences.cloudSyncEnabled) { _, _ in model.applyPreferences() }
                Text("iCloud sync works when the iCloud Key-Value Store capability is enabled for the signing team. Local-only mode never sends this data to iCloud.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Upload backup") { Task { await model.syncToICloud() } }
                    .disabled(model.preferences.localOnlyMode)
                Button("Restore backup") { Task { await model.restoreFromICloud() } }
                    .disabled(model.preferences.localOnlyMode)
                if let message = model.cloudMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("Reliability") {
                Label("Continuous route checkpoints", systemImage: "externaldrive.badge.checkmark")
                Label("Persistent routine target times", systemImage: "calendar.badge.checkmark")
                Label("Watchdog for stale sessions", systemImage: "waveform.path.ecg")
                Label("Kill switch and crash recovery", systemImage: "stop.circle")
            }

            Section("Diagnostics") {
                if let diagnostics = try? model.diagnosticsURL() {
                    ShareLink(item: diagnostics) { Label("Export diagnostics", systemImage: "doc.text.magnifyingglass") }
                }
                Text("The diagnostics file contains engine state and counts, not your saved coordinates or place names.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .xml, .data]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == "gpx" {
                    try model.importGPX(url: url)
                    importMessage = "GPX route imported."
                } else {
                    try model.importBackup(from: url)
                    importMessage = "Backup imported."
                }
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private var permissionLabel: String {
        switch location.authorization {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        @unknown default: return "Unknown"
        }
    }
}
