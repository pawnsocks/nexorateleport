import SwiftUI

private struct RoutineDraftStep: Identifiable {
    var id = UUID()
    var title = "Route"
    var time = Date()
    var routeID: UUID?
    var minimumDelay = 0
    var maximumDelay = 10
    var stayMinutes = 0
}

struct RoutinesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routineEngine: RoutineEngine
    @State private var showingEditor = false
    @State private var showingExceptionEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Scheduler") {
                    Label(routineEngine.nextEvent, systemImage: "clock").font(.subheadline)
                }

                if model.routines.isEmpty {
                    ContentUnavailableView("No routines", systemImage: "calendar.badge.plus", description: Text("Create a routine with days, routes, delays and stay times."))
                }

                ForEach($model.routines) { $profile in
                    Section {
                        Toggle("Enabled", isOn: $profile.enabled)
                            .onChange(of: profile.enabled) { _, _ in model.saveRoutines() }
                        Text(weekdayText(profile.weekdays)).font(.caption).foregroundStyle(.secondary)

                        ForEach(profile.steps) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(step.title).font(.headline)
                                    Spacer()
                                    if !step.enabled { Text("Disabled").font(.caption).foregroundStyle(.secondary) }
                                }
                                Text(String(format: "%02d:%02d", step.scheduledHour, step.scheduledMinute)).monospacedDigit()
                                Text("Delay \(step.delay.minimumMinutes)–\(step.delay.maximumMinutes) min · Stay \(step.stayDurationMinutes) min")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let routeID = step.routeID, let route = model.routes.first(where: { $0.id == routeID }) {
                                    Text(route.name).font(.caption).foregroundStyle(.indigo)
                                } else {
                                    Text("Route missing").font(.caption).foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 3)
                        }

                        HStack {
                            Button("Skip today") {
                                model.addException(RoutineException(profileID: profile.id, date: .now, kind: .skipDay, note: "Quick skip"))
                            }
                            .buttonStyle(.bordered)
                            Button("+15 min today") {
                                model.addException(RoutineException(profileID: profile.id, date: .now, kind: .delay, delayMinutes: 15, note: "Quick delay"))
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) { model.deleteRoutine(profile.id) } label: {
                            Label("Delete routine", systemImage: "trash")
                        }
                    } header: { Text(profile.name) }
                }

                Section("Exception Days") {
                    if model.exceptions.isEmpty {
                        Text("No exception days").foregroundStyle(.secondary)
                    }
                    ForEach(model.exceptions.sorted { $0.date < $1.date }) { exception in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exception.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Text(exceptionLabel(exception)).font(.caption).foregroundStyle(.secondary)
                            if !exception.note.isEmpty { Text(exception.note).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = model.exceptions.sorted { $0.date < $1.date }
                        for index in offsets { model.deleteException(sorted[index].id) }
                    }
                    Button { showingExceptionEditor = true } label: {
                        Label("Add exception", systemImage: "calendar.badge.exclamationmark")
                    }
                    .disabled(model.routines.isEmpty)
                }
            }
            .navigationTitle("Daily Routine")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                        .disabled(model.routes.isEmpty)
                }
            }
            .sheet(isPresented: $showingEditor) {
                RoutineEditorView(routes: model.routes) { profile in
                    model.addRoutine(profile)
                    showingEditor = false
                }
            }
            .sheet(isPresented: $showingExceptionEditor) {
                RoutineExceptionEditor(routines: model.routines) { exception in
                    model.addException(exception)
                    showingExceptionEditor = false
                }
            }
        }
    }

    private func weekdayText(_ weekdays: Set<Int>) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: " · ")
    }

    private func exceptionLabel(_ exception: RoutineException) -> String {
        let routine = model.routines.first(where: { $0.id == exception.profileID })?.name ?? "Deleted routine"
        return exception.kind == .skipDay ? "\(routine) · Skip day" : "\(routine) · +\(exception.delayMinutes) min"
    }
}

private struct RoutineEditorView: View {
    let routes: [RoutePlan]
    let onSave: (RoutineProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Daily Routine"
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var steps: [RoutineDraftStep] = [RoutineDraftStep()]

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Name", text: $name)
                    weekdayPicker
                }
                ForEach($steps) { $step in
                    Section {
                        TextField("Step name", text: $step.title)
                        DatePicker("Start time", selection: $step.time, displayedComponents: .hourAndMinute)
                        Picker("Route", selection: $step.routeID) {
                            Text("Select route").tag(UUID?.none)
                            ForEach(routes) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Stepper("Delay minimum: \(step.minimumDelay) min", value: $step.minimumDelay, in: 0...180)
                            .onChange(of: step.minimumDelay) { _, value in if step.maximumDelay < value { step.maximumDelay = value } }
                        Stepper("Delay maximum: \(step.maximumDelay) min", value: $step.maximumDelay, in: step.minimumDelay...240)
                        Stepper("Stay: \(step.stayMinutes) min", value: $step.stayMinutes, in: 0...720)
                        if steps.count > 1 {
                            Button("Remove step", role: .destructive) { steps.removeAll { $0.id == step.id } }
                        }
                    } header: { Text(step.title.isEmpty ? "Step" : step.title) }
                }
                Section {
                    Button {
                        var draft = RoutineDraftStep(); draft.routeID = routes.first?.id; steps.append(draft)
                    } label: { Label("Add step", systemImage: "plus.circle") }
                }
            }
            .navigationTitle("New Routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear { if steps.first?.routeID == nil { steps[0].routeID = routes.first?.id } }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let symbol = Calendar.current.veryShortWeekdaySymbols[weekday - 1]
                    Button(symbol) {
                        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    }
                    .buttonStyle(.bordered).tint(weekdays.contains(weekday) ? .indigo : .secondary)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !weekdays.isEmpty && !steps.isEmpty && steps.allSatisfy { $0.routeID != nil }
    }

    private func save() {
        let calendar = Calendar.current
        let routineSteps = steps.map { draft -> RoutineStep in
            let components = calendar.dateComponents([.hour, .minute], from: draft.time)
            return RoutineStep(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Route" : draft.title,
                scheduledHour: components.hour ?? 0,
                scheduledMinute: components.minute ?? 0,
                routeID: draft.routeID,
                stayDurationMinutes: draft.stayMinutes,
                delay: DelayWindow(minimumMinutes: min(draft.minimumDelay, draft.maximumDelay), maximumMinutes: max(draft.minimumDelay, draft.maximumDelay))
            )
        }
        onSave(RoutineProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), weekdays: weekdays, steps: routineSteps))
    }
}

private struct RoutineExceptionEditor: View {
    let routines: [RoutineProfile]
    let onSave: (RoutineException) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var routineID: UUID?
    @State private var date = Date()
    @State private var kind: RoutineExceptionKind = .skipDay
    @State private var delayMinutes = 15
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Routine", selection: $routineID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(routines) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Action", selection: $kind) {
                    ForEach(RoutineExceptionKind.allCases) { Text($0.label).tag($0) }
                }
                if kind == .delay { Stepper("Extra delay: \(delayMinutes) min", value: $delayMinutes, in: 1...240) }
                TextField("Note", text: $note)
            }
            .navigationTitle("Exception Day").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let routineID else { return }
                        onSave(RoutineException(profileID: routineID, date: date, kind: kind, delayMinutes: kind == .delay ? delayMinutes : 0, note: note))
                    }.disabled(routineID == nil)
                }
            }
            .onAppear { routineID = routineID ?? routines.first?.id }
        }
    }
}
