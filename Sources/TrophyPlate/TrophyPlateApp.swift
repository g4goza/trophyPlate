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
                            TextField("Presenter",text:$model.design.presenter)
                            TextField("Talk title",text:$model.design.title1)
                            TextField("Second title line (optional)",text:$model.design.title2)
                            TextField("Talk date",text:$model.design.date)
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
                        Section("Engraving — settings untested") {
                            numeric("Power (%)",value:$model.design.powerPercent)
                            numeric("Speed (mm/min)",value:$model.design.speed)
                            Stepper("Passes: \(model.design.passes)",value:$model.design.passes,in:1...10)
                            numeric("Scan interval (mm)",value:$model.design.scanInterval)
                            Text("Test on a scrap plate to establish clean coating removal. These are not calibrated material settings.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Placement in 100 × 100 mm workspace") {
                            numeric("Plate left X (mm)",value:$model.design.offsetX)
                            numeric("Plate bottom Y (mm)",value:$model.design.offsetY)
                            Text("Coordinates must be verified on your machine. No automatic homing.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.formStyle(.grouped).disabled(model.busy || model.generating)
                }.frame(minWidth:330,idealWidth:370,maxWidth:430)
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text("Plate preview").font(.headline)
                        Spacer()
                        Toggle("Engraving paths",isOn:$model.showPaths).toggleStyle(.switch)
                    }
                    PlatePreview(design:model.design,job:model.job,showPaths:model.showPaths).frame(minHeight:200,maxHeight:.infinity)
                    if let error = model.layoutError { Label(error,systemImage:"exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                    HStack {
                        Button(model.generating ? "Generating…":"Generate Preview") { model.generate() }.disabled(model.busy || model.connecting || model.generating || model.layoutError != nil)
                        if let job = model.job {
                            Text("\(job.strokes.count) strokes • about \(Int(ceil(job.estimatedSeconds/60))) min").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    connection
                    if !model.simulation {
                        Toggle("I verified the coordinate origin, axis directions and plate placement.",isOn:$model.originConfirmed)
                        Toggle("I will test these power/speed settings on scrap material.",isOn:$model.materialConfirmed)
                        Text("Software Stop is best effort. Stay at the machine and use physical controls if needed.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Frame — Laser Off") { model.start(frame:true) }.disabled(!model.canFrame)
                        Button(model.simulation ? "Run Simulation":"Engrave Plate") { model.start() }.buttonStyle(.borderedProminent).disabled(!model.canStart)
                        Button(model.phase == .paused ? "Resume":"Pause") { model.pauseOrResume() }.disabled(!model.busy || model.phase == .ready)
                        Button("Stop",role:.destructive) { model.stop() }.disabled(!model.busy)
                    }
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
        }
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
                }.disabled(model.busy || model.connecting || model.generating || (!model.simulation && model.selectedPort.isEmpty))
            }
            if let info = model.info { Text("\(info.identity) • S max \(Int(info.powerMaximum ?? 0)) • \(info.status)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct PlatePreview: View {
    let design: PlateDesign
    let job: EngravingJob?
    let showPaths: Bool
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
