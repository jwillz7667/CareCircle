import CloudKit
import Foundation
import OSLog

// MARK: - CircleSharingService

/// Creates and accepts `CKShare`s for `Circle`s.
///
/// The owner's SwiftData store syncs against the private database automatically once the
/// `ModelContainer` is configured with `.private("iCloud.Res.CareCircle")`. This service
/// supplies the *sharing* half — it manages the per-circle `CKRecordZone`, mirrors the
/// `Circle` into a `CKRecord` that can act as the share's root, and emits the resulting
/// `CKShare.url` for handoff via the system share sheet.
///
/// `CircleSharingService.shared` is the single-instance escape hatch the `UISceneDelegate`
/// uses to forward inbound share acceptances. SwiftUI views inject the service via
/// `EnvironmentValues.circleSharingService` for testability.
@MainActor
final class CircleSharingService {
    static let memberCap = 8
    static let shared = CircleSharingService()

    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: CloudKitConfiguration.containerIdentifier)) {
        self.container = container
    }

    // MARK: Account status

    func iCloudAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            AppLogger.cloudKit.error(
                "accountStatus failed: \(String(describing: error), privacy: .public)"
            )
            return .couldNotDetermine
        }
    }

    // MARK: Share creation

    /// Creates (or retrieves) a `CKShare` for the given Circle and returns a payload suitable
    /// for handing to a share sheet.
    func share(
        _ circle: Circle,
        suggestedRole: MemberRole
    ) async throws(CircleSharingError)
        -> CircleSharePayload
    {
        let status = await iCloudAccountStatus()
        guard status == .available else {
            throw .notSignedIntoiCloud
        }

        guard activeMemberCount(in: circle) < Self.memberCap else {
            throw .capReached(limit: Self.memberCap)
        }

        do {
            return try await buildSharePayload(for: circle, suggestedRole: suggestedRole)
        } catch let error as CircleSharingError {
            throw error
        } catch let ck as CKError {
            AppLogger.cloudKit.error(
                "share(_:) CKError: \(ck.localizedDescription, privacy: .public)"
            )
            throw .ckFailure(ck.localizedDescription)
        } catch {
            AppLogger.cloudKit.error(
                "share(_:) failed: \(String(describing: error), privacy: .public)"
            )
            throw .ckFailure(error.localizedDescription)
        }
    }

    private func buildSharePayload(
        for circle: Circle,
        suggestedRole: MemberRole
    ) async throws
        -> CircleSharePayload
    {
        let zoneID = CloudKitConfiguration.recordZoneID(for: circle.id)
        let recordID = CKRecord.ID(recordName: circle.id.uuidString, zoneID: zoneID)

        try await ensureZoneExists(zoneID)

        let circleRecord = try await fetchOrCreateCircleRecord(
            recordID: recordID,
            name: circle.name,
            ownerAppleUserID: circle.ownerAppleUserID
        )

        let share = try await fetchOrCreateShare(
            for: circleRecord,
            titleFallback: circle.name
        )

        guard let url = share.url else {
            throw CircleSharingError.ckFailure("Share has no URL")
        }

        return CircleSharePayload(
            url: url,
            share: share,
            container: container,
            participantRoleHint: suggestedRole
        )
    }

    // MARK: Share acceptance

    func acceptShare(metadata: CKShare.Metadata) async throws(CircleSharingError) {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
                operation.perShareResultBlock = { _, result in
                    if case let .failure(error) = result {
                        AppLogger.cloudKit.error(
                            "perShare acceptance failure: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                operation.acceptSharesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                container.add(operation)
            }
            NotificationCenter.default.post(
                name: CloudKitConfiguration.shareAcceptedNotification,
                object: metadata.share.recordID
            )
        } catch let ck as CKError {
            AppLogger.cloudKit.error(
                "acceptShare CKError: \(ck.localizedDescription, privacy: .public)"
            )
            throw .ckFailure(ck.localizedDescription)
        } catch {
            AppLogger.cloudKit.error(
                "acceptShare failed: \(String(describing: error), privacy: .public)"
            )
            throw .ckFailure(error.localizedDescription)
        }
    }

    // MARK: Member cap

    func activeMemberCount(in circle: Circle) -> Int {
        circle.members.count(where: { $0.status != .removed })
    }

    // MARK: Private helpers

    private func ensureZoneExists(_ zoneID: CKRecordZone.ID) async throws {
        let privateDB = container.privateCloudDatabase
        do {
            _ = try await privateDB.recordZone(for: zoneID)
        } catch let ck as CKError where ck.code == .zoneNotFound {
            let zone = CKRecordZone(zoneID: zoneID)
            _ = try await privateDB.save(zone)
        }
    }

    private func fetchOrCreateCircleRecord(
        recordID: CKRecord.ID,
        name: String,
        ownerAppleUserID: String
    ) async throws
        -> CKRecord
    {
        let privateDB = container.privateCloudDatabase
        do {
            let existing = try await privateDB.record(for: recordID)
            existing["name"] = name as CKRecordValue
            existing["ownerAppleUserID"] = ownerAppleUserID as CKRecordValue
            _ = try await privateDB.save(existing)
            return existing
        } catch let ck as CKError where ck.code == .unknownItem {
            let record = CKRecord(recordType: CloudKitConfiguration.circleRecordType, recordID: recordID)
            record["name"] = name as CKRecordValue
            record["ownerAppleUserID"] = ownerAppleUserID as CKRecordValue
            record["createdAt"] = Date.now as CKRecordValue
            _ = try await privateDB.save(record)
            return record
        }
    }

    private func fetchOrCreateShare(
        for rootRecord: CKRecord,
        titleFallback: String
    ) async throws
        -> CKShare
    {
        let privateDB = container.privateCloudDatabase
        let shareRecordID = CKRecord.ID(
            recordName: "share-\(rootRecord.recordID.recordName)",
            zoneID: rootRecord.recordID.zoneID
        )
        do {
            if let existing = try await privateDB.record(for: shareRecordID) as? CKShare {
                return existing
            }
            // Record exists but is not a CKShare — abnormal, recreate below.
        } catch let ck as CKError where ck.code == .unknownItem {
            // Fall through to creation.
        }

        let share = CKShare(rootRecord: rootRecord, shareID: shareRecordID)
        share[CKShare.SystemFieldKey.title] = "Join the \(titleFallback) Circle" as CKRecordValue
        share.publicPermission = .none

        let operation = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
            var savedShare: CKShare?
            operation.perRecordSaveBlock = { _, result in
                if case let .success(record) = result, let asShare = record as? CKShare {
                    savedShare = asShare
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let s = savedShare {
                        continuation.resume(returning: s)
                    } else {
                        continuation.resume(returning: share)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }
}
