import Foundation

/// Every surface that carries dev notes, a tour step or decisions. The raw value is the id exported for Claude.
public enum ScreenID: String, Sendable, Codable, CaseIterable, Identifiable {
    case canvas = "day.canvas"
    case sidebar = "shell.sidebar"
    case recorder = "capture.recorder"
    case capturePanel = "capture.panel"
    case menuBar = "capture.menubar"
    case momentDetail = "detail.moment"
    case voiceDetail = "detail.voice"
    case writingDetail = "detail.writing"
    case stillDetail = "detail.still"
    case stack = "canvas.stack"
    case noticed = "inspector.noticed"
    case letter = "reflection.letter"
    case safetyCard = "safety.card"
    case trash = "shell.trash"
    case decisions = "dev.decisions"
    case settings = "shell.settings"
    case onboardingWelcome = "onboarding.welcome"
    case onboardingAboutYou = "onboarding.about"
    case onboardingFirstWeek = "onboarding.firstweek"
    case onboardingFindLight = "onboarding.light"
    case knows = "memory.knows"
    case lens = "navigation.lens"
    case datePicker = "navigation.datepicker"

    public var id: String { rawValue }
}
