import FamilyControls
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onNotificationTap: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Phos is designed light only. System sheets and pickers follow the window style.
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { note in
            (note.object as? UIWindow)?.overrideUserInterfaceStyle = .light
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onNotificationTap?() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct PhosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .environment(\.colorScheme, .light)
                .onAppear {
                    delegate.onNotificationTap = {
                        model.refresh()
                        model.routeFromLock()
                    }
                }
                .onOpenURL { url in model.open(url) }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var model = model
        Group {
            if let screen = DemoScreen.requested, model.demo {
                DemoRouter(screen: screen)
            } else if model.settings.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.light)
        .onChange(of: phase) { _, p in
            if p == .active {
                model.refresh()
                model.routeFromLock()
            }
        }
        .fullScreenCover(item: $model.route) { route in
            Group {
                switch route {
                case .reading: ReadingFlow(ref: model.todaysChapter)
                case .unlock: UnlockCenter()
                }
            }
            .environment(model)
            .preferredColorScheme(.light)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            TodayScreen()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "flame") }
                .tag(1)
            TrophyScreen()
                .tabItem { Label("Trophies", systemImage: "trophy") }
                .tag(3)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .overlay {
            if let first = model.celebrating.first {
                TrophyCelebration(achievement: first, more: model.celebrating.count - 1) {
                    withAnimation(.easeOut(duration: 0.25)) { model.celebrating.removeAll() }
                }
                .transition(.opacity)
            }
        }
    }
}
