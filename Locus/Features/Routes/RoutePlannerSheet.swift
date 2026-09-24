import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    @Binding var waypoints: [RouteWaypoint]
    let routePath: [CLLocationCoordinate2D]
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void
    var onAddWaypointAtPin: () -> Void
    var onResetWaypoints: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Road route") {
                    Button("Use current pin / spoof as start") {
                        start = session.simulated ?? session.pin
                    }
                    Button("Use current pin as end") {
                        end = session.pin
                    }
                    LabeledContent("Start") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("End") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Build walk/drive route on roads", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("Waypoints") {
                    Text("Drop a waypoint before a stop sign, light, or highway merge. The speed on each waypoint controls the segment leading into it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        onAddWaypointAtPin()
                    } label: {
                        Label("Add waypoint at pin", systemImage: "mappin.and.ellipse")
                    }
                    .disabled(routePath.count < 2)

                    Button(role: .destructive) {
                        onResetWaypoints()
                    } label: {
                        Label("Reset waypoint speeds", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(routePath.count < 2)

                    if waypoints.isEmpty {
                        Text("No waypoints yet. Start with the route endpoints, then add extras where you want to slow down or speed up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(waypoints.indices, id: \.self) { index in
                            let waypoint = waypoints[index]
                            let isStart = index == 0
                            let isEnd = index == waypoints.count - 1

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isStart ? "Start" : isEnd ? "Destination" : "Waypoint \(index + 1)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(isStart ? "Route anchor" : waypointLabel(waypoint))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.2fx", waypoint.speedMultiplier))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }

                                Slider(
                                    value: Binding(
                                        get: { waypoints[index].speedMultiplier },
                                        set: { waypoints[index].speedMultiplier = $0 }
                                    ),
                                    in: 0.4...2.5,
                                    step: 0.05
                                )
                                .disabled(isStart)

                                if !isStart && !isEnd {
                                    Button(role: .destructive) {
                                        waypoints.remove(at: index)
                                    } label: {
                                        Label("Remove waypoint", systemImage: "trash")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Play / draw / GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("Use drawn path from map", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("Follow route", systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("Routes follow Apple Maps roads/footpaths for the selected travel mode. Waypoints let you slow down or speed up specific route segments.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    private func waypointLabel(_ waypoint: RouteWaypoint) -> String {
        guard routePath.indices.contains(waypoint.pathIndex) else {
            return "Snapped point"
        }
        let coordinate = routePath[waypoint.pathIndex]
        let progress = routePath.count > 1
            ? Int((Double(waypoint.pathIndex) / Double(routePath.count - 1)) * 100)
            : 0
        return String(format: "%d%% • %.5f, %.5f", progress, coordinate.latitude, coordinate.longitude)
    }
}
