import Testing
@testable import HolzBarCore

@Suite("AlertNotificationPlan")
struct AlertNotificationPlanTests {
    private let snapshot = AlertSnapshot(signal: .cpu, severity: .amber, observation: .fraction(0.95))

    private var effects: [ThresholdEvaluator.Effect] {
        [.fired(snapshot), .updated(snapshot), .cleared(.cpu), .ended(.cpu)]
    }

    private let accesses: [NotificationAccess] = [.notDetermined, .denied, .allowed]

    @Test("The identifiers are fixed per rule, distinct and free of spaces")
    func identifiers() {
        #expect(AlertNotificationPlan.identifier(for: .cpu) == "com.holzcloud.holzBar.alert.cpu")
        #expect(AlertNotificationPlan.testIdentifier == "com.holzcloud.holzBar.alert.test")
        let all = AlertNotificationPlan.allIdentifiers
        #expect(all.count == 6)
        #expect(Set(all).count == 6)
        #expect(all.allSatisfy { !$0.contains(" ") && $0.hasPrefix(AlertNotificationPlan.identifierPrefix) })
        #expect(all.contains(AlertNotificationPlan.testIdentifier))
    }

    @Test("A rule's notifications share one thread")
    func threads() {
        #expect(AlertNotificationPlan.threadIdentifier(for: .cpu) == AlertNotificationPlan.identifier(for: .cpu))
        let threads = AlertSignal.allCases.map { AlertNotificationPlan.threadIdentifier(for: $0) }
        #expect(Set(threads).count == AlertSignal.allCases.count)
    }

    @Test("A fire is delivered only with the switch on and the permission given")
    func fired() {
        let effect = ThresholdEvaluator.Effect.fired(snapshot)
        #expect(
            AlertNotificationPlan.actions(for: effect, notificationsOn: true, access: .allowed)
                == [.showInNotch(.cpu), .deliver(.cpu)]
        )
        for access in [NotificationAccess.denied, .notDetermined] {
            #expect(
                AlertNotificationPlan.actions(for: effect, notificationsOn: true, access: access)
                    == [.showInNotch(.cpu)]
            )
        }
        #expect(
            AlertNotificationPlan.actions(for: effect, notificationsOn: false, access: .allowed)
                == [.showInNotch(.cpu)]
        )
    }

    @Test("An update changes the notch only and never delivers again")
    func updated() {
        for on in [true, false] {
            for access in accesses {
                #expect(
                    AlertNotificationPlan.actions(for: .updated(snapshot), notificationsOn: on, access: access)
                        == [.showInNotch(.cpu)]
                )
            }
        }
    }

    @Test("A clear finishes in the notch and withdraws the notification while the switch is on")
    func cleared() {
        #expect(
            AlertNotificationPlan.actions(for: .cleared(.cpu), notificationsOn: true, access: .allowed)
                == [.finishInNotch(.cpu), .withdraw(.cpu)]
        )
        #expect(
            AlertNotificationPlan.actions(for: .cleared(.cpu), notificationsOn: false, access: .allowed)
                == [.finishInNotch(.cpu)]
        )
    }

    @Test("An end removes from the notch and withdraws the notification while the switch is on")
    func ended() {
        #expect(
            AlertNotificationPlan.actions(for: .ended(.cpu), notificationsOn: true, access: .allowed)
                == [.removeFromNotch(.cpu), .withdraw(.cpu)]
        )
        #expect(
            AlertNotificationPlan.actions(for: .ended(.cpu), notificationsOn: false, access: .allowed)
                == [.removeFromNotch(.cpu)]
        )
    }

    private func isNotchAction(_ action: AlertChannelAction) -> Bool {
        switch action {
        case .showInNotch, .finishInNotch, .removeFromNotch:
            true
        case .deliver, .withdraw:
            false
        }
    }

    @Test("Every effect yields exactly one notch action, the same whatever the switch and permission say")
    func notchChannelIsUnconditional() {
        for effect in effects {
            var notchActions: [[AlertChannelAction]] = []
            for on in [true, false] {
                for access in accesses {
                    let actions = AlertNotificationPlan.actions(for: effect, notificationsOn: on, access: access)
                    let notch = actions.filter(isNotchAction)
                    #expect(notch.count == 1)
                    notchActions.append(notch)
                }
            }
            #expect(notchActions.count == 6)
            #expect(Set(notchActions.map { "\($0)" }).count == 1)
        }
    }

    @Test("A request that fails or is refused is denied")
    func afterRequest() {
        #expect(NotificationAccess.afterRequest(granted: true) == .allowed)
        #expect(NotificationAccess.afterRequest(granted: false) == .denied)
        #expect(NotificationAccess.afterRequest(granted: nil) == .denied)
    }
}
