import Cocoa
import Vision
import CoreGraphics
import ScreenCaptureKit

struct ExtractedText {
    let word: String
    let context: String
}

class TextExtractor {
    
    /// Extracts the word (English or Chinese depending on translation mode) directly under the mouse cursor,
    /// along with its containing line/sentence as context.
    ///
    /// Screen capture + OCR are heavy, so this hops off the main thread; only the mouse
    /// position is read here on the main thread.
    @MainActor
    static func extractWordAtCursor(mode: String) async -> ExtractedText? {
        let mousePos = NSEvent.mouseLocation
        let cgPoint = CGPoint(
            x: mousePos.x,
            y: CGFloat(CGDisplayBounds(CGMainDisplayID()).height) - mousePos.y
        )
        return await Task.detached(priority: .userInitiated) {
            await extract(mode: mode, center: cgPoint)
        }.value
    }

    private static func extract(mode: String, center cgPoint: CGPoint) async -> ExtractedText? {
        // Define capture bounds centered around the mouse cursor (in Quartz global coordinates).
        let width: CGFloat = 400
        let height: CGFloat = 80
        let captureRect = CGRect(
            x: cgPoint.x - (width / 2),
            y: cgPoint.y - (height / 2),
            width: width,
            height: height
        )

        // Capture screen contents in memory (ScreenCaptureKit; app requires macOS 15.2+).
        guard #available(macOS 15.2, *) else { return nil }
        guard let cgImage = try? await SCScreenshotManager.captureImage(in: captureRect) else {
            print("[TextExtractor] Failed to capture screen image. Screen Recording permission might be missing.")
            return nil
        }

        // 4. Set up and run Vision OCR
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        
        // Setup OCR languages dynamically
        if mode == "zh-to-en" {
            request.recognitionLanguages = ["zh-Hans", "en-US"]
        } else {
            request.recognitionLanguages = ["en-US"]
        }
        
        request.usesLanguageCorrection = true

        do {
            try requestHandler.perform([request])
        } catch {
            print("[TextExtractor] OCR error: \(error)")
            return nil
        }

        guard let results = request.results, !results.isEmpty else {
            return nil
        }

        // The mouse coordinate inside the captured image is exactly the center of the image.
        // In Vision's normalized coordinate system, (0,0) is bottom-left, (1,1) is top-right.
        // Therefore, the mouse is exactly at (0.5, 0.5).
        let targetPoint = CGPoint(x: 0.5, y: 0.5)

        var bestWord: String? = nil
        var bestContext: String? = nil
        var closestDistance: CGFloat = CGFloat.infinity

        for observation in results {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let lineText = candidate.string
            let lineBox = observation.boundingBox

            // Expand the height box slightly to capture letters that go below baseline (g, y, p, etc.)
            let verticalPadding: CGFloat = 0.05
            let expandedLineBox = CGRect(
                x: lineBox.origin.x,
                y: lineBox.origin.y - verticalPadding,
                width: lineBox.size.width,
                height: lineBox.size.height + (verticalPadding * 2)
            )

            // If the cursor is vertically and horizontally inside this line's box
            if expandedLineBox.contains(targetPoint) {
                let tokenizedWords = tokenize(lineText, mode: mode)
                
                for wordInfo in tokenizedWords {
                    do {
                        if let wordBox = try candidate.boundingBox(for: wordInfo.range) {
                            let box = wordBox.boundingBox
                            
                            // Check if cursor x-coordinate is within word's horizontal bounds
                            if targetPoint.x >= box.minX && targetPoint.x <= box.maxX {
                                bestWord = wordInfo.word
                                bestContext = lineText
                                break
                            }
                            
                            // Otherwise record the closest word by center distance
                            let centerX = box.midX
                            let distance = abs(targetPoint.x - centerX)
                            if distance < closestDistance {
                                closestDistance = distance
                                bestWord = wordInfo.word
                                bestContext = lineText
                            }
                        }
                    } catch {
                        print("[TextExtractor] Error getting bounding box for word: \(error)")
                    }
                }
                
                if bestWord != nil {
                    break
                }
            }
        }

        // Clean and filter the word (ensure it matches the active translation mode)
        if let word = bestWord {
            if mode == "zh-to-en" {
                // Chinese-to-English: Filter characters to make sure it contains Chinese
                let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedWord.isEmpty && isChineseWord(cleanedWord) {
                    return ExtractedText(word: cleanedWord, context: bestContext ?? word)
                }
            } else {
                // English-to-Chinese: Filter characters to make sure it is English
                // Preserve hyphens and apostrophes within words (e.g. "wi-fi", "don't")
                let allowedChars = CharacterSet.letters.union(CharacterSet(charactersIn: "-'"))
                let cleanedWord = word.trimmingCharacters(in: allowedChars.inverted)
                if !cleanedWord.isEmpty && isEnglishWord(cleanedWord) {
                    return ExtractedText(word: cleanedWord, context: bestContext ?? word)
                }
            }
        }

        return nil
    }

    private static let englishWordRegex = try! NSRegularExpression(pattern: "^[a-zA-Z]+(['-][a-zA-Z]+)*$")
    private static let hanRegex = try! NSRegularExpression(pattern: "\\p{Han}")

    /// Check if the word is composed of English alphabetical characters (allowing hyphens and apostrophes within).
    private static func isEnglishWord(_ word: String) -> Bool {
        // Must start and end with a letter, may contain hyphens/apostrophes in the middle
        let range = NSRange(word.startIndex..., in: word)
        return englishWordRegex.firstMatch(in: word, range: range) != nil
    }

    /// Check if the word contains Chinese Han characters.
    private static func isChineseWord(_ word: String) -> Bool {
        let range = NSRange(word.startIndex..., in: word)
        return hanRegex.firstMatch(in: word, range: range) != nil
    }

    /// Tokenizes a line into words and their corresponding Ranges in the String.
    private static func tokenize(_ text: String, mode: String) -> [(word: String, range: Range<String.Index>)] {
        var words: [(word: String, range: Range<String.Index>)] = []
        
        if mode == "zh-to-en" {
            // Apple's .byWords option natively splits Chinese sentences into words using linguistic analysis
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
                if let word = substring {
                    words.append((word: word, range: range))
                }
            }
            
            // Fallback to characters if word segmentation returns empty
            if words.isEmpty {
                text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byComposedCharacterSequences) { substring, range, _, _ in
                    if let word = substring {
                        words.append((word: word, range: range))
                    }
                }
            }
        } else {
            // Standard English word segmentation
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
                if let word = substring {
                    words.append((word: word, range: range))
                }
            }
            
            // Merge adjacent words connected by hyphens (e.g. "wi" + "fi" → "wi-fi")
            words = mergeHyphenatedWords(words, in: text)
        }
        
        return words
    }
    
    /// Merges adjacent tokenized words that are connected by hyphens in the original text.
    /// e.g. ["wi", "fi"] in "wi-fi" → ["wi-fi"]
    /// e.g. ["state", "of", "the", "art"] in "state-of-the-art" → ["state-of-the-art"]
    private static func mergeHyphenatedWords(_ words: [(word: String, range: Range<String.Index>)], in text: String) -> [(word: String, range: Range<String.Index>)] {
        guard words.count > 1 else { return words }
        
        var merged: [(word: String, range: Range<String.Index>)] = []
        var i = 0
        
        while i < words.count {
            var currentWord = words[i].word
            var currentRange = words[i].range
            
            // Look ahead: check if the next word is connected by a hyphen
            while i + 1 < words.count {
                let gapStart = currentRange.upperBound
                let gapEnd = words[i + 1].range.lowerBound
                
                // Check if the text between current and next word is exactly a hyphen
                if gapStart < gapEnd {
                    let gap = String(text[gapStart..<gapEnd])
                    if gap == "-" {
                        // Merge: "wi" + "-" + "fi" → "wi-fi"
                        currentWord += "-" + words[i + 1].word
                        currentRange = currentRange.lowerBound..<words[i + 1].range.upperBound
                        i += 1
                        continue
                    }
                }
                break
            }
            
            merged.append((word: currentWord, range: currentRange))
            i += 1
        }
        
        return merged
    }
}
