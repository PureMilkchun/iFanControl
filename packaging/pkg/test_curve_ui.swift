// Compiled next to the actual curve controller in an isolated module; no production config writes.
@MainActor extension FanCurvePresetWindowController {
    public static func runUIRegression() throws {
        let precise = [FanPoint(temperature:20,rpm:600),FanPoint(temperature:41.123456789,rpm:700),FanPoint(temperature:62.654321,rpm:1400),FanPoint(temperature:84.8,rpm:2800),FanPoint(temperature:100,rpm:3500)]
        let configDir = UIRegressionPaths.config
        let file = configDir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at:configDir,withIntermediateDirectories:true)
        let seed = Config(version:"1.0",curve:precise,mode:"manual",autoStart:false,maxRPM:4900,manualRPM:2345,manualRPMControlMode:"stepped",manualRPMStep:500,safetyFloorRPM:3600,temperatureSourceMode:"fixed",selectedTemperatureSensorKey:"Tp01",curvePresetNames:["A","B","C"],curvePresets:[precise,precise,precise],activeCurvePreset:1)
        try JSONEncoder().encode(seed).write(to:file,options:.atomic)
        let controller = FanCurvePresetWindowController(fanCurve:precise,maxRPM:4900,presetNames:["A","B","C"],presets:[precise,precise,precise],activePresetIndex:1)
        controller.window!.setFrame(NSRect(x:0,y:0,width:900,height:500),display:false)
        controller.window!.contentView!.layoutSubtreeIfNeeded()
        let root = controller.window!.contentView!.subviews.first!
        precondition(root.frame.minY >= 0 && root.frame.maxY <= controller.window!.contentView!.bounds.height, "AppKit minimum layout must keep the editor inside the window")
        func read() throws -> Config { try JSONDecoder().decode(Config.self,from:Data(contentsOf:file)) }
        precondition(controller.windowShouldClose(controller.window!))
        var stored = try read()
        precondition(stored.curve[1].temperature == precise[1].temperature,"Untouched display rounding must not alter persisted temperatures")
        precondition(stored.mode==seed.mode && stored.autoStart==seed.autoStart && stored.manualRPM==seed.manualRPM && stored.manualRPMControlMode==seed.manualRPMControlMode && stored.manualRPMStep==seed.manualRPMStep && stored.safetyFloorRPM==seed.safetyFloorRPM && stored.temperatureSourceMode==seed.temperatureSourceMode && stored.selectedTemperatureSensorKey==seed.selectedTemperatureSensorKey)
        let rpm = controller.pointFields[1].rpm
        rpm.stringValue="1234"; controller.pointEdited(rpm)
        precondition(controller.fanCurveView.fanCurve[1].temperature == precise[1].temperature,"RPM-only edit must retain temperature precision")
        let temp = controller.pointFields[1].temperature
        temp.stringValue="99";controller.pointEdited(temp)
        precondition(controller.fanCurveView.fanCurve[1].temperature == precise[2].temperature-1)
        rpm.stringValue="99999";controller.pointEdited(rpm)
        precondition(controller.fanCurveView.fanCurve[1].rpm==4900)
        rpm.stringValue="-1";controller.pointEdited(rpm)
        precondition(controller.fanCurveView.fanCurve[1].rpm==0)
        let originalBytes=try Data(contentsOf:file)
        rpm.stringValue="invalid";controller.pointEdited(rpm)
        precondition(!controller.windowShouldClose(controller.window!))
        precondition(!controller.pointStack.isHidden && controller.showNumericEditor, "An invalid hidden editor must be revealed when closing is vetoed")
        let afterInvalid = try Data(contentsOf:file)
        precondition(afterInvalid==originalBytes)
        controller.resetCurve()
        precondition(!controller.hasInvalidPointInput)
        controller.switchPreset(to:2)
        precondition(controller.activePresetIndex==2)
        precondition(controller.windowShouldClose(controller.window!))
        stored=try read();precondition(stored.activeCurvePreset==2 && stored.curvePresets?.count==3)
        let backup=configDir.appendingPathComponent("config-backup.json")
        try FileManager.default.moveItem(at:file,to:backup)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        precondition(!controller.windowShouldClose(controller.window!),"Write failure must veto window closing")
        precondition(NativeUITestAlert.lastMessage == "保存未完成" || NativeUITestAlert.lastMessage == "Save Not Completed")
        try FileManager.default.removeItem(at:file)
        try FileManager.default.moveItem(at:backup,to:file)
        precondition(controller.windowShouldClose(controller.window!))
        print("PASS: curve precision, RPM-only edits, ordered temperatures/RPM bounds, invalid-input retention, preset reset/switch, config-field preservation and save-failure close veto")
    }
}
