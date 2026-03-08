//
//  cameraLogic.swift
//  weary-tracker3
//
//  Created by Leo Nguyen on 3/7/26.
//

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController,
                           AVCaptureVideoDataOutputSampleBufferDelegate {
    //ear vars
    
    let earOpenThreshold = 0.28
    let earClosedThreshold = 0.115

    let drowsyFrameThreshold = 25
    let blinkFrameThreshold = 5

    var earHistory: [Double] = []

    // MARK: Camera
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!

    // MARK: Vision
    var faceRequest = VNDetectFaceLandmarksRequest()

    // MARK: Drowsiness Tracking
    var frameCount = 0
    let frameThresh = 15
    let earThreshold = 0.25
    var drowsFlag = true
    var alarmFlag = 0
    
    // audio
    var alarmPlayer: AVAudioPlayer?
        
    var realPlayer: AVAudioPlayer?

    // assets
    
    let meter: [UIImage] = [
        UIImage(named: "full2")!,
        UIImage(named: "half2")!,
        UIImage(named: "less2")!,
        UIImage(named: "none2")!
    ]
    var meterAsset: UIImageView!
    var imageIndex = 0
    var statusLabel: UILabel!
    //button
    
    var alarmButton: UIButton!
    var stopCooldown = false
    let cooldownDur: TimeInterval = 3.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
        if let url = Bundle.main.url(forResource: "warning", withExtension: "wav") {
            alarmPlayer = try? AVAudioPlayer(contentsOf: url)
            alarmPlayer?.numberOfLoops = -1
            alarmPlayer?.prepareToPlay()
        }
        
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") {
            realPlayer = try? AVAudioPlayer(contentsOf: url)
            realPlayer?.prepareToPlay()
            alarmPlayer?.numberOfLoops = 1
        }
        
        meterAsset = UIImageView(image: meter[imageIndex])
        meterAsset.frame = CGRect(x: 0, y: 575, width: 100, height: 150)
        
        alarmButton = UIButton(type: .custom)
        alarmButton.setImage(UIImage(named: "stop2"),for: .normal)
        alarmButton.frame = CGRect(x: 285, y: 600, width: 100, height: 100)
        alarmButton.addTarget(self,
                              action: #selector(stopAlarm),
                              for: .touchUpInside)
        
        statusLabel = UILabel(frame: CGRect(x: 20, y: 500, width: view.bounds.width - 40, height: 50))
        statusLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)  // bold large font
        statusLabel.textColor = .green
        statusLabel.textAlignment = .center
        statusLabel.text = "Status: Awake"  // default text
        
        let blurEffect = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = CGRect(
            x: 0,
            y: 500,     // start at middle
            width: view.bounds.width,
            height: view.bounds.height / 2 // bottom half
        )
        
        view.addSubview(blurView)
        view.addSubview(statusLabel)
        view.addSubview(alarmButton)
        view.addSubview(meterAsset)

    }

    // MARK: Camera Setup (YOUR CAMERA — UNCHANGED)
    func setupCamera() {

        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Camera error")
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String :
            kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self,
                                            queue: DispatchQueue(label: "cameraQueue"))

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
//        previewLayer.frame = CGRect(x:0,y:0,width:view.bounds.width,height:view.bounds.height/2)
        
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    func eyeAspectRatio(points: [CGPoint]) -> Double {

        guard points.count >= 6 else { return 1.0 }

        func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return sqrt(dx*dx + dy*dy)
        }

        let p2p6 = dist(points[1], points[5])
        let p3p5 = dist(points[2], points[4])
        let p1p4 = dist(points[0], points[3])

        return (p2p6 + p3p5) / (2.0 * p1p4)
    }
    
    func updateImages(imageIndex: Int) {
        meterAsset.image = meter[imageIndex]
    }
    
    func updateStatus(text: String, color: String) {
        self.statusLabel.text = text
        if color == "green" {
            self.statusLabel.textColor = .green
        }
        
        if color == "red" {
            self.statusLabel.textColor = .red
        }
    }
    @objc func stopAlarm() {
        alarmPlayer?.stop()
        realPlayer?.stop()
        stopCooldown = true
        alarmFlag = 0
        imageIndex = 0
        frameCount = 0
        updateImages(imageIndex: imageIndex)
        
        self.updateStatus(text: "Status: Awake", color: "green")

        DispatchQueue.main.asyncAfter(deadline: .now() + cooldownDur) {
            self.stopCooldown = false
        }
                
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer =
                CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .rightMirrored,
            options: [:]
        )

        do {

            let request = VNDetectFaceLandmarksRequest()
            try handler.perform([request])

            guard let results = request.results else { return }

            for face in results {

                guard let landmarks = face.landmarks,
                      let leftEye = landmarks.leftEye,
                      let rightEye = landmarks.rightEye else { continue }

                let leftEAR = eyeAspectRatio(points: leftEye.normalizedPoints)
                let rightEAR = eyeAspectRatio(points: rightEye.normalizedPoints)

                let avgEAR = (leftEAR + rightEAR) / 2.0

                // Store history
                earHistory.append(avgEAR)
                if earHistory.count > 60 { earHistory.removeFirst() }

                DispatchQueue.main.async {

                    // Visualization numbers
                    print("Ear & Eye Thresholds:", avgEAR)

                    // Draw EAR value on screen
                    self.view.subviews.forEach {
                        if $0.tag == 999 { $0.removeFromSuperview() }
                    }

                    let label = UILabel(frame: CGRect(x: self.view.bounds.midX-100, y: 730, width: 300, height: 50))
                    label.tag = 999
                    label.font = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
                    label.text =
                    String(format: "Eye Thresholds: %.3f", avgEAR)

                    self.view.addSubview(label)

                    // Drowsiness logic
                    if !self.stopCooldown {
                        if avgEAR < self.earClosedThreshold {
                            self.frameCount += 1
                        } else {
                            self.frameCount = 0
                        }
                        
                        if self.frameCount > 10 && self.drowsFlag{
                            print("DROWSY")
                            
                            self.updateStatus(text: "Status: Drowsy", color: "red")
                            
                            self.drowsFlag = false
                            self.imageIndex = self.imageIndex+1
                            
                            if self.imageIndex >= 4 {
                                self.imageIndex = 3
                            }
                            
                            self.updateImages(imageIndex: self.imageIndex)
                            
                            if self.alarmFlag<4 {
                                self.alarmPlayer?.play()
                                self.alarmFlag = self.alarmFlag+1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now()+1.0) {
                                self.drowsFlag = true
                            }
                        }
                        
                        if self.alarmFlag == 4 {
                            self.realPlayer?.play()
                        }
                    }
                    

//                    if self.frameCount > self.drowsyFrameThreshold {
//                        self.view.backgroundColor =
//                        UIColor.red.withAlphaComponent(0.3)
//                    } else {
//                        self.view.backgroundColor =
//                        UIColor.green.withAlphaComponent(0.2)
//                    }
                    
                }
            }

        } catch {
            print(error)
        }
    }
}


//    func captureOutput (_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
//        
//        let ci = CIImage(cvPixelBuffer: pixelBuffer)
//        let ui = UIImage(ciImage: ci)
//        let processed = wearyWrapper.processImage(ui)
//
//        }
//    
//    
//}
