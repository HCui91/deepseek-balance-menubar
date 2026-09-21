//
//  DeepSeekBalance.swift
//  macOS menu bar app showing the DeepSeek API credit balance.
//  Native Swift/AppKit, no Python/pip dependency.
//
//  API: GET https://api.deepseek.com/user/balance
//  API key storage: macOS Keychain only. No config file is read or written.
//  Key lookup order:
//    1. Environment variable DEEPSEEK_API_KEY (debug only)
//    2. macOS Keychain
//  First run: set the key via the menu bar "Set API Key…" item.
//
//  Build: swiftc -O DeepSeekBalance.swift -o build/DeepSeekBalance
//  CLI self-check (no GUI): ./build/DeepSeekBalance --check
//

import Cocoa
import Security

// MARK: - Models & constants

struct BalanceInfo: Codable {
    let currency: String
    let total_balance: String
    let granted_balance: String
    let topped_up_balance: String
}

struct BalanceResponse: Codable {
    let is_available: Bool
    let balance_infos: [BalanceInfo]
}

private let apiURL = URL(string: "https://api.deepseek.com/user/balance")!
private let dashboardURL = URL(string: "https://platform.deepseek.com/usage")!

private let currencySymbols: [String: String] = [
    "CNY": "¥", "USD": "$", "EUR": "€", "GBP": "£",
    "HKD": "HK$", "JPY": "¥", "KRW": "₩",
]

// MARK: - API key (env var / Keychain only, no config file)

/// Source of the current API key; shown in the UI only.
private var keySource: String = "not set"

private func loadApiKey() -> String? {
    if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
        keySource = "env DEEPSEEK_API_KEY"
        return env
    }
    if let key = keychainLoad() {
        keySource = "macOS Keychain"
        return key
    }
    keySource = "not set"
    return nil
}

// MARK: - macOS Keychain

private let keychainService = "dev.deepseek.balance"
private let keychainAccount = "deepseek_api_key"

/// Read the API key from the Keychain.
private func keychainLoad() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let key = String(data: data, encoding: .utf8),
          !key.isEmpty else { return nil }
    return key
}

/// Store/update the API key in the Keychain (encrypted by the system).
@discardableResult
private func keychainSave(_ key: String) -> Bool {
    let data = Data(key.utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
    ]
    var status = SecItemUpdate(query as CFDictionary,
                               [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        status = SecItemAdd(addQuery as CFDictionary, nil)
    }
    return status == errSecSuccess
}

/// Delete the API key from the Keychain.
@discardableResult
private func keychainDelete() -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
}

// MARK: - Status bar icon

/// Load the menu bar icon (transparent background, shown before the balance).
/// Prefers the .app Resources, then falls back to assets/ found by walking up
/// from the executable or the current directory.
private func loadStatusIcon() -> NSImage? {
    if let img = Bundle.main.image(forResource: "icon") {
        return img
    }

    var dirs: [URL] = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
    if let exec = Bundle.main.executableURL {
        var dir = exec.deletingLastPathComponent()
        for _ in 0..<6 {
            dirs.append(dir)
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
    }
    for dir in dirs {
        for name in ["assets/icon@2x.png", "assets/icon.png"] {
            let path = dir.appendingPathComponent(name).path
            guard let img = NSImage(contentsOfFile: path) else { continue }
            if name.contains("@2x") {
                img.size = NSSize(width: img.size.width / 2, height: img.size.height / 2)
            }
            return img
        }
    }
    return nil
}

// MARK: - API request

enum FetchError: LocalizedError {
    case noData
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .noData: return "No response data"
        case .server(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

private func fetchBalance(apiKey: String,
                          completion: @escaping (Result<BalanceResponse, Error>) -> Void) {
    var request = URLRequest(url: apiURL)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 6

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completion(.failure(FetchError.noData))
            return
        }
        guard let data = data, http.statusCode == 200 else {
            completion(.failure(FetchError.server(http.statusCode,
                                                  extractErrorMessage(data) ?? "Server error")))
            return
        }
        do {
            let decoded = try JSONDecoder().decode(BalanceResponse.self, from: data)
            completion(.success(decoded))
        } catch {
            completion(.failure(FetchError.server(200,
                                                  extractErrorMessage(data) ?? "Failed to parse response")))
        }
    }.resume()
}

/// Try to extract error.message from an error response body.
private func extractErrorMessage(_ data: Data?) -> String? {
    guard let data = data,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let err = obj["error"] as? [String: Any],
          let msg = err["message"] as? String else { return nil }
    return msg
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var balance: BalanceResponse?
    private var errorMessage: String?
    private var lastUpdated: Date?
    private var apiKey: String?
    private var refreshInterval: TimeInterval = 60
    private var timer: Timer?
    private var isFetching = false

    private var detailMenu: NSMenu!
    private var intervalItems: [NSMenuItem: TimeInterval] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory mode: no Dock icon, menu bar only.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            // Icon before the balance text; keep original color (no template).
            if let icon = loadStatusIcon() {
                icon.isTemplate = false
                button.image = icon
                button.imagePosition = .imageLeading
                button.imageScaling = .scaleProportionallyDown
                button.imageHugsTitle = true
            }
        }

        apiKey = loadApiKey()
        buildMenu()
        scheduleTimer()
        fetch()
    }

    // MARK: Menu construction

    private func buildMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        detailMenu = NSMenu()
        let detailItem = NSMenuItem(title: "Balance Details", action: nil, keyEquivalent: "")
        detailItem.submenu = detailMenu
        menu.addItem(detailItem)
        menu.addItem(.separator())

        let console = NSMenuItem(title: "Open DeepSeek Console", action: #selector(openConsole), keyEquivalent: "")
        console.target = self
        menu.addItem(console)
        menu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        intervalItem.submenu = intervalMenu
        for sec in [30.0, 60.0, 300.0, 900.0, 1800.0] {
            let label = sec < 60 ? "\(Int(sec)) s" : "\(Int(sec) / 60) min"
            let item = NSMenuItem(title: label, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.target = self
            intervalItems[item] = sec
            intervalMenu.addItem(item)
        }
        syncIntervalCheckmarks()
        menu.addItem(intervalItem)

        let setKey = NSMenuItem(title: "Set API Key…", action: #selector(setApiKey), keyEquivalent: "")
        setKey.target = self
        menu.addItem(setKey)

        let clearKey = NSMenuItem(title: "Delete Saved API Key", action: #selector(clearApiKey), keyEquivalent: "")
        clearKey.target = self
        menu.addItem(clearKey)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// With multiple currency accounts, show the one with the largest balance
    /// so a zero-balance account is never displayed.
    private func primaryInfo(_ infos: [BalanceInfo]) -> BalanceInfo? {
        return infos.max { a, b in
            (Double(a.total_balance) ?? 0) < (Double(b.total_balance) ?? 0)
        } ?? infos.first
    }

    private func syncIntervalCheckmarks() {
        for (item, sec) in intervalItems {
            item.state = sec == refreshInterval ? .on : .off
        }
    }

    // MARK: Menu actions

    @objc private func refreshNow() { fetch() }

    @objc private func openConsole() {
        NSWorkspace.shared.open(dashboardURL)
    }

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let sec = intervalItems[sender] else { return }
        refreshInterval = sec
        syncIntervalCheckmarks()
        scheduleTimer()
        fetch()
    }

    @objc private func setApiKey() {
        let alert = NSAlert()
        alert.messageText = "Set DeepSeek API Key"
        alert.informativeText = "Enter your API key (sk-…). It is stored encrypted in the macOS Keychain:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = apiKey ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            let warn = NSAlert()
            warn.messageText = "API key cannot be empty"
            warn.runModal()
            return
        }

        guard keychainSave(key) else {
            let warn = NSAlert()
            warn.messageText = "Failed to save to Keychain"
            warn.informativeText = "Check Keychain access permissions and try again."
            warn.runModal()
            return
        }
        keySource = "macOS Keychain"
        apiKey = key
        fetch()
    }

    @objc private func clearApiKey() {
        let alert = NSAlert()
        alert.messageText = "Delete API key from Keychain?"
        alert.informativeText = "The balance will stop refreshing until you set it again."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        keychainDelete()
        apiKey = nil
        balance = nil
        lastUpdated = nil
        keySource = "not set"
        errorMessage = "API key not set (use the menu to set it)"
        updateUI()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: Fetch & UI updates

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    private func fetch() {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            errorMessage = "API key not set (use the menu to set it)"
            updateUI()
            return
        }
        guard !isFetching else { return }
        isFetching = true
        updateUI() // show loading state

        fetchBalance(apiKey: apiKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false
                switch result {
                case .success(let balance):
                    self.balance = balance
                    self.errorMessage = nil
                    self.lastUpdated = Date()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.updateUI()
            }
        }
    }

    private func updateUI() {
        guard let button = statusItem.button else { return }

        if let apiKey = apiKey, !apiKey.isEmpty, let balance = balance {
            if let primary = primaryInfo(balance.balance_infos) {
                let symbol = currencySymbols[primary.currency] ?? ""
                button.title = "\(symbol)\(primary.total_balance)"
                button.toolTip = "DeepSeek API balance · \(balance.balance_infos.count) currency accounts"
            } else {
                button.title = "¥ —"
            }
        } else if let apiKey = apiKey, !apiKey.isEmpty, isFetching {
            button.title = "⋯"
        } else if apiKey == nil || apiKey!.isEmpty {
            button.title = "⚠ No Key"
            button.toolTip = "DeepSeek API key not set"
        } else {
            button.title = "⚠ Error"
        }
        rebuildDetailMenu()
    }

    private func rebuildDetailMenu() {
        detailMenu.removeAllItems()

        if let balance = balance {
            if balance.balance_infos.isEmpty {
                detailMenu.addItem(withTitle: "No balance info", action: nil, keyEquivalent: "")
            }
            for info in balance.balance_infos {
                detailMenu.addItem(withTitle: "\(info.currency) Total: \(info.total_balance)",
                                   action: nil, keyEquivalent: "")
                detailMenu.addItem(withTitle: "    Granted: \(info.granted_balance)",
                                   action: nil, keyEquivalent: "")
                detailMenu.addItem(withTitle: "    Topped up: \(info.topped_up_balance)",
                                   action: nil, keyEquivalent: "")
            }
            if !balance.is_available {
                detailMenu.addItem(.separator())
                detailMenu.addItem(withTitle: "⚠ Account unavailable", action: nil, keyEquivalent: "")
            }
        }

        if let apiKey = apiKey, !apiKey.isEmpty {
            let masked = apiKey.count > 8
                ? String(apiKey.prefix(6)) + "…" + String(apiKey.suffix(4))
                : apiKey
            detailMenu.addItem(.separator())
            detailMenu.addItem(withTitle: "API Key: \(masked)", action: nil, keyEquivalent: "")
            detailMenu.addItem(withTitle: "Key source: \(keySource)", action: nil, keyEquivalent: "")
        }
        if let errorMessage = errorMessage {
            detailMenu.addItem(withTitle: "Error: \(errorMessage)", action: nil, keyEquivalent: "")
        }
        if let lastUpdated = lastUpdated {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            detailMenu.addItem(.separator())
            detailMenu.addItem(withTitle: "Last update: \(f.string(from: lastUpdated))",
                               action: nil, keyEquivalent: "")
        }
    }
}

// MARK: - Entry point

/// CLI self-check: fetch the balance once and print it, no GUI.
private func runCheckMode() {
    guard let key = loadApiKey() else {
        FileHandle.standardError.write(
            Data("No API key found (set it from the menu bar, or set DEEPSEEK_API_KEY)\n".utf8))
        exit(1)
    }
    print("Key source: \(keySource)")

    let semaphore = DispatchSemaphore(value: 0)
    fetchBalance(apiKey: key) { result in
        switch result {
        case .success(let balance):
            if let encoded = try? JSONEncoder().encode(balance),
               let pretty = String(data: encoded, encoding: .utf8) {
                print(pretty)
            }
        case .failure(let error):
            FileHandle.standardError.write(Data("Request failed: \(error.localizedDescription)\n".utf8))
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 15)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

if CommandLine.arguments.contains("--check") {
    runCheckMode()
} else {
    app.run()
}
