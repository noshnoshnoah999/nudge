// ReminderScanner.swift — Nudge (iOS / macCatalyst)
// On-device OCR. Turns a photo/screenshot of a list into plain text lines using Apple's
// Vision framework. Runs entirely on the device — the image is NEVER uploaded. Only the
// extracted TEXT is later sent to Claude (see AIScanParser) to structure into reminders.

import Foundation
import Vision
import UIKit

enum ReminderScanner {
    enum ScanError: LocalizedError {
        case noImage
        case noText
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .noImage: return "Couldn't read that image."
            case .noText:  return "No text found in the image."
            case .failed(let m): return m
            }
        }
    }

    /// Recognise text in `image` on-device and return it as newline-joined lines, ordered
    /// top-to-bottom, left-to-right. Uses the accurate path with language correction so typed
    /// screenshots and reasonably clear handwriting both come through.
    static func extractText(from image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { throw ScanError.noImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    continuation.resume(throwing: ScanError.failed(err.localizedDescription)); return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                // Sort top-to-bottom (Vision's origin is bottom-left, so larger y = higher up),
                // then left-to-right, so multi-column-ish lists still read in a sane order.
                let lines: [String] = observations
                    .sorted { a, b in
                        if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01 {
                            return a.boundingBox.midY > b.boundingBox.midY
                        }
                        return a.boundingBox.minX < b.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !lines.isEmpty else {
                    continuation.resume(throwing: ScanError.noText); return
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            // Vision is synchronous work — keep it off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { continuation.resume(throwing: ScanError.failed(error.localizedDescription)) }
            }
        }
    }
}
