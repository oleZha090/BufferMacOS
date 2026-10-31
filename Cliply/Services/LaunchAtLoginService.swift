import ServiceManagement
import Combine

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?
    private(set) var errorCode: Int?
    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    var statusLabel: String {
        switch status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Waiting for approval in System Settings"
        case .notRegistered: return "Off"
        case .notFound: return "Application registration unavailable"
        @unknown default: return "Unknown status"
        }
    }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        errorCode = nil
        do {
            if enabled && status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
            if !enabled && (status == .enabled || status == .requiresApproval) { try SMAppService.mainApp.unregister() }
        } catch {
            errorCode = (error as NSError).code
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
