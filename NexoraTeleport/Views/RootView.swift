import SwiftUI

struct RootView: View {
    @AppStorage("nexora.teleport.onboarding.complete") private var onboardingComplete = false

    var body: some View {
        TabView {
            MapHomeView()
                .tabItem { Label("Teleport", systemImage: "location.fill") }

            RoutesView()
                .tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }

            RoutinesView()
                .tabItem { Label("Routine", systemImage: "calendar.badge.clock") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(.indigo)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingComplete },
            set: { if !$0 { onboardingComplete = true } }
        )) {
            OnboardingView()
        }
    }
}
