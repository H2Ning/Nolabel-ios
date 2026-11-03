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

        guard let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "www"
        ) else {
            return webView
        }

        webView.loadFileURL(
            indexURL,
            allowingReadAccessTo: indexURL.deletingLastPathComponent()
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static func bridgeScript(for raw: String) -> String {
        let encoded = (try? JSONEncoder().encode(raw)) ?? Data("\"\"".utf8)
        let literal = String(data: encoded, encoding: .utf8) ?? "\"\""
        return "window.__nolabelNativeBills = \(literal);"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
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
