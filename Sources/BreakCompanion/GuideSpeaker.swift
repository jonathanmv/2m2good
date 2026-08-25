import AVFoundation

@MainActor
/// The spoken side of the companion, injectable so guidance can be observed in tests.
protocol RoutineSpeaking {
    func speak(_ text: String)
    func stop()
}

final class GuideSpeaker: RoutineSpeaking {
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
