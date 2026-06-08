import Foundation
import SwiftUI

// Shared helpers for the menu view sections: draft <-> live syncing, the
// live-progress projection, and RTL detection for track metadata.
extension BeastMenuView {
    var isRTLText: Bool {
        let sample = [model.media?.title, model.media?.author]
            .compactMap { $0 }
            .joined(separator: " ")
        return sample.unicodeScalars.contains { scalar in
            (0x0590...0x08FF).contains(scalar.value) || (0xFB50...0xFDFF).contains(scalar.value) || (0xFE70...0xFEFF).contains(scalar.value)
        }
    }

    func syncVolumeDraft() {
        if let volume = model.media?.volume {
            volumeDraft = volume
        } else {
            volumeDraft = 0
        }
    }

    func syncSeekDraft() {
        seekDraft = progress(for: model.media)
    }

    func progress(for media: BeastMediaSnapshot?) -> Double {
        guard let media else { return 0 }
        let base = media.progressSeconds ?? 0
        guard media.isPlaying == true, let fetchedAt = media.fetchedAt else {
            return clamp(base, lower: 0, upper: media.durationSeconds ?? base)
        }
        let age = Date().timeIntervalSince1970 - fetchedAt
        let next = base + max(0, age)
        if let duration = media.durationSeconds, duration > 0 {
            return clamp(next, lower: 0, upper: duration)
        }
        return max(0, next)
    }
}
