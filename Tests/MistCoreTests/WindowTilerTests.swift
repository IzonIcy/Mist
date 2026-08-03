import Testing
import Foundation
import CoreGraphics
@testable import MistCore

/// The pure glue between windows, a display, and a layout — what the coordinator
/// uses to decide where each window goes.
struct WindowTilerTests {

    private let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let config = LayoutConfig(gap: 8, outerGap: 16)

    private func makeWindow(_ id: String, floating: Bool = false) -> Window {
        Window(id: id, displayIdentifier: nil, appName: "App",
               title: "w-\(id)", bundleID: "b", frame: .zero,
               isFloating: floating)
    }

    @Test("no windows yields an empty plan")
    func emptyInput() {
        let plan = WindowTiler(display: display, layout: makeLayout(for: .monocle), config: config).plan(for: [])
        #expect(plan.isEmpty)
    }

    @Test("floating windows are excluded from the plan")
    func floatingExcluded() {
        let plan = WindowTiler(display: display, layout: makeLayout(for: .monocle), config: config)
            .plan(for: [makeWindow("a"), makeWindow("f", floating: true), makeWindow("b")])
        #expect(plan.count == 2)
        #expect(plan["f"] == nil)
    }

    @Test("monocle fills the display minus outer gap for one window")
    func monocleInsetsSingleWindow() {
        let plan = WindowTiler(display: display, layout: makeLayout(for: .monocle), config: config)
            .plan(for: [makeWindow("a")])
        guard let frame = plan["a"] else {
            Issue.record("expected a frame for the single window")
            return
        }
        let inset = display.insetBy(dx: config.outerGap, dy: config.outerGap)
        #expect(abs(frame.minX - inset.minX) < 0.001)
        #expect(abs(frame.width - inset.width) < 0.001)
    }

    @Test("every layout keeps all frames within the display")
    func framesStayInBounds() {
        for name in LayoutName.allCases {
            let layout = makeLayout(for: name)
            let windows = (1...6).map { makeWindow("w\($0)") }
            let plan = WindowTiler(display: display, layout: layout, config: config).plan(for: windows)
            let out = plan.filter {
                $0.value.minX < display.minX - 0.001 || $0.value.maxX > display.maxX + 0.001 ||
                $0.value.minY < display.minY - 0.001 || $0.value.maxY > display.maxY + 0.001
            }
            #expect(out.isEmpty, "\(name.rawValue) produced out-of-bounds frames")
        }
    }
}