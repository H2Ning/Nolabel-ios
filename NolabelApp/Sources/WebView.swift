import SwiftUI
import UIKit
import WebKit

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "nolabelStore")

        if let raw = BillStore.shared.loadRaw() {
            let userScript = WKUserScript(
                source: Self.bridgeScript(for: raw),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            controller.addUserScript(userScript)
        }

        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(
            red: 7.0 / 255.0,
            green: 11.0 / 255.0,
            blue: 9.0 / 255.0,
            alpha: 1.0
        )
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadRemote(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static func bridgeScript(for raw: String) -> String {
        let encoded = (try? JSONEncoder().encode(raw)) ?? Data("\"\"".utf8)
        let literal = String(data: encoded, encoding: .utf8) ?? "\"\""
        return "window.__nolabelNativeBills = \(literal);"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private static let remoteURL = URL(string: "https://h2ning.com/Nolabel/")!
        private var didFallback = false

        func loadRemote(in webView: WKWebView) {
            webView.load(URLRequest(url: Self.remoteURL))
        }

        private func loadLocalFallback(in webView: WKWebView) {
            guard !didFallback else { return }
            didFallback = true
            guard let indexURL = Bundle.main.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "www"
            ) else {
                return
            }
            webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: indexURL.deletingLastPathComponent()
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            loadLocalFallback(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            loadLocalFallback(in: webView)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "nolabelStore",
                  let raw = message.body as? String else {
                return
            }
            BillStore.shared.saveRaw(raw)
        }
    }
}
