import AppKit
import SwiftUI
import WeftCore
import WeftUI

/// How long the app takes over what a person does to it, for making it
/// quicker: run with a snapshot's other settings,
///
///     WEFT_SNAPSHOT=out.png WEFT_TABS="A|B;C" WEFT_BENCH=switch,hover,type \
///       build/Weft.app/Contents/MacOS/WeftMac -GraphPath <graph>
///
/// each scenario done `WEFT_BENCH_N` times (30), and for each the time from
/// doing it to the main thread being idle again — laid out, drawn, the frame
/// committed — printed as its median, 90th percentile and worst; with the
/// main thread's busy share over the run, for what animates after.
///
/// - `switch`: the first two tabs shown in turn.
/// - `hover`: the pointer run back and forth along the tabs, a move each 8ms.
/// - `type`: a letter typed at the end of the card being written in, then taken out.
/// - `save`: the same, a pause after each for the page to be written: its work, the writing's.
/// - `open`: each card of `WEFT_BENCH_OPEN` (A|B) opened at the top, then closed.
/// - `scroll`: the river scrolled down and back, 40 points a step.
@MainActor
enum Bench {
    static var isAsked: Bool { ProcessInfo.processInfo.environment["WEFT_BENCH"] != nil }

    /// The graph loaded: how long since the process started.
    static func loaded() {
        print("LAUNCH", Int((Date().timeIntervalSince1970 - processStart()) * 1000), "ms to the graph loaded")
    }

    /// Held while timing: the app not napped, nor put on the slow cores,
    /// as one in the background otherwise is.
    private static var activity: NSObjectProtocol?

    static func run(river: River, rivers: RiverSet?) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                                                         reason: "Timing the app")
        let environment = ProcessInfo.processInfo.environment
        let scenarios = (environment["WEFT_BENCH"] ?? "").split(separator: ",").map(String.init)
        let count = Int(environment["WEFT_BENCH_N"] ?? "") ?? 30
        var queue = scenarios
        func next() {
            guard !queue.isEmpty else { exit(0) }
            let name = queue.removeFirst()
            guard let steps = steps(for: name, count: count, river: river, rivers: rivers) else {
                print("BENCH", name, "can't be run here")
                return next()
            }
            let gaps = ["select": 0.1, "step": 0.5, "fold": 0.4, "edit": 0.6, "hover": 0.008, "scroll": 0.016, "type": 0.05, "switch": 0.15, "open": 0.5, "save": 3.5]
            measure(name, steps: steps, gap: gaps[name] ?? 0.1) { next() }
        }
        next()
    }

    /// The scenario's actions, one each step.
    private static func steps(for name: String, count: Int, river: River, rivers: RiverSet?) -> [() -> Void]? {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return nil }
        switch name {
        case "switch":
            guard let rivers, rivers.rivers.count > 1 else { return nil }
            return (0..<count).map { round in { rivers.select(rivers.rivers[(round + 1) % 2]) } }
        case "hover":
            guard let tracker = find(in: window.contentView?.superview, where: { view in
                view.className.contains("Tracker") && view.trackingAreas.contains { $0.owner === view }
            }) else { return nil }
            let width = tracker.bounds.width
            // Back and forth, 12 points a move.
            let xs = (0..<count).map { step -> CGFloat in
                let span = Int(width / 12)
                let place = step % (2 * span)
                return CGFloat(place < span ? place : 2 * span - place) * 12 + 6
            }
            window.acceptsMouseMovedEvents = true
            return xs.map { x in {
                let point = tracker.convert(NSPoint(x: x, y: tracker.bounds.midY), to: nil)
                if let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                    tracker.mouseMoved(with: event)
                }
            } }
        case "type", "save":
            guard let view = NSApp.windows.lazy.compactMap({ $0.firstResponder as? NSTextView }).first else { return nil }
            return (0..<count).map { round in {
                // At the end of the last line, as one would type: not after
                // the line break an outline's text ends with.
                let string = view.string as NSString
                let end = string.length - (string.hasSuffix("\n") ? 1 : 0)
                if round % 2 == 0 {
                    view.setSelectedRange(NSRange(location: end, length: 0))
                    view.insertText("a", replacementRange: NSRange(location: end, length: 0))
                } else {
                    view.deleteBackward(nil)
                }
            } }
        case "select":
            // Each card chosen in turn, as a click on it, or ↓, does.
            let cards = river.cards
            guard !cards.isEmpty else { return nil }
            return (0..<count).map { round in { river.select(cards[round % cards.count]) } }
        case "step":
            return (0..<count).map { round in { river.step((round / 4) % 2 == 0 ? 1 : -1) } }
        case "fold":
            // The first card folded and unfolded, as its title clicked does.
            guard let card = river.cards.first else { return nil }
            return (0..<count).map { _ in { withAnimation(.snappy(duration: 0.22)) { river.toggleFold(card) } } }
        case "edit":
            // The first card written in, then left, as a click in it and Escape do.
            guard let card = river.cards.first else { return nil }
            return (0..<count).map { round in {
                if round % 2 == 0 { river.edit(card) } else { window.makeFirstResponder(nil) }
            } }
        case "open":
            let titles = (ProcessInfo.processInfo.environment["WEFT_BENCH_OPEN"] ?? "").split(separator: "|").map(String.init)
            guard !titles.isEmpty else { return nil }
            return (0..<count).map { round in {
                let title = titles[(round / 2) % titles.count]
                if round % 2 == 0 { river.open(title) } else { river.close(title) }
            } }
        case "scroll":
            guard let scroll = find(in: window.contentView, where: { ($0 as? NSScrollView)?.documentView.map { $0.bounds.height > 2000 } ?? false }) as? NSScrollView else { return nil }
            return (0..<count).map { round in {
                let clip = scroll.contentView
                let down = (round / 20) % 2 == 0
                let y = max(0, clip.bounds.origin.y + (down ? 40 : -40))
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
                scroll.reflectScrolledClipView(clip)
            } }
        default:
            return nil
        }
    }

    /// Each step done once the one before has settled, timed to the main
    /// thread's going idle after it.
    private static func measure(_ name: String, steps: [() -> Void], gap: TimeInterval, done: @escaping () -> Void) {
        var times: [Double] = []
        var work: [Double] = []
        var stepCPU = threadTime()
        var index = 0
        let cpuStart = threadTime()
        let wallStart = CACurrentMediaTime()
        func step() {
            guard index < steps.count else {
                let busy = (threadTime() - cpuStart) / (CACurrentMediaTime() - wallStart)
                work.append((threadTime() - stepCPU) * 1000)
                report(name, times, work: Array(work.dropFirst()), busy: busy)
                // What animates after the last step, let finish.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: done)
                return
            }
            let start = CACurrentMediaTime()
            let cpu = threadTime()
            work.append((cpu - stepCPU) * 1000)
            stepCPU = cpu
            steps[index]()
            index += 1
            whenIdle {
                times.append((CACurrentMediaTime() - start) * 1000)
                DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: step)
            }
        }
        step()
    }

    /// Once the run loop is next about to sleep: every update, layout and
    /// commit of the frame done.
    private static func whenIdle(_ then: @escaping () -> Void) {
        var observer: CFRunLoopObserver?
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            then()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Its latency — to the first frame — and the main thread's work in
    /// all, what animates after it too.
    private static func report(_ name: String, _ times: [Double], work: [Double], busy: Double) {
        func stats(_ values: [Double]) -> String {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return "-" }
            func at(_ share: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))] }
            return String(format: "p10=%.1f median=%.1f p90=%.1f max=%.1f", at(0.1), at(0.5), at(0.9), sorted.last!)
        }
        print(String(format: "BENCH %@ n=%d latency(ms) %@ | work(ms) %@ | main-busy=%.0f%%",
                     name, times.count, stats(times), stats(work), busy * 100))
    }

    private static func find(in view: NSView?, where matches: (NSView) -> Bool) -> NSView? {
        guard let view else { return nil }
        if matches(view) { return view }
        for subview in view.subviews { if let found = find(in: subview, where: matches) { return found } }
        return nil
    }

    /// The main thread's CPU time, in seconds.
    private static func threadTime() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// When the process started, in seconds since 1970.
    private static func processStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        return Double(start.tv_sec) + Double(start.tv_usec) / 1e6
    }
}
