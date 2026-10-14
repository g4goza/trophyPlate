import XCTest
@testable import TrophyPlate
import TrophyPlateCore

final class AppModelTests: XCTestCase {
    @MainActor func testTextEditsPreserveCommissioningButInvalidatePreview() async throws {
        let model = AppModel()
        model.originConfirmed = true; model.materialConfirmed = true
        model.job = try EngravingJob.generate(design:model.design,powerMaximum:1000)
        model.design.presenter = "Another Presenter"
        XCTAssertTrue(model.originConfirmed)
        XCTAssertTrue(model.materialConfirmed)
        XCTAssertNil(model.job)
        model.design.title1 = "Another Talk"
        model.design.date = "October 14, 2026"
        model.design.titleSize = 13
        XCTAssertTrue(model.originConfirmed)
        XCTAssertTrue(model.materialConfirmed)
    }
    @MainActor func testPlacementEditClearsOriginButKeepsMaterialTest() async {
        let model = AppModel()
        model.originConfirmed = true; model.materialConfirmed = true
        model.design.offsetX = 0
        XCTAssertFalse(model.originConfirmed)
        XCTAssertTrue(model.materialConfirmed)
    }
    @MainActor func testPowerEditRequiresMaterialConfirmationAgain() async {
        let model = AppModel()
        model.originConfirmed = true; model.materialConfirmed = true
        model.design.powerPercent = 50
        XCTAssertTrue(model.originConfirmed)
        XCTAssertFalse(model.materialConfirmed)
    }
    @MainActor func testPhysicalJobsRequireMachinePositionAsWellAsOffset() async {
        let model = AppModel()
        model.simulation = false; model.connected = true; model.originConfirmed = true
        var info = ControllerInfo(); info.workOffset = [0,0,0]
        model.info = info
        XCTAssertFalse(model.canFrame)
        XCTAssertFalse(model.canMarkOutline)
        info.machinePosition = [37.3,29.45,0]; model.info = info
        XCTAssertTrue(model.canFrame)
        info.machinePosition = [.nan,0,0]; model.info = info
        XCTAssertFalse(model.canFrame)
    }
}

extension AppModelTests {
    @MainActor func testPositionChangePreventsEveryPhysicalJob() async throws {
        for action in [PlateAction.engrave, .frame, .markOutline] {
            let model = AppModel(makeTransport: { _, _ in SimulatedTransport() })
            model.simulation = false
            model.connect()
            for _ in 0..<300 where model.connecting { try await Task.sleep(nanoseconds:10_000_000) }
            XCTAssertTrue(model.connected)
            // The fresh transport reports zero, simulating a reset after commissioning.
            model.info?.machinePosition = [37.3,29.45,0]
            model.originConfirmed = true; model.materialConfirmed = true
            model.job = try EngravingJob.generate(design:model.design,powerMaximum:1000)
            model.start(action)
            for _ in 0..<300 where model.busy { try await Task.sleep(nanoseconds:10_000_000) }
            XCTAssertEqual(model.phase,.failed,"\(action) must reject a reset position")
            XCTAssertTrue(model.message.contains("position changed"))
            XCTAssertEqual(model.accepted,0)
            XCTAssertFalse(model.connected)
            if model.busy { model.stop() } else { model.disconnect() }
        }
    }
}

extension AppModelTests {
    func testOnlyMatchingSettingsAreLabeledOwnerTested() {
        let design = PlateDesign()
        XCTAssertTrue(design.usesOwnerTestedSettings)
        for change in [
            { (d: inout PlateDesign) in d.powerPercent = 30 },
            { (d: inout PlateDesign) in d.speed = 1000 },
            { (d: inout PlateDesign) in d.passes = 2 },
            { (d: inout PlateDesign) in d.scanInterval = 0.2 }
        ] {
            var custom = design; change(&custom)
            XCTAssertFalse(custom.usesOwnerTestedSettings)
        }
    }
}
