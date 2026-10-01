import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingEditor = false

    var body: some View {
        List {
            if model.profiles.isEmpty {
                ContentUnavailableView("No profiles", systemImage: "person.crop.square", description: Text("Profiles can switch routine sets, battery mode, map style and idle Live behavior together."))
            }
            ForEach(model.profiles) { profile in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(profile.name).font(.headline)
                        Spacer()
                        if model.activeProfileID == profile.id {
                            Text("Active").font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                    Text("\(profile.routineIDs.count) routines · \(profile.batteryMode.label) · \(profile.mapAppearance.label)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Activate") { model.activateProfile(profile.id) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                for index in offsets { model.deleteProfile(model.profiles[index].id) }
            }
        }
        .navigationTitle("Profiles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ProfileEditorView(routines: model.routines) { profile in
                model.addProfile(profile)
                showingEditor = false
            }
        }
    }
}

private struct ProfileEditorView: View {
    let routines: [RoutineProfile]
    let onSave: (TeleportProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Profile"
    @State private var selectedRoutineIDs: Set<UUID> = []
    @State private var batteryMode: BatteryMode = .balanced
    @State private var mapAppearance: MapAppearance = .standard
    @State private var liveWhenIdle = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Routines") {
                    ForEach(routines) { routine in
                        Toggle(routine.name, isOn: Binding(
                            get: { selectedRoutineIDs.contains(routine.id) },
                            set: { enabled in
                                if enabled { selectedRoutineIDs.insert(routine.id) }
                                else { selectedRoutineIDs.remove(routine.id) }
                            }
                        ))
                    }
                }
                Picker("Battery", selection: $batteryMode) {
                    ForEach(BatteryMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Map", selection: $mapAppearance) {
                    ForEach(MapAppearance.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Live when idle", isOn: $liveWhenIdle)
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(TeleportProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), routineIDs: selectedRoutineIDs, batteryMode: batteryMode, mapAppearance: mapAppearance, liveWhenIdle: liveWhenIdle))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
