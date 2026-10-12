import AppKit

enum MainMenu {
    static func build(appName: String, recentMenu: NSMenu) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(appName: appName)))
        main.addItem(submenu(fileMenu(recentMenu: recentMenu)))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu(appName: String) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentMenu: NSMenu) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(submenu(recentMenu))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(.separator())
        menu.addItem(item("Export…", #selector(GraphWindowController.exportGraph(_:)), "e", modifiers: [.command, .shift]))
        menu.addItem(item("Show in Finder", #selector(GraphWindowController.revealSourceInFinder(_:)), "r", modifiers: [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Reload", #selector(GraphWindowController.reloadGraph(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", #selector(GraphWindowController.zoomToActualSize(_:)), "0"))
        menu.addItem(item("Zoom to Fit", #selector(GraphWindowController.zoomToFit(_:)), "9"))
        menu.addItem(item("Zoom In", #selector(GraphWindowController.zoomInGraph(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(GraphWindowController.zoomOutGraph(_:)), "-"))
        menu.addItem(.separator())

        let engines = NSMenu(title: "Layout Engine")
        for (index, engine) in LayoutEngine.allCases.enumerated() {
            let entry = item(engine.title, #selector(GraphWindowController.selectLayoutEngine(_:)))
            entry.representedObject = engine.rawValue
            engines.addItem(entry)
            if index == 0 {
                engines.addItem(.separator())
            }
        }
        menu.addItem(submenu(engines))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
