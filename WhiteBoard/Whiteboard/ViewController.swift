/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The primary view controller.
*/

import UIKit

class ViewController: UIViewController {

    var cgView: StrokeCGView!
    
    var fingerStrokeRecognizer: StrokeGestureRecognizer!
    var pencilStrokeRecognizer: StrokeGestureRecognizer!


    @IBOutlet var scrollView: UIScrollView!
    

    var strokeCollection = StrokeCollection()
    var canvasContainerView: CanvasContainerView!

    /// Prepare the drawing canvas.
    /// - Tag: CanvasMainViewController-viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        let screenBounds = UIScreen.main.bounds
        let maxScreenDimension = max(screenBounds.width, screenBounds.height)

        let cgView = StrokeCGView(frame: CGRect(origin: .zero, size: CGSize(width: maxScreenDimension, height: maxScreenDimension)))
        cgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.cgView = cgView
        
        let canvasContainerView = CanvasContainerView(canvasSize: cgView.frame.size)
        canvasContainerView.documentView = self.cgView
        
        self.canvasContainerView = canvasContainerView
        scrollView.contentSize = canvasContainerView.frame.size
        scrollView.contentOffset = CGPoint(x: (canvasContainerView.frame.width - scrollView.bounds.width) / 2.0,
                                           y: (canvasContainerView.frame.height - scrollView.bounds.height) / 2.0)
        scrollView.addSubview(canvasContainerView)
        scrollView.backgroundColor = canvasContainerView.backgroundColor
        scrollView.maximumZoomScale = 3.0
        scrollView.minimumZoomScale = 0.5
        scrollView.panGestureRecognizer.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        // We put our UI elements on top of the scroll view, so we don't want any of the
        // delay or cancel machinery in place.
        scrollView.delaysContentTouches = false

        self.fingerStrokeRecognizer = setupStrokeGestureRecognizer(isForPencil: false)
        self.pencilStrokeRecognizer = setupStrokeGestureRecognizer(isForPencil: true)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.didTapView(sender:)))
        scrollView.addGestureRecognizer(tapGesture)
        
        
        setupPencilUI()
    }
    
    @objc
    func didTapView(sender: UITapGestureRecognizer) {
      print("View Tapped")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.flashScrollIndicators()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }

    /// A helper method that creates stroke gesture recognizers.
    /// - Tag: setupStrokeGestureRecognizer
    func setupStrokeGestureRecognizer(isForPencil: Bool) -> StrokeGestureRecognizer {
        print("Setting up recognizer")
        let recognizer = StrokeGestureRecognizer(target: self, action: #selector(strokeUpdated(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        
        scrollView.addGestureRecognizer(recognizer)
        recognizer.coordinateSpaceView = cgView
        recognizer.isForPencil = isForPencil
        return recognizer
    }
    
    func receivedAllUpdatesForStroke(_ stroke: Stroke) {
        cgView.setNeedsDisplay(for: stroke)
        stroke.clearUpdateInfo()
    }

    @IBAction func clearButtonAction(_ sender: AnyObject) {
        self.strokeCollection = StrokeCollection()
        cgView.strokeCollection = self.strokeCollection
    }

    /// Handles the gesture for `StrokeGestureRecognizer`.
    /// - Tag: strokeUpdate
    @objc
    func strokeUpdated(_ strokeGesture: StrokeGestureRecognizer) {
        
        print("Stroke detected")
        
        if strokeGesture === pencilStrokeRecognizer {
            lastSeenPencilInteraction = Date()
        }
        
        var stroke: Stroke?
        if strokeGesture.state != .cancelled {
            stroke = strokeGesture.stroke
            if strokeGesture.state == .began ||
               (strokeGesture.state == .ended && strokeCollection.activeStroke == nil) {
                strokeCollection.activeStroke = stroke
            }
        } else {
            strokeCollection.activeStroke = nil
        }
        
        if let stroke = stroke {
            if strokeGesture.state == .ended {
                if strokeGesture === pencilStrokeRecognizer {
                    // Make sure we get the final stroke update if needed.
                    stroke.receivedAllNeededUpdatesBlock = { [weak self] in
                        self?.receivedAllUpdatesForStroke(stroke)
                    }
                }
               strokeCollection.takeActiveStroke()
            }
        }

        cgView.strokeCollection = strokeCollection
    }

    // MARK: Pencil Recognition and UI Adjustments
    /*
         Since usage of the Apple Pencil can be very temporary, the best way to
         actually check for it being in use is to remember the last interaction.
         Also make sure to provide an escape hatch if you modify your UI for
         times when the pencil is in use vs. not.
     */

    // Timeout the pencil mode if no pencil has been seen for 5 minutes and the app is brought back in foreground.
    let pencilResetInterval = TimeInterval(60.0 * 5)

    var lastSeenPencilInteraction: Date? {
        didSet {
            if lastSeenPencilInteraction != nil && !pencilMode {
                pencilMode = true
            }
        }
    }

    func shouldTimeoutPencilMode() -> Bool {
        guard let lastSeenPencilInteraction = self.lastSeenPencilInteraction else { return true }
        return abs(lastSeenPencilInteraction.timeIntervalSinceNow) > self.pencilResetInterval
    }
    
    private func setupPencilUI() {
        self.pencilMode = false

        self.willEnterForegroundNotification = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: UIApplication.shared,
            queue: nil) { [unowned self](_) in
                if self.pencilMode && self.shouldTimeoutPencilMode() {
                    self.stopPencilButtonAction(nil)
                }
        }
    }

    var willEnterForegroundNotification: NSObjectProtocol?

    /// Toggles pencil mode for the app.
    /// - Tag: pencilMode
    var pencilMode = false {
        didSet {
            if pencilMode {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
                if let view = fingerStrokeRecognizer.view {
                    print("immediately removing stroke gesture recognizer")
                    view.removeGestureRecognizer(fingerStrokeRecognizer)
                }
            } else {
                scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
                if fingerStrokeRecognizer.view == nil {
                    print("Adding finger Recognizer")
                    scrollView.addGestureRecognizer(fingerStrokeRecognizer)
                }
            }
        }
    }
    
    @IBAction func stopPencilButtonAction(_ sender: AnyObject?) {
        lastSeenPencilInteraction = nil
        pencilMode = false
    }

}

// MARK: - UIGestureRecognizerDelegate

extension ViewController: UIGestureRecognizerDelegate {

    // Since our gesture recognizer is beginning immediately, we do the hit test ambiguation here
    // instead of adding failure requirements to the gesture for minimizing the delay
    // to the first action sent and therefore the first lines drawn.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return false
    }

    // We want the pencil to recognize simultaniously with all others.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pencilStrokeRecognizer {
            return otherGestureRecognizer !== fingerStrokeRecognizer
        }

        return false
    }

}

// MARK: - UIScrollViewDelegate

extension ViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.canvasContainerView
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        var desiredScale = self.traitCollection.displayScale
        let existingScale = cgView.contentScaleFactor
        
        if scale >= 2.0 {
            desiredScale *= 2.0
        }
        
        if abs(desiredScale - existingScale) > 0.000_01 {
            cgView.contentScaleFactor = desiredScale
            cgView.setNeedsDisplay()
        }
    }
}

