import Foundation

/// Evaluates a path against the rule catalog and the user's exclusion list to
/// produce a single, auditable `SafetyDecision`. This is the brain that decides
/// what Cleanup may even *offer* — and what it may pre-tick.
///
/// Decision precedence (most cautious wins):
/// 1. User exclusion list → always `.protected` (the user said hands-off).
/// 2. Among active matching rules, the strictest disposition wins.
/// 3. No rule matches → `.protected` (unknown ⇒ never auto-cleaned). This is the
///    core invariant: nothing outside known-safe paths is selected automatically.
public struct SafetyRuleEngine: Sendable {
    private let rules: [SafetyRule]
    private let exclusions: ExclusionMatcher
    private let osVersion: OSVersion
    private let installedApps: Set<String>

    public init(
        rules: [SafetyRule],
        exclusions: ExclusionMatcher = .empty,
        osVersion: OSVersion = .current,
        installedApps: Set<String> = []
    ) {
        self.rules = rules
        self.exclusions = exclusions
        self.osVersion = osVersion
        self.installedApps = installedApps
    }

    public func evaluate(_ url: URL) -> SafetyDecision {
        if exclusions.shouldExclude(url) {
            return SafetyDecision(
                disposition: .protected,
                category: .unknown,
                ruleID: "user.exclusion",
                reason: "On your exclusion list."
            )
        }

        let active = rules.filter {
            $0.isActive(on: osVersion, installedApps: installedApps) && $0.matcher.matches(url)
        }

        guard let winner = active.max(by: { $0.disposition < $1.disposition }) else {
            return SafetyDecision(
                disposition: .protected,
                category: .unknown,
                ruleID: "default.deny",
                reason: "Not on a known-safe path — Nimbus won’t touch it automatically."
            )
        }

        return SafetyDecision(
            disposition: winner.disposition,
            category: winner.category,
            ruleID: winner.id,
            reason: winner.reason
        )
    }
}
