//
//  AppScrubberTouchBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.

import Cocoa

class AppScrubberTouchBarItem: NSCustomTouchBarItem, NSScrubberDelegate, NSScrubberDataSource {
    
    private var scrubber: NSScrubber!
    
    private let hf: HapticFeedback = HapticFeedback()
    
    private var timer: Timer!
    private var ticks: Int = 0
    private let minTicks: Int = 5
    private let maxTicks: Int = 20
    private var lastSelected: Int = 0

    private var persistentAppIdentifiers: [String] = []
    private var runningAppsIdentifiers: [String] = []
    
    private var frontmostApplicationIdentifier: String? {
        get {
            guard let frontmostId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
            return frontmostId
        }
    }
    
    private var applications: [DockItem] = []
    
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        
        scrubber = NSScrubber();
        scrubber.delegate = self
        scrubber.dataSource = self
        scrubber.mode = .free // .fixed
        let layout = NSScrubberFlowLayout();
        layout.itemSize = NSSize(width: 36, height: 32)
        layout.itemSpacing = 2
        scrubber.scrubberLayout = layout
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.showsAdditionalContentIndicators = true

        view = scrubber
        
        scrubber.register(NSScrubberImageItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"))
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        if let persistent = UserDefaults.standard.stringArray(forKey: "com.toxblh.mtmr.dock.persistent") {
            self.persistentAppIdentifiers = persistent
        }
        
        updateRunningApplication()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func activeApplicationChanged(n: Notification) {
        updateRunningApplication()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        updateRunningApplication()
    }
    
    func updateRunningApplication() {
        let newApplications = launchedApplications()
        
        let index = newApplications.index {
            $0.bundleIdentifier == frontmostApplicationIdentifier
        }

        applications = newApplications
        applications += getDockPersistentAppsList()
        scrubber.reloadData()
        
        scrubber.selectedIndex = index ?? 0
    }
    
    public func numberOfItems(for scrubber: NSScrubber) -> Int {
        return applications.count
    }
    
    public func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let item = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"), owner: self) as? NSScrubberImageItemView ?? NSScrubberImageItemView()
        item.imageView.imageScaling = .scaleProportionallyDown
        
        let app = applications[index]
        
        if let icon = app.icon {
            item.image = icon
            item.image.size = NSSize(width: 26, height: 26)
        }

        item.removeFromSuperview()
    
        let dotView = NSView(frame: .zero)
        dotView.wantsLayer = true
        if self.runningAppsIdentifiers.contains(app.bundleIdentifier!) {
            dotView.layer?.backgroundColor = NSColor.white.cgColor
        } else {
            dotView.layer?.backgroundColor = NSColor.black.cgColor
        }
        dotView.layer?.cornerRadius = 1.5
        dotView.setFrameOrigin(NSPoint(x: 17, y: 1))
        dotView.frame.size = NSSize(width: 3, height: 3)
        item.addSubview(dotView)

        return item
    }
    
    public func didBeginInteracting(with scrubber: NSScrubber) {
        stopTimer()
        self.ticks = 0
        self.timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkTimer), userInfo: nil, repeats: true)
    }
    
    @objc private func checkTimer() {
        self.ticks += 1
        
        if (self.ticks == minTicks) {
            hf.tap(strong: 2)
        }
        
        if (self.ticks > maxTicks) {
            stopTimer()
            hf.tap(strong: 6)
        }
    }
    
    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
        self.lastSelected = 0
    }
    
    public func didCancelInteracting(with scrubber: NSScrubber) {
        stopTimer()
    }
    
    public func didFinishInteracting(with scrubber: NSScrubber) {
        stopTimer()
        
        if (ticks == 0) {
            return
        }
        
        if (self.ticks >= minTicks && scrubber.selectedIndex > 0) {
            self.longPress(selected: scrubber.selectedIndex)
            return
        }
        
        let bundleIdentifier = applications[scrubber.selectedIndex].bundleIdentifier
        if bundleIdentifier!.contains("file://") {
            NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        } else {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
            hf.tap(strong: 6)
        }
        updateRunningApplication()
        
        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }
    
    private func longPress(selected: Int) {
        let bundleIdentifier = applications[selected].bundleIdentifier
        
        if (self.ticks > maxTicks) {
            if let processIdentifier = applications[selected].pid {
                if !(NSRunningApplication(processIdentifier: processIdentifier)?.terminate())! {
                    NSRunningApplication(processIdentifier: processIdentifier)?.forceTerminate()
                }
            }
        } else {
            hf.tap(strong: 6)
            if let index = self.persistentAppIdentifiers.index(of: bundleIdentifier!) {
                self.persistentAppIdentifiers.remove(at: index)
            } else {
                self.persistentAppIdentifiers.append(bundleIdentifier!)
            }
            
            UserDefaults.standard.set(self.persistentAppIdentifiers, forKey: "com.toxblh.mtmr.dock.persistent")
            UserDefaults.standard.synchronize()
        }
        self.ticks = 0
        updateRunningApplication()
    }

    private func launchedApplications() -> [DockItem] {
        self.runningAppsIdentifiers = []
        var returnable: [DockItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == NSApplication.ActivationPolicy.regular else { continue }
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            
            self.runningAppsIdentifiers.append(bundleIdentifier)
            
            let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: getIcon(forBundleIdentifier: bundleIdentifier), pid: app.processIdentifier)
            returnable.append(dockItem)
        }
        return returnable
    }

    public func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil, orType type: String? = nil) -> NSImage {
        if bundleIdentifier != nil {
            if let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier!) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }

        if path != nil {
            return NSWorkspace.shared.icon(forFile: path!)
        }

        let genericIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns")
        return genericIcon ?? NSImage(size: .zero)
    }
    

    public func getDockPersistentAppsList() -> [DockItem] {
        var returnable: [DockItem] = []
        
        for bundleIdentifier in persistentAppIdentifiers {
            if !self.runningAppsIdentifiers.contains(bundleIdentifier) {
                let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: getIcon(forBundleIdentifier: bundleIdentifier))
                returnable.append(dockItem)
            }
        }

        return returnable
    }
}

public class DockItem: NSObject {
    var bundleIdentifier: String!, icon: NSImage!, pid: Int32!

    convenience init(bundleIdentifier: String, icon: NSImage, pid: Int32? = nil) {
        self.init()
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.pid = pid
    }
}
