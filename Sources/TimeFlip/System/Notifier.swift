import Foundation
import UserNotifications

/// 通知只是锦上添花：ad-hoc 签名下可能拿不到授权，失败时静默降级。
final class Notifier {
    private(set) var isAuthorized = false

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else {
                DispatchQueue.main.async {
                    self?.isAuthorized = settings.authorizationStatus == .authorized
                }
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                }
            }
        }
    }

    func notify(title: String, body: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
