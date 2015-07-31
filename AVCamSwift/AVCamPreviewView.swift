//
//  AVCamPreviewView.swift
//  AVCamSwift
//
//  Created by sunset on 14-11-18.
//  Copyright (c) 2014年 sunset. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation


class AVCamPreviewView: UIView{
    
    var session: AVCaptureSession? {
        get{
            return (self.layer as! AVCaptureVideoPreviewLayer).session;
        }
        set(session){
            (self.layer as! AVCaptureVideoPreviewLayer).session = session;
        }
    };
    
    
    
    override class func layerClass() ->AnyClass{
        return AVCaptureVideoPreviewLayer.self;
    }
    
    
    
    
    
    
    
    
    
}
