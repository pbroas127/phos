import FamilyControls
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onNotificationTap: ((String?) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// The natural voices download keeps going while the app is closed. iOS wakes the app to finish it.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        KokoroModel.backgroundCompletion = completionHandler
        _ = KokoroModel.shared
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let target = response.notification.request.content.userInfo["route"] as? String
        DispatchQueue.main.async { self.onNotificationTap?(target) }
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
                .preferredColorScheme(model.settings.appearance.scheme)
                .onAppear {
                    delegate.onNotificationTap = { target in
                        model.routeFromNotification(target)
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
        .onChange(of: phase) { _, p in
            if p == .active {
                model.refresh()
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

extension AppAppearance {
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
