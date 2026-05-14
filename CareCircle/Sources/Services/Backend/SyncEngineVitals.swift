import Foundation
import SwiftData

// MARK: - SyncEngine vitals enqueue (Phase 33)

extension SyncEngine {
    func enqueueVitalCreate(_ vital: Vital) {
        enqueue(
            operationType: SyncOperationType.createVital,
            circleId: vital.circle?.id,
            payload: CreateVitalPayload(
                vitalId: vital.id,
                kind: vital.kindRaw,
                recordedAt: vital.recordedAt,
                valueNumeric: vital.valueNumeric,
                valueText: vital.valueText,
                unit: vital.unit,
                source: vital.sourceRaw,
                healthkitUUID: vital.healthkitUUID,
                notes: vital.notes,
                recordedByAppleUserID: vital.recordedByAppleUserID,
                createdAt: vital.createdAt
            )
        )
    }
}
