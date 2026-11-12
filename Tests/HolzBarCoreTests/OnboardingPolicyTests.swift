import Testing
@testable import HolzBarCore

@Suite("Onboarding policy")
struct OnboardingPolicyTests {
    @Test("The onboarding opens by itself only on a new install without imports or profiles")
    func opensByItself() {
        #expect(OnboardingPolicy.opensByItself(isPending: true, hasImportedSettings: false, hasProfiles: false))
        #expect(!OnboardingPolicy.opensByItself(isPending: false, hasImportedSettings: false, hasProfiles: false))
        #expect(!OnboardingPolicy.opensByItself(isPending: true, hasImportedSettings: true, hasProfiles: false))
        #expect(!OnboardingPolicy.opensByItself(isPending: true, hasImportedSettings: false, hasProfiles: true))
    }

    @Test("Continue in the Permissions window opens Settings unless the onboarding waits")
    func continueOpensSettings() {
        #expect(!OnboardingPolicy.continueOpensSettings(isPending: true, hasImportedSettings: false))
        #expect(OnboardingPolicy.continueOpensSettings(isPending: false, hasImportedSettings: false))
        #expect(OnboardingPolicy.continueOpensSettings(isPending: true, hasImportedSettings: true))
    }

    @Test("Step 2 names the way of this macOS and the click only while both show settings are on")
    func stepTwo() {
        #expect(OnboardingPolicy.hidingWay(isMacOS27: false) == .commandDrag)
        #expect(OnboardingPolicy.hidingWay(isMacOS27: true) == .perApp)
        #expect(OnboardingPolicy.mentionsClickAndScroll(showOnClick: true, showOnScroll: true))
        #expect(!OnboardingPolicy.mentionsClickAndScroll(showOnClick: true, showOnScroll: false))
        #expect(!OnboardingPolicy.mentionsClickAndScroll(showOnClick: false, showOnScroll: true))
    }

    @Test("The three steps come in order")
    func steps() {
        #expect(OnboardingStep.allCases == [.whatHolzBarDoes, .showHiddenItems, .arrange])
        #expect(OnboardingStep.whatHolzBarDoes.next == .showHiddenItems)
        #expect(OnboardingStep.showHiddenItems.next == .arrange)
        #expect(OnboardingStep.arrange.next == nil)
        #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3])
        #expect(OnboardingStep.count == 3)
    }

    @Test("The tidy-up line shows once, with enough items and a proposal")
    func tidyUpLine() {
        #expect(TidyUpSuggestionPolicy.minimumVisibleItems == 6)
        #expect(TidyUpSuggestionPolicy.showsLine(wasOffered: false, hasImportedSettings: false, hasProfiles: false, visibleItemCount: 6, proposalCount: 1))
        #expect(!TidyUpSuggestionPolicy.showsLine(wasOffered: true, hasImportedSettings: false, hasProfiles: false, visibleItemCount: 6, proposalCount: 1))
        #expect(!TidyUpSuggestionPolicy.showsLine(wasOffered: false, hasImportedSettings: true, hasProfiles: false, visibleItemCount: 6, proposalCount: 1))
        #expect(!TidyUpSuggestionPolicy.showsLine(wasOffered: false, hasImportedSettings: false, hasProfiles: true, visibleItemCount: 6, proposalCount: 1))
        #expect(!TidyUpSuggestionPolicy.showsLine(wasOffered: false, hasImportedSettings: false, hasProfiles: false, visibleItemCount: 5, proposalCount: 1))
        #expect(!TidyUpSuggestionPolicy.showsLine(wasOffered: false, hasImportedSettings: false, hasProfiles: false, visibleItemCount: 6, proposalCount: 0))
    }

    @Test("The pending onboarding is a local key")
    func pendingKey() {
        #expect(Defaults.Key.onboardingPending.rawValue == "OnboardingPending")
        #expect(Defaults.Key.localOnlyKeys.contains(.onboardingPending))
    }
}
