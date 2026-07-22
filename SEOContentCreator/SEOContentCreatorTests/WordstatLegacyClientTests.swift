import Testing
import Foundation
@testable import SEOContentCreator

struct WordstatLegacyClientTests {
    @Test func recognizesCertificateFailureCodes() {
        let certificateCodes: [URLError.Code] = [
            .serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateNotYetValid,
            .secureConnectionFailed
        ]

        for code in certificateCodes {
            #expect(WordstatLegacyClient.isCertificateFailure(URLError(code)))
        }
    }

    @Test func doesNotFlagUnrelatedNetworkErrorsAsCertificateFailures() {
        let unrelatedCodes: [URLError.Code] = [.notConnectedToInternet, .timedOut, .cannotFindHost, .badServerResponse]

        for code in unrelatedCodes {
            #expect(!WordstatLegacyClient.isCertificateFailure(URLError(code)))
        }
    }
}
