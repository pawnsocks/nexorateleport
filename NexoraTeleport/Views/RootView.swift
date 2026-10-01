import SwiftUI

struct RootView: View {
    @AppStorage("nexora.teleport.onboarding.complete") private var onboardingComplete = false

    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }
            MapHomeView().tabItem { Label("Map", systemImage: "map") }
            RoutesView().tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            RoutinesView().tabItem { Label("Routine", systemImage: "calendar.badge.clock") }
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }
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
