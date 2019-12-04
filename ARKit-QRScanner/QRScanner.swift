//
//  QRScanner.swift
//  ARKit-QRScanner
//
//  Created by Max Cobb on 11/15/18.
//  Copyright © 2018 Max Cobb. All rights reserved.
//

import ARKit

public enum QRPositionAccruacy {
	case guess
	case distanceApprox
    case transformAndSizeApprox//with size
}

public struct QRResponse {
	public var feature: CIQRCodeFeature
	public var position: simd_float3
	public var transform: simd_float4x4 = matrix_identity_float4x4//QRCode in XZ plane
    public var accuracy: QRPositionAccruacy
    public var size:CGSize = CGSize(width: 0, height: 0)
}


public struct QRScanner {
	/// Return a list of QR Codes and transform, size
	///
	/// - Parameter frame: ARFrame provided by ARKit
    /// - Parameter orientation: UIInterfaceOrientation, ARSCNView's oriention
    /// - Parameter viewSize: ARSCNView's size
	/// - Returns: A QRResponse array containing the estimated transform, feature and accuracy
    @available(iOS 12.0, *)
    public static func findQRTransform(in frame: ARFrame, orientation: UIInterfaceOrientation,viewSize: CGSize) -> [QRResponse] {
        let features = QRScanner.findQR(in: frame.capturedImage)
        
        let (factor,imageWidth,imageHeight) = scaleFactor(image:frame.capturedImage, aspectFillIn: viewSize)
        
        return features.reduce(into: [QRResponse]()) { (responses, feature) in
            let cgpointsInImage = generateNinePointsInImage(from: feature)
            // convert to View coor
            let cgpointsInView = generateNinePointsInView(from: cgpointsInImage, imageWidth: imageWidth, imageHeight: imageHeight, scaleFactor: factor, viewSize: viewSize)
            
            if cgpointsInView.count < 9 {return}
            
            let bottomLeftInView = cgpointsInView[0]
            let bottomRightInView = cgpointsInView[1]
            let topRightInView = cgpointsInView[2]
            let topLeftInView = cgpointsInView[3]
            let centerInView = cgpointsInView[8]
            
            var bottomLeftRough = simd_float3(repeating: 0)
            var bottomRightRough = simd_float3(repeating: 0)
            var topRightRough = simd_float3(repeating: 0)
            var topLeftRough = simd_float3(repeating: 0)
            
            let points = cgpointsInImage.reduce(into: [simd_float3]()) { (points, cgpoint) in
                let newPoint = CGPoint(x: cgpoint.x/imageWidth, y: (imageHeight-cgpoint.y)/imageHeight);
                let hitResult = frame.hitTest(newPoint,
                                              types: [.estimatedVerticalPlane, .estimatedHorizontalPlane, .existingPlane, .featurePoint, .existingPlaneUsingExtent, .existingPlaneUsingGeometry])
                
                // TODO: right now, just use the first result and ignore their type;
                // next step, we can put same type of results in different groups, to get different planes, then choose the best plane.
                if let worldT = hitResult.first?.worldTransform {
                    let position3D = simd_float3(worldT.columns.3.x, worldT.columns.3.y, worldT.columns.3.z)
                    points.append(position3D)
                    
                    if cgpoint == feature.bottomLeft {
                        bottomLeftRough = position3D
                    }
                    if cgpoint == feature.bottomRight {
                        bottomRightRough = position3D
                    }
                    if cgpoint == feature.topRight {
                        topRightRough = position3D
                    }
                    if cgpoint == feature.topLeft {
                        topLeftRough = position3D
                    }
                    
                }
            }
            if points.count < 4 {return}
            
            var planeT = computeBestFitPlaneInXZ(points: points)
            let positionRough = simd_float3(planeT.columns.3.x, planeT.columns.3.y, planeT.columns.3.z)
            
            // unproject the screen point to 3D plane, to get accruacy size and position
            // The plane is the xz-plane of the local coordinate space this transform defines.
            let bottomLeft = frame.camera.unprojectPoint(bottomLeftInView, ontoPlane: planeT, orientation: orientation, viewportSize: viewSize) ?? bottomLeftRough
            let bottomRight = frame.camera.unprojectPoint(bottomRightInView, ontoPlane: planeT, orientation: orientation, viewportSize: viewSize) ?? bottomRightRough
            let topRight = frame.camera.unprojectPoint(topRightInView, ontoPlane: planeT, orientation: orientation, viewportSize: viewSize) ?? topRightRough
            let topLeft = frame.camera.unprojectPoint(topLeftInView, ontoPlane: planeT, orientation: orientation, viewportSize: viewSize) ?? topLeftRough
            // center
            let position = frame.camera.unprojectPoint(centerInView, ontoPlane: planeT, orientation: orientation, viewportSize: viewSize) ?? positionRough
            planeT.columns.3 = simd_float4(position, 1)
            
            let size = CGSize(width: CGFloat(simd_distance(bottomLeft, bottomRight) * 0.5 + simd_distance(topLeft, topRight) * 0.5), height: CGFloat(simd_distance(bottomLeft, topLeft) * 0.5 + simd_distance(topRight, bottomRight) * 0.5))
            
            
            let response = QRResponse(feature: feature, position: position, transform: planeT, accuracy: .transformAndSizeApprox, size: size)
            
            responses.append(response)
        }
    }
    
    /// Return a list of QR Codes and transform, size
    /// - Parameter view: ARSCNView provided by ARKit
    /// - Returns: A QRResponse array containing the estimated transform, feature and accuracy
    @available(iOS 12.0, *)
    public static func findQRTransform(view:ARSCNView) -> [QRResponse] {
        guard let frame = view.session.currentFrame else { return [QRResponse]() }
        
        // orientation and size, must be getten in mainThread
        var orientation = UIInterfaceOrientation.portrait
        var size = CGSize(width: 0, height: 0)
        if Thread.isMainThread {
            orientation = UIApplication.shared.statusBarOrientation
            size = view.bounds.size
        } else {
            DispatchQueue.main.sync {
                orientation = UIApplication.shared.statusBarOrientation
                size = view.bounds.size
            }
        }
        return findQRTransform(in: frame, orientation: orientation, viewSize: size)
    }
    
    private static func computeBestFitPlaneInXZ(points: [simd_float3]) -> simd_float4x4 {
        var result = matrix_identity_float4x4
        if points.count < 1 {
            return result
        }
        var normal = simd_float3(repeating: 0)
        var center = simd_float3(repeating: 0)
        var second = points.last!
        
        for vector in points {
            normal.x += (second.z + vector.z) * (second.y - vector.y)
            normal.y += (second.x + vector.x) * (second.z - vector.z)
            normal.z += (second.y + vector.y) * (second.x - vector.x)
            second = vector
            
            center += (vector / Float(points.count))
        }
        
        normal = simd_normalize(normal)
        
        let quat = simd_quatf(from: simd_float3(x: 0, y: 1, z: 0), to: normal)
        let normalT = matrix_float4x4(quat)
        result = simd_mul(result, normalT)
        
        
        result.columns.3 = simd_float4(center, 1)
        return result
    }
    public static func findQR(in frame: ARFrame) -> [QRResponse] {
            let features = QRScanner.findQR(in: frame.capturedImage)
            let camTransform = frame.camera.transform
            let cameraPosition = SCNVector3(
                camTransform.columns.3.x,
                camTransform.columns.3.y,
                camTransform.columns.3.z
            )
            return features.map { feature -> QRResponse in
                let posInFrame = CGPoint(
                    x: (feature.bottomLeft.x + feature.topRight.x) / 2,
                    y: (feature.bottomLeft.y + feature.topRight.y) / 2
                )
                var types = ARHitTestResult.ResultType(rawValue: 0)
                types = [.estimatedHorizontalPlane, .existingPlane, .featurePoint]
                
                
                let hitResult = frame.hitTest(posInFrame,
                    types: types)
                // I'm assuming the qr code is about 0.5m in front of the camera for now
                // if there is no better estimate
                // distance seems to be the only reliable metric for this
                let distanceInfront = hitResult.first?.distance ?? 0.5

                let camForward = SCNVector3(
                    camTransform.columns.2.x,
                    camTransform.columns.2.y,
                    camTransform.columns.2.z
                ).setLength(Float(-distanceInfront))

                return QRResponse(feature: feature, position: simd_float3(
                    cameraPosition.x + camForward.x,
                    cameraPosition.y + camForward.y,
                    cameraPosition.z + camForward.z
                ), accuracy: hitResult.isEmpty ? .guess : .distanceApprox)
                // The transform matrix is always coming back with tiny numbers
    //            let col3 = firstResult.worldTransform.columns.3
    //            return SCNVector3(
    //                col3.x,
    //                col3.y,
    //                col3.z
    //            )
            }
        }
	/// Return just the QR code information given a [CVPixelBuffer](apple-reference-documentation://hsVf8OXaJX)
	///
	/// - Parameter buffer: [CVPixelBuffer](apple-reference-documentation://hsVf8OXaJX), provided by ARframe
	/// - Returns: A CoreImage QR code feature
	public static func findQR(in buffer: CVPixelBuffer) -> [CIQRCodeFeature] {
		return QRScanner.findQR(in: CIImage(cvPixelBuffer: buffer))
	}

	/// Return just the QR code information given a [CVPixelBuffer](apple-reference-documentation://hsVf8OXaJX)
	///
	/// - Parameter buffer: Image of type CIImage from any source
	/// - Returns: A CoreImage QR code feature
	public static func findQR(in image: CIImage) -> [CIQRCodeFeature] {
		guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil) else {
			return []
		}
		return detector.features(in: image) as? [CIQRCodeFeature] ?? []
	}
    
    private static func generateNinePointsInImage(from feature:CIQRCodeFeature) -> [CGPoint] {
        var cgpointsInImage = [feature.bottomLeft,feature.bottomRight,feature.topRight,feature.topLeft]
        
        // more point by interpolation
        let bottomMiddle = CGPoint(x: (feature.bottomLeft.x + feature.bottomRight.x) * 0.5, y: (feature.bottomLeft.y + feature.bottomRight.y) * 0.5)
        cgpointsInImage.append(bottomMiddle)
        
        let rightMiddle = CGPoint(x: (feature.topRight.x + feature.bottomRight.x) * 0.5, y: (feature.topRight.y + feature.bottomRight.y) * 0.5)
        cgpointsInImage.append(rightMiddle)
        
        let topMiddle = CGPoint(x: (feature.topRight.x + feature.topLeft.x) * 0.5, y: (feature.topRight.y + feature.topLeft.y) * 0.5)
        cgpointsInImage.append(topMiddle)
        
        let leftMiddle = CGPoint(x: (feature.bottomLeft.x + feature.topLeft.x) * 0.5, y: (feature.bottomLeft.y + feature.topLeft.y) * 0.5)
        cgpointsInImage.append(leftMiddle)
        
        let center = CGPoint(x: (feature.bottomLeft.x + feature.topLeft.x + feature.topRight.x + feature.bottomRight.x) * 0.25, y: (feature.bottomLeft.y + feature.topLeft.y + feature.topRight.y + feature.bottomRight.y) * 0.25)
        cgpointsInImage.append(center)
        
        return cgpointsInImage
    }
    
    private static func generateNinePointsInView(from cgpointsInImage:[CGPoint], imageWidth:CGFloat, imageHeight:CGFloat,scaleFactor:CGFloat,viewSize:CGSize) -> [CGPoint] {
        
        // convert to View coor
        let cgpointsInView = cgpointsInImage.map { (cgpointInImage) -> CGPoint in
            let cgpointInView = CGPoint(x: (cgpointInImage.y - imageHeight * 0.5)*scaleFactor + viewSize.width * 0.5, y: (cgpointInImage.x - imageWidth * 0.5)*scaleFactor + viewSize.height * 0.5)
            return cgpointInView
        }
        
        return cgpointsInView
    }
    private static func scaleFactor(image:CVPixelBuffer ,aspectFillIn viewSize:CGSize) -> (CGFloat,CGFloat,CGFloat) {
       
        let imageWidth = CGFloat(CVPixelBufferGetWidth(image))//1920
        let imageHeight = CGFloat(CVPixelBufferGetHeight(image))//1440
        
        let factorH = viewSize.height / imageWidth
        let factorW = viewSize.width / imageHeight
        let factor = CGFloat.minimum(factorH, factorW)
        
        return (factor,imageWidth,imageHeight)
    }
}
