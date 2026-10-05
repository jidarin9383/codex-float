import AppKit
import Foundation
import Observation
import CodexFloatCore

/// Main-actor UI store. Live quota via `QuotaRepository`; optional static fixtures for QA.
@MainActor
@Observable
final class QuotaViewModel {
    var snapshot: QuotaSnapshot
    private(set) var isManuallyRefreshing = false
    var isExpanded: Bool
    var useStaticFixtures: Bool
    /// When true, detail shows per-credit date rows (only if dates exist).
    var isResetOpportunityListExpanded: Bool = false

    /// Floating widget currently shown (surface mode; poll cadence is 60s either way).
    var floatingWidgetVisible: Bool = true

    @ObservationIgnored
    private let repository: QuotaRepository

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?

    @ObservationIgnored
    private var snapshotTask: Task<Void, Never>?

    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    init(
        snapshot: QuotaSnapshot = QuotaSnapshot(freshness: .loading, statusMessage: "正在读取额度…"),
        isExpanded: Bool = false,
        useStaticFixtures: Bool? = nil,
        repository: QuotaRepository = QuotaRepository()
    ) {
        self.repository = repository
        self.isExpanded = isExpanded

        let envStatic = ProcessInfo.processInfo.environment["CODEX_FLOAT_STATIC_FIXTURES"] == "1"
        let staticMode = useStaticFixtures ?? envStatic
        self.useStaticFixtures = staticMode

        if staticMode {
            self.snapshot = QuotaFixtures.healthy75Percent
        } else {
            self.snapshot = snapshot
        }
    }

    deinit {
        pollTask?.cancel()
        snapshotTask?.cancel()
    }

    // MARK: - Surfaces

    func expand() {
        isExpanded = true
        if !useStaticFixtures {
            Task { await refreshNow() }
        }
    }

    func collapse() {
        isExpanded = false
        isResetOpportunityListExpanded = false
    }

    func toggleExpanded() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    /// Number of reset-credit detail rows currently shown (0 when collapsed or no dates).
    var visibleResetOpportunityDetailRows: Int {
        guard isExpanded, isResetOpportunityListExpanded else { return 0 }
        let dated = snapshot.resetOpportunities.filter { $0.expiresAt != nil }
        return dated.isEmpty ? 0 : dated.count
    }

    var canExpandResetOpportunityList: Bool {
        snapshot.resetOpportunities.contains { $0.expiresAt != nil }
    }

    func setResetOpportunityListExpanded(_ expanded: Bool) {
        guard canExpandResetOpportunityList else {
            isResetOpportunityListExpanded = false
            return
        }
        isResetOpportunityListExpanded = expanded
    }

    func setFloatingWidgetVisible(_ visible: Bool) {
        floatingWidgetVisible = visible
        if visible, !useStaticFixtures {
            Task { await refreshNow() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        installWakeObserverIfNeeded()
        guard !useStaticFixtures else { return }
        restartPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        Task { await repository.shutdown() }
    }

    func restartPolling() {
        pollTask?.cancel()
        guard !useStaticFixtures else { return }
        observeSnapshotsIfNeeded()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    /// Immediate refresh (launch, wake, widget shown, expand).
    func refreshNow() async {
        guard !useStaticFixtures else { return }
        observeSnapshotsIfNeeded()
        await repository.refresh()
    }

    /// Explicit recovery bypasses the long-lived process and enrichment cache.
    func refreshManually() async {
        guard !useStaticFixtures, !isManuallyRefreshing else { return }
        isManuallyRefreshing = true
        defer { isManuallyRefreshing = false }
        observeSnapshotsIfNeeded()
        await repository.refresh(force: true)
    }

    // MARK: - Fixtures (dev QA via CODEX_FLOAT_STATIC_FIXTURES=1 only)

    func cycleFixture() {
        guard useStaticFixtures else { return }
        let fixtures = QuotaFixtures.debugCycle
        guard let index = fixtures.firstIndex(of: snapshot) else {
            snapshot = fixtures[0]
            return
        }
        snapshot = fixtures[(index + 1) % fixtures.count]
    }

    func setUseStaticFixtures(_ enabled: Bool) {
        useStaticFixtures = enabled
        if enabled {
            pollTask?.cancel()
            pollTask = nil
            snapshotTask?.cancel()
            snapshotTask = nil
            snapshot = QuotaFixtures.healthy75Percent
        } else {
            snapshot = QuotaSnapshot(freshness: .loading, statusMessage: "正在读取额度…")
            restartPolling()
        }
    }

    // MARK: - Private

    private func observeSnapshotsIfNeeded() {
        guard snapshotTask == nil else { return }
        let repository = self.repository
        snapshotTask = Task { [weak self] in
            let updates = await repository.snapshotUpdates()
            for await next in updates {
                guard !Task.isCancelled, let self, !self.useStaticFixtures else { return }
                self.snapshot = next
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await repository.refresh()
            guard !Task.isCancelled else { return }

            let mode: QuotaRepository.SurfaceMode =
                (floatingWidgetVisible || isExpanded) ? .widgetVisible : .menuBarOnly
            let delay = await repository.nextPollingDelay(mode: mode)
            let ns = UInt64(max(delay, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func installWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.useStaticFixtures else { return }
                await self.refreshNow()
            }
        }
    }
}
