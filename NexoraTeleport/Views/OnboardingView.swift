import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nexora.teleport.onboarding.complete") private var complete = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.indigo)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer()
            Button(page == 2 ? "Finish" : "Continue") {
                if page == 0 { model.location.requestPermissions() }
                if page < 2 { page += 1 }
                else {
                    complete = true
                    model.preferences.liveWhenIdle = true
                    model.applyPreferences()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if page > 0 { Button("Back") { page -= 1 } }
        }
        .padding()
        .interactiveDismissDisabled()
    }

    private var title: String {
        ["Location Permission", "Live & Background", "Ready to Go"][page]
    }
    private var message: String {
        [
            "Nexora Teleport uses your device location for the Live screen and route tools.",
            "Live can stay useful without an active route. Background location is only enabled while an active route needs it.",
            "Create places and routes, then build routines, profiles and exception days."
        ][page]
    }
    private var icon: String {
        ["location.fill", "waveform.path.ecg", "checkmark.circle.fill"][page]
    }
}
