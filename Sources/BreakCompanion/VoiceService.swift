import AVFoundation
import Foundation
import Speech

enum VoiceCommand: Equatable {
    case start
    case later(minutes: Int)
    case tomorrow
    case unknown
}

enum VoiceCommandParser {
    static func parse(_ rawText: String) -> VoiceCommand {
        let text = rawText.lowercased()

        if text.contains("tomorrow") { return .tomorrow }

        if let minutes = firstNumber(in: text), text.contains("minute") {
            return .later(minutes: max(1, min(minutes, 12 * 60)))
        }

        if let hours = firstNumber(in: text), text.contains("hour") {
            return .later(minutes: max(1, min(hours * 60, 12 * 60)))
        }

        if text.contains("later") || text.contains("not now") || text.contains("in an hour") {
            return .later(minutes: 60)
        }

        if text.contains("start") || text.contains("yes") || text.contains("okay") || text.contains("ready") {
            return .start
        }

        return .unknown
    }

    private static func firstNumber(in text: String) -> Int? {
        if let range = text.range(of: #"\b\d+\b"#, options: .regularExpression) {
            return Int(text[range])
        }

        let words: [(String, Int)] = [
            ("forty-five", 45), ("sixty", 60), ("forty", 40), ("thirty", 30),
            ("twenty", 20), ("fifteen", 15), ("ten", 10), ("five", 5),
            ("four", 4), ("three", 3), ("two", 2), ("one", 1)
        ]
        return words.first(where: { word, _ in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
        })?.1
    }
}

@MainActor
final class VoiceService: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var availabilityMessage: String?

    var onCommand: ((VoiceCommand) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAndListen() {
        guard recognizer?.isAvailable == true else {
            availabilityMessage = "Voice isn’t available right now."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.availabilityMessage = "Voice permission is off — the buttons still work."
                    return
                }
                let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard microphoneAllowed else {
                    self?.availabilityMessage = "Microphone permission is off — the buttons still work."
                    return
                }
                self?.beginListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    private func beginListening() {
        if isListening { stopListening() }

        transcript = ""
        availabilityMessage = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            availabilityMessage = "Voice couldn’t start — the buttons still work."
            stopListening()
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    let command = VoiceCommandParser.parse(self.transcript)
                    if command != .unknown {
                        self.stopListening()
                        self.onCommand?(command)
                        return
                    }
                }
                if error != nil || result?.isFinal == true {
                    self.stopListening()
                }
            }
        }
    }
}

@MainActor
final class GuideSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.02
        utterance.volume = 0.82
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
