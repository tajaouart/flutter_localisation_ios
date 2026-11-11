import FlutterLocalisation
import SwiftUI

private let sampleName = "Lina"
private let shippedLanguages = ["en", "es", "es-MX", "fr", "ar", "zh-Hans", "zh-Hant"]

enum Gender: String, CaseIterable, Identifiable {
    case he, she, they
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct HomeView: View {
    @EnvironmentObject private var live: LiveLocalisation
    @State private var count = 2
    @State private var gender = Gender.she

    /// The language iOS picked for the app among the ones it ships.
    private var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// App language with the device region, for dates and numbers.
    private var formatLocale: Locale {
        var components = Locale.Components(identifier: language)
        if components.region == nil { components.region = Locale.current.region }
        return Locale(components: components)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                hero.padding(.top, 36)
                LanguageStrip(current: language).padding(.top, 28)

                SectionTitle("Strings").padding(.top, 32)
                Panel {
                    StringRow(key: "greeting.simple", value: String(localized: "greeting.simple"))
                    StringRow(key: "greeting.hello %@", value: String(localized: "greeting.hello \(sampleName)"))
                    StringRow(key: "greeting.welcome %@", value: String(localized: "greeting.welcome \(sampleName)"))
                    StringRow(key: "FlutterLocalisation", value: String(localized: "FlutterLocalisation"), note: "Not translated")
                }

                SectionTitle("Plurals").padding(.top, 28)
                PluralPanel(count: $count, language: language)

                SectionTitle("One string per gender").padding(.top, 28)
                genderPanel

                SectionTitle("Dates and numbers").padding(.top, 28)
                formatsPanel

                SectionTitle("Live updates").padding(.top, 28)
                LivePanel()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
    }

    private var header: some View {
        HStack {
            Text("FlutterLocalisation").font(.headline)
            Spacer()
            Text(verbatim: "String Catalog").font(.footnote).foregroundStyle(Palette.muted)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LocalizedStringKey: SwiftUI's own lookup path.
            Text("greeting.simple")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-0.8)
            Text("greeting.welcome \(sampleName)")
                .font(.title3)
                .foregroundStyle(Palette.muted)
        }
    }

    private var genderPanel: some View {
        Panel {
            Picker(selection: $gender) {
                ForEach(Gender.allCases) { Text(verbatim: $0.label).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .padding(16)
            switch gender {
            case .he:
                StringRow(key: "message.from.he", value: String(localized: "message.from.he"))
                StringRow(key: "friends.invited.he %lld", value: String(localized: "friends.invited.he \(count)"))
            case .she:
                StringRow(key: "message.from.she", value: String(localized: "message.from.she"))
                StringRow(key: "friends.invited.she %lld", value: String(localized: "friends.invited.she \(count)"))
            case .they:
                StringRow(key: "message.from.they", value: String(localized: "message.from.they"))
                StringRow(key: "friends.invited.they %lld", value: String(localized: "friends.invited.they \(count)"))
            }
        }
    }

    private var formatsPanel: some View {
        let locale = formatLocale
        let lastSeen = Date(timeIntervalSince1970: 1_767_225_600)
        let event = Date(timeIntervalSince1970: 1_772_380_800)
        let date = lastSeen.formatted(.dateTime.year().month(.wide).day().locale(locale))
        let when = event.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().locale(locale))
        let amount = 1234.5.formatted(.currency(code: "USD").locale(locale))
        let downloads = 1_234_567.formatted(.number.notation(.compactName).locale(locale))
        let progress = 0.42.formatted(.percent.locale(locale))
        return Panel {
            StringRow(key: "seen.last %@", value: String(localized: "seen.last \(date)"))
            StringRow(key: "event.starts %@", value: String(localized: "event.starts \(when)"))
            StringRow(key: "order.total %@", value: String(localized: "order.total \(amount)"))
            StringRow(key: "stats.downloads %@", value: String(localized: "stats.downloads \(downloads)"))
            StringRow(key: "stats.progress %@", value: String(localized: "stats.progress \(progress)"))
        }
    }
}

// MARK: - Pieces

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(verbatim: title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.muted)
            .padding(.leading, 4)
            .padding(.bottom, 10)
            .environment(\.layoutDirection, .leftToRight)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 { Divider().overlay(Palette.line).padding(.leading, 16) }
                    rows[index]
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line))
    }
}

struct StringRow: View {
    @EnvironmentObject private var live: LiveLocalisation
    let key: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .environment(\.layoutDirection, .leftToRight)
                if live.isLive(key) { Tag(text: "Live") }
                if let note { Tag(text: note, quiet: true) }
                Spacer(minLength: 0)
            }
            Text(verbatim: value).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct Tag: View {
    let text: String
    var quiet = false

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(quiet ? Palette.muted : Palette.accent)
            .background(quiet ? Palette.line : Palette.accentSoft, in: Capsule())
    }
}

struct LanguageStrip: View {
    let current: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(shippedLanguages, id: \.self) { code in
                    let selected = code == current
                    Text(verbatim: Locale(identifier: code).localizedString(forIdentifier: code)?.capitalized(with: Locale(identifier: code)) ?? code)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Palette.surface : Palette.ink)
                        .background(selected ? Palette.ink : Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? .clear : Palette.line))
                }
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text(verbatim: "Change the app language in Settings")
                    .font(.footnote.weight(.medium))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, layout.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

struct PluralPanel: View {
    @EnvironmentObject private var live: LiveLocalisation
    @Binding var count: Int
    let language: String

    private var languageCode: String { Locale(identifier: language).language.languageCode?.identifier ?? language }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(verbatim: "cart.items %lld")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .environment(\.layoutDirection, .leftToRight)
                    if live.isLive("cart.items %lld") { Tag(text: "Live") }
                }
                HStack(spacing: 12) {
                    Text(verbatim: String(localized: "cart.items \(count)"))
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                    StepButton(symbol: "minus", label: "Remove one") { count = max(0, count - 1) }
                        .disabled(count == 0)
                    StepButton(symbol: "plus", label: "Add one") { count += 1 }
                }
                HStack(spacing: 6) {
                    ForEach([0, 1, 2, 3, 11, 100], id: \.self) { value in
                        Button { withAnimation(.snappy) { count = value } } label: {
                            Text(verbatim: "\(value)")
                                .font(.footnote.weight(.medium).monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .foregroundStyle(count == value ? Palette.accent : Palette.ink)
                                .background(count == value ? Palette.accentSoft : Palette.paper, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                Text(verbatim: "Plural category of \(count): \(PluralCategory.of(count, language: languageCode, hasZeroArm: true))")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(16)
        }
    }
}

struct StepButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Palette.paper, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

struct LivePanel: View {
    @EnvironmentObject private var live: LiveLocalisation
    @State private var checkedAt: Date?

    private var edits: String {
        live.liveLocales.map { locale in
            let count = live.liveKeys(in: locale).count
            return "\(count) \(count == 1 ? "string" : "strings") updated in \(locale)"
        }.joined(separator: "\n")
    }

    private var detail: String {
        if !live.isConfigured {
            return [
                edits.isEmpty ? nil : "Showing edits saved from the last sync:\n\(edits)",
                "Build with FL_SECRET_KEY and FL_PROJECT_ID to pull new edits from your dashboard.",
            ].compactMap { $0 }.joined(separator: "\n\n")
        }
        if let error = live.lastError { return error }
        if edits.isEmpty { return "No edits yet. Change a string in the dashboard and refresh to see it here." }
        return edits
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(live.isConfigured ? (live.lastError == nil ? Palette.accent : .red) : Palette.muted)
                        .frame(width: 8, height: 8)
                    Text(verbatim: live.isConfigured ? "Connected" : "Off").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let checkedAt {
                        Text(verbatim: "Checked \(checkedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        try? await live.refresh()
                        checkedAt = Date()
                    }
                } label: {
                    Group {
                        if live.isRefreshing { ProgressView().tint(Palette.surface) } else { Text("live.refresh") }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Palette.surface)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!live.isConfigured || live.isRefreshing)
                .opacity(live.isConfigured ? 1 : 0.4)
                .padding(.top, 8)
                if !live.liveLocales.isEmpty {
                    Button { live.reset() } label: {
                        Text(verbatim: "Show the bundled strings again").font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(16)
        }
    }
}
