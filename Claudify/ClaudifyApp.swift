//
//  ClaudifyApp.swift
//  Claudify
//
//  Created by Sh on 01/08/2026.
//

import SwiftUI

@main
struct ClaudifyApp: App {
    @State private var monitor = UsageMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
                .onAppear { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The compact label shown in the system menu bar: the 5-hour session usage %.
struct MenuBarLabel: View {
    var monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image("ClaudifyLogo")
            if let session = monitor.session {
                Text("\(Int(session.percent.rounded()))%")
            }
        }
    }
}
