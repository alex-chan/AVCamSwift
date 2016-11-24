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

struct Constants {
	static var SessionRunningAndDeviceAuthorizedContext = "SessionRunningAndDeviceAuthorizedContext"
	static var CapturingStillImageContext = "CapturingStillImageContext"
	static var RecordingContext = "RecordingContext"
}

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
	
	// MARK: property
	
	var sessionQueue: DispatchQueue!
	var session: AVCaptureSession?
	var videoDeviceInput: AVCaptureDeviceInput?
	var movieFileOutput: AVCaptureMovieFileOutput?
	var stillImageOutput: AVCaptureStillImageOutput?
	
	var deviceAuthorized: Bool  = false
	var backgroundRecordId: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
	var sessionRunningAndDeviceAuthorized: Bool {
		get {
			return (self.session?.isRunning != nil && self.deviceAuthorized )
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
		
		self.sessionQueue = DispatchQueue(label: "com.example.AVCamSwift.sessionQueue",attributes: [])
		
		sessionQueue.async {
			
			self.backgroundRecordId = UIBackgroundTaskInvalid
			
			let videoDevice: AVCaptureDevice! = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.back)
			
			
			var videoDeviceInput: AVCaptureDeviceInput?
			do {
				videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
			} catch {
				let alert = UIAlertController(title: "Camera Error", message: error.localizedDescription
					, preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				self.present(alert, animated: true, completion: nil)
				// disable the buttons, which will cause a crash if there is no AVCaptureDeviceInput
				self.cameraButton.isEnabled = false
				self.snapButton.isEnabled = false
				self.recordButton.isEnabled = false
			}
			
			if session.canAddInput(videoDeviceInput){
				session.addInput(videoDeviceInput)
				self.videoDeviceInput = videoDeviceInput
				
				DispatchQueue.main.async {
					// Why are we dispatching this to the main queue?
					// Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
					// Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
					
					let orientation: AVCaptureVideoOrientation =  AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
					
					(self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = orientation
				}
			}
			
			let audioCheck = AVCaptureDevice.devices(withMediaType: AVMediaTypeAudio)
			if (audioCheck?.isEmpty)! {
				print("no audio device")
				return
			}
			let audioDevice: AVCaptureDevice! = audioCheck!.first as! AVCaptureDevice
			
			var audioDeviceInput: AVCaptureDeviceInput?
			
			do {
				audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
			} catch {
				let alert = UIAlertController(title: "Error", message: error.localizedDescription
					, preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				self.present(alert, animated: true, completion: nil)
			}
			
			if session.canAddInput(audioDeviceInput){
				session.addInput(audioDeviceInput)
			}
			
			let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
			if session.canAddOutput(movieFileOutput){
				session.addOutput(movieFileOutput)
				
				let connection: AVCaptureConnection? = movieFileOutput.connection(withMediaType: AVMediaTypeVideo)
				let stab = connection?.isVideoStabilizationSupported
				if (stab != nil) {
					connection!.preferredVideoStabilizationMode = .auto
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
	
	override func viewWillAppear(_ animated: Bool) {
		self.sessionQueue.async {
			
			self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: [.old , .new] , context: &Constants.SessionRunningAndDeviceAuthorizedContext)
			self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options:[.old , .new], context: &Constants.CapturingStillImageContext)
			self.addObserver(self, forKeyPath: "movieFileOutput.recording", options: [.old , .new], context: &Constants.RecordingContext)
			
			NotificationCenter.default.addObserver(self, selector: #selector(ViewController.subjectAreaDidChange(_:)), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: self.videoDeviceInput?.device)
			
			self.runtimeErrorHandlingObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureSessionRuntimeError, object: self.session, queue: nil) {
				(note: Notification?) in
				self.sessionQueue.async { [weak self] in
					guard let strongSelf = self else { return }
					guard let session = strongSelf.session else { return }
					session.startRunning()
				}
			}
			self.session?.startRunning()
		}
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		
		self.sessionQueue.async {
			if let sess = self.session {
				sess.stopRunning()
				
				NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: self.videoDeviceInput?.device)
				NotificationCenter.default.removeObserver(self.runtimeErrorHandlingObserver!)
				
				self.removeObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", context: &Constants.SessionRunningAndDeviceAuthorizedContext)
				
				self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: &Constants.CapturingStillImageContext)
				self.removeObserver(self, forKeyPath: "movieFileOutput.recording", context: &Constants.RecordingContext)
			}
		}
	}
	
	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}
	
	
	override var prefersStatusBarHidden : Bool {
		return true
	}
	
	override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
		
		(self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: toInterfaceOrientation.rawValue)!
		
		//        if let layer = self.previewView.layer as? AVCaptureVideoPreviewLayer{
		//            layer.connection.videoOrientation = self.convertOrientation(toInterfaceOrientation)
		//        }
		
	}
	
	override var shouldAutorotate : Bool {
		return !self.lockInterfaceRotation
	}
	//    observeValueForKeyPath:ofObject:change:context:
	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		
		if context == &Constants.CapturingStillImageContext{
			let isCapturingStillImage: Bool = (change![NSKeyValueChangeKey.newKey]! as AnyObject).boolValue
			if isCapturingStillImage {
				self.runStillImageCaptureAnimation()
			}
			
		} else if context  == &Constants.RecordingContext{
			let isRecording: Bool = (change![NSKeyValueChangeKey.newKey]! as AnyObject).boolValue
			
			DispatchQueue.main.async {
				if isRecording {
					self.recordButton.titleLabel!.text = "Stop"
					self.recordButton.isEnabled = true
					//                    self.snapButton.enabled = false
					self.cameraButton.isEnabled = false
				} else {
					//                    self.snapButton.enabled = true
					self.recordButton.titleLabel!.text = "Record"
					self.recordButton.isEnabled = true
					self.cameraButton.isEnabled = true
				}
			}
			
		} else {
			return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}
	
	// MARK: Selector
	func subjectAreaDidChange(_ notification: Notification){
		let devicePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
		self.focusWithMode(AVCaptureFocusMode.continuousAutoFocus, exposureMode: AVCaptureExposureMode.continuousAutoExposure, point: devicePoint, monitorSubjectAreaChange: false)
	}
	
	// MARK:  Custom Function
	
	func focusWithMode(_ focusMode:AVCaptureFocusMode, exposureMode:AVCaptureExposureMode, point:CGPoint, monitorSubjectAreaChange:Bool){
		
		self.sessionQueue.async {
			guard let device: AVCaptureDevice = self.videoDeviceInput?.device else { return }
			
			do {
				try device.lockForConfiguration()
				
				if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode){
					device.focusMode = focusMode
					device.focusPointOfInterest = point
				}
				if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode){
					device.exposurePointOfInterest = point
					device.exposureMode = exposureMode
				}
				device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
				device.unlockForConfiguration()
				
			} catch {
				print(error)
			}
		}
		
	}
	
	class func setFlashMode(_ flashMode: AVCaptureFlashMode, device: AVCaptureDevice){
		
		if device.hasFlash && device.isFlashModeSupported(flashMode) {
			do {
				try device.lockForConfiguration()
				device.flashMode = flashMode
				device.unlockForConfiguration()
				
			} catch {
				print(error)
			}
		}
	}
	
	func runStillImageCaptureAnimation() {
		DispatchQueue.main.async {
			self.previewView.layer.opacity = 0.0
			print("opacity 0")
			UIView.animate(withDuration: 0.25, animations: {
				self.previewView.layer.opacity = 1.0
				print("opacity 1")
			})
		}
	}
	
	class func deviceWithMediaType(_ mediaType: String, preferringPosition:AVCaptureDevicePosition) -> AVCaptureDevice? {
		
		guard let devices = AVCaptureDevice.devices(withMediaType: mediaType) else { return nil }
		
		if devices.isEmpty {
			print("This device has no camera. Probably the simulator.")
			return nil
		} else {
			guard let firstCaptureDevice: AVCaptureDevice = devices[0] as? AVCaptureDevice else { return nil }
			var captureDevice = firstCaptureDevice
			
			for device in devices {
				if (device as AnyObject).position == preferringPosition {
					captureDevice = device as! AVCaptureDevice
					break
				}
			}
			return captureDevice
		}
	}
	
	func checkDeviceAuthorizationStatus(){
		let mediaType:String = AVMediaTypeVideo;
		
		AVCaptureDevice.requestAccess(forMediaType: mediaType) { (granted: Bool) in
			if granted {
				self.deviceAuthorized = true
			} else {
				
				DispatchQueue.main.async {
					let alert: UIAlertController = UIAlertController(
						title: "AVCam",
						message: "AVCam does not have permission to access camera",
						preferredStyle: UIAlertControllerStyle.alert)
					let action = UIAlertAction(title: "OK", style: .default, handler: nil)
					alert.addAction(action)
					self.present(alert, animated: true, completion: nil)
				}
				self.deviceAuthorized = false
			}
		}
	}
	
	
	// MARK: File Output Delegate
	func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
		
		if error != nil {
			print(error)
		}
		
		self.lockInterfaceRotation = false
		
		// Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
		
		let backgroundRecordId: UIBackgroundTaskIdentifier = self.backgroundRecordId
		self.backgroundRecordId = UIBackgroundTaskInvalid
		
		ALAssetsLibrary().writeVideoAtPath(toSavedPhotosAlbum: outputFileURL) { (url:URL?, error:Error?) in
			
			if error != nil { print(error as Any) }
			
			do {
				try FileManager.default.removeItem(at: outputFileURL)
			} catch {
				print(error)
			}
			
			if backgroundRecordId != UIBackgroundTaskInvalid {
				UIApplication.shared.endBackgroundTask(backgroundRecordId)
			}
		}
	}
	
	// MARK: Actions
	
	@IBAction func toggleMovieRecord(_ sender: AnyObject) {
		
		self.recordButton.isEnabled = false
		
		self.sessionQueue.async {
			if !self.movieFileOutput!.isRecording{
				self.lockInterfaceRotation = true
				
				if UIDevice.current.isMultitaskingSupported {
					self.backgroundRecordId = UIApplication.shared.beginBackgroundTask(expirationHandler: {})
				}
				
				self.movieFileOutput!.connection(withMediaType: AVMediaTypeVideo).videoOrientation =
					AVCaptureVideoOrientation(rawValue: (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation.rawValue )!
				
				// Turning OFF flash for video recording
				ViewController.setFlashMode(AVCaptureFlashMode.off, device: self.videoDeviceInput!.device)
				
				let outputFilePath  =
					URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("movie.mov")
				
				self.movieFileOutput!.startRecording( toOutputFileURL: outputFilePath, recordingDelegate: self)
			} else {
				self.movieFileOutput!.stopRecording()
			}
		}
		
	}
	
	@IBAction func snapStillImage(_ sender: AnyObject) {
		print("snapStillImage")
		self.sessionQueue.async {
			// Update the orientation on the still image output video connection before capturing.
			
			let videoOrientation =  (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
			
			self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo).videoOrientation = videoOrientation
			
			// Flash set to Auto for Still Capture
			ViewController.setFlashMode(AVCaptureFlashMode.auto, device: self.videoDeviceInput!.device)
			
			self.stillImageOutput!.captureStillImageAsynchronously(from: self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo)) {
				(imageDataSampleBuffer: CMSampleBuffer?, error: Error?) in
				
				if error == nil {
					let data:Data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
					let image:UIImage = UIImage( data: data)!
					
					let libaray:ALAssetsLibrary = ALAssetsLibrary()
					let orientation: ALAssetOrientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
					libaray.writeImage(toSavedPhotosAlbum: image.cgImage, orientation: orientation, completionBlock: nil)
					
					print("save to album")
					
				} else {
					print(error as Any)
				}
			}
		}
	}
	
	@IBAction func changeCamera(_ sender: AnyObject) {
		
		print("Camera changed")
		
		self.cameraButton.isEnabled = false
		self.recordButton.isEnabled = false
		self.snapButton.isEnabled = false
		
		self.sessionQueue.async {
			
			let currentVideoDevice:AVCaptureDevice = self.videoDeviceInput!.device
			let currentPosition: AVCaptureDevicePosition = currentVideoDevice.position
			var preferredPosition: AVCaptureDevicePosition = AVCaptureDevicePosition.unspecified
			
			switch currentPosition {
			case AVCaptureDevicePosition.front:
				preferredPosition = AVCaptureDevicePosition.back
			case AVCaptureDevicePosition.back:
				preferredPosition = AVCaptureDevicePosition.front
			case AVCaptureDevicePosition.unspecified:
				preferredPosition = AVCaptureDevicePosition.back
				
			}
			
			guard let device:AVCaptureDevice = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition) else {
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
				
				NotificationCenter.default.removeObserver(self, name:NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object:currentVideoDevice)
				
				ViewController.setFlashMode(AVCaptureFlashMode.auto, device: device)
				
				NotificationCenter.default.addObserver(self, selector: #selector(ViewController.subjectAreaDidChange(_:)), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: device)
				
				self.session!.addInput(videoDeviceInput)
				self.videoDeviceInput = videoDeviceInput
				
			} else {
				self.session!.addInput(self.videoDeviceInput)
			}
			
			self.session!.commitConfiguration()
			
			DispatchQueue.main.async {
				self.recordButton.isEnabled = true
				self.snapButton.isEnabled = true
				self.cameraButton.isEnabled = true
			}
			
		}
	}
	
	@IBAction func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
		print("focusAndExposeTap")
		let devicePoint: CGPoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterest(for: gestureRecognizer.location(in: gestureRecognizer.view))
		
		print(devicePoint)
		
		self.focusWithMode(AVCaptureFocusMode.autoFocus, exposureMode: AVCaptureExposureMode.autoExpose, point: devicePoint, monitorSubjectAreaChange: true)
	}
}

