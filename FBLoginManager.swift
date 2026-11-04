import Foundation
import AuthenticationServices
import Combine

class FBLoginManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    let appId = "2326255351520305"
    let redirectURI = "https://tcokchallenge.com/scripts/smcreportreach/index.php"
    
    func loginWithFacebook(completion: @escaping (String?) -> Void) {
        let permissions = [
            "pages_show_list",
            "pages_read_engagement",
            "pages_read_user_content",
            "business_management"
        ].joined(separator: ",")
        
        var components = URLComponents(string: "https://www.facebook.com/v19.0/dialog/oauth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: permissions)
        ]
        
        guard let authURL = components.url else {
            self.errorMessage = "Failed to construct authorization URL."
            completion(nil)
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fb2326255351520305"
        ) { callbackURL, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.errorMessage = "Login error: \(error.localizedDescription)"
                    }
                    completion(nil)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let fragment = callbackURL.fragment else {
                    self.errorMessage = "No access token fragment found in response."
                    completion(nil)
                    return
                }
                
                let items = fragment.components(separatedBy: "&")
                for item in items {
                    let pair = item.components(separatedBy: "=")
                    if pair.count == 2, pair[0] == "access_token" {
                        completion(pair[1])
                        return
                    }
                }
                
                self.errorMessage = "Access token missing from hash response."
                completion(nil)
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? NSWindow()
    }
}
