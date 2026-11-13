import AuthenticationServices
import Foundation

/// PLA-103: a short, human reason for a failed Spotify sign-in, shown in
/// Settings and on the HUD's connect screen. `nil` means "say nothing":
/// closing the sign-in window isn't a failure.
enum SignInFailure {
  static func message(for error: Error) -> String? {
    if let auth = error as? ASWebAuthenticationSessionError, auth.code == .canceledLogin {
      return nil
    }
    if let auth = error as? SpotifyAuthError {
      switch auth {
      case .tokenEndpointStatus(let status):
        return "Spotify turned down the sign-in (error \(status)). Try again."
      case .invalidResponse:
        return "Spotify sent back something unexpected. Try again."
      case .refreshRejected:
        return "Spotify rejected the saved sign-in. Connect again."
      case .missingStoredToken:
        return "Sign-in didn't save. Try again."
      }
    }
    if let url = error as? URLError {
      switch url.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
           .cannotConnectToHost, .timedOut, .dnsLookupFailed:
        return "Couldn't reach Spotify. Check your connection and try again."
      default:
        return "Couldn't reach Spotify. Try again."
      }
    }
    let ns = error as NSError
    if ns.domain == "Dial.Auth" {
      return "Sign-in didn't finish. Try again."
    }
    return "Sign-in failed. Try again."
  }
}
