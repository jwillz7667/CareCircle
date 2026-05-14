import Foundation

// MARK: - ShiftArtifactBuilder

/// Snapshots the structured care events that fall inside a shift window.
/// The resulting `ShiftDigestArtifactsSnapshot` is encoded onto the
/// digest at compose time so the historical record stays stable even
/// if the source rows are later edited or deleted.
///
/// Vitals and journal entries land in later phases (33 and 34); their
/// arrays stay empty for now and are wired in once those models exist.
enum ShiftArtifactBuilder {
    static func build(
        circle: Circle,
        shiftStartAt: Date,
        shiftEndAt: Date
    )
        -> ShiftDigestArtifactsSnapshot
    {
        let window = shiftStartAt ... shiftEndAt
        return ShiftDigestArtifactsSnapshot(
            doses: doseSnapshots(in: window, circle: circle),
            appointments: appointmentSnapshots(in: window, circle: circle),
            vitals: [],
            journal: []
        )
    }

    private static func doseSnapshots(
        in window: ClosedRange<Date>,
        circle: Circle
    )
        -> [ShiftDigestArtifactsSnapshot.DoseSnapshot]
    {
        var snapshots: [ShiftDigestArtifactsSnapshot.DoseSnapshot] = []
        for medication in circle.medications {
            for event in medication.doseEvents {
                let reference = event.takenAt ?? event.scheduledAt
                guard window.contains(reference) else { continue }
                snapshots.append(
                    ShiftDigestArtifactsSnapshot.DoseSnapshot(
                        id: event.id,
                        medicationName: medication.name,
                        dosage: medication.dosage.isEmpty ? nil : medication.dosage,
                        scheduledAt: event.scheduledAt,
                        takenAt: event.takenAt,
                        status: event.status.rawValue
                    )
                )
            }
        }
        return snapshots.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private static func appointmentSnapshots(
        in window: ClosedRange<Date>,
        circle: Circle
    )
        -> [ShiftDigestArtifactsSnapshot.AppointmentSnapshot]
    {
        circle.appointments
            .filter { window.contains($0.startsAt) }
            .sorted { $0.startsAt < $1.startsAt }
            .map { appointment in
                ShiftDigestArtifactsSnapshot.AppointmentSnapshot(
                    id: appointment.id,
                    title: appointment.title,
                    startsAt: appointment.startsAt,
                    durationMinutes: appointment.durationMinutes,
                    status: appointment.completedAt != nil ? "attended" : nil
                )
            }
    }
}
