import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class AppLockManager {
    private static let enabledKey = "startrails.biometricLockEnabled.v1"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                isLocked = false
            }
        }
    }
    var isLocked: Bool = false
    var authError: String?

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    var biometricLabel: String {
        let context = LAContext()
        var err: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch context.biometryType {
        case .faceID: return "Face ID 解锁"
        case .touchID: return "Touch ID 解锁"
        case .opticID: return "Optic ID 解锁"
        default: return "生物识别 / 密码解锁"
        }
    }

    var biometricIcon: String {
        let context = LAContext()
        var err: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.shield"
        }
    }

    func lockIfNeeded() {
        if isEnabled {
            isLocked = true
        }
    }

    func unlock() async {
        guard isEnabled else {
            isLocked = false
            return
        }
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: "解锁 Startrails 控制台")
            if success {
                isLocked = false
                authError = nil
            }
        } catch {
            authError = error.localizedDescription
        }
    }
}
