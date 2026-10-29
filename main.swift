// KeepAwake — a tiny menu bar app for long waits (like AI agent runs).
//
// One switch controls both:
//   • Keep Awake: stops the Mac and display from sleeping
//   • Simulate Activity: after 1 minute of no input, nudges the mouse a few
//     pixels and taps Shift so apps like Slack keep showing you as active
//
// Options submenu lets you turn off Simulate Activity if you ever want
// keep-awake only (e.g. watching a video). This preference is remembered.
//
// Simulate Activity needs Accessibility permission:
//   System Settings > Privacy & Security > Accessibility > enable KeepAwake

import Cocoa
import IOKit.pwr_mgt
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Settings
    private let idleThreshold: TimeInterval = 60   // seconds idle before simulating input
    private let checkInterval: TimeInterval = 15   // how often to check idle time
    private let nudgePixels: CGFloat = 3

    // MARK: State
    private var statusItem: NSStatusItem!
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var isOn = false
    private var endDate: Date?
    private var awakeTimer: Timer?
    private var activityTimer: Timer?

    // Remembered preference: simulate activity along with keep-awake (default on)
    private var simulateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "simulateEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "simulateEnabled") }
    }

    // MARK: Menu items
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "t")
    private let simulateCheck = NSMenuItem(title: "Simulate Activity (mouse + Shift)", action: #selector(toggleSimulatePref), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        toggleItem.target = self
        menu.addItem(toggleItem)

        let forItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, minutes) in [("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240), ("8 hours", 480)] {
            let item = NSMenuItem(title: title, action: #selector(turnOnFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            sub.addItem(item)
        }
        forItem.submenu = sub
        menu.addItem(forItem)

        menu.addItem(.separator())
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        simulateCheck.target = self
        optionsMenu.addItem(simulateCheck)
        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit KeepAwake", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateUI()
    }

    @objc private func quit() {
        turnOff()
        NSApp.terminate(nil)
    }

    // MARK: - Main toggle

    @objc private func toggle() {
        if isOn { turnOff() } else { turnOn(minutes: nil) }
    }

    @objc private func turnOnFor(_ sender: NSMenuItem) {
        turnOff()
        turnOn(minutes: sender.tag)
    }

    private func turnOn(minutes: Int?) {
        // Keep Awake (no permission needed)
        let reason = "KeepAwake: waiting on a long-running task" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, level, reason, &displayAssertion)
        IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString, level, reason, &systemAssertion)
        isOn = true

        if let minutes = minutes {
            endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        }
        awakeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let end = self.endDate, Date() >= end { self.turnOff() } else { self.updateUI() }
        }

        // Simulate Activity (only if enabled; asks for permission if needed)
        if simulateEnabled {
            startSimulating()
        }
        updateUI()
    }

    private func turnOff() {
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        awakeTimer?.invalidate(); awakeTimer = nil
        activityTimer?.invalidate(); activityTimer = nil
        endDate = nil
        isOn = false
        updateUI()
    }

    // MARK: - Options

    @objc private func toggleSimulatePref() {
        simulateEnabled.toggle()
        // Apply immediately if the app is currently running
        if isOn {
            if simulateEnabled {
                startSimulating()
            } else {
                activityTimer?.invalidate(); activityTimer = nil
            }
        }
        updateUI()
    }

    // MARK: - Simulate Activity

    private func startSimulating() {
        guard hasAccessibilityPermission(prompt: true) else {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission needed"
            alert.informativeText = "To simulate mouse and keyboard input, enable KeepAwake in System Settings > Privacy & Security > Accessibility. Keep Awake still works without it."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        activityTimer?.invalidate()
        activityTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    private func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func checkIdle() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        if idle >= idleThreshold {
            simulateInput()
        }
    }

    private func simulateInput() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Nudge the mouse a few pixels and move it back
        if let current = CGEvent(source: nil)?.location {
            let dx = Bool.random() ? nudgePixels : -nudgePixels
            let dy = Bool.random() ? nudgePixels : -nudgePixels
            let nudged = CGPoint(x: current.x + dx, y: current.y + dy)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: nudged, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(150_000)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }

        // Tap Shift (key code 56) — a real keystroke that types nothing
        let shiftKey: CGKeyCode = 56
        if let down = CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: true) {
            down.flags = .maskShift
            down.post(tap: .cghidEventTap)
        }
        usleep(50_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: false) {
            up.flags = []
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - UI

    private func updateUI() {
        let symbol = isOn ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KeepAwake")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = isOn ? "KeepAwake: On" : "KeepAwake: Off"

        toggleItem.title = isOn ? "Turn Off" : "Turn On"
        simulateCheck.state = simulateEnabled ? .on : .off

        if !isOn {
            statusLine.title = "Off — Mac sleeps normally"
        } else {
            let activity = simulateEnabled ? " + activity" : ""
            if let end = endDate {
                let remaining = max(0, Int(end.timeIntervalSinceNow))
                let h = remaining / 3600, m = (remaining % 3600) / 60
                let left = h > 0 ? "\(h)h \(m)m left" : "\(max(m, 1))m left"
                statusLine.title = "On\(activity) — \(left)"
            } else {
                statusLine.title = "On\(activity) — until you turn it off"
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
