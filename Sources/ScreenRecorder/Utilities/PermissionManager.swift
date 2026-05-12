import Foundation
import CoreGraphics

class PermissionManager {
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
