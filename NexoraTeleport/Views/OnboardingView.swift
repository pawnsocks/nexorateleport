import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nexora.teleport.onboarding.complete") private var complete = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()

            Button(page == 2 ? "Open Teleport" : "Continue") {
                if page == 0 { model.location.requestPermissions() }
                if page < 2 {
                    page += 1
                } else {
                    complete = true
                    model.preferences.liveWhenIdle = true
                    model.applyPreferences()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if page > 0 { Button("Back") { page -= 1 } }
        }
        .padding()
        .interactiveDismissDisabled()
    }

    private var title: String {
        ["Allow Location", "Pick a Target", "You're Ready"][page]
    }

    private var message: String {
        [
            "Allow location access so Nexora can show your current iPhone position and build routes from where you are.",
            "On Teleport, search for a city, street, postcode, or landmark. Tap a result and it becomes your Target.",
            "The main screen always shows Current, Target, Live ON/OFF, and route controls. Start and stop everything from one place."
        ][page]
    }

    private var icon: String {
        ["location.fill", "mappin.and.ellipse", "checkmark.circle.fill"][page]
    }
}
