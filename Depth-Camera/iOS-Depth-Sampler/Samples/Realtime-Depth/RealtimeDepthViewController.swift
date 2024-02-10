//
//  RealtimeDepthViewController.swift
//
//  Created by Shuichi Tsutsumi on 2018/08/20.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import UIKit
import MetalKit
import AVFoundation
import CoreImage
import Accelerate
import AVFoundation

class RealtimeDepthViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var mtkView: MTKView!
    @IBOutlet weak var filterSwitch: UISwitch!
    @IBOutlet weak var disparitySwitch: UISwitch!
    @IBOutlet weak var equalizeSwitch: UISwitch!

    private var videoCapture: VideoCapture!
    var currentCameraType: CameraType = .back(true)
    private let serialQueue = DispatchQueue(label: "com.shu223.iOS-Depth-Sampler.queue")

    private var renderer: MetalRenderer!
    private var depthImage: CIImage?
    private var currentDrawableSize: CGSize!
    
    private var videoImage: CIImage?
    
    private var sumOfAverageDepths: CGFloat = 0.0
    private var depthUpdateCount: CGFloat = 0.0

    var player: AVAudioPlayer?

    func playSound() {
        guard let path = Bundle.main.path(forResource: "beep-04", ofType:"mp3") else {
            return }
        let url = URL(fileURLWithPath: path)
        print("playing sound")
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    func cropAndAverageDepth(image: CIImage?, cropRect: CGRect) -> Float? {
        guard let image = image else {
            print("Image is nil")
            return nil
        }

        // Crop the CIImage
        let croppedImage = image.cropped(to: cropRect)
        
        
        // Convert CIImage to CGImage for processing
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else {
            print("Failed to create CGImage from depth data map")
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()

        // Prepare to calculate the average depth using Accelerate
        var format = vImage_CGImageFormat(bitsPerComponent: 8,
                                          bitsPerPixel: 8,
                                          colorSpace:  Unmanaged.passRetained(colorSpace),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          version: 0,
                                          decode: nil,
                                          renderingIntent: .defaultIntent)
        
        var error: vImage_Error
        var inBuffer = vImage_Buffer()
        
        error = vImageBuffer_InitWithCGImage(&inBuffer, &format, nil, cgImage, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        if error != kvImageNoError {
            print("Error in vImageBuffer_InitWithCGImage: \(error)")
            return nil
        }
        
        // Use Accelerate to calculate the average value
        let totalPixels = Int(inBuffer.height) * Int(inBuffer.width)
        var histogramBins = [UInt](repeating: 0, count: 256)
        var histogram = [vImagePixelCount](repeating: 0, count: histogramBins.count)
        
        error = vImageHistogramCalculation_Planar8(&inBuffer, &histogram, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        if error != kvImageNoError {
            print("Error in vImageHistogramCalculation_Planar8: \(error)")
            return nil
        }
        
        let sum = histogram.enumerated().reduce(0) { $0 + UInt($1.element) * UInt($1.offset) }
        let averageDepth = Float(sum) / Float(totalPixels)
        
        // Cleanup
        free(inBuffer.data)
        
        return averageDepth
    }
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        disparitySwitch.isOn = true // Enable disparity by default
        equalizeSwitch.isOn = true  // Enable histogram equalization by default
        
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        mtkView.backgroundColor = UIColor.clear
        mtkView.delegate = self
        renderer = MetalRenderer(metalDevice: device, renderDestination: mtkView)
        currentDrawableSize = mtkView.currentDrawable!.layer.drawableSize

        videoCapture = VideoCapture(cameraType: currentCameraType,
                                    preferredSpec: nil,
                                    previewContainer: previewView.layer)
        
        videoCapture.syncedDataBufferHandler = { [weak self] videoPixelBuffer, depthData, face in
            guard let self = self else { return }
            
            self.videoImage = CIImage(cvPixelBuffer: videoPixelBuffer)

            var useDisparity: Bool = true
            var applyHistoEq: Bool = true
            DispatchQueue.main.sync(execute: {
                useDisparity = self.disparitySwitch.isOn
                applyHistoEq = self.equalizeSwitch.isOn
            })
            
            
            self.serialQueue.async {
                guard let depthData = useDisparity ? depthData?.convertToDisparity() : depthData else { return }
                
                guard let ciImage = depthData.depthDataMap.transformedImage(targetSize: self.currentDrawableSize, rotationAngle: 0) else { return }
                self.depthImage = applyHistoEq ? ciImage.applyingFilter("YUCIHistogramEqualization") : ciImage
                //                print("depthImage: \(self.depthImage)")
                //                let imageSize = self.depthImage?.extent.size
                //
                //                // You can access the width and height like this
                //                let width = imageSize?.width
                //                let height = imageSize?.height
                let rect: CGRect = CGRect(x: 368, y: 505, width: 100, height: 100)
                
                // If you need to print or use the size
                //                print("Image Width: \(width), Image Height: \(height)")
                let averageDepth = self.cropAndAverageDepth(image: self.depthImage, cropRect: rect)
                print("Average depth: \(averageDepth)")
//                if (averageDepth ?? 0 > 200) {
//                    self.playSound()
//                }
                if let avgDepth = averageDepth {
                    self.sumOfAverageDepths += CGFloat(avgDepth)
                    self.depthUpdateCount += 1
                }
                
                // Check if we have reached 10 updates
                if self.depthUpdateCount == 10 {
                    let runningAverageDepth = self.sumOfAverageDepths / CGFloat(self.depthUpdateCount)
                    print("Running Average Depth: \(runningAverageDepth)")
                    
                    // Reset for the next cycle
                    self.depthUpdateCount = 0
                    self.sumOfAverageDepths = 0
                    
                    // Check your condition with the running average
                    if runningAverageDepth > 200 {
                        self.playSound()
                    }
                }
            }
            
        }
        videoCapture.setDepthFilterEnabled(filterSwitch.isOn)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let videoCapture = videoCapture else {return}
        videoCapture.startCapture()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let videoCapture = videoCapture else {return}
        videoCapture.resizePreview()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        guard let videoCapture = videoCapture else {return}
        videoCapture.imageBufferHandler = nil
        videoCapture.stopCapture()
        mtkView.delegate = nil
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Actions
    
    @IBAction func cameraSwitchBtnTapped(_ sender: UIButton) {
        switch currentCameraType {
        case .back:
            currentCameraType = .front(true)
        case .front:
            currentCameraType = .back(true)
        }
        videoCapture.changeCamera(with: currentCameraType)
    }
    
    @IBAction func filterSwitched(_ sender: UISwitch) {
        videoCapture.setDepthFilterEnabled(sender.isOn)
    }
}

extension RealtimeDepthViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        currentDrawableSize = size
    }
    
    func draw(in view: MTKView) {
        if let image = depthImage {
            renderer.update(with: image)
        }
    }
}
