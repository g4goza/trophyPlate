import SwiftUI
import AppKit
import TrophyPlateCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true {
            let alert = NSAlert(); alert.messageText = "Stop the active job before quitting."; alert.informativeText = "Use Stop in TrophyPlate, and verify the machine has stopped."; alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}
@main
struct TrophyPlateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("TrophyPlate") {
            EditorView(model:model)
                .frame(minWidth:1000,minHeight:760)
                .onAppear { delegate.model = model; model.refreshPorts() }
        }
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("Open Design…") { model.open() }.keyboardShortcut("o").disabled(model.busy)
                Button("Save Design…") { model.save() }.keyboardShortcut("s").disabled(model.busy)
            }
        }
    }
}
struct EditorView: View {
    @State private var confirmOutline = false
    @FocusState private var textFocus: String?
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading) {
                    Text("TrophyPlate").font(.title.bold())
                    Text("80 × 40 mm • Genmitsu Kiosk").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.simulation ? "SIMULATION":"USB LASER").font(.caption.bold()).padding(8).background(model.simulation ? Color.blue.opacity(0.15):Color.orange.opacity(0.15),in:Capsule())
                Button("Open…") { model.open() }.disabled(model.busy)
                Button("Save…") { model.save() }.disabled(model.busy)
            }.padding()
            Divider()
            HSplitView {
                ScrollView {
                    Form {
                        Section("Plate text") {
                            TextField("Presenter",text:textBinding(\.presenter)).focused($textFocus,equals:"presenter")
                            TextField("Talk title",text:textBinding(\.title1)).focused($textFocus,equals:"title1")
                            TextField("Second title line (optional)",text:textBinding(\.title2)).focused($textFocus,equals:"title2")
                            TextField("Talk date",text:textBinding(\.date)).focused($textFocus,equals:"date")
                        }
                        Section("Typography") {
                            Picker("Font",selection:$model.design.fontName) {
                                ForEach(Array(Set(NSFontManager.shared.availableFontFamilies+[model.design.fontName])).sorted(),id:\.self) { Text($0).tag($0) }
                            }
                            numeric("Name size (pt)",value:$model.design.nameSize)
                            numeric("Title size (pt)",value:$model.design.titleSize)
                            numeric("Date size (pt)",value:$model.design.dateSize)
                            numeric("Line gap (mm)",value:$model.design.lineSpacing)
                            numeric("Margins (mm)",value:$model.design.margin)
                        }
                        Section(model.design.usesOwnerTestedSettings ? "Engraving — your tested plate settings":"Engraving — custom settings") {
                            numeric("Power (%)",value:$model.design.powerPercent)
                            numeric("Speed (mm/min)",value:$model.design.speed)
                            Stepper("Passes: \(model.design.passes)",value:$model.design.passes,in:1...10)
                            numeric("Scan interval (mm)",value:$model.design.scanInterval)
                            Text(model.design.usesOwnerTestedSettings ? "40% at 2,000 mm/min, one pass, 0.10 mm spacing worked on your coated-metal plates. Test again for a different coating or focus setup.":"Custom settings: test on a scrap plate to establish clean coating removal.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Board outline — separate test settings") {
                            numeric("Outline power (%)",value:$model.design.outline.powerPercent)
                            numeric("Outline speed (mm/min)",value:$model.design.outline.speed)
                            Text("One pass around the 80 × 40 mm plate boundary. Test on your laser-suitable backing board; remove the metal plate first.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Placement in 100 × 100 mm workspace") {
                            numeric("Plate left X (mm)",value:$model.design.offsetX)
                            numeric("Plate bottom Y (mm)",value:$model.design.offsetY)
                            Text("Coordinates must be verified on your machine. No automatic homing.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.formStyle(.grouped).disabled(model.busy)
                }.frame(minWidth:330,idealWidth:370,maxWidth:430)
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text("Plate preview").font(.headline)
                        Spacer()
                        Toggle("Paths",isOn:$model.showPaths).toggleStyle(.switch)
                        Toggle("Plate outline",isOn:$model.showOutline).toggleStyle(.switch)
                    }
                    PlatePreview(design:model.design,job:model.job,showPaths:model.showPaths,showOutline:model.showOutline).frame(minHeight:200,maxHeight:.infinity)
                    if let error = model.layoutError { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                    HStack {
                        Button(model.generating ? "Generating…":"Generate Preview") { model.generate() }.disabled(model.previewBlockReason != nil).help(model.previewBlockReason ?? "Regenerate engraving paths")
                        if let job = model.job {
                            Text("\(job.strokes.count) strokes • about \(Int(ceil(job.estimatedSeconds/60))) min").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let reason = model.previewBlockReason, model.layoutError == nil { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    connection
                    HStack {
                        Text("Laser-off check:").font(.caption)
                        Button("X +2 mm") { model.start(.testX) }.disabled(!model.canTestMovement)
                        Button("X +10 mm") { model.start(.testX10) }.disabled(!model.canTestMovement)
                        Button("Y +2 mm") { model.start(.testY) }.disabled(!model.canTestMovement)
                    }
                    Text("Clear the selected distance before each check. X+ should move right; Y+ should move toward the back.").font(.caption).foregroundStyle(.secondary)
                    if !model.simulation {
                        Toggle("I verified the coordinate origin, axis directions and plate placement.",isOn:$model.originConfirmed)
                        Toggle("I have tested these settings on this plate material.",isOn:$model.materialConfirmed)
                        Text("Software Stop is best effort. Stay at the machine and use physical controls if needed.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Frame — Laser Off") { model.start(.frame) }.disabled(!model.canFrame)
                        Button("Mark Plate Outline") {
                            model.showOutline = true
                            if model.simulation { model.start(.markOutline) } else { confirmOutline = true }
                        }.disabled(!model.canMarkOutline)
                    }
                    .confirmationDialog("Mark the 80 × 40 mm outline on the backing board?",isPresented:$confirmOutline,titleVisibility:.visible) {
                        Button("Mark Board — Laser On") { model.start(.markOutline) }
                        Button("Cancel",role:.cancel) {}
                    } message: {
                        Text("Remove the metal plate first. The laser will fire at \(model.design.outline.powerPercent.formatted())% and \(model.design.outline.speed.formatted()) mm/min. Use a laser-suitable board and keep it and the coordinate origin fixed afterward.")
                    }
                    HStack {
                        Button(model.simulation ? "Run Simulation":"Engrave Plate") { model.start() }.buttonStyle(.borderedProminent).disabled(!model.canStart)
                        Button(model.phase == .paused ? "Resume":"Pause") { model.pauseOrResume() }.disabled(!model.busy || model.phase == .ready)
                        Button("Stop",role:.destructive) { model.stop() }.disabled(!model.busy)
                    }
                    if let reason = model.engravingBlockReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    if let reason = model.placementBlockReason, reason != model.engravingBlockReason { Text("Frame / outline: " + reason).font(.caption).foregroundStyle(.secondary) }
                    if let error = model.outlineError, error != model.placementError { Text("Board outline: " + error).font(.caption).foregroundStyle(.secondary) }
                    if model.busy {
                        ProgressView(value:Double(model.accepted),total:Double(max(1,model.total)))
                        Text("\(model.accepted)/\(model.total) lines accepted • \(model.phase.rawValue). Accepted lines may still be executing.").font(.caption)
                    }
                    Text(model.message).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    DisclosureGroup("Controller console") {
                        ScrollView { Text(model.console.isEmpty ? "No controller messages yet.":model.console).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(height:100)
                    }
                }.padding().frame(minWidth:580)
            }
        }.onAppear { model.schedulePreview() }
        .onChange(of:textFocus) { previous, _ in
            let fields: [String:WritableKeyPath<PlateDesign,String>] = ["presenter":\.presenter,"title1":\.title1,"title2":\.title2,"date":\.date]
            if let previous, let key = fields[previous] { model.setText(model.design[keyPath:key],for:key,finished:true) }
        }
    }
    private func textBinding(_ key: WritableKeyPath<PlateDesign,String>) -> Binding<String> {
        Binding(get:{ model.design[keyPath:key] },set:{ model.setText($0,for:key) })
    }
    private func numeric(_ label: String,value: Binding<Double>) -> some View {
        TextField(label,value:value,format:.number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder)
    }
    private var connection: some View {
        VStack(alignment:.leading,spacing:8) {
            Divider()
            HStack {
                Picker("Connection",selection:$model.simulation) {
                    Text("Simulator").tag(true); Text("USB").tag(false)
                }.frame(width:210).disabled(model.connected || model.busy || model.connecting || model.generating)
                if !model.simulation {
                    Picker("Port",selection:$model.selectedPort) {
                        if model.ports.isEmpty { Text("No USB port").tag("") }
                        ForEach(model.ports,id:\.self) { Text($0).tag($0) }
                    }.disabled(model.connected || model.connecting)
                    Button { model.refreshPorts() } label: { Image(systemName:"arrow.clockwise") }.disabled(model.connected || model.connecting)
                }
                Spacer()
                Button(model.connecting ? "Connecting…":(model.connected ? "Disconnect":"Connect")) {
                    if model.connected { model.disconnect() } else { model.connect() }
                }.disabled(model.busy || model.connecting || model.generating || (!model.connected && !model.simulation && model.selectedPort.isEmpty))
            }
            if let info = model.info { Text("\(info.identity) • S max \(Int(info.powerMaximum ?? 0)) • \(info.status)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct PlatePreview: View {
    let design: PlateDesign
    let job: EngravingJob?
    let showPaths: Bool
    let showOutline: Bool
    var body: some View {
        Canvas { context,size in
            let scale = min((size.width-48)/80,(size.height-48)/40)
            guard scale > 0 else { return }
            context.translateBy(x:(size.width-80*scale)/2,y:(size.height+40*scale)/2)
            context.scaleBy(x:scale,y:-scale)
            let plate = CGRect(x:0,y:0,width:80,height:40)
            context.fill(Path(roundedRect:plate,cornerRadius:0.8),with:.color(Color(red:0.16,green:0.19,blue:0.23)))
            context.stroke(Path(roundedRect:plate,cornerRadius:0.8),with:.color(.gray),lineWidth:0.15)
            if design.margin.isFinite && design.margin > 0 && design.margin < 20 {
                context.stroke(Path(CGRect(x:design.margin,y:design.margin,width:80-2*design.margin,height:40-2*design.margin)),with:.color(.white.opacity(0.2)),style:StrokeStyle(lineWidth:0.1,dash:[0.5,0.5]))
            }
            if showOutline {
                context.stroke(Path(plate),with:.color(.orange),lineWidth:0.15)
            }
            if showPaths, let job {
                var path = Path()
                for s in job.strokes.prefix(job.strokes.count/max(1,design.passes)) {
                    path.move(to:CGPoint(x:s.start.x-design.offsetX,y:s.start.y-design.offsetY))
                    path.addLine(to:CGPoint(x:s.end.x-design.offsetX,y:s.end.y-design.offsetY))
                }
                context.stroke(path,with:.color(.orange),lineWidth:design.scanInterval*0.85)
            } else if let layout = try? TextLayout.make(design) {
                for line in layout.lines { context.fill(Path(line.path),with:.color(Color(red:0.94,green:0.83,blue:0.53))) }
            }
        }.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
        .accessibilityLabel("80 by 40 millimeter plate preview")
    }
}
