//
//  SpinWheelControl.swift
//  SpinWheelControl
//
//  Created by Josh Henry on 4/27/17.
//  Copyright © 2017 Big Smash Software. All rights reserved.
//
//Trigonometry is used extensively in SpinWheel Control. Here is a quick refresher.
//Sine, Cosine and Tangent are each a ratio of sides of a right angled triangle
//Arc tangent (atan2) calculates the angles of a right triangle (tangent = Opposite / Adjacent)
//The sin is ratio of the length of the side that is opposite that angle to the length of the longest side of the triangle (the hypotenuse) (sin = Opposite / Hypotenuse)
//The cosine is (cosine = Adjacent / Hypotenuse)

import UIKit

typealias Degrees = CGFloat
public typealias Radians = CGFloat
typealias Velocity = CGFloat

public enum SpinWheelStatus {
    case idle, decelerating, snapping
}

public enum SpinWheelDirection {
    case up, right, down, left
    
    var radiansValue: Radians {
        switch self {
        case .up:
            return Radians.pi / 2
        case .right:
            return 0
        case .down:
            return -(Radians.pi / 2)
        case .left:
            return Radians.pi
        }
    }
}


@objc open class SpinWheelControl: UIControl {
    
    //MARK: Properties
    weak public var dataSource: SpinWheelControlDataSource?
    public var delegate: SpinWheelControlDelegate?
    
    static let kMinimumRadiansForSpin: Radians = 0.1
    static let kMinDistanceFromCenter: CGFloat = 30.0
    static let kMaxVelocity: Velocity = 20
    static let kDecelerationVelocityMultiplier: CGFloat = 0.98 //The deceleration multiplier is not to be set past 0.99 in order to avoid issues
    static let kSpeedToSnap: CGFloat = 0.1
    static let kSnapRadiansProximity: Radians = 0.001
    static let kWedgeSnapVelocityMultiplier: CGFloat = 10.0
    static let kZoomZoneThreshold = 1.5
    static let kPreferredFramesPerSecond: Int = 60
    
    //A circle = 360 degrees = 2 * pi radians
    let kCircleRadians: Radians = 2 * CGFloat.pi
    
    var spinWheelView: UIView!
    
    private var numberOfWedges: UInt!
    private var radiansPerWedge: CGFloat!
    
    var decelerationDisplayLink: CADisplayLink? = nil
    var snapDisplayLink: CADisplayLink? = nil
    
    var startTrackingTime: CFTimeInterval!
    var endTrackingTime: CFTimeInterval!
    
    var previousTouchRadians: Radians!
    var currentTouchRadians: Radians!
    var startTouchRadians: Radians!
    var currentlyDetectingTap: Bool!
    
    var currentStatus: SpinWheelStatus = .idle
    
    var currentDecelerationVelocity: Velocity!
    
    var snapDestinationRadians: Radians!
    var snapIncrementRadians: Radians!
    
    public var selectedIndex: Int = 0
    
    let colorPalette: [UIColor] = [UIColor.blue, UIColor.brown, UIColor.cyan, UIColor.darkGray, UIColor.green, UIColor.magenta, UIColor.red, UIColor.orange, UIColor.black, UIColor.gray, UIColor.lightGray, UIColor.purple, UIColor.yellow, UIColor.white]
    
    //MARK: Computed Properties
    var degreesPerWedge: Degrees {
        return 360 / CGFloat(numberOfWedges)
    }
    
    var radius: CGFloat {
        return self.frame.width / 2
    }
    
    //How far the wheel is turned from its default position
    var currentRadians: Radians {
        return atan2(self.spinWheelView.transform.b, self.spinWheelView.transform.a)
    }
    
    // This determines which angle the numbers are deemed to be selected. In this case it is pi / 2, which is the top center of the wheel
    var snappingPositionRadians: Radians {
        return SpinWheelDirection.up.radiansValue
    }
    
    var radiansToDestinationSlice: Radians {
        return snapDestinationRadians - currentRadians
    }
    
    
    //The velocity of the spinwheel
    var velocity: Velocity {
        var computedVelocity: Velocity = 0
        
        //If the wheel was actually spun, calculate the new velocity
        if endTrackingTime != startTrackingTime &&
            abs(previousTouchRadians - currentTouchRadians) >= SpinWheelControl.kMinimumRadiansForSpin {
            computedVelocity = (previousTouchRadians - currentTouchRadians) / CGFloat(endTrackingTime - startTrackingTime)
        }
        
        //If the velocity is beyond the maximum allowed velocity, throttle it
        if computedVelocity > SpinWheelControl.kMaxVelocity {
            computedVelocity = SpinWheelControl.kMaxVelocity
        }
        else if computedVelocity < -SpinWheelControl.kMaxVelocity {
            computedVelocity = -SpinWheelControl.kMaxVelocity
        }
        
        return computedVelocity
    }
    
    
    //MARK: Initialization Methods
    @objc override public init(frame: CGRect) {
        super.init(frame: frame)
        
        self.drawWheel()
    }
    
    
    @objc required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    //MARK: Methods
    public func clear() {
        for subview in spinWheelView.subviews {
            subview.removeFromSuperview()
        }
        guard let sublayers = spinWheelView.layer.sublayers else {
            return
        }
        for sublayer in sublayers {
            sublayer.removeFromSuperlayer()
        }
    }
    
    
    public func drawWheel() {
        //NSLog("Drawing wheel...")
        
        spinWheelView = UIView(frame: self.bounds)
        
        self.backgroundColor = UIColor.cyan
        
        guard self.dataSource?.numberOfWedgesInSpinWheel(spinWheel: self) != nil else {
            return
        }
        numberOfWedges = self.dataSource?.numberOfWedgesInSpinWheel(spinWheel: self)
        
        guard numberOfWedges >= 2 else {
            return
        }
        
        radiansPerWedge = kCircleRadians / CGFloat(numberOfWedges)
        
        //Draw each individual wedge
        for wedgeNumber in 0..<numberOfWedges {
            drawWedge(wedgeNumber: wedgeNumber)
        }
        
        //Draw each individual label
        for wedgeNumber in 0..<numberOfWedges {
            drawWedgeLabel(wedgeNumber: wedgeNumber)
        }
        
        self.spinWheelView.isUserInteractionEnabled = false
        
        //Rotate the wheel to put the first wedge at the top
        self.spinWheelView.transform = CGAffineTransform(rotationAngle: -(snappingPositionRadians) - (radiansPerWedge / 2))
        
        self.addSubview(self.spinWheelView)
    }
    
    
    func drawWedge(wedgeNumber: UInt) {
        let newWedge: CAShapeLayer = CAShapeLayer()
        newWedge.fillColor = colorPalette[Int(wedgeNumber)].cgColor
        newWedge.strokeColor = UIColor.black.cgColor
        newWedge.lineWidth = 3.0
        
        let newWedgePath: UIBezierPath = UIBezierPath()
        newWedgePath.move(to: center)
        let startRadians: Radians = CGFloat(wedgeNumber) * degreesPerWedge * CGFloat.pi / 180
        let endRadians: Radians = CGFloat(wedgeNumber + 1) * degreesPerWedge * CGFloat.pi / 180
        
        newWedgePath.addArc(withCenter: center, radius: radius, startAngle: startRadians, endAngle: endRadians, clockwise: true)
        newWedgePath.close()
        newWedge.path = newWedgePath.cgPath
        
        spinWheelView.layer.addSublayer(newWedge)
    }
    
    
    func drawWedgeLabel(wedgeNumber: UInt) {
        let wedgeLabelFrame: CGRect = CGRect(x: 0, y: 0, width: radius / 2, height: 30)
        
        let wedgeLabel: UILabel = UILabel(frame: wedgeLabelFrame)
        wedgeLabel.layer.anchorPoint = CGPoint(x: 1.50, y: 0.5)
        wedgeLabel.layer.position = CGPoint(x: self.spinWheelView.bounds.size.width / 2 - self.spinWheelView.frame.origin.x, y: self.spinWheelView.bounds.size.height / 2 - self.spinWheelView.frame.origin.y)
        
        wedgeLabel.transform = CGAffineTransform(rotationAngle: radiansPerWedge * CGFloat(wedgeNumber) + CGFloat.pi + (radiansPerWedge / 2))
        
        wedgeLabel.backgroundColor = colorPalette[Int(wedgeNumber)]
        wedgeLabel.textColor = UIColor.white
        wedgeLabel.text = "Label #" + String(wedgeNumber)
        wedgeLabel.shadowColor = UIColor.black
        spinWheelView.addSubview(wedgeLabel)
    }
    
    
    func didEndRotationOnWedgeAtIndex(index: UInt) {
        selectedIndex = Int(index)
        delegate?.spinWheelDidEndDecelerating?(spinWheel: self)
        self.sendActions(for: .valueChanged)
    }
    
    
    //User began touching/dragging the UIControl
    override open func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        //NSLog("Begin Tracking...")
        
        switch currentStatus {
        case SpinWheelStatus.idle:
            currentlyDetectingTap = true
        case SpinWheelStatus.decelerating:
            endDeceleration()
            endSnap()
        case SpinWheelStatus.snapping:
            endSnap()
        }
        
        let touchPoint: CGPoint = touch.location(in: self)
        
        if distanceFromCenter(point: touchPoint) < SpinWheelControl.kMinDistanceFromCenter {
            return false
        }
        
        startTrackingTime = CACurrentMediaTime()
        endTrackingTime = startTrackingTime
        
        startTouchRadians = radiansForTouch(touch: touch)
        currentTouchRadians = startTouchRadians
        previousTouchRadians = startTouchRadians
        
        return true
    }
    
    
    //User is in the middle of dragging the UIControl
    override open func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        //NSLog("Continue Tracking....")
        
        currentlyDetectingTap = false
        
        startTrackingTime = endTrackingTime
        endTrackingTime = CACurrentMediaTime()
        
        let touchPoint: CGPoint = touch.location(in: self)
        let distanceFromCenterOfSpinWheel: CGFloat = distanceFromCenter(point: touchPoint)
        
        if distanceFromCenterOfSpinWheel < SpinWheelControl.kMinDistanceFromCenter {
            return true
        }
        
        previousTouchRadians = currentTouchRadians
        currentTouchRadians = radiansForTouch(touch: touch)
        let touchRadiansDifference: Radians = currentTouchRadians - previousTouchRadians
        
        self.spinWheelView.transform = self.spinWheelView.transform.rotated(by: touchRadiansDifference)
        
        delegate?.spinWheelDidRotateByRadians?(radians: touchRadiansDifference)
        
        return true
    }
    
    
    //User ended touching/dragging the UIControl
    override open func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        //NSLog("End Tracking...")
        
        let tapCount = touch?.tapCount != nil ? (touch?.tapCount)! : 0
        //If the user just tapped, move to that wedge
        if currentStatus == .idle &&
            tapCount > 0 &&
            currentlyDetectingTap {}
            //Else decelerate
        else {
            beginDeceleration()
        }
    }
    
    
    //After user has lifted their finger from dragging, begin the deceleration
    func beginDeceleration() {
        //NSLog("Beginning deceleration...")
        
        currentDecelerationVelocity = velocity
        
        //If the wheel was spun, begin deceleration
        if currentDecelerationVelocity != 0 {
            currentStatus = .decelerating
            
            decelerationDisplayLink?.invalidate()
            decelerationDisplayLink = CADisplayLink(target: self, selector: #selector(SpinWheelControl.decelerationStep))
            decelerationDisplayLink?.preferredFramesPerSecond = SpinWheelControl.kPreferredFramesPerSecond
            decelerationDisplayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        }
            //Else snap to the nearest wedge.  No deceleration necessary.
        else {
            snapToNearestWedge()
        }
    }
    
    
    //Deceleration step run for each frame of decelerationDisplayLink
    func decelerationStep() {
        let newVelocity: Velocity = currentDecelerationVelocity * SpinWheelControl.kDecelerationVelocityMultiplier
        let radiansToRotate: Radians = currentDecelerationVelocity / CGFloat(SpinWheelControl.kPreferredFramesPerSecond)
        
        //If the spinwheel has slowed down to under the minimum speed, end the deceleration
        if newVelocity <= SpinWheelControl.kSpeedToSnap &&
            newVelocity >= -SpinWheelControl.kSpeedToSnap {
            endDeceleration()
        }
            //else continue decelerating the SpinWheel
        else {
            currentDecelerationVelocity = newVelocity
            self.spinWheelView.transform = self.spinWheelView.transform.rotated(by: -radiansToRotate)
            delegate?.spinWheelDidRotateByRadians?(radians: -radiansToRotate)
        }
    }
    
    
    //End decelerating the spinwheel
    func endDeceleration() {
        //NSLog("End Decelerating...")
        
        decelerationDisplayLink?.invalidate()
        snapToNearestWedge()
    }
    
    
    //Snap to the nearest wedge
    func snapToNearestWedge() {
        currentStatus = .snapping
        
        let nearestWedge: Int = Int(round(((currentRadians + (radiansPerWedge / 2)) + snappingPositionRadians) / radiansPerWedge))
        
        selectWedgeAtIndexOffset(index: nearestWedge, animated: true)
    }
    
    
    func snapStep() {
        //NSLog("Snap step...")
        let difference: Radians = atan2(sin(radiansToDestinationSlice), cos(radiansToDestinationSlice))
        
        //If the spin wheel is turned close enough to the destination it is snapping to, end snapping
        if abs(difference) <= SpinWheelControl.kSnapRadiansProximity {
            endSnap()
        }
            //else continue snapping to the nearest wedge
        else {
            let newPositionRadians: Radians = currentRadians + snapIncrementRadians
            self.spinWheelView.transform = CGAffineTransform(rotationAngle: newPositionRadians)
            
            delegate?.spinWheelDidRotateByRadians?(radians: newPositionRadians)
        }
    }
    
    
    //End snapping
    func endSnap() {
        //NSLog("End snap...")
        
        //snappingPositionRadians is the default snapping position (in this case, up)
        //currentRadians in this case is where in the wheel it is currently snapped
        //Distance of zero wedge from the default snap position (up)
        var indexSnapped: Radians = (-(snappingPositionRadians) - currentRadians - (radiansPerWedge / 2))
        
        
        //Number of wedges from the zero wedge to the default snap position (up)
        indexSnapped = indexSnapped / radiansPerWedge + CGFloat(numberOfWedges)
        
        indexSnapped = indexSnapped.rounded(FloatingPointRoundingRule.toNearestOrAwayFromZero)
        indexSnapped = indexSnapped.truncatingRemainder(dividingBy: CGFloat(numberOfWedges))
        
        didEndRotationOnWedgeAtIndex(index: UInt(indexSnapped))
        
        snapDisplayLink?.invalidate()
        currentStatus = .idle
    }
    
    
    //Return the radians at the touch point. Return values range from -pi to pi
    func radiansForTouch(touch: UITouch) -> Radians {
        let touchPoint: CGPoint = touch.location(in: self)
        let dx: CGFloat = touchPoint.x - self.spinWheelView.center.x
        let dy: CGFloat = touchPoint.y - self.spinWheelView.center.y
        
        return atan2(dy, dx)
    }
    
    
    //Select a wedge with an index offset relative to 0 position. May be positive or negative.
    func selectWedgeAtIndexOffset(index: Int, animated: Bool) {
        NSLog("Select wedge at index " + String(index))
        snapDestinationRadians = -(snappingPositionRadians) + (CGFloat(index) * radiansPerWedge) - (radiansPerWedge / 2)
        
        if currentRadians != snapDestinationRadians {
            snapIncrementRadians = radiansToDestinationSlice / SpinWheelControl.kWedgeSnapVelocityMultiplier
        }
        else {
            return
        }
        
        currentStatus = .snapping
        
        snapDisplayLink?.invalidate()
        snapDisplayLink = CADisplayLink(target: self, selector: #selector(snapStep))
        snapDisplayLink?.preferredFramesPerSecond = SpinWheelControl.kPreferredFramesPerSecond
        snapDisplayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
    }
    
    
    //Distance of a point from the center of the spinwheel
    func distanceFromCenter(point: CGPoint) -> CGFloat {
        let center: CGPoint = CGPoint(x: self.bounds.size.width / 2, y: self.bounds.size.height / 2)
        let dx: CGFloat = point.x - center.x
        let dy: CGFloat = point.y - center.y
        
        return sqrt(dx * dx + dy * dy)
    }
    
    
    //Clear all views and redraw the spin wheel
    public func reloadData() {
        clear()
        drawWheel()
    }
}
