//
//  AlarmsView.swift
//  Broke
//

import SwiftUI

struct AlarmsView: View {
    @EnvironmentObject private var alarmManager: TagAlarmManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingAlarm: TagAlarm?

    var body: some View {
        NavigationView {
            List {
                if alarmManager.alarms.isEmpty {
                    Text("Wake-up alarms only stop when you scan your tag. Bedtime alarms keep ringing until you brick your phone.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                ForEach(alarmManager.alarms) { alarm in
                    AlarmRow(alarm: alarm) { isEnabled in
                        var updated = alarm
                        updated.isEnabled = isEnabled
                        alarmManager.save(updated)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingAlarm = alarm }
                }
                .onDelete { offsets in
                    offsets.map { alarmManager.alarms[$0] }.forEach(alarmManager.delete)
                }

                if !alarmManager.alarms.isEmpty && !alarmManager.isAuthorized {
                    Text("Alarms need permission to ring. Allow them in Settings → Broke → Alarms.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Alarms")
            .navigationBarItems(
                leading: Button("Done") { dismiss() },
                trailing: Button(action: {
                    editingAlarm = TagAlarm(kind: .wakeUp, hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6])
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(item: $editingAlarm) { alarm in
                AlarmFormView(
                    alarm: alarm,
                    isNew: !alarmManager.alarms.contains { $0.id == alarm.id },
                    onSave: { alarmManager.save($0) },
                    onDelete: { alarmManager.delete($0) }
                )
            }
        }
    }
}

struct AlarmRow: View {
    let alarm: TagAlarm
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString(hour: alarm.hour, minute: alarm.minute))
                    .font(.system(size: 40, weight: .light))
                Label("\(alarm.kind.label) · \(weekdaySummary(alarm.weekdays))", systemImage: alarm.kind.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
        }
        .opacity(alarm.isEnabled ? 1 : 0.5)
    }
}

struct AlarmFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: TagAlarm
    @State private var time: Date
    let isNew: Bool
    let onSave: (TagAlarm) -> Void
    let onDelete: (TagAlarm) -> Void

    init(alarm: TagAlarm, isNew: Bool, onSave: @escaping (TagAlarm) -> Void, onDelete: @escaping (TagAlarm) -> Void) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute)) ?? Date())
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section(footer: Text(alarm.kind == .wakeUp
                                     ? "Scanning your tag stops the alarm. Put the tag somewhere you have to get up to reach."
                                     : "The alarm keeps coming back until you brick your phone with your tag.")) {
                    Picker("Type", selection: $alarm.kind) {
                        ForEach(TagAlarm.Kind.allCases) { kind in
                            Label(kind.label, systemImage: kind.icon).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Repeat"), footer: Text(alarm.weekdays.isEmpty ? "Rings once." : "")) {
                    HStack {
                        ForEach(orderedWeekdays(), id: \.self) { weekday in
                            let isOn = alarm.weekdays.contains(weekday)
                            Button(Calendar.current.veryShortWeekdaySymbols[weekday - 1]) {
                                if isOn {
                                    alarm.weekdays.remove(weekday)
                                } else {
                                    alarm.weekdays.insert(weekday)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundColor(isOn ? .white : .primary)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            onDelete(alarm)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    alarm.hour = components.hour ?? 0
                    alarm.minute = components.minute ?? 0
                    alarm.isEnabled = true
                    onSave(alarm)
                    dismiss()
                }
            )
        }
    }

    // Weekday numbers starting from the user's first day of the week
    private func orderedWeekdays() -> [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

private func timeString(hour: Int, minute: Int) -> String {
    let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    return date.formatted(date: .omitted, time: .shortened)
}

private func weekdaySummary(_ weekdays: Set<Int>) -> String {
    if weekdays.isEmpty { return "Once" }
    if weekdays == Set(1...7) { return "Every day" }
    if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
    if weekdays == [1, 7] { return "Weekends" }

    let symbols = Calendar.current.shortWeekdaySymbols
    return weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
}
