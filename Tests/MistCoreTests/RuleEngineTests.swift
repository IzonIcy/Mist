import Testing
import Foundation
@testable import MistCore

/// Exercises the rules engine against `WindowSnapshot`s — the charter's "rule
/// engine tests".
struct RuleEngineTests {

    private let safari = WindowSnapshot(appName: "Safari", title: "New Tab", bundleID: "com.apple.Safari")

    @Test func appNameConditionMatches() {
        let condition = AppNameCondition(value: "Safari")
        #expect(condition.matches(safari))
        #expect(!condition.matches(make(app: "Finder")))
    }

    @Test func titleContainsCondition() {
        let condition = TitleContainsCondition(substring: "Picture")
        #expect(condition.matches(make(title: "Picture in Picture")))
        #expect(!condition.matches(make(title: "Browser")))
    }

    @Test func bundleIDConditionMatchesExact() {
        let condition = BundleIDCondition(bundleID: "com.apple.Safari")
        #expect(condition.matches(safari))
    }

    @Test func ruleFiresActionsOnMatch() {
        let rule = Rule(name: "float safari",
                        condition: AppNameCondition(value: "Safari"),
                        actions: [.float(true)])
        let engine = RuleEngine(rules: [rule])
        #expect(engine.actions(for: safari) == [.float(true)])
        #expect(engine.actions(for: make(app: "Finder")).isEmpty)
    }

    @Test func compoundConditionRequiresAll() {
        let condition = CompoundCondition(conditions: [
            AppNameCondition(value: "Safari"),
            TitleContainsCondition(substring: "Tab")
        ])
        #expect(condition.matches(safari))
        #expect(!condition.matches(make(app: "Safari", title: "Home")))
    }

    @Test func multipleRulesCombineActionsInOrder() {
        let engine = RuleEngine(rules: [
            Rule(name: nil, condition: AppNameCondition(value: "Safari"), actions: [.monitor(2)]),
            Rule(name: nil, condition: BundleIDCondition(bundleID: "com.apple.Safari"), actions: [.alwaysOnTop(true)])
        ])
        #expect(engine.actions(for: safari) == [.monitor(2), .alwaysOnTop(true)])
    }

    private func make(app: String = "Safari", title: String = "New Tab", bundle: String = "com.apple.Safari") -> WindowSnapshot {
        WindowSnapshot(appName: app, title: title, bundleID: bundle)
    }
}