import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var tabs: TabSelection

    private var style: Binding<ReviewStyle> {
        Binding(get: { state.settings.reviewStyle },
                set: { var s = state.settings; s.reviewStyle = $0; state.settings = s })
    }

    var body: some View {
        let items = state.pending
        VStack(spacing: 0) {
            header(count: items.count)
            if let err = state.lastError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { state.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
            if let notice = state.notice {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.sparkles").foregroundStyle(Brand.accent)
                    Text(notice).font(.callout)
                    Spacer()
                    Button { state.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(Brand.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
            content(items)
        }
        .overlay(alignment: .bottom) { backgroundWork }
        .animation(.snappy, value: state.busy)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review").font(.largeTitle.weight(.bold))
                Text(count == 0 ? "You're all caught up" : "\(count) sender\(count == 1 ? "" : "s") waiting for a decision")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.deepCleanRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(state.scanStatus).font(.callout).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 320, alignment: .trailing)
                    Button("Stop") { state.cancelDeepClean() }
                        .buttonStyle(PillButtonStyle(tint: Brand.remove, prominent: false))
                }
            } else if !state.data.accounts.isEmpty {
                Button {
                    state.showDeepClean = true
                } label: {
                    Label("Deep Clean…", systemImage: "wand.and.sparkles")
                }
                .buttonStyle(PillButtonStyle(tint: Brand.accent, prominent: false))
                .disabled(state.isScanning)
                .help("Look through older mail once and add clutter senders to Review")
            }
            if !state.data.accounts.isEmpty && count > 0 {
                Picker("View", selection: style) {
                    ForEach(ReviewStyle.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                .help("Switch between one-at-a-time cards and a list")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    @ViewBuilder private func content(_ items: [Candidate]) -> some View {
        if state.data.accounts.isEmpty {
            EmptyStateView(icon: "envelope.badge.shield.half.filled", title: "Connect an inbox to begin",
                           detail: "Clutter Clear checks your inboxes each morning and lines up the senders worth cutting.",
                           actionTitle: "Add an Account", action: { tabs.selected = .accounts })
        } else if items.isEmpty {
            if state.isScanning {
                EmptyStateView(icon: "magnifyingglass", title: "Looking through your inboxes…", detail: state.scanStatus)
            } else {
                EmptyStateView(icon: "sparkles", title: "All clear!",
                               detail: "Nothing needs a decision. New promotional or spam senders show up here after the next check.",
                               actionTitle: "Check Now", action: { Task { await state.scan(auto: false) } })
            }
        } else if state.settings.reviewStyle == .cards {
            CardDeck(items: items)
        } else {
            ListReview(items: items)
        }
    }

    @ViewBuilder private var backgroundWork: some View {
        if !state.busy.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Cleaning up \(state.busy.count) sender\(state.busy.count == 1 ? "" : "s") in the background…")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Shared sender summary

struct SenderSummary: View {
    @EnvironmentObject var state: AppState
    let candidate: Candidate
    var compact = false

    private var c: Candidate { candidate }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            HStack(alignment: .center, spacing: 14) {
                SenderAvatar(name: c.senderName, email: c.senderEmail, size: compact ? 56 : 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.senderName).font(.title2.weight(.bold)).lineLimit(1).textSelection(.enabled)
                    Text(c.senderEmail).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                CategoryPill(category: c.category)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                Text(c.reason).fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)

            HStack(spacing: 10) {
                StatTile(icon: "envelope.fill", value: "\(c.flagged.count) new", label: "flagged", tint: Brand.accent)
                StatTile(icon: "calendar", value: "\(c.recentCount) emails", label: "in \(c.windowDays) days", tint: Brand.violet)
                if c.category == .suspicious {
                    StatTile(icon: "hand.raised.fill", value: "Don't click", label: "links in spam", tint: Brand.remove)
                } else {
                    StatTile(icon: c.methodShort.icon, value: c.methodShort.text, label: "unsubscribe", tint: .teal)
                }
            }

            if let when = c.previouslyUnsubscribed {
                notice("arrow.uturn.backward.circle.fill", .orange,
                       "You unsubscribed on \(when.formatted(date: .abbreviated, time: .omitted)). Their older emails are still in your mail.")
            }
            if c.category == .suspicious {
                notice("shield.lefthalf.filled", Brand.remove,
                       "Unsubscribing from spam tells the sender your address is real. Moving it to Junk is safer.")
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Recent emails").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
                let subjects = c.flagged.sorted { $0.date > $1.date }
                ForEach(Array(subjects.prefix(compact ? 3 : 50).enumerated()), id: \.offset) { i, m in
                    HStack(spacing: 10) {
                        Image(systemName: "envelope").foregroundStyle(.tertiary)
                        Text(m.subject).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(m.date.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    if i < min(subjects.count, compact ? 3 : 50) - 1 { Divider() }
                }
                if compact && subjects.count > 3 {
                    Text("+ \(subjects.count - 3) more").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
            }

            if let account = state.account(for: c.accountID) {
                Label("Found in \(account.email)", systemImage: "tray").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func notice(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - List mode

final class ListUI: ObservableObject {
    @Published var selection: String?
}

struct ListReview: View {
    @EnvironmentObject var state: AppState
    let items: [Candidate]
    @StateObject private var ui = ListUI()

    var body: some View {
        HStack(spacing: 0) {
            List(items, selection: $ui.selection) { c in
                CandidateRow(candidate: c).tag(c.id)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(width: 310)

            Divider()

            if let c = items.first(where: { $0.id == ui.selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SenderSummary(candidate: c).surface(radius: 20, padding: 22)
                        DecisionPanel(candidate: c)
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .id(c.id)
                .transition(.opacity)
            } else {
                EmptyStateView(icon: "hand.point.left", title: "Pick a sender", detail: "")
            }
        }
        .onAppear { if ui.selection == nil { ui.selection = items.first?.id } }
        .onChange(of: items.map(\.id)) { old, ids in
            guard let sel = ui.selection, ids.contains(sel) else {
                // Move to the sender that took the removed one's place.
                let i = ui.selection.flatMap { old.firstIndex(of: $0) } ?? 0
                ui.selection = ids.isEmpty ? nil : ids[min(i, ids.count - 1)]
                return
            }
        }
    }
}

struct CandidateRow: View {
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 11) {
            SenderAvatar(name: candidate.senderName, email: candidate.senderEmail, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(candidate.senderName).font(.body.weight(.semibold)).lineLimit(1)
                    Image(systemName: candidate.category.icon)
                        .font(.caption2)
                        .foregroundStyle(candidate.category.color)
                }
                Text(candidate.latestSubject).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(candidate.flagged.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 5)
    }
}

@MainActor
final class DecisionUI: ObservableObject {
    @Published var scope: DeleteScope
    @Published var treatAsNewsletter = false
    init(scope: DeleteScope) { self.scope = scope }
}

/// Keep / unsubscribe controls for the list mode.
struct DecisionPanel: View {
    @EnvironmentObject var state: AppState
    let candidate: Candidate
    @StateObject private var ui: DecisionUI

    init(candidate: Candidate) {
        self.candidate = candidate
        _ui = StateObject(wrappedValue: DecisionUI(scope: AppState.shared.settings.defaultCleanup))
    }

    private var isSpam: Bool { candidate.category == .suspicious && !ui.treatAsNewsletter }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isSpam ? "When moving to Junk" : "After unsubscribing")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            CleanupPicker(options: isSpam ? [.flagged, .allFromSender] : [.flagged, .allFromSender, .none],
                          selection: Binding(get: { ui.scope }, set: { ui.scope = $0; if !isSpam { state.rememberCleanup($0) } }),
                                  junk: isSpam)
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { state.keep(candidate) }
                } label: {
                    Label("Keep", systemImage: "checkmark")
                }
                .buttonStyle(PillButtonStyle(tint: Brand.keep, prominent: false))
                .keyboardShortcut("k", modifiers: [])
                .help("Keep (K): stays in your inbox and is never flagged again")

                Button {
                    withAnimation(.snappy) {
                        if isSpam {
                            state.startJunk(candidate, scope: ui.scope == .none ? .flagged : ui.scope)
                        } else {
                            state.startUnsubscribe(candidate, delete: ui.scope)
                        }
                    }
                } label: {
                    Label(isSpam ? "Move to Junk" : "Unsubscribe", systemImage: isSpam ? "xmark.bin.fill" : "hand.wave.fill")
                }
                .buttonStyle(PillButtonStyle(tint: Brand.remove))
                .keyboardShortcut(isSpam ? "j" : "u", modifiers: [])
                .help(isSpam ? "Move to Junk (J)" : "Unsubscribe (U)")

                Spacer()
                if candidate.category == .suspicious {
                    Button(ui.treatAsNewsletter ? "Treat as spam" : "It's a real newsletter") {
                        withAnimation(.snappy) { ui.treatAsNewsletter.toggle() }
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .surface(radius: 20, padding: 20)
    }
}

// MARK: - Card mode

@MainActor
final class DeckUI: ObservableObject {
    @Published var offset: CGSize = .zero
    @Published var skipped: [String] = []
    @Published var done = 0
    @Published var scope: DeleteScope = AppState.shared.settings.defaultCleanup
    @Published var treatAsNewsletter = false
    var animating = false
}

struct CardDeck: View {
    @EnvironmentObject var state: AppState
    let items: [Candidate]
    @StateObject private var ui = DeckUI()

    private enum Decision { case keep, remove, later }

    private var deck: [Candidate] {
        let skipped = Set(ui.skipped)
        return items.filter { !skipped.contains($0.id) } + ui.skipped.compactMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        let deck = deck
        let top = deck.first
        let isSpam = top?.category == .suspicious && !ui.treatAsNewsletter
        VStack(spacing: 18) {
            progress(remaining: deck.count)

            ZStack {
                ForEach(Array(deck.prefix(3).enumerated()).reversed(), id: \.element.id) { depth, c in
                    card(c, depth: depth, isSpam: depth == 0 && isSpam)
                }
            }
            .frame(maxWidth: 620)
            .frame(minHeight: 380, maxHeight: 470)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)

            if let top {
                VStack(spacing: 14) {
                    CleanupPicker(options: isSpam ? [.flagged, .allFromSender] : [.flagged, .allFromSender, .none],
                                  selection: Binding(get: { ui.scope }, set: { ui.scope = $0; if !isSpam { state.rememberCleanup($0) } }),
                                  junk: isSpam)
                    HStack(spacing: 34) {
                        RoundActionButton(icon: isSpam ? "xmark.bin.fill" : "xmark", label: isSpam ? "Junk" : "Unsubscribe",
                                          tint: Brand.remove) { decide(.remove, top) }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        RoundActionButton(icon: "arrow.uturn.down", label: "Later", tint: .secondary, size: 48) { decide(.later, top) }
                            .keyboardShortcut(.downArrow, modifiers: [])
                        RoundActionButton(icon: "checkmark", label: "Keep", tint: Brand.keep) { decide(.keep, top) }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                    HStack(spacing: 14) {
                        Text("Swipe the card, or use ← → and ↓").font(.caption).foregroundStyle(.tertiary)
                        if top.category == .suspicious {
                            Button(ui.treatAsNewsletter ? "Treat as spam" : "It's a real newsletter") {
                                withAnimation(.snappy) { ui.treatAsNewsletter.toggle() }
                            }
                            .buttonStyle(.link).font(.caption)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
    }

    private func progress(remaining: Int) -> some View {
        let total = max(1, ui.done + remaining)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Brand.gradient)
                        .frame(width: max(8, geo.size.width * CGFloat(ui.done) / CGFloat(total)))
                }
            }
            .frame(height: 6)
            Text(ui.done == 0 ? "\(remaining) to go" : "\(ui.done) done · \(remaining) to go")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 320)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: ui.done)
    }

    private func borderColor(_ dx: CGFloat) -> Color {
        if dx > 0 { return Brand.keep.opacity(Double(min(1, dx / 120))) }
        if dx < 0 { return Brand.remove.opacity(Double(min(1, -dx / 120))) }
        return Color.secondary.opacity(0.15)
    }

    private func cardFace(_ c: Candidate, dx: CGFloat, isTop: Bool, isSpam: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let keepOpacity = Double(min(1, dx / 110))
        let removeOpacity = Double(min(1, -dx / 110))
        return SenderSummary(candidate: c, compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)
            .background(.background, in: shape)
            .overlay(shape.strokeBorder(borderColor(dx), lineWidth: dx == 0 ? 0.5 : 3))
            .overlay(alignment: .topLeading) {
                if isTop && dx > 20 { stamp("KEEP", Brand.keep, angle: -12).opacity(keepOpacity) }
            }
            .overlay(alignment: .topTrailing) {
                if isTop && dx < -20 { stamp(isSpam ? "JUNK" : "UNSUBSCRIBE", Brand.remove, angle: 12).opacity(removeOpacity) }
            }
    }

    private func card(_ c: Candidate, depth: Int, isSpam: Bool) -> some View {
        let isTop = depth == 0
        let dx: CGFloat = isTop ? ui.offset.width : 0
        let dy: CGFloat = isTop ? ui.offset.height : CGFloat(depth) * 14
        let scale: CGFloat = 1 - CGFloat(depth) * 0.045
        let angle = Angle.degrees(isTop ? Double(dx / 24) : 0)
        let shadowOpacity: Double = isTop ? 0.14 : 0.06
        return cardFace(c, dx: dx, isTop: isTop, isSpam: isSpam)
            .shadow(color: .black.opacity(shadowOpacity), radius: isTop ? 22 : 10, y: isTop ? 10 : 4)
            .scaleEffect(scale, anchor: .bottom)
            .offset(x: dx, y: dy)
            .rotationEffect(angle, anchor: .bottom)
            .opacity(depth == 2 ? 0.55 : 1)
            .allowsHitTesting(isTop)
            .gesture(drag(c), including: isTop ? .all : .none)
            .zIndex(Double(10 - depth))
            .transition(.identity)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: depth)
    }

    private func stamp(_ text: String, _ color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(28)
    }

    private func drag(_ c: Candidate) -> some Gesture {
        DragGesture()
            .onChanged { v in
                guard !ui.animating else { return }
                ui.offset = CGSize(width: v.translation.width, height: v.translation.height * 0.25)
            }
            .onEnded { v in
                guard !ui.animating else { return }
                let w = v.translation.width, predicted = v.predictedEndTranslation.width
                if w > 130 || predicted > 360 { decide(.keep, c) }
                else if w < -130 || predicted < -360 { decide(.remove, c) }
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { ui.offset = .zero } }
            }
    }

    private func decide(_ d: Decision, _ c: Candidate) {
        guard !ui.animating else { return }
        ui.animating = true
        let fly: CGSize
        switch d {
        case .keep: fly = CGSize(width: 1100, height: ui.offset.height + 60)
        case .remove: fly = CGSize(width: -1100, height: ui.offset.height + 60)
        case .later: fly = CGSize(width: 0, height: 900)
        }
        withAnimation(.easeIn(duration: 0.24)) { ui.offset = fly }

        let spam = c.category == .suspicious && !ui.treatAsNewsletter
        let scope = ui.scope
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                ui.offset = .zero
                ui.treatAsNewsletter = false
                ui.scope = state.settings.defaultCleanup
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                switch d {
                case .keep:
                    state.keep(c)
                    ui.done += 1
                case .remove:
                    if spam { state.startJunk(c, scope: scope == .none ? .flagged : scope) }
                    else { state.startUnsubscribe(c, delete: scope) }
                    ui.done += 1
                case .later:
                    ui.skipped.removeAll { $0 == c.id }
                    ui.skipped.append(c.id)
                }
            }
            ui.animating = false
        }
    }
}
