//
//  ContentView.swift
//  Claudify
//
//  Created by Sh on 01/08/2026.
//

import SwiftUI

struct ContentView: View {
    var monitor: UsageMonitor
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let error = monitor.errorText, !monitor.hasData {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if monitor.hasData {
                windowRow("Session", subtitle: "5-hour", window: monitor.session)
                windowRow("Weekly", subtitle: "7-day", window: monitor.weekly)
            } else {
                Text("Loading Claude usage…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 260)
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image("ClaudeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.claudeOrange)
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if let plan = monitor.plan {
                Text(plan)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.claudeOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.claudeOrange.opacity(0.15), in: Capsule())
                    .help("Your Claude subscription plan")
            }
        }
    }

    private func windowRow(_ title: String, subtitle: String, window: UsageWindow?) -> some View {
        let percent = window?.percent ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(percent))
                    .contentTransition(.numericText())
            }
            ProgressView(value: min(percent, 100), total: 100)
                .tint(color(percent))
            Text("Resets in \(resetText(window?.resetsAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                monitor.refresh()
            } label: {
                if monitor.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(monitor.isRefreshing)
            .font(.caption)

            Spacer()

            if let version = monitor.claudeVersion {
                Text("Claude Code \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    // MARK: Helpers

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "now" }
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func color(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }
}

extension Color {
    /// Claude's brand orange (#D97757).
    static let claudeOrange = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
}
