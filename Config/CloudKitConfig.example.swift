import Foundation

/// Copy this file to `Shared/CloudKitConfig.swift` and fill it in. That path is gitignored,
/// so the key never reaches the public repo. Leave the values empty and the app simply works
/// without remote sending: guests can still send over the local network.
///
/// Where the values come from — CloudKit Console (https://icloud.developer.apple.com):
///  1. Create the container `iCloud.com.leeo.moa`.
///  2. Tokens & Keys → Server-to-Server Keys → create a key. Keep the printed private key;
///     it is shown only once. `keyID` is the long hex string next to it.
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
    /// Server-to-server key ID (long hex string).
    static let keyID = ""
    /// EC P-256 private key, DER, base64 encoded.
    static let privateKeyBase64 = ""

    static var isConfigured: Bool {
        !containerID.isEmpty && !keyID.isEmpty && !privateKeyBase64.isEmpty
    }
}
