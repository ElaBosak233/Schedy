//
//  AcademicAffairsWebView.swift
//  Schedy
//
//  导入流程中的内嵌浏览器：打开教务系统、地址栏、进度条、「导入当前页」注入 JS 抓取课程数据。
//

import SwiftUI
import WebKit

struct AcademicAffairsWebView: View {
    let initialURL: URL
    let academicAffairsType: AcademicAffairsType
    @Binding var urlBarText: String
    @Binding var pendingLoadURL: URL?
    @Binding var requestHTML: Bool
    @State private var loadProgress: Double = 1
    let onCourseDataReceived: (URL?, Result<String, Error>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            AcademicAffairsWebViewRepresentable(
                initialURL: initialURL,
                academicAffairsType: academicAffairsType,
                urlBarText: $urlBarText,
                pendingLoadURL: $pendingLoadURL,
                requestHTML: $requestHTML,
                loadProgress: $loadProgress,
                onCourseDataReceived: onCourseDataReceived
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
    let academicAffairsType: AcademicAffairsType
    @Binding var urlBarText: String
    @Binding var pendingLoadURL: URL?
    @Binding var requestHTML: Bool
    @Binding var loadProgress: Double
    let onCourseDataReceived: (URL?, Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> AcademicAffairsWebViewController {
        let vc = AcademicAffairsWebViewController(initialURL: initialURL, academicAffairsType: academicAffairsType)
        vc.onCourseDataReceived = onCourseDataReceived
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
    private let academicAffairsType: AcademicAffairsType
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var pendingHTMLRequest = false
    private var waitingForInjectedResult = false
    private var originalTitle: String?
    var onCourseDataReceived: ((URL?, Result<String, Error>) -> Void)?
    var onHTMLRequestConsumed: (() -> Void)?
    var onURLChange: ((URL?) -> Void)?
    var onProgressChange: ((Double) -> Void)?

    init(initialURL: URL, academicAffairsType: AcademicAffairsType) {
        self.initialURL = initialURL
        self.academicAffairsType = academicAffairsType
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
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            self?.handleTitleChange(webView.title)
        }
        webView.load(URLRequest(url: initialURL))
    }

    deinit {
        progressObservation?.invalidate()
        titleObservation?.invalidate()
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
            injectCourseCaptureNow()
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

    // MARK: - Course data capture
    func requestHTMLCapture() {
        onHTMLRequestConsumed?()
        if webView.isLoading {
            pendingHTMLRequest = true
            return
        }
        injectCourseCaptureNow()
    }

    private func injectCourseCaptureNow() {
        guard !waitingForInjectedResult else { return }
        waitingForInjectedResult = true
        originalTitle = webView.title

        let js = AcademicAffairsInjectedCourseParser.providerScript(for: academicAffairsType)
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.finishInjectedCapture(.failure(error))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.waitingForInjectedResult else { return }
                self.finishInjectedCapture(.failure(AcademicAffairsWebViewError.timeout))
            }
        }
    }

    private func handleTitleChange(_ title: String?) {
        guard waitingForInjectedResult, let title else { return }
        if title.hasPrefix("KEBIAO_OK:") {
            let payload = String(title.dropFirst("KEBIAO_OK:".count))
            finishInjectedCapture(.success(payload))
        } else if title.hasPrefix("KEBIAO_ERR:") {
            let message = String(title.dropFirst("KEBIAO_ERR:".count))
            finishInjectedCapture(.failure(AcademicAffairsWebViewError.provider(message)))
        }
    }

    private func finishInjectedCapture(_ result: Result<String, Error>) {
        guard waitingForInjectedResult else { return }
        waitingForInjectedResult = false
        let callback = onCourseDataReceived
        let url = webView.url
        if let originalTitle {
            webView.evaluateJavaScript("document.title = \(Self.javascriptStringLiteral(originalTitle));", completionHandler: nil)
        }
        callback?(url, result)
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "''"
        }
        return String(json.dropFirst().dropLast())
    }

    func captureWebArchive(completion: @escaping (Data?) -> Void) {
        webView.createWebArchiveData { result in
            completion(try? result.get())
        }
    }
}

private enum AcademicAffairsWebViewError: LocalizedError {
    case provider(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .provider(let message):
            return message
        case .timeout:
            return "注入脚本执行超时，请确认已进入课表页面后重试。"
        }
    }
}
