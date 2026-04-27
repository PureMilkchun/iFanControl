//
//  FanCurveView.swift
//  iFanControl
//
//  Created by iFanControl on 2026-03-17.
//  Copyright © 2026 iFanControl. All rights reserved.
//

import AppKit
import Foundation

// 风扇控制点结构
public struct FanPoint: Codable {
    public var temperature: Double
    public var rpm: Int
    
    public init(temperature: Double, rpm: Int) {
        self.temperature = temperature
        self.rpm = rpm
    }
}

// 风扇曲线视图
class FanCurveView: NSView {
    var fanCurve: [FanPoint] = [] {
        didSet {
            setNeedsDisplay(bounds)
        }
    }
    
    var currentTemperature: Double = 0 {
        didSet {
            setNeedsDisplay(bounds)
        }
    }
    
    var maxRPM = 4900 {
        didSet {
            setNeedsDisplay(bounds)
        }
    }
    private let minTemp = 20.0
    private let maxTemp = 100.0
    private let padding = 40.0
    
    private var selectedPointIndex: Int? = nil
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 绘制背景
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        
        // 绘制坐标轴
        drawAxes(context: context)
        
        // 绘制曲线
        drawCurve(context: context)
        
        // 绘制控制点
        drawControlPoints(context: context)
        
        // 绘制当前温度线
        drawCurrentTemperatureLine(context: context)

        // 拖拽时右下角显示温度/RPM
        drawEditingInfo()
    }
    
    private func drawAxes(context: CGContext) {
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        // X轴（温度）
        let xAxisPath = CGMutablePath()
        xAxisPath.move(to: CGPoint(x: padding, y: padding))
        xAxisPath.addLine(to: CGPoint(x: padding + width, y: padding))
        context.addPath(xAxisPath)
        context.setStrokeColor(NSColor.gray.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        
        // Y轴（RPM）
        let yAxisPath = CGMutablePath()
        yAxisPath.move(to: CGPoint(x: padding, y: padding))
        yAxisPath.addLine(to: CGPoint(x: padding, y: padding + height))
        context.addPath(yAxisPath)
        context.strokePath()
        
        // 绘制标签
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ]
        
        // 温度标签
        for temp in stride(from: minTemp, through: maxTemp, by: 20) {
            let x = padding + (temp - minTemp) / (maxTemp - minTemp) * width
            let label = String(format: "%.0f℃", temp)
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: x - size.width / 2, y: padding - 15), withAttributes: attributes)
        }
        
        // RPM标签
        for rpm in stride(from: 0, through: maxRPM, by: maxRPM / 4) {
            let y = padding + height - (CGFloat(rpm) / CGFloat(maxRPM)) * height
            let label = String(format: "%d", rpm)
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: padding - size.width - 5, y: y - size.height / 2), withAttributes: attributes)
        }
    }
    
    private func drawCurve(context: CGContext) {
        guard fanCurve.count >= 2 else { return }
        
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        var points: [CGPoint] = []
        for point in fanCurve {
            let x = padding + (point.temperature - minTemp) / (maxTemp - minTemp) * width
            let y = padding + height - (CGFloat(point.rpm) / CGFloat(maxRPM)) * height
            points.append(CGPoint(x: x, y: y))
        }
        
        let path = catmullRomPath(points: points, segments: 20)
        
        context.addPath(path)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }
    
    private func catmullRomPath(points: [CGPoint], segments: Int = 20) -> CGMutablePath {
        guard points.count >= 2 else { return CGMutablePath() }
        
        let path = CGMutablePath()
        path.move(to: points[0])
        
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            
            for j in 1...segments {
                let t = CGFloat(j) / CGFloat(segments)
                let t2 = t * t
                let t3 = t2 * t
                
                let x = 0.5 * ((2 * p1.x) +
                    (-p0.x + p2.x) * t +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                    (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                
                let y = 0.5 * ((2 * p1.y) +
                    (-p0.y + p2.y) * t +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                    (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
    
    private func drawControlPoints(context: CGContext) {
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        for (index, point) in fanCurve.enumerated() {
            let x = padding + (point.temperature - minTemp) / (maxTemp - minTemp) * width
            let y = padding + height - (CGFloat(point.rpm) / CGFloat(maxRPM)) * height
            
            let circlePath = CGMutablePath()
            circlePath.addArc(center: CGPoint(x: x, y: y), radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            
            context.addPath(circlePath)
            
            if selectedPointIndex == index {
                context.setFillColor(NSColor.systemRed.cgColor)
            } else {
                context.setFillColor(NSColor.systemBlue.cgColor)
            }
            context.fillPath()
            
            // 绘制边框
            context.addPath(circlePath)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
    }
    
    private func drawCurrentTemperatureLine(context: CGContext) {
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        let x = padding + (currentTemperature - minTemp) / (maxTemp - minTemp) * width
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: padding))
        path.addLine(to: CGPoint(x: x, y: padding + height))
        
        context.addPath(path)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    private func drawEditingInfo() {
        guard let index = selectedPointIndex, index < fanCurve.count else { return }

        let point = fanCurve[index]
        let text = String(format: "%.1f°C · %d", point.temperature, point.rpm)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding

        let x = padding + width - size.width
        let y = padding + 4
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = event.locationInWindow
        let point = convert(location, from: nil)
        
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        for (index, fanPoint) in fanCurve.enumerated() {
            let x = padding + (fanPoint.temperature - minTemp) / (maxTemp - minTemp) * width
            let y = padding + height - (CGFloat(fanPoint.rpm) / CGFloat(maxRPM)) * height
            
            let distance = hypot(point.x - x, point.y - y)
            if distance < 10 {
                selectedPointIndex = index
                setNeedsDisplay(bounds)
                return
            }
        }
        
        selectedPointIndex = nil
        setNeedsDisplay(bounds)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let index = selectedPointIndex else { return }
        
        let location = event.locationInWindow
        let point = convert(location, from: nil)
        
        let width = bounds.width - 2 * padding
        let height = bounds.height - 2 * padding
        
        let newTemp = minTemp + (point.x - padding) / width * (maxTemp - minTemp)
        let newRPM = Int((1 - (point.y - padding) / height) * Double(maxRPM))
        
        if index == 0 {
            fanCurve[index].temperature = minTemp
            fanCurve[index].rpm = max(0, min(maxRPM, newRPM))
        } else if index == fanCurve.count - 1 {
            fanCurve[index].temperature = maxTemp
            fanCurve[index].rpm = max(0, min(maxRPM, newRPM))
        } else {
            let minAllowedTemp = fanCurve[index - 1].temperature + 1
            let maxAllowedTemp = fanCurve[index + 1].temperature - 1
            fanCurve[index].temperature = max(minAllowedTemp, min(maxAllowedTemp, newTemp))
            fanCurve[index].rpm = max(0, min(maxRPM, newRPM))
        }
        
        setNeedsDisplay(bounds)
    }
    
    override func mouseUp(with event: NSEvent) {
        selectedPointIndex = nil
        setNeedsDisplay(bounds)
    }
}
