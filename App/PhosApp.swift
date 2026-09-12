import FamilyControls
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onNotificationTap: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
                .onAppear {
                    delegate.onNotificationTap = {
                        model.refresh()
                        model.routeFromLock()
                    }
                }
                .onOpenURL { _ in
                    model.refresh()
                    model.routeFromLock()
                }
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
                case .recall: RecallFlow()
                case .focus: FocusSessionView()
                case .recite: ReciteView()
                case .emergency: EmergencyPassView(asSheet: true)
                }
            }
            .environment(model)
            .preferredColorScheme(.light)
        }
    }
}

struct MainTabs: View {
    @State private var tab = DemoScreen.startTab

    var body: some View {
        TabView(selection: $tab) {
            TodayScreen()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "flame") }
                .tag(1)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
    }
}
