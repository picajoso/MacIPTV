import AVFoundation
import AppKit
import Observation
import SwiftUI
import MacIPTVCore

enum PlayerStatus: Equatable {
    case idle
    case loading
    case playing
    case failed(String)
}

@Observable @MainActor final class RetryCounter { var count = 0 }

/// Reproductor AVFoundation con recuperacion acotada de emisiones en directo.
/// Acepta canal opcional: sin seleccion muestra un aviso en lugar de fallar.
struct PlayerView: View {
    let channel: Channel?
    @State private var player = AVPlayer()
    @State private var status: PlayerStatus = .idle
    @State private var observation: NSKeyValueObservation?
    @State private var retryCounter = RetryCounter()
    @State private var generation = 0
    @State private var isPaused = false
    @State private var isMuted = false
    @State private var volume = 1.0
    @State private var recovery = PlaybackRecovery()
    @State private var watchdog: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var notifications: [NSObjectProtocol] = []
    @State private var isBuffering = false
    @State private var sessionID = UUID()
    @State private var startedAt = 0.0
    @State private var relay: HLSRelay?
    @State private var connectionTask: Task<Void, Never>?
    @State private var relayCleanup: Task<Void, Never>?
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // La superficie no se destruye al pasar de loading a playing ni
            // al cambiar de canal. No usa los controles internos de AVKit.
            NativePlayerView(player: player)
            if status != .playing {
                placeholder
            }
        }
        .overlay(alignment: .bottom) {
            if status == .playing {
                playbackControls
                    .opacity(controlsVisible ? 1 : 0)
                    // Los controles ocultos no capturan clics ni voz.
                    .allowsHitTesting(controlsVisible)
                    .accessibilityHidden(!controlsVisible)
            }
        }
        .overlay {
            if status == .loading || isBuffering {
                ProgressView(isBuffering ? "Recuperando la emisión..." : "Conectando con el canal...")
                    .padding()
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        // Una sola transicion por cambio de canal evita abrir dos conexiones
        // a la vez cuando cambian su id y su URL en el mismo render.
        .onChange(of: channel) { _, _ in start() }
        .onChange(of: retryCounter.count) { _, _ in start() }
        // Los cambios de estado reprograman o fijan la visibilidad sin
        // necesidad de mover el puntero (p. ej. inicio de recuperacion).
        .onChange(of: status) { _, _ in scheduleHideControls() }
        .onChange(of: isPaused) { _, _ in scheduleHideControls() }
        .onChange(of: isBuffering) { _, _ in scheduleHideControls() }
        // El movimiento continuo del puntero revela los controles; al
        // detenerse se reprograma el ocultado de tres segundos.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showControls()
                scheduleHideControls()
            case .ended:
                scheduleHideControls()
            }
        }
        .onKeyPress { _ in
            showControls()
            scheduleHideControls()
            return .ignored
        }
        .onAppear { start() }
        .onDisappear {
            stop()
            hideControlsTask?.cancel()
            hideControlsTask = nil
        }
    }

    private func showControls() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        guard !controlsVisible else { return }
        controlsVisible = true
    }

    /// Aplaza el ocultado tres segundos durante reproduccion sin pausar ni
    /// recuperar emision; en cualquier otro estado los controles quedan fijos.
    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        guard status == .playing, !isPaused, !isBuffering, !NSWorkspace.shared.isVoiceOverEnabled else {
            controlsVisible = true
            return
        }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            hideControlsTask = nil
            controlsVisible = false
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 14) {
            Button {
                isPaused.toggle()
                recovery.resetProgress()
                if isPaused {
                    player.pause()
                    scheduleHideControls()
                } else {
                    player.play()
                    scheduleHideControls()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
            }
            .help(isPaused ? "Reproducir" : "Pausar")
            .accessibilityLabel(isPaused ? "Reproducir" : "Pausar")
            Button {
                isMuted.toggle()
                player.isMuted = isMuted
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(isMuted ? "Activar sonido" : "Silenciar")
            .accessibilityLabel(isMuted ? "Activar sonido" : "Silenciar")
            Slider(value: $volume, in: 0...1)
                .frame(width: 100)
                .accessibilityLabel("Volumen")
                .onChange(of: volume) { _, value in player.volume = Float(value) }
            Spacer()
            Text("En directo").font(.caption).foregroundStyle(.secondary)
            Button {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Pantalla completa")
            .accessibilityLabel("Pantalla completa")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.8))
    }

    @ViewBuilder private var placeholder: some View {
        VStack(spacing: 14) {
            if let channel, case .failed(let detail) = status {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("El canal «" + channel.name + "» no se pudo reproducir o se corto la emision.")
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                Button("Reintentar") { retryCounter.count += 1 }
                    .keyboardShortcut("r", modifiers: .command)
                Text("Si este canal no funciona con el reproductor integrado, puede necesitar un reproductor externo compatible con MPEG-TS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if channel == nil {
                Image(systemName: "play.tv")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Selecciona un canal de la lista para reproducir")
                    .foregroundStyle(.secondary)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }

    private func cleanObservers() {
        connectionTask?.cancel()
        connectionTask = nil
        if let previousRelay = relay {
            let previousCleanup = relayCleanup
            relayCleanup = Task { await previousCleanup?.value; await previousRelay.stop() }
            relay = nil
        }
        watchdog?.cancel()
        watchdog = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        observation?.invalidate()
        observation = nil
    }

    private func stop() {
        generation += 1
        cleanObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func start(resetRecovery: Bool = true) {
        generation += 1
        cleanObservers()
        if resetRecovery { recovery = PlaybackRecovery() }
        recovery.resetProgress()
        isBuffering = false
        let generation = self.generation
        player.replaceCurrentItem(with: nil)
        guard let channel, let url = URL(string: channel.url) else {
            status = .idle
            return
        }
        status = .loading
        sessionID = UUID()
        startedAt = ProcessInfo.processInfo.systemUptime
        DiagnosticLog.record(.started)
        isPaused = false
        player.volume = Float(volume)
        player.isMuted = isMuted
        let nativeURL = PlaybackPolicy.nativeURL(for: url)
        if PlaybackPolicy.needsHLSRelay(for: nativeURL) {
            let adapter = HLSRelay()
            relay = adapter
            let cleanup = relayCleanup
            connectionTask = Task { @MainActor in
                await cleanup?.value
                guard generation == self.generation, !Task.isCancelled else { return }
                do {
                    let localURL = try await adapter.start(upstream: nativeURL)
                    guard generation == self.generation, !Task.isCancelled else { await adapter.stop(); return }
                    self.configurePlayer(url: localURL, generation: generation, isReconnect: !resetRecovery)
                } catch {
                    await adapter.stop()
                    guard generation == self.generation, !Task.isCancelled else { return }
                    DiagnosticLog.record(.playback, error: error)
                    self.status = .failed(ErrorDiagnostics.summary(error))
                }
            }
        } else {
            configurePlayer(url: nativeURL, generation: generation, isReconnect: !resetRecovery)
        }
    }

    private func configurePlayer(url: URL, generation: Int, isReconnect: Bool) {
        let asset = AVURLAsset(url: url,
                               options: [AVURLAssetHTTPUserAgentKey: PlaybackPolicy.userAgent])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            DispatchQueue.main.async {
                guard generation == self.generation, self.player.currentItem === item else { return }
                switch item.status {
                case .failed:
                    self.handleInterruption(item, generation: generation)
                case .readyToPlay:
                    self.snapshot(item, trigger: .ready)
                    self.status = .playing
                default:
                    break
                }
            }
        }
        for name in [AVPlayerItem.playbackStalledNotification,
                     AVPlayerItem.failedToPlayToEndTimeNotification,
                     AVPlayerItem.didPlayToEndTimeNotification,
                     AVPlayerItem.newErrorLogEntryNotification, AVPlayerItem.newAccessLogEntryNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { notification in
                guard generation == self.generation, self.player.currentItem === item else { return }
                if name == AVPlayerItem.newAccessLogEntryNotification {
                    self.snapshot(item, trigger: .access)
                } else if name == AVPlayerItem.newErrorLogEntryNotification {
                    self.logMediaError(item)
                } else if name == AVPlayerItem.playbackStalledNotification {
                    DiagnosticLog.record(.stalled)
                    self.snapshot(item, trigger: .stalled)
                    self.isBuffering = !self.isPaused
                } else {
                    DiagnosticLog.record(.ended)
                    self.snapshot(item, trigger: .ended)
                    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
                        DiagnosticLog.record(.playback, error: error)
                    }
                    self.handleInterruption(item, generation: generation)
                }
            }
            notifications.append(token)
        }
        watchdog = Task { @MainActor in
            var reportedRecovery = !isReconnect
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard generation == self.generation, self.player.currentItem === item else { return }
                if !reportedRecovery && self.player.timeControlStatus == .playing && self.player.currentTime().seconds > 0.1 {
                    DiagnosticLog.record(.recovered)
                    reportedRecovery = true
                }
                ticks += 1
                if ticks % 5 == 0 { self.snapshot(item, trigger: .periodic) }
                let stalled = self.recovery.sample(now: ProcessInfo.processInfo.systemUptime,
                    position: self.player.currentTime().seconds, paused: self.isPaused)
                self.isBuffering = !self.isPaused && self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if stalled {
                    DiagnosticLog.record(.stalled)
                    self.handleInterruption(item, generation: generation)
                    return
                }
            }
        }
        player.play()
    }

    private func snapshot(_ item: AVPlayerItem, trigger: PlaybackSnapshot.Trigger) {
        let position = player.currentTime().seconds
        let ahead = item.loadedTimeRanges.map { $0.timeRangeValue }.map { $0.end.seconds - position }.max() ?? 0
        let ranges = item.seekableTimeRanges.map { $0.timeRangeValue }
        let event = item.accessLog()?.events.last
        let transport: PlaybackSnapshot.Transport = player.timeControlStatus == .playing ? .playing : (player.timeControlStatus == .paused ? .paused : .waiting)
        let reason = player.reasonForWaitingToPlay
        let wait: PlaybackSnapshot.Wait = reason == nil ? .none : (reason == .toMinimizeStalls ? .buffer : (reason == .evaluatingBufferingRate ? .evaluate : (reason == .noItemToPlay ? .noItem : .other)))
        DiagnosticLog.record(PlaybackSnapshot(trigger: trigger, session: sessionID,
            elapsed: ProcessInfo.processInfo.systemUptime - startedAt, position: position,
            duration: item.duration.seconds, rate: player.rate, itemStatus: item.status.rawValue,
            transport: transport, wait: wait, bufferedAhead: max(0, ahead),
            seekableStart: ranges.first?.start.seconds ?? .nan, seekableEnd: ranges.last?.end.seconds ?? .nan,
            bufferEmpty: item.isPlaybackBufferEmpty, likelyToKeepUp: item.isPlaybackLikelyToKeepUp,
            mediaRequests: event?.numberOfMediaRequests ?? 0, stalls: event?.numberOfStalls ?? 0,
            bytes: event?.numberOfBytesTransferred ?? 0, observedBitrate: event?.observedBitrate ?? 0,
            indicatedBitrate: event?.indicatedBitrate ?? 0, droppedFrames: event?.numberOfDroppedVideoFrames ?? 0))
    }

    private func logMediaError(_ item: AVPlayerItem) {
        snapshot(item, trigger: .mediaError)
        if let event = item.errorLog()?.events.last {
            DiagnosticLog.recordMediaReason(.classify(event.errorComment))
            DiagnosticLog.record(.playback, error: NSError(domain: event.errorDomain, code: event.errorStatusCode))
        }
    }

    private func handleInterruption(_ item: AVPlayerItem, generation: Int) {
        guard generation == self.generation, reconnectTask == nil,
              player.currentItem === item, !isPaused else { return }
        snapshot(item, trigger: .failed)
        if let error = item.error { DiagnosticLog.record(.playback, error: error) }
        logMediaError(item)
        watchdog?.cancel()
        watchdog = nil
        // Detach the old stream before retrying: IPTV accounts often allow one connection.
        observation?.invalidate()
        observation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        guard let delay = recovery.nextRetryDelay() else {
            DiagnosticLog.record(.exhausted)
            isBuffering = false
            status = .failed("La emisión se ha detenido y no se ha recuperado tras tres reconexiones. " +
                (item.error.map(ErrorDiagnostics.summary) ?? "El reproductor ha interrumpido la emisión. Consulta el diagnóstico para conocer el motivo."))
            return
        }
        DiagnosticLog.record(.reconnecting)
        status = .loading
        isBuffering = true
        reconnectTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard generation == self.generation, !Task.isCancelled else { return }
            self.start(resetRecovery: false)
        }
    }
}

/// Superficie de video persistente, sin los controles AVKit que activaban
/// un SIGTRAP dentro de su Binding SwiftUI en macOS 27 al cambiar de canal.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurface {
        let view = PlayerSurface(frame: .zero)
        view.videoLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerSurface, context: Context) {
        if nsView.videoLayer.player !== player {
            nsView.videoLayer.player = player
        }
    }

    static func dismantleNSView(_ nsView: PlayerSurface, coordinator: ()) {
        nsView.videoLayer.player = nil
    }
}

final class PlayerSurface: NSView {
    let videoLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.black.cgColor
        layer = videoLayer
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
