import AppKit
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
        let text = normalized(rawText)
        let words = Set(text.split(separator: " ").map(String.init))

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

        let affirmativeWords: Set<String> = [
            "start", "yes", "yeah", "yea", "yep", "okay", "ok", "ready", "sure"
        ]
        let affirmativePhrases = [
            "lets do it", "let us do it", "lets go", "go ahead", "sounds good"
        ]
        if !words.isDisjoint(with: affirmativeWords)
            || affirmativePhrases.contains(where: text.contains) {
            return .start
        }

        return .unknown
    }

    private static func normalized(_ rawText: String) -> String {
        rawText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: #"[^a-z0-9-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
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

enum CheckInVoiceAction: Equatable {
    case startRoutine
    case postpone(minutes: Int)
    case tomorrow
    case ignore

    static func resolve(_ command: VoiceCommand) -> CheckInVoiceAction {
        switch command {
        case .start: return .startRoutine
        case .later(let minutes): return .postpone(minutes: minutes)
        case .tomorrow: return .tomorrow
        case .unknown: return .ignore
        }
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
    private var listeningTimeout: Task<Void, Never>?
    private var tapInstalled = false

    func requestAndListen() {
        NSApp.activate(ignoringOtherApps: true)
        guard recognizer?.isAvailable == true else {
            availabilityMessage = "Voice isn’t available right now."
            return
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            availabilityMessage = "Allow Speech Recognition when macOS asks."
        case .authorized:
            availabilityMessage = "Checking microphone access…"
        case .denied, .restricted:
            availabilityMessage = "Enable Speech Recognition in System Settings, or use the buttons."
            return
        @unknown default:
            availabilityMessage = "Voice isn’t available right now — the buttons still work."
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.availabilityMessage = "Enable Speech Recognition in System Settings, or use the buttons."
                    return
                }

                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    self?.availabilityMessage = "Allow Microphone access when macOS asks."
                } else {
                    self?.availabilityMessage = "Starting voice…"
                }
                let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard microphoneAllowed else {
                    self?.availabilityMessage = "Enable Microphone access in System Settings, or use the buttons."
                    return
                }
                self?.beginListening()
            }
        }
    }

    func stopListening() {
        listeningTimeout?.cancel()
        listeningTimeout = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    private func beginListening() {
        if isListening { stopListening() }

        transcript = ""
        availabilityMessage = "Starting voice…"
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            availabilityMessage = "No microphone input is available — the buttons still work."
            self.request = nil
            return
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            availabilityMessage = nil
            startListeningTimeout()
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
                    self.availabilityMessage = self.transcript.isEmpty
                        ? "I didn’t hear anything. Try again or use a button."
                        : "I didn’t catch a command. Say start, later, or tomorrow."
                }
            }
        }
    }

    private func startListeningTimeout() {
        listeningTimeout?.cancel()
        listeningTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isListening else { return }
            self.stopListening()
            self.availabilityMessage = "I didn’t hear a command. Try again or use a button."
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
