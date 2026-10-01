import Foundation

/// Copy this file to `Shared/CloudKitConfig.swift` and fill it in. That path is gitignored,
/// so the key never reaches the public repo. The copy is required to build: a fresh clone has
/// no `CloudKitConfig` and fails to compile. Leaving the values empty builds fine and simply
/// turns remote sending off — guests can still send over the local network.
///
/// Where the values come from — CloudKit Console (https://icloud.developer.apple.com):
///  1. Create the container `iCloud.com.leeo.moa`.
///  2. Generate a key pair locally (`openssl ecparam -name prime256v1 -genkey -noout -out eckey.pem`,
///     then `openssl ec -in eckey.pem -pubout`). In Tokens & Keys → Server-to-Server Keys, register
///     the public key in **both** Development and Production; each gives its own key ID.
///  3. Turn the PEM private key into the base64 DER string this file wants:
///       openssl ec -in eckey.pem -outform DER | base64
///  4. Schema → Record Types → `MoaItem`: mark the `eventID` field **Queryable**,
///     and `___createTime` Sortable. Without that index the host can't list what arrived.
///
/// The key lives inside the App Clip binary, so treat it as "anyone determined can read it".
/// That is why every file and all metadata are encrypted with the key from the QR before
/// upload — CloudKit only ever sees ciphertext.
enum CloudKitConfig {
    /// e.g. "iCloud.com.leeo.moa"
    static let containerID = ""
    /// Server-to-server key IDs (long hex strings). CloudKit Console issues keys per
    /// environment, so register the same public key in Development and Production.
    static let developmentKeyID = ""
    static let productionKeyID = ""

    static var keyID: String {
        #if DEBUG
        developmentKeyID
        #else
        productionKeyID
        #endif
    }
    /// EC P-256 private key, DER, base64 encoded.
    static let privateKeyBase64 = ""

    static var isConfigured: Bool {
        !containerID.isEmpty && !keyID.isEmpty && !privateKeyBase64.isEmpty
    }
}
