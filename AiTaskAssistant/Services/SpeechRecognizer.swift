import Foundation
import Speech
import AVFoundation

enum RecognitionState {
    case idle, recording, unavailable
}

@MainActor
@Observable
final class SpeechRecognizer {
    private(set) var state: RecognitionState = .idle
    private(set) var transcript: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // Confirmed via an actual TestFlight crash log (2026-07-02, iPhone 14 / iOS 26.5):
    // `dispatch_assert_queue_fail` inside `_swift_task_checkIsolatedSwift`, in the completion
    // closure passed to `SFSpeechRecognizer.requestAuthorization`. Because this method lives on
    // a `@MainActor` class, the compiler infers that closure as MainActor-isolated — but TCC
    // actually invokes it on its own background XPC callback thread, and Swift 6's runtime
    // isolation check crashes on that mismatch. Marking the method `nonisolated` stops the
    // closure from being inferred as MainActor-bound in the first place, since resuming a
    // continuation is safe from any thread regardless.
    nonisolated func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        return audioStatus
    }

    func startRecording() {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Forcing on-device recognition when the current locale's on-device model isn't
        // downloaded/available (common for non-English locales, e.g. German, unless the user has
        // specifically downloaded that dictation language) is a plausible source of unpredictable
        // behavior — fall back to server-based recognition instead of hard-requiring it.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        do {
            let session = AVAudioSession.sharedInstance()
            // .measurement disables the system's audio processing entirely, which on some
            // devices/routes leaves the input node reporting an invalid (zero-sample-rate)
            // format — installTap then throws an Objective-C exception Swift can't catch,
            // crashing the app outright. .default is what Apple's own speech-recognition sample
            // code uses and does not have this failure mode.
            try session.setCategory(.record, mode: .default, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Defensive guard against the crash above regardless of root cause: never install a tap
        // with a format the engine can't actually use.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .unavailable
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            state = .unavailable
            return
        }

        transcript = ""
        audioEngine = engine
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopRecording()
                    }
                }
            }
            if let error {
                let nsError = error as NSError
                // 203 = "Retry" — transient, ignore. 1110 = no speech detected.
                if nsError.code != 203 && nsError.code != 1110 {
                    Task { @MainActor in self.stopRecording() }
                }
            }
        }

        state = .recording
    }

    func stopRecording() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
    }
}
