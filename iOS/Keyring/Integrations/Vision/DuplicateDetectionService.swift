import Foundation
import Vision
import UIKit

/// On-device visual similarity between key photos, entirely local — nothing
/// leaves the device. Used to flag possible duplicates when a Pro user adds
/// a new key photo. Distances are Apple's raw feature-print metric, not a
/// calibrated probability, so results are surfaced as qualitative labels
/// ("very similar") rather than a fabricated percentage — the app never
/// claims certainty a photo alone can't support.
enum DuplicateDetectionService {
    enum Similarity {
        case veryHigh
        case high
        case moderate

        var label: String {
            switch self {
            case .veryHigh: return "Very similar"
            case .high: return "Similar"
            case .moderate: return "Possibly similar"
            }
        }
    }

    struct Candidate {
        let key: KeyEntity
        let similarity: Similarity
    }

    /// Distances below this are worth surfacing at all; Apple's feature
    /// print distance has no fixed upper bound, but empirically distinct
    /// everyday objects land well above this.
    private static let moderateThreshold: Float = 22
    private static let highThreshold: Float = 14
    private static let veryHighThreshold: Float = 8

    private static func featurePrint(for imageData: Data) -> VNFeaturePrintObservation? {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    /// Runs on a background thread; call with `await Task.detached`.
    static func findCandidates(forNewPhoto newPhotoData: Data, among keys: [KeyEntity]) -> [Candidate] {
        guard let newPrint = featurePrint(for: newPhotoData) else { return [] }
        var candidates: [Candidate] = []
        for key in keys {
            guard let photoData = key.photoData, let print = featurePrint(for: photoData) else { continue }
            var distance: Float = .greatestFiniteMagnitude
            guard (try? newPrint.computeDistance(&distance, to: print)) != nil else { continue }
            guard distance < moderateThreshold else { continue }
            let similarity: Similarity = distance < veryHighThreshold ? .veryHigh : (distance < highThreshold ? .high : .moderate)
            candidates.append(Candidate(key: key, similarity: similarity))
        }
        return candidates.sorted { lhs, rhs in
            rank(lhs.similarity) < rank(rhs.similarity)
        }
    }

    private static func rank(_ similarity: Similarity) -> Int {
        switch similarity {
        case .veryHigh: return 0
        case .high: return 1
        case .moderate: return 2
        }
    }
}
