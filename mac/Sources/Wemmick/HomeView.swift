import Charts
import SwiftUI

struct HomeView: View {
    @Environment(Store.self) private var store
    @State private var stats: HomeStats?
    @State private var storage: Storage?
    @State private var freeing = false

    var body: some View {
        Group {
            if let stats { content(stats) } else { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Data")
        .task(id: store.revision) {
            stats = try? await API.get(["api", "home"])
            storage = try? await API.get(["api", "storage"])
            if store.people.isEmpty { await store.loadPeople() }
        }
    }

    private func content(_ s: HomeStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let storage { card("Storage") { StorageBar(storage: storage) { freeing = true } } }
                tiles(s)
                card("Meetings per month") { MonthChart(rows: s.byMonth) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 20, alignment: .top)], spacing: 20) {
                    card("Who you meet with most") {
                        RankedBars(rows: s.peopleTop, note: { $0.minutes.map { "\(Int($0)) min talking" } }) { row in
                            store.people.first { $0.name == row.label }.map { person in
                                { store.section = .people; store.personSelection = person.personId }
                            }
                        }
                    }
                    card("Teams you meet with most") { RankedBars(rows: s.teamsTop) }
                    card("Busiest projects") { RankedBars(rows: s.projectsTop) }
                    card("Meetings by weekday") { WeekdayChart(rows: weekdays(s.byWeekday)) }
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $freeing) {
            if let storage {
                FreeUpSpace(recordings: storage.recordings) {
                    self.storage = try? await API.get(["api", "storage"])
                }
            }
        }
    }

    // one row of equal tiles across the page, or a grid when the window's too narrow for that
    private func tiles(_ s: HomeStats) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tileList(s) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) { tileList(s) }
        }
    }

    @ViewBuilder
    private func tileList(_ s: HomeStats) -> some View {
        tile(number(s.meetings), "meetings")
        tile(String(format: "%.1f", s.hours), "hours recorded")
        tile(number(s.people), "people met")
        tile(number(s.voices), "voices known")
        if let share = s.ownerShare { tile("\(Int((share * 100).rounded()))%", "of talk time is you") }
        if let review = s.review, review > 0 {
            Button { store.section = .inbox } label: {
                tile(number(review), "meetings to review", warn: true)
            }
            .buttonStyle(.plain)
            .help("Open the Inbox")
        }
    }

    private func tile(_ value: String, _ label: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if warn { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                Text(value).font(.title.weight(.semibold)).monospacedDigit()
            }
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        // no least width, so every tile in the row gets the same share
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // weekends show only when there are real weekend meetings, not the odd one
    private func weekdays(_ rows: [Count]) -> [Count] {
        let busiest = rows.map(\.value).max() ?? 1
        return rows.filter { !["Sat", "Sun"].contains($0.label) || $0.value >= busiest / 10 }
    }

    private func number(_ n: Double) -> String { "\(Int(n))" }
}

// columns over time, with the hovered month's count above the chart
struct MonthChart: View {
    @Environment(Store.self) private var store
    let rows: [Count]
    @State private var hovered: String?

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        if rows.isEmpty {
            Text("Nothing yet").foregroundStyle(.secondary)
        } else {
            // a dozen labels at most, on months that divide the year evenly, so with three
            // months apart they fall on jan, apr, jul and oct whenever the history starts
            let every = [1, 2, 3, 6, 12].first { rows.count <= $0 * 12 } ?? 12
            let labelled = rows.map(\.label).filter { Self.month($0).map { ($0 - 1) % every == 0 } ?? false }
            VStack(alignment: .leading, spacing: 6) {
                readout
                Chart(rows, id: \.label) { row in
                    BarMark(x: .value("Month", row.label), y: .value("Meetings", row.value), width: .ratio(0.7))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                        .foregroundStyle(store.accentColor.opacity(hovered == nil || hovered == row.label ? 1 : 0.45))
                }
                .chartXSelection(value: $hovered)
                .chartXAxis {
                    AxisMarks(values: labelled) { value in
                        AxisValueLabel { Text(value.as(String.self).map(Self.short) ?? "") }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private var readout: some View {
        let row = rows.first { $0.label == hovered }
        return Text(row.map { "\(Self.long($0.label)): \(Int($0.value)) meetings" } ?? "Hover a month for its count")
            .font(.callout)
            .foregroundStyle(row == nil ? .tertiary : .secondary)
            .monospacedDigit()
    }

    // 8 for "2024-08"
    static func month(_ label: String) -> Int? {
        let parts = label.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        return m
    }

    // "2024-08" as "Aug 24" on the axis and "August 2024" in the readout
    static func short(_ label: String) -> String {
        let parts = label.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return label }
        return "\(months[m - 1]) \(parts[0].suffix(2))"
    }

    static func long(_ label: String) -> String {
        let parts = label.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return label }
        return "\(DateFormatter().monthSymbols[m - 1]) \(parts[0])"
    }
}

struct WeekdayChart: View {
    @Environment(Store.self) private var store
    let rows: [Count]
    @State private var hovered: String?

    var body: some View {
        Chart(rows, id: \.label) { row in
            BarMark(x: .value("Day", row.label), y: .value("Meetings", row.value), width: .ratio(0.55))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(store.accentColor.opacity(hovered == nil || hovered == row.label ? 1 : 0.45))
                .annotation(position: .top, spacing: 4) {
                    if hovered == row.label {
                        Text("\(Int(row.value))").font(.caption.weight(.medium)).monospacedDigit()
                    }
                }
        }
        .chartXSelection(value: $hovered)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: 180)
    }
}

// longest first, a thin bar per row with its count, and an action when a row can open something
struct RankedBars: View {
    @Environment(Store.self) private var store
    let rows: [Count]
    var note: (Count) -> String? = { _ in nil }
    var open: (Count) -> (() -> Void)? = { _ in nil }

    var body: some View {
        if rows.isEmpty {
            Text("Nothing yet").foregroundStyle(.secondary)
        } else {
            let top = rows.map(\.value).max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.label) { row in
                    if let action = open(row) {
                        Button(action: action) { line(row, top: top, linked: true) }
                            .buttonStyle(.plain)
                            .help("Open \(row.label) in People")
                    } else {
                        line(row, top: top, linked: false)
                    }
                }
            }
        }
    }

    private func line(_ row: Count, top: Double, linked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(linked ? store.accentColor : .primary)
                Spacer(minLength: 8)
                Text("\(Int(row.value))").monospacedDigit()
                if let extra = note(row) {
                    Text(extra).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.callout)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.6))
                    Capsule().fill(store.accentColor)
                        .frame(width: max(4, geo.size.width * row.value / top))
                }
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
    }
}

// the library's size in three parts, with the recordings first since they're the part that
// can go
struct StorageBar: View {
    @Environment(Store.self) private var store
    let storage: Storage
    let freeUp: () -> Void

    private var parts: [(label: String, detail: String, bytes: Double, style: AnyShapeStyle)] {
        [("Recordings", "\(storage.recordings.count) original recordings", storage.recordingsBytes, AnyShapeStyle(store.accentColor)),
         ("Transcripts and notes", "Kept when a recording is deleted", storage.notesBytes, AnyShapeStyle(store.accentColor.opacity(0.45))),
         ("App and models", "Python and the transcription and note models", storage.appBytes, AnyShapeStyle(.tertiary))]
    }

    var body: some View {
        let total = parts.map(\.bytes).reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(bytes(total)).font(.title.weight(.semibold)).monospacedDigit()
                Text("used, \(bytes(storage.freeBytes)) free on this Mac").foregroundStyle(.secondary)
                Spacer()
                Button("Free Up Space...", action: freeUp)
                    .disabled(storage.recordings.isEmpty)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.label) { part in
                        Rectangle().fill(part.style)
                            .frame(width: max(2, (geo.size.width - 4) * part.bytes / max(total, 1)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 24) {
                ForEach(parts, id: \.label) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(part.style).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(part.label): \(bytes(part.bytes))").monospacedDigit()
                            Text(part.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// recordings to delete, biggest first. a meeting keeps its transcript and note, but can't be
// played back or transcribed again
struct FreeUpSpace: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recordings: [Storage.Recording]
    let reload: () async -> Void
    @State private var picked: Set<String> = []
    @State private var confirming = false

    private var pickedBytes: Double { recordings.filter { picked.contains($0.id) }.map(\.bytes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free Up Space").font(.title2.weight(.semibold))
            Text("Deleting a recording keeps its meeting's transcript and note, but it can't be played back or transcribed again.")
                .foregroundStyle(.secondary)
            Table(recordings, selection: $picked) {
                TableColumn("Meeting") { r in Text(r.title ?? r.meetingId) }
                TableColumn("Date") { r in Text(r.date ?? "") }
                    .width(90)
                TableColumn("Status") { r in Text(r.archived == nil ? "Inbox" : "Archived").foregroundStyle(.secondary) }
                    .width(70)
                TableColumn("Size") { r in Text(bytes(r.bytes)).monospacedDigit() }
                    .width(70)
            }
            .frame(minHeight: 320)
            HStack {
                Button("Select Archived") { picked = Set(recordings.filter { $0.archived != nil }.map(\.id)) }
                    .help("Pick every recording whose meeting is done")
                Text(picked.isEmpty ? "Pick recordings, with cmd or shift for more than one"
                     : "\(picked.count) picked, \(bytes(pickedBytes))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete Recordings...", role: .destructive) { confirming = true }
                    .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 480)
        .confirmationDialog("Delete \(picked.count) recording\(picked.count == 1 ? "" : "s")?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { Task { await drop() } }
        } message: {
            Text("They move to the Trash, freeing \(bytes(pickedBytes)) once it's emptied. The meetings keep their transcripts and notes.")
        }
    }

    private func drop() async {
        let ids = Array(picked)
        await store.run {
            let result: Dropped = try await API.post(["api", "storage", "drop-recordings"], DropRecordings(meetingIds: ids))
            let moved = ids.count - result.skipped.count
            store.show("Moved \(moved) recording\(moved == 1 ? "" : "s") to the Trash, \(bytes(result.freed)). Empty it to free the space."
                       + (result.skipped.isEmpty ? "" : " \(result.skipped.count) still being worked on were left."))
        }
        await reload()
        dismiss()
    }
}
