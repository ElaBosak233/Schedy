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
    let onHTMLReceived: (String) -> Void

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
                if loadProgress < 1 {
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
                .autocapitalization(.none)
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
        let raw = urlBarText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        var s = raw
        if !s.hasPrefix("http://"), !s.hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s) else { return }
        pendingLoadURL = url
    }
}

private struct AcademicAffairsWebViewRepresentable: UIViewControllerRepresentable {
    let initialURL: URL
    @Binding var urlBarText: String
    @Binding var pendingLoadURL: URL?
    @Binding var requestHTML: Bool
    @Binding var loadProgress: Double
    let onHTMLReceived: (String) -> Void

    func makeUIViewController(context: Context) -> AcademicAffairsWebViewController {
        let vc = AcademicAffairsWebViewController(initialURL: initialURL)
        vc.onHTMLReceived = onHTMLReceived
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
            uiViewController.captureHTML { [onHTMLReceived] html in
                DispatchQueue.main.async {
                    onHTMLReceived(html)
                    requestHTML = false
                }
            }
        }
    }
}

private final class AcademicAffairsWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let initialURL: URL
    private var progressObservation: NSKeyValueObservation?
    private var pendingDisplayURL: URL?
    var onHTMLReceived: ((String) -> Void)?
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
        if navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url {
            pendingDisplayURL = url
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onURLChange?(pendingDisplayURL ?? webView.url)
        onProgressChange?(0)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        onURLChange?(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onURLChange?(webView.url)
        onProgressChange?(1)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onProgressChange?(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onProgressChange?(1)
    }

    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url != nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func captureHTML(completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
            if let html = result as? String {
                completion(html)
            } else {
                completion("")
            }
        }
    }
}
