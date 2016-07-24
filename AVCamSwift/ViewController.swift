//
//  ViewController.swift
//  AVCamSwift
//
//  Created by sunset on 14-11-9.
//  Copyright (c) 2014年 sunset. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

var SessionRunningAndDeviceAuthorizedContext = "SessionRunningAndDeviceAuthorizedContext"
var CapturingStillImageContext = "CapturingStillImageContext"
var RecordingContext = "RecordingContext"

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    // MARK: property
    
    var sessionQueue: dispatch_queue_t!
    var session: AVCaptureSession?
    var videoDeviceInput: AVCaptureDeviceInput?
    var movieFileOutput: AVCaptureMovieFileOutput?
    var stillImageOutput: AVCaptureStillImageOutput?
    
    var deviceAuthorized: Bool  = false
    var backgroundRecordId: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    var sessionRunningAndDeviceAuthorized: Bool {
        get {
            return (self.session?.running != nil && self.deviceAuthorized )
        }
    }
    
    var runtimeErrorHandlingObserver: AnyObject?
    var lockInterfaceRotation: Bool = false
    
    @IBOutlet weak var previewView: AVCamPreviewView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var snapButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    
    // MARK: Override methods

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let session: AVCaptureSession = AVCaptureSession()
        self.session = session
        
        self.previewView.session = session
        
        self.checkDeviceAuthorizationStatus()
        
        let sessionQueue: dispatch_queue_t = dispatch_queue_create("com.bradleymackey.Backchat.sessionQueue",DISPATCH_QUEUE_SERIAL)
        
        self.sessionQueue = sessionQueue
        dispatch_async(sessionQueue) {
            self.backgroundRecordId = UIBackgroundTaskInvalid
            
            let videoDevice: AVCaptureDevice! = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            var error: NSError? = nil
            

            var videoDeviceInput: AVCaptureDeviceInput?
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            } catch let error1 as NSError {
                error = error1
                videoDeviceInput = nil
            } catch {
                fatalError()
            }
            
            if (error != nil) {
                print(error)
                let alert = UIAlertController(title: "Error", message: error!.localizedDescription
                    , preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                self.presentViewController(alert, animated: true, completion: nil)
            }

            if session.canAddInput(videoDeviceInput){
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue()) {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.

                    let orientation: AVCaptureVideoOrientation =  AVCaptureVideoOrientation(rawValue: UIDevice.currentDevice().orientation.rawValue)!
                    
                    (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = orientation
                }
            }
            
            let audioCheck = AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio)
            if audioCheck.isEmpty {
                print("no audio device")
                return
            }
            let audioDevice: AVCaptureDevice! = audioCheck.first as! AVCaptureDevice
            
            var audioDeviceInput: AVCaptureDeviceInput?
            
            do {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            } catch let error2 as NSError {
                error = error2
                audioDeviceInput = nil
            } catch {
                fatalError()
            }
            
            if error != nil{
                print(error)
                let alert = UIAlertController(title: "Error", message: error!.localizedDescription
                    , preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                self.presentViewController(alert, animated: true, completion: nil)
            }
            if session.canAddInput(audioDeviceInput){
                session.addInput(audioDeviceInput)
            }
            
            let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieFileOutput){
                session.addOutput(movieFileOutput)

                let connection: AVCaptureConnection? = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                let stab = connection?.supportsVideoStabilization
                if (stab != nil) {
                    connection!.preferredVideoStabilizationMode = .Auto
                }
                self.movieFileOutput = movieFileOutput
            }

            let stillImageOutput: AVCaptureStillImageOutput = AVCaptureStillImageOutput()
            if session.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
                session.addOutput(stillImageOutput)
                
                self.stillImageOutput = stillImageOutput
            }
        }
    }

    
    override func viewWillAppear(animated: Bool) {
        dispatch_async(self.sessionQueue) {
            
            self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: [.Old , .New] , context: &SessionRunningAndDeviceAuthorizedContext)
            self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options:[.Old , .New], context: &CapturingStillImageContext)
            self.addObserver(self, forKeyPath: "movieFileOutput.recording", options: [.Old , .New], context: &RecordingContext)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
            
            self.runtimeErrorHandlingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.session, queue: nil) {
                (note: NSNotification?) in
                dispatch_async(self.sessionQueue) { [unowned self] in
                    if let sess = self.session {
                        sess.startRunning()
                    }
//                    strongSelf.recordButton.title  = NSLocalizedString("Record", "Recording button record title")
                }
            }
            self.session?.startRunning()
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        
        dispatch_async(self.sessionQueue) {
            if let sess = self.session {
                sess.stopRunning()
                
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput?.device)
                NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandlingObserver!)
                
                self.removeObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", context: &SessionRunningAndDeviceAuthorizedContext)
                
                self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: &CapturingStillImageContext)
                self.removeObserver(self, forKeyPath: "movieFileOutput.recording", context: &RecordingContext)
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        
        (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: toInterfaceOrientation.rawValue)!
        
//        if let layer = self.previewView.layer as? AVCaptureVideoPreviewLayer{
//            layer.connection.videoOrientation = self.convertOrientation(toInterfaceOrientation)
//        }
        
    }
    
    override func shouldAutorotate() -> Bool {
        return !self.lockInterfaceRotation
    }
//    observeValueForKeyPath:ofObject:change:context:
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        
        if context == &CapturingStillImageContext{
            let isCapturingStillImage: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            if isCapturingStillImage {
                self.runStillImageCaptureAnimation()
            }
            
        } else if context  == &RecordingContext{
            let isRecording: Bool = change![NSKeyValueChangeNewKey]!.boolValue
            
            dispatch_async(dispatch_get_main_queue()) {
                if isRecording {
                    self.recordButton.titleLabel!.text = "Stop"
                    self.recordButton.enabled = true
//                    self.snapButton.enabled = false
                    self.cameraButton.enabled = false
                } else {
//                    self.snapButton.enabled = true
                    self.recordButton.titleLabel!.text = "Record"
                    self.recordButton.enabled = true
                    self.cameraButton.enabled = true
                }
            }
            
        } else {
            return super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    // MARK: Selector
    func subjectAreaDidChange(notification: NSNotification){
        let devicePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposureMode: AVCaptureExposureMode.ContinuousAutoExposure, point: devicePoint, monitorSubjectAreaChange: false)
    }
    
    // MARK:  Custom Function
    
    func focusWithMode(focusMode:AVCaptureFocusMode, exposureMode:AVCaptureExposureMode, point:CGPoint, monitorSubjectAreaChange:Bool){
        
        dispatch_async(self.sessionQueue) {
            let device: AVCaptureDevice! = self.videoDeviceInput!.device
  
            do {
                try device.lockForConfiguration()
                
                if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode){
                    device.focusMode = focusMode
                    device.focusPointOfInterest = point
                }
                if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode){
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
            } catch {
                print(error)
            }
        }
        
    }
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, device: AVCaptureDevice){
        
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            var error: NSError? = nil
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
                
            } catch let error1 as NSError {
                error = error1
                print(error)
            }
        }
    }
    
    func runStillImageCaptureAnimation(){
        dispatch_async(dispatch_get_main_queue()) {
            self.previewView.layer.opacity = 0.0
            print("opacity 0")
            UIView.animateWithDuration(0.25) {
                self.previewView.layer.opacity = 1.0
            print("opacity 1")
            }
        }
    }
    
    class func deviceWithMediaType(mediaType: String, preferringPosition:AVCaptureDevicePosition) -> AVCaptureDevice? {
        
        var devices = AVCaptureDevice.devicesWithMediaType(mediaType);
        
        if devices.isEmpty {
            print("This device has no camera. Probably the simulator.")
            return nil
        } else {
            var captureDevice: AVCaptureDevice = devices[0] as! AVCaptureDevice
            
            for device in devices {
                if device.position == preferringPosition {
                    captureDevice = device as! AVCaptureDevice
                    break
                }
            }
            return captureDevice
        }
    }
    
    func checkDeviceAuthorizationStatus(){
        let mediaType:String = AVMediaTypeVideo;
        
        AVCaptureDevice.requestAccessForMediaType(mediaType) { (granted: Bool) in
            if granted {
                self.deviceAuthorized = true;
            } else {
                
                dispatch_async(dispatch_get_main_queue()) {
                    let alert: UIAlertController = UIAlertController(
                                                        title: "AVCam",
                                                        message: "AVCam does not have permission to access camera",
                                                        preferredStyle: UIAlertControllerStyle.Alert)
                    let action = UIAlertAction(title: "OK", style: .Default) { _ in }
                    alert.addAction(action)
                    self.presentViewController(alert, animated: true, completion: nil)
                }
                self.deviceAuthorized = false;
            }
        }
    }
    

    // MARK: File Output Delegate
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        
        if error != nil {
            print(error)
        }
        
        self.lockInterfaceRotation = false
        
        // Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
        
        let backgroundRecordId: UIBackgroundTaskIdentifier = self.backgroundRecordId
        self.backgroundRecordId = UIBackgroundTaskInvalid
        
        ALAssetsLibrary().writeVideoAtPathToSavedPhotosAlbum(outputFileURL) {
            (assetURL:NSURL!, error:NSError!) in
            if error != nil{
                print(error)
            }
            
            do {
                try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
            } catch {
                print(error)
            }
            
            if backgroundRecordId != UIBackgroundTaskInvalid {
                UIApplication.sharedApplication().endBackgroundTask(backgroundRecordId)
            }
        }
    }
    
    // MARK: Actions
    
    @IBAction func toggleMovieRecord(sender: AnyObject) {
        
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            if !self.movieFileOutput!.recording{
                self.lockInterfaceRotation = true
                
                if UIDevice.currentDevice().multitaskingSupported {
                    self.backgroundRecordId = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler({})
                }
                
                self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation =
                    AVCaptureVideoOrientation(rawValue: (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation.rawValue )!
                
                // Turning OFF flash for video recording
                ViewController.setFlashMode(AVCaptureFlashMode.Off, device: self.videoDeviceInput!.device)
                
                let outputFilePath  =
                NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("movie.mov")

                self.movieFileOutput!.startRecordingToOutputFileURL( outputFilePath, recordingDelegate: self)
            } else {
                self.movieFileOutput!.stopRecording()
            }
        }
        
    }
    @IBAction func snapStillImage(sender: AnyObject) {
        print("snapStillImage")
        dispatch_async(self.sessionQueue) {
            // Update the orientation on the still image output video connection before capturing.
            
            let videoOrientation =  (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
            
            self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = videoOrientation
            
            // Flash set to Auto for Still Capture
            ViewController.setFlashMode(AVCaptureFlashMode.Auto, device: self.videoDeviceInput!.device)

            self.stillImageOutput!.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)) {
                (imageDataSampleBuffer: CMSampleBuffer!, error: NSError!) in
        
                if error == nil {
                    let data:NSData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    let image:UIImage = UIImage( data: data)!
                    
                    let libaray:ALAssetsLibrary = ALAssetsLibrary()
                    let orientation: ALAssetOrientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
                    libaray.writeImageToSavedPhotosAlbum(image.CGImage, orientation: orientation, completionBlock: nil)
                    
                    print("save to album")

                } else {
//                    print("Did not capture still image")
                    print(error)
                }
            }
        }
    }
    
    @IBAction func changeCamera(sender: AnyObject) {
        
        print("Camera changed")
        
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.snapButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            
            let currentVideoDevice:AVCaptureDevice = self.videoDeviceInput!.device
            let currentPosition: AVCaptureDevicePosition = currentVideoDevice.position
            var preferredPosition: AVCaptureDevicePosition = AVCaptureDevicePosition.Unspecified
            
            switch currentPosition {
            case AVCaptureDevicePosition.Front:
                preferredPosition = AVCaptureDevicePosition.Back
            case AVCaptureDevicePosition.Back:
                preferredPosition = AVCaptureDevicePosition.Front
            case AVCaptureDevicePosition.Unspecified:
                preferredPosition = AVCaptureDevicePosition.Back
                
            }
        
            guard let device:AVCaptureDevice! = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition) else {
                print("there is no AVCapture Device")
                return
            }
            
            var videoDeviceInput: AVCaptureDeviceInput?
            
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: device)
            } catch _ as NSError {
                videoDeviceInput = nil
            } catch {
                fatalError()
            }
            
            self.session!.beginConfiguration()
            
            self.session!.removeInput(self.videoDeviceInput)
            
            if self.session!.canAddInput(videoDeviceInput) {
       
                NSNotificationCenter.defaultCenter().removeObserver(self, name:AVCaptureDeviceSubjectAreaDidChangeNotification, object:currentVideoDevice)
                
                ViewController.setFlashMode(AVCaptureFlashMode.Auto, device: device!)
                
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: device)
                                
                self.session!.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                self.session!.addInput(self.videoDeviceInput)
            }
            
            self.session!.commitConfiguration()
        
            dispatch_async(dispatch_get_main_queue()) {
                self.recordButton.enabled = true
                self.snapButton.enabled = true
                self.cameraButton.enabled = true
            }
            
        }
    }
    
    @IBAction func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        print("focusAndExposeTap")
        let devicePoint: CGPoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        
        print(devicePoint)
        
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposureMode: AVCaptureExposureMode.AutoExpose, point: devicePoint, monitorSubjectAreaChange: true)
    }
}

