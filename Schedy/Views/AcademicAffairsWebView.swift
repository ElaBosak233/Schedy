//
//  AcademicAffairsWebView.swift
//  schedy
//
//  内嵌浏览器：打开教务（Academic Affairs）系统，支持地址栏修改网址、「导入当前页」获取 HTML
//

import SwiftUI
import WebKit

struct AcademicAffairsWebView: View {
    let initialURL: URL
    @Binding var urlBarText: String
    @Binding var pendingLoadURL: URL?
    @Binding var requestHTML: Bool
    @State private var loadProgress: Double = 1
    let onHTMLReceived: (URL?, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            AcademicAffairsWebViewRepresentable(
                initialURL: initialURL,
                urlBarText: $urlBarText,
                pendingLoadURL: $pendingLoadURL,
                requestHTML: $requestHTML,
                loadProgress: $loadProgress,
                onHTMLReceived: onHTMLReceived
            )
            .overlay(alignment: .top) {
                if loadProgress < 0.99 {
                    ProgressView(value: loadProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(height: 3)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            TextField("输入或粘贴网址", text: $urlBarText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit { tryLoadURL() }
            Button("前往") {
                tryLoadURL()
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlBarText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    private func tryLoadURL() {
        guard let url = normalizeURL(from: urlBarText) else { return }
        pendingLoadURL = url
    }

    private func normalizeURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "http://" + trimmed)
    }
}

private struct AcademicAffairsWebViewRepresentable: UIViewControllerRepresentable {
    let initialURL: URL
    @Binding var urlBarText: String
    @Binding var pendingLoadURL: URL?
    @Binding var requestHTML: Bool
    @Binding var loadProgress: Double
    let onHTMLReceived: (URL?, String) -> Void

    func makeUIViewController(context: Context) -> AcademicAffairsWebViewController {
        let vc = AcademicAffairsWebViewController(initialURL: initialURL)
        vc.onHTMLReceived = onHTMLReceived
        vc.onHTMLRequestConsumed = { DispatchQueue.main.async { requestHTML = false } }
        vc.onURLChange = { url in
            DispatchQueue.main.async {
                urlBarText = url?.absoluteString ?? ""
            }
        }
        vc.onProgressChange = { progress in
            DispatchQueue.main.async {
                loadProgress = progress
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AcademicAffairsWebViewController, context: Context) {
        if let url = pendingLoadURL {
            uiViewController.loadURL(url)
            DispatchQueue.main.async { pendingLoadURL = nil }
        }
        if requestHTML {
            uiViewController.requestHTMLCapture()
        }
    }
}

private final class AcademicAffairsWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let initialURL: URL
    private var progressObservation: NSKeyValueObservation?
    private var pendingHTMLRequest = false
    var onHTMLReceived: ((URL?, String) -> Void)?
    var onHTMLRequestConsumed: (() -> Void)?
    var onURLChange: ((URL?) -> Void)?
    var onProgressChange: ((Double) -> Void)?

    init(initialURL: URL) {
        self.initialURL = initialURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.onProgressChange?(webView.estimatedProgress)
        }
        webView.load(URLRequest(url: initialURL))
    }

    deinit {
        progressObservation?.invalidate()
    }

    func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onURLChange?(webView.url)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        onURLChange?(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onURLChange?(webView.url)
        if pendingHTMLRequest {
            pendingHTMLRequest = false
            captureHTMLNow()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}

    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url != nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    // MARK: - HTML capture
    func requestHTMLCapture() {
        onHTMLRequestConsumed?()
        if webView.isLoading {
            pendingHTMLRequest = true
            return
        }
        captureHTMLNow()
    }

    private func captureHTMLNow() {
        captureHTML { [weak self] url, html in
            self?.onHTMLReceived?(url, html)
        }
    }

    func captureHTML(completion: @escaping (URL?, String) -> Void) {
        let js = """
        (function() {
          var html = document.documentElement ? document.documentElement.outerHTML : "";
          if (html && html.length > 100) return html;
          var body = document.body ? document.body.innerText : "";
          return body ? "<pre>" + body + "</pre>" : html;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let html = (result as? String) ?? ""
            completion(self?.webView.url, html)
        }
    }

    func captureWebArchive(completion: @escaping (Data?) -> Void) {
        webView.createWebArchiveData { result in
            completion(try? result.get())
        }
    }
}
