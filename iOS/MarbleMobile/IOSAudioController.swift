import AVFoundation
import Foundation

struct MediaSettings: Equatable {
    var sfxEnabled: Bool
    var sfxVolume: Int
    var bgmEnabled: Bool
    var bgmVolume: Int

    static func load(from defaults: UserDefaults = .standard) -> MediaSettings {
        MediaSettings(
            sfxEnabled: defaults.object(forKey: "marble.media.sfxEnabled") as? Bool ?? true,
            sfxVolume: min(100, max(0, defaults.object(forKey: "marble.media.sfxVolume") as? Int ?? 70)),
            bgmEnabled: defaults.object(forKey: "marble.media.bgmEnabled") as? Bool ?? true,
            bgmVolume: min(100, max(0, defaults.object(forKey: "marble.media.bgmVolume") as? Int ?? 50))
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(sfxEnabled, forKey: "marble.media.sfxEnabled")
        defaults.set(sfxVolume, forKey: "marble.media.sfxVolume")
        defaults.set(bgmEnabled, forKey: "marble.media.bgmEnabled")
        defaults.set(bgmVolume, forKey: "marble.media.bgmVolume")
    }
}

@MainActor
final class IOSAudioController: NSObject, AVAudioPlayerDelegate {
    enum Role: Hashable { case sfx, voice }

    private struct ActivePlayback {
        let player: AVAudioPlayer
        let role: Role
        let completion: ((Bool) -> Void)?
    }

    private var active: [ObjectIdentifier: ActivePlayback] = [:]
    private var bgmPlayer: AVAudioPlayer?
    private var bgmRequest: (clip: String, loop: Bool)?
    private var turnWarningTickPlayer: AVAudioPlayer?
    private var turnWarningVoicePlayer: AVAudioPlayer?
    private var turnWarningZeroPlayer: AVAudioPlayer?
    private var turnWarningZeroCompletion: (() -> Void)?
    private var sessionConfigured = false
    private(set) var settings = MediaSettings.load()

    func applySettings(_ value: MediaSettings) {
        let previous = settings
        settings = MediaSettings(
            sfxEnabled: value.sfxEnabled,
            sfxVolume: min(100, max(0, value.sfxVolume)),
            bgmEnabled: value.bgmEnabled,
            bgmVolume: min(100, max(0, value.bgmVolume))
        )
        settings.save()
        if !settings.sfxEnabled && previous.sfxEnabled {
            stopTransient()
            stopTurnWarningAudio()
        }
        let sfxLevel = Float(settings.sfxVolume) / 100
        for playback in active.values { playback.player.volume = sfxLevel }
        turnWarningTickPlayer?.volume = sfxLevel
        turnWarningVoicePlayer?.volume = sfxLevel
        turnWarningZeroPlayer?.volume = sfxLevel
        if !settings.bgmEnabled {
            bgmPlayer?.stop()
            bgmPlayer = nil
        } else if !previous.bgmEnabled, let request = bgmRequest {
            playBGM(request.clip, loop: request.loop)
        } else {
            bgmPlayer?.volume = Float(settings.bgmVolume) / 100
        }
    }

    func configureIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio failure must never stop the authoritative game flow. The caller
            // falls back to VoiceOver for information-bearing recorded voice cues.
        }
    }

    @discardableResult
    func playSFX(_ clip: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        playOneShot(clip, role: .sfx, completion: completion)
    }

    @discardableResult
    func playVoice(_ clip: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        playOneShot(clip, role: .voice, completion: completion)
    }

    func playBGM(_ clip: String, loop: Bool) {
        bgmRequest = (clip, loop)
        guard settings.bgmEnabled else { return }
        configureIfNeeded()
        guard let url = resourceURL(for: clip) else { return }
        if let current = bgmPlayer,
           current.url == url,
           current.isPlaying {
            return
        }
        bgmPlayer?.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loop ? -1 : 0
            player.volume = Float(settings.bgmVolume) / 100
            player.prepareToPlay()
            player.play()
            bgmPlayer = player
        } catch {
            bgmPlayer = nil
        }
    }

    func stopBGM() {
        bgmRequest = nil
        bgmPlayer?.stop()
        bgmPlayer = nil
    }

    func pauseBGM() { bgmPlayer?.pause() }
    func resumeBGM() { if settings.bgmEnabled { bgmPlayer?.play() } }

    func stopVoice() {
        stopActiveRoles([.voice])
    }

    /// PC AudioController.stop_transient_output()/preempt_for_user_input()와 같은 경계.
    /// 현재 Voice와 SFX만 중단하고 persistent BGM은 유지한다.
    func stopTransient() {
        stopActiveRoles([.voice, .sfx])
    }

    func stopAll() {
        let values = Array(active.values)
        active.removeAll()
        for playback in values {
            playback.player.stop()
            playback.completion?(false)
        }
        stopTurnWarningAudio()
        stopBGM()
    }

    // MARK: - Turn deadline warning (PC dedicated channels 8/9 equivalent)

    @discardableResult
    func startTurnWarningTick(_ clip: String = "ticktock.wav") -> Bool {
        guard settings.sfxEnabled else { return false }
        configureIfNeeded()
        guard let url = resourceURL(for: clip) else { return false }
        turnWarningTickPlayer?.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = Float(settings.sfxVolume) / 100
            player.prepareToPlay()
            guard player.play() else { return false }
            turnWarningTickPlayer = player
            return true
        } catch {
            turnWarningTickPlayer = nil
            return false
        }
    }

    @discardableResult
    func playTurnWarningVoice(_ clip: String) -> Bool {
        guard settings.sfxEnabled else { return false }
        configureIfNeeded()
        guard let url = resourceURL(for: clip) else { return false }
        turnWarningVoicePlayer?.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(settings.sfxVolume) / 100
            player.prepareToPlay()
            guard player.play() else { return false }
            turnWarningVoicePlayer = player
            return true
        } catch {
            turnWarningVoicePlayer = nil
            return false
        }
    }

    @discardableResult
    func playTurnWarningZeroSFX(_ clip: String = "ticktock_0.WAV", completion: @escaping () -> Void) -> Bool {
        guard settings.sfxEnabled else { return false }
        configureIfNeeded()
        guard let url = resourceURL(for: clip) else { return false }
        turnWarningVoicePlayer?.stop()
        turnWarningVoicePlayer = nil
        if let player = turnWarningZeroPlayer {
            player.stop()
            turnWarningZeroCompletion?()
        }
        turnWarningZeroPlayer = nil
        turnWarningZeroCompletion = nil
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(settings.sfxVolume) / 100
            player.delegate = self
            player.prepareToPlay()
            turnWarningZeroPlayer = player
            turnWarningZeroCompletion = completion
            guard player.play() else {
                turnWarningZeroPlayer = nil
                turnWarningZeroCompletion = nil
                return false
            }
            return true
        } catch {
            turnWarningZeroPlayer = nil
            turnWarningZeroCompletion = nil
            return false
        }
    }

    func stopTurnWarningTickOnly() {
        turnWarningTickPlayer?.stop()
        turnWarningTickPlayer = nil
    }

    func stopTurnWarningAudio() {
        stopTurnWarningTickOnly()
        turnWarningVoicePlayer?.stop()
        turnWarningVoicePlayer = nil
        if let player = turnWarningZeroPlayer { player.stop() }
        turnWarningZeroPlayer = nil
        let completion = turnWarningZeroCompletion
        turnWarningZeroCompletion = nil
        completion?()
    }

    private func stopActiveRoles(_ roles: Set<Role>) {
        let keys = active.compactMap { key, playback in roles.contains(playback.role) ? key : nil }
        for key in keys {
            guard let playback = active.removeValue(forKey: key) else { continue }
            playback.player.stop()
            playback.completion?(false)
        }
    }

    private func playOneShot(_ clip: String, role: Role, completion: ((Bool) -> Void)?) -> Bool {
        guard settings.sfxEnabled else { return false }
        configureIfNeeded()
        guard let url = resourceURL(for: clip) else { return false }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(settings.sfxVolume) / 100
            player.delegate = self
            player.prepareToPlay()
            let key = ObjectIdentifier(player)
            active[key] = ActivePlayback(player: player, role: role, completion: completion)
            guard player.play() else {
                active.removeValue(forKey: key)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func resourceURL(for clip: String) -> URL? {
        let ns = clip as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Resources/Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.turnWarningZeroPlayer === player {
                self.turnWarningZeroPlayer = nil
                let completion = self.turnWarningZeroCompletion
                self.turnWarningZeroCompletion = nil
                completion?()
                return
            }
            let key = ObjectIdentifier(player)
            let playback = self.active.removeValue(forKey: key)
            playback?.completion?(flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.turnWarningZeroPlayer === player {
                self.turnWarningZeroPlayer = nil
                let completion = self.turnWarningZeroCompletion
                self.turnWarningZeroCompletion = nil
                completion?()
                return
            }
            let key = ObjectIdentifier(player)
            let playback = self.active.removeValue(forKey: key)
            playback?.completion?(false)
        }
    }
}
