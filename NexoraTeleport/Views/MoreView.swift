import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Activity") {
                    NavigationLink { HistoryView() } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    NavigationLink { StatusView() } label: { Label("Status Center", systemImage: "waveform.path.ecg") }
                }
                Section("Setup") {
                    NavigationLink { ProfilesView() } label: { Label("Profiles", systemImage: "person.crop.square") }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationTitle("More")
        }
    }
}
