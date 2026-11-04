import Foundation
import Security

/// iOS 27 can reject the h2ning.com chain with NSURLErrorServerCertificateUntrusted
/// (-1202) even though Safari accepts it. The server presents a valid leaf
/// issued by TLC DV TLS CA, but its cross-signed root is not accepted by the
/// app's trust evaluation. Pin the intermediate CA and let Security.framework
/// re-check hostname, validity and key usage against that anchor.
final class PinnedTrustDelegate: NSObject, URLSessionDelegate {
    static let shared = PinnedTrustDelegate()

    private static let pinnedIntermediate: SecCertificate? = {
        let base64 = "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"
        guard let data = Data(base64Encoded: base64) else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()
        guard host == "h2ning.com" || host.hasSuffix(".h2ning.com") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        guard let pinned = Self.pinnedIntermediate else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        SecTrustSetAnchorCertificates(trust, [pinned] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
