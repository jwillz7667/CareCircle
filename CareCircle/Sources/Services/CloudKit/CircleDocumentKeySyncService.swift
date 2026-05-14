import CloudKit
import CryptoKit
import Foundation
import OSLog

// MARK: - CircleDocumentKeySyncService

/// Distributes the per-circle document DEK across share participants.
///
/// The owner publishes a `DocumentKeyEnvelope` record into their
/// private CloudKit database; CloudKit propagates it through the
/// share to every accepted participant. Members fetch the envelope
/// from the shared database after accepting the share. The DEK rides
/// on `CKRecord.encryptedValues["dek"]` so CloudKit applies per-user
/// end-to-end encryption — the field is unreadable to anyone outside
/// the share, including Apple.
///
/// The service is idempotent on both sides: `publishIfNeeded` skips if
/// the record already exists, and `pullIfMissing` skips if the local
/// Keychain already has a DEK for the circle.
@MainActor
final class CircleDocumentKeySyncService {
    static let shared = CircleDocumentKeySyncService()

    private let container: CKContainer
    private let keyStore: DocumentKeyStore

    init(
        container: CKContainer = CKContainer(identifier: CloudKitConfiguration.containerIdentifier),
        keyStore: DocumentKeyStore = .shared
    ) {
        self.container = container
        self.keyStore = keyStore
    }

    enum SyncError: LocalizedError {
        case notSignedIntoiCloud
        case envelopeMissing
        case envelopeMalformed
        case ckFailure(String)
        case keychain(DocumentKeyStore.KeyStoreError)

        var errorDescription: String? {
            switch self {
            case .notSignedIntoiCloud:
                "Sign into iCloud so the Circle's document key can be shared."
            case .envelopeMissing:
                "The Circle's document key hasn't been published yet."
            case .envelopeMalformed:
                "The Circle's document key envelope is unreadable."
            case let .ckFailure(message):
                "CloudKit error: \(message)"
            case let .keychain(error):
                error.errorDescription ?? "Keychain error"
            }
        }
    }

    // MARK: - Publish (owner)

    /// Writes the local DEK to a `DocumentKeyEnvelope` record in the
    /// owner's private database. No-op if the record already exists.
    /// Provisions the DEK locally first so a brand-new circle gets a
    /// key on first publish.
    func publishIfNeeded(circleID: UUID) async throws(SyncError) {
        let rawKey: Data
        do {
            let key = try keyStore.provisionKey(circleID: circleID)
            rawKey = key.withUnsafeBytes { Data($0) }
        } catch let error as DocumentKeyStore.KeyStoreError {
            throw .keychain(error)
        } catch {
            throw .ckFailure(error.localizedDescription)
        }

        let recordID = CloudKitConfiguration.dekEnvelopeRecordID(for: circleID)
        let privateDB = container.privateCloudDatabase

        do {
            _ = try await privateDB.record(for: recordID)
            return
        } catch let ck as CKError where ck.code == .unknownItem {
            // Fall through to create the envelope.
        } catch let ck as CKError {
            AppLogger.cloudKit.error(
                "DEK envelope fetch failed: \(ck.localizedDescription, privacy: .public)"
            )
            throw .ckFailure(ck.localizedDescription)
        } catch {
            throw .ckFailure(error.localizedDescription)
        }

        let record = CKRecord(
            recordType: CloudKitConfiguration.dekEnvelopeRecordType,
            recordID: recordID
        )
        record.encryptedValues["dek"] = rawKey

        do {
            _ = try await privateDB.save(record)
            AppLogger.cloudKit.info(
                "Published DEK envelope for circle \(circleID.uuidString, privacy: .public)"
            )
        } catch let ck as CKError where ck.code == .serverRecordChanged {
            // Another device beat us to it; nothing to do.
            return
        } catch let ck as CKError {
            AppLogger.cloudKit.error(
                "DEK envelope save failed: \(ck.localizedDescription, privacy: .public)"
            )
            throw .ckFailure(ck.localizedDescription)
        } catch {
            throw .ckFailure(error.localizedDescription)
        }
    }

    // MARK: - Pull (member)

    /// Fetches the DEK envelope from the shared database and persists
    /// the DEK into the local Keychain. No-op if a local key already
    /// exists or if the envelope hasn't been published yet — both
    /// are valid resting states.
    func pullIfMissing(circleID: UUID) async {
        do {
            if try keyStore.loadKey(circleID: circleID) != nil {
                return
            }
        } catch {
            AppLogger.cloudKit.error(
                "DEK presence check failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        let recordID = CloudKitConfiguration.dekEnvelopeRecordID(for: circleID)
        let sharedDB = container.sharedCloudDatabase

        let record: CKRecord
        do {
            record = try await sharedDB.record(for: recordID)
        } catch let ck as CKError where ck.code == .unknownItem {
            return
        } catch {
            AppLogger.cloudKit.error(
                "DEK envelope fetch failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        guard let dek = record.encryptedValues["dek"] as? Data, dek.count == 32 else {
            AppLogger.cloudKit.error(
                "DEK envelope payload malformed for circle \(circleID.uuidString, privacy: .public)"
            )
            return
        }

        do {
            _ = try keyStore.persist(rawKey: dek, circleID: circleID)
            AppLogger.cloudKit.info(
                "Pulled DEK envelope for circle \(circleID.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.cloudKit.error(
                "DEK envelope persist failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Bulk helpers

    /// Convenience for cold-start: tries `pullIfMissing` across every
    /// circle the device knows about. Errors are logged, never thrown.
    func pullForAllCircles(_ ids: [UUID]) async {
        for circleID in ids {
            await pullIfMissing(circleID: circleID)
        }
    }
}
