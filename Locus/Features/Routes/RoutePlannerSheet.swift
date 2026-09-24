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
    var onAddSpeedWaypointAtPin: () -> Void
    var onAddPauseWaypointAtPin: () -> Void
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
                    Text("Drop a waypoint before a stop sign, light, or highway merge. Speed waypoints control how fast the segment leading into them moves. Pause waypoints stop on arrival for the set duration.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        onAddSpeedWaypointAtPin()
                    } label: {
                        Label("Add speed waypoint", systemImage: "speedometer")
                    }
                    .disabled(routePath.count < 2)

                    Button {
                        onAddPauseWaypointAtPin()
                    } label: {
                        Label("Add pause waypoint", systemImage: "pause.circle")
                    }
                    .disabled(routePath.count < 2)

                    Button(role: .destructive) {
                        onResetWaypoints()
                    } label: {
                        Label("Reset waypoint settings", systemImage: "arrow.counterclockwise")
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
                                        Text(isStart
                                             ? "Route anchor"
                                             : (waypoint.isPause
                                                ? "Pause: \(String(format: "%.1f", waypoint.pauseSeconds ?? 0))s"
                                                : waypointLabel(waypoint)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    if !isStart {
                                        Text(waypoint.isPause
                                             ? "PAUSE"
                                             : (waypoints[index].speedMPH == nil
                                                ? "AUTO"
                                                : "\(String(format: "%.0f", waypoints[index].speedMPH ?? 0))mph"))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    }
                                }

                                Toggle("Pause on arrival", isOn: Binding(
                                    get: { waypoints[index].isPause },
                                    set: { newValue in
                                        if isStart { return }
                                        if newValue {
                                            waypoints[index].pauseSeconds = waypoints[index].pauseSeconds ?? 3.0
                                            waypoints[index].speedMPH = nil
                                        } else {
                                            waypoints[index].pauseSeconds = nil
                                            if waypoints[index].speedMPH == nil {
                                                waypoints[index].speedMPH = session.travelMode.baseSpeed * 2.23693629
                                            }
                                        }
                                    }
                                ))
                                .disabled(isStart)

                                if waypoints[index].isPause {
                                    Stepper(
                                        value: Binding(
                                            get: { waypoints[index].pauseSeconds ?? 3.0 },
                                            set: { waypoints[index].pauseSeconds = $0 }
                                        ),
                                        in: 0.5...30,
                                        step: 0.5
                                    ) {
                                        Text("Duration: \(String(format: "%.1f", waypoints[index].pauseSeconds ?? 0))s")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Slider(
                                        value: Binding(
                                            get: { waypoints[index].speedMPH ?? 0 },
                                            set: { newValue in
                                                waypoints[index].speedMPH = newValue <= 0 ? nil : newValue
                                            }
                                        ),
                                        in: 0...70,
                                        step: 0.5
                                    )
                                    .disabled(isStart)

                                    let speedText = waypoints[index].speedMPH == nil
                                        ? "AUTO"
                                        : String(format: "%.1f", waypoints[index].speedMPH ?? 0)
                                    Text("Speed: \(speedText) mph")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

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
