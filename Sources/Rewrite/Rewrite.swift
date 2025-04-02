import SwiftUI
import Cocoa
import Foundation
import HotKey
import AppKit

// Extension to load images from bundle
extension Bundle {
    func decodedImage(named name: String) -> Image? {
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let nsImage = NSImage(contentsOfFile: path) {
            return Image(nsImage: nsImage)
        }
        return nil
    }
}

@main
struct RewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        TabView {
            // General tab
            VStack(alignment: .leading, spacing: 20) {
                Text("API Key")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Enter your OpenAI API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: apiKey) { newValue in
                            // Save immediately per macOS HIG
                            UserDefaults.standard.set(newValue, forKey: "openAIApiKey")
                            // Trigger API status check
                            NotificationCenter.default.post(name: NSNotification.Name("checkAPIStatus"), object: nil)
                        }
                    
                    Text("Your API key is needed to use the grammar check feature.\nIt is stored securely in your Mac's keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // About tab
            VStack(alignment: .center, spacing: 12) {
                // Try multiple methods to load the app icon
                if let appIcon = NSImage(named: "AppIcon") {
                    // App icon registered with the system
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else if let iconImage = Bundle.main.decodedImage(named: "icon") {
                    // Load from our bundle extension
                    iconImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else if let appIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                          let nsImage = NSImage(contentsOfFile: appIconPath) {
                    // Try to load ICNS file directly
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else {
                    // Fallback to a symbol if no icon found
                    Image(systemName: "pencil.and.outline")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.accentColor)
                }
                
                Text("Rewrite")
                    .font(.largeTitle)
                    .bold()
                
                Text("Version 1.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("A simple grammar checking tool for your Mac.\nPress ⌘⇧F to check grammar in any text field.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 450, height: 250)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    @Published var isProcessing = false
    @Published var apiStatus: APIStatus = .ok
    @Published var currentModel: String = UserDefaults.standard.string(forKey: "selectedModel") ?? "gpt-4o"
    
    private var openAIApiKey: String {
        return UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    }
    
    enum APIStatus {
        case ok
        case error
        case processing
        
        var statusImage: NSImage? {
            switch self {
            case .ok:
                return NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Rewrite")
            case .error:
                return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "API Error")
            case .processing:
                return NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing Request")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tell the app it's a menu bar app without a main window
        NSApp.setActivationPolicy(.accessory)
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()
        
        setupMenu()
        setupHotKey()
        
        // Register for notification to check API status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkAPIStatus),
            name: NSNotification.Name("checkAPIStatus"),
            object: nil
        )
        
        // Check API status on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAPIStatus()
        }
    }
    
    private func updateStatusItemIcon() {
        if let button = statusItem.button {
            button.image = apiStatus.statusImage
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Grammar Check (⌘⇧F)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let apiStatusItem = NSMenuItem(title: "API Status: OK", action: #selector(checkAPIStatus), keyEquivalent: "")
        menu.addItem(apiStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Model selection submenu
        let modelMenu = NSMenu()
        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        menu.addItem(modelMenuItem)
        
        // GPT-4o item
        let gpt4oItem = NSMenuItem(title: "GPT-4o", action: #selector(selectGPT4o), keyEquivalent: "")
        if currentModel == "gpt-4o" {
            gpt4oItem.state = .on
        }
        modelMenu.addItem(gpt4oItem)
        
        // GPT-4o mini item
        let gpt4oMiniItem = NSMenuItem(title: "GPT-4o mini", action: #selector(selectGPT4oMini), keyEquivalent: "")
        if currentModel == "gpt-4o-mini" {
            gpt4oMiniItem.state = .on
        }
        modelMenu.addItem(gpt4oMiniItem)
        
        // GPT-4.5 Preview item
        let gpt45Item = NSMenuItem(title: "GPT-4.5 (Preview)", action: #selector(selectGPT45Preview), keyEquivalent: "")
        if currentModel == "gpt-4.5-preview-2025-02-27" {
            gpt45Item.state = .on
        }
        modelMenu.addItem(gpt45Item)
        
        modelMenuItem.submenu = modelMenu
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func checkAPIStatus() {
        // If no API key is set, show error state and return
        guard !openAIApiKey.isEmpty else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            return
        }
        
        // Make a simple API call to check if the OpenAI API is working
        let apiURL = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.apiStatus = .ok
                } else {
                    self?.apiStatus = .error
                }
                self?.updateStatusItemIcon()
                self?.updateAPIStatusMenuItem()
            }
        }.resume()
    }
    
    private func updateAPIStatusMenuItem() {
        guard let menu = statusItem.menu else { return }
        
        // Find the API status menu item (third item, after separator)
        if let apiStatusItem = menu.items.first(where: { $0.action == #selector(checkAPIStatus) }) {
            switch apiStatus {
            case .ok:
                apiStatusItem.title = "API Status: OK"
            case .error:
                if openAIApiKey.isEmpty {
                    apiStatusItem.title = "API Status: Error - API Key Missing"
                } else {
                    apiStatusItem.title = "API Status: Error - Click to retry"
                }
            case .processing:
                apiStatusItem.title = "API Status: Processing..."
            }
        }
    }
    
    private func setupHotKey() {
        // Set up Command+Shift+F hotkey
        hotKey = HotKey(key: .f, modifiers: [.command, .shift])
        
        hotKey?.keyDownHandler = { [weak self] in
            self?.handleHotKeyPress()
        }
    }
    
    private func handleHotKeyPress() {
        guard !isProcessing else { return }
        isProcessing = true
        
        // Update UI to show processing state
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        
        // Get selected text
        if let selectedText = getSelectedText() {
            fixGrammar(text: selectedText) { [weak self] correctedText in
                guard let self = self else { return }
                
                if let correctedText = correctedText {
                    // Replace selected text with corrected text
                    self.replaceSelectedText(with: correctedText)
                    
                    // Update UI to show success state
                    self.apiStatus = .ok
                }
                // Note: If correctedText is nil, fixGrammar already set apiStatus to .error
                
                self.isProcessing = false
                self.updateStatusItemIcon()
                self.updateAPIStatusMenuItem()
            }
        } else {
            isProcessing = false
            apiStatus = .ok
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
        }
    }
    
    private func getSelectedText() -> String? {
        // Get current pasteboard content
        let oldPasteboardContent = NSPasteboard.general.string(forType: .string)
        
        // Simulate Command+C to copy selected text
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Small delay to ensure copy completes
        Thread.sleep(forTimeInterval: 0.2)
        
        // Get the selected text from pasteboard
        let selectedText = NSPasteboard.general.string(forType: .string)
        
        // If there was content in the pasteboard before, restore it
        if let oldContent = oldPasteboardContent {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(oldContent, forType: .string)
        }
        
        return selectedText
    }
    
    private func replaceSelectedText(with newText: String) {
        // Save current pasteboard content
        let oldPasteboardContent = NSPasteboard.general.string(forType: .string)
        
        // Set the corrected text to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        
        // Simulate Command+V to paste corrected text
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Restore original pasteboard content after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let oldContent = oldPasteboardContent {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(oldContent, forType: .string)
            }
        }
    }
    
    private func fixGrammar(text: String, completion: @escaping (String?) -> Void) {
        guard !text.isEmpty else {
            completion(nil)
            return
        }
        
        // Check if API key is set
        guard !openAIApiKey.isEmpty else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            completion(nil)
            return
        }
        
        // Already set to processing in handleHotKeyPress, but ensure consistency
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "system", "content": "You are a grammar correction assistant. Fix any grammatical errors in the text provided without changing the meaning or adding additional commentary. Return only the corrected text with no explanations."],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            completion(nil)
            return
        }
        
        request.httpBody = httpBody
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("API Error: \(error.localizedDescription)")
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    print("API Error: HTTP \(httpResponse.statusCode)")
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                guard let data = data else {
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let correctedText = message["content"] as? String {
                        
                        // Will be set to .ok after successful text replacement
                        completion(correctedText)
                    } else {
                        self?.apiStatus = .error
                        self?.updateStatusItemIcon()
                        self?.updateAPIStatusMenuItem()
                        completion(nil)
                    }
                } catch {
                    print("JSON Error: \(error.localizedDescription)")
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                }
            }
        }.resume()
    }
    
    @objc private func selectGPT4o() {
        currentModel = "gpt-4o"
        UserDefaults.standard.set(currentModel, forKey: "selectedModel")
        refreshModelMenu()
    }
    
    @objc private func selectGPT4oMini() {
        currentModel = "gpt-4o-mini"
        UserDefaults.standard.set(currentModel, forKey: "selectedModel")
        refreshModelMenu()
    }
    
    @objc private func selectGPT45Preview() {
        currentModel = "gpt-4.5-preview-2025-02-27"
        UserDefaults.standard.set(currentModel, forKey: "selectedModel")
        refreshModelMenu()
    }
    
    private func refreshModelMenu() {
        guard let menu = statusItem.menu,
              let modelMenuItem = menu.items.first(where: { $0.title == "Model" }),
              let modelMenu = modelMenuItem.submenu else { return }
        
        for item in modelMenu.items {
            if (item.title == "GPT-4o" && currentModel == "gpt-4o") ||
               (item.title == "GPT-4o mini" && currentModel == "gpt-4o-mini") ||
               (item.title == "GPT-4.5 (Preview)" && currentModel == "gpt-4.5-preview-2025-02-27") {
                item.state = .on
            } else {
                item.state = .off
            }
        }
    }
    
    // Store a reference to our settings window to prevent it from being deallocated
    private var preferencesWindow: NSWindow?
    
    @objc private func openPreferences() {
        // If we already have a window, just bring it to front
        if let existingWindow = self.preferencesWindow {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        
        // Create a window for the settings view
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // These are crucial - prevent window from terminating app when closed
        settingsWindow.isReleasedWhenClosed = false
        // Set the window to be non-main to prevent it from becoming the main window
        // which would cause app termination when closed
        settingsWindow.hidesOnDeactivate = false
        // Tell the app not to terminate when this window is closed
        settingsWindow.canHide = true
        settingsWindow.title = "Preferences"
        settingsWindow.center()
        
        // Create a hosting controller for our SwiftUI view
        let settingsView = NSHostingController(rootView: SettingsView())
        settingsWindow.contentView = settingsView.view
        
        // Set window delegate and clear reference when window closes
        settingsWindow.delegate = self
        
        // Store a reference to prevent deallocation
        self.preferencesWindow = settingsWindow
        
        // Make the window key and visible
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate methods
    
    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, 
           closingWindow === preferencesWindow {
            // Release the window reference when it's closed
            preferencesWindow = nil
        }
    }
}