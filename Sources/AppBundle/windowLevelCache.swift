import CoreGraphics
import Foundation

@MainActor
private var cache: [UInt32: MacOsWindowLevel] = [:]

/// Set of window IDs that are currently on-screen. Populated from
/// CGWindowList with optionOnScreenOnly. Refreshed alongside the
/// window level cache.
@MainActor
private var onScreenWindowIds: Set<UInt32> = []

/// Set of all window IDs known to the system, across all Spaces.
/// Populated from CGWindowList WITHOUT optionOnScreenOnly.
@MainActor
private var allSystemWindowIds: Set<UInt32> = []

/// Window IDs that AX reports as alive during the current refresh.
/// AX returns background tabs but NOT windows on inactive Spaces.
@MainActor
private var axAliveWindowIds: Set<UInt32> = []

@MainActor
func getWindowLevel(for windowId: UInt32) -> MacOsWindowLevel? {
    if let existing = cache[windowId] { return existing }
    refreshCGWindowListCache()
    return cache[windowId]
}

/// Returns true if the window is currently visible on-screen.
/// Background tabs in native macOS tab groups are not on-screen
/// and will return false.
@MainActor
func isWindowOnScreen(_ windowId: UInt32) -> Bool {
    return onScreenWindowIds.contains(windowId)
}

/// Returns true if the window exists anywhere in the system
/// (any Space, any state). Uses CGWindowList without
/// optionOnScreenOnly.
@MainActor
func isWindowAliveInSystem(_ windowId: UInt32) -> Bool {
    return allSystemWindowIds.contains(windowId)
}

/// Store the AX-alive window IDs for the current refresh cycle.
@MainActor
func setAxAliveWindowIds(_ ids: Set<UInt32>) {
    axAliveWindowIds = ids
}

/// Returns true if AX considers the window alive (returned by
/// kAXWindowsAttribute during the current refresh cycle).
/// Background tabs return true; inactive-Space windows return
/// false.
@MainActor
func isWindowAxAlive(_ windowId: UInt32) -> Bool {
    return axAliveWindowIds.contains(windowId)
}

/// Refresh the on-screen window cache. Call this once at the start
/// of a refresh session to get a consistent snapshot.
@MainActor
func refreshOnScreenWindowCache() {
    refreshCGWindowListCache()
}

@MainActor
private func refreshCGWindowListCache() {
    var levelResult: [UInt32: MacOsWindowLevel] = [:]
    var onScreenResult: Set<UInt32> = []
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let cfArray = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [CFDictionary] else { return }
    for elem in cfArray {
        let dict = elem as NSDictionary

        guard let _windowLayer = dict[kCGWindowLayer] else { continue }
        let windowLayer = ((_windowLayer as! CFNumber) as NSNumber).intValue

        guard let _windowId = dict[kCGWindowNumber] else { continue }
        let windowId = ((_windowId as! CFNumber) as NSNumber).uint32Value

        levelResult[windowId] = .new(windowLevel: windowLayer)
        onScreenResult.insert(windowId)
    }
    cache = levelResult
    onScreenWindowIds = onScreenResult

    // All-windows query (includes windows on inactive Spaces).
    var allResult: Set<UInt32> = []
    let allOptions = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
    if let cfArray = CGWindowListCopyWindowInfo(allOptions, CGWindowID(0)) as? [CFDictionary] {
        for elem in cfArray {
            let dict = elem as NSDictionary
            guard let _windowId = dict[kCGWindowNumber] else { continue }
            let windowId = ((_windowId as! CFNumber) as NSNumber).uint32Value
            allResult.insert(windowId)
        }
    }
    allSystemWindowIds = allResult
}

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
            case .string("normalWindow"): .normalWindow
            case .string("alwaysOnTopWindow"): .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: Int(exactly: int).orDie())
            default: nil
        }
    }

    func toJson() -> Json {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}
