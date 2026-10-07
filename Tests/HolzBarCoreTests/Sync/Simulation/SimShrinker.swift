import Foundation

/// Delta debugging (ddmin) over an event list. Re-running from the same seed is the caller's job: `failing` runs
/// a candidate list in a fresh world and says whether the same violation shows up.
struct SimShrinker {
    /// The most candidate runs one shrink may spend.
    var maximumRuns = 3_000

    init(maximumRuns: Int = 3_000) { self.maximumRuns = maximumRuns }

    /// A minimal sublist that still fails. The input must fail; if it does not it is returned unchanged.
    func shrink(_ events: [SimEvent], failing: ([SimEvent]) -> Bool) -> [SimEvent] {
        var runs = 0
        func fails(_ candidate: [SimEvent]) -> Bool {
            guard runs < maximumRuns else { return false }
            runs += 1
            return failing(candidate)
        }
        guard fails(events) else { return events }
        var current = events
        var chunks = 2
        while current.count >= 2 {
            let size = Int((Double(current.count) / Double(chunks)).rounded(.up))
            var reduced = false
            // Try every chunk alone, then every complement.
            var start = 0
            while start < current.count {
                let end = min(start + size, current.count)
                let subset = Array(current[start..<end])
                if subset.count < current.count, fails(subset) {
                    current = subset
                    chunks = 2
                    reduced = true
                    break
                }
                start = end
            }
            if !reduced {
                start = 0
                while start < current.count {
                    let end = min(start + size, current.count)
                    var complement = current
                    complement.removeSubrange(start..<end)
                    if !complement.isEmpty, fails(complement) {
                        current = complement
                        chunks = max(chunks - 1, 2)
                        reduced = true
                        break
                    }
                    start = end
                }
            }
            if !reduced {
                if chunks >= current.count { break }
                chunks = min(current.count, chunks * 2)
            }
        }
        // A final pass removes single events that survived chunking.
        var index = 0
        while index < current.count {
            var candidate = current
            candidate.remove(at: index)
            if !candidate.isEmpty, fails(candidate) {
                current = candidate
            } else {
                index += 1
            }
        }
        return current
    }
}
