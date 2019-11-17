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
	public var transform: simd_float4x4 = matrix_identity_float4x4
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
        
        let imageWidth = CGFloat(CVPixelBufferGetWidth(frame.capturedImage))//1920
        let imageHeight = CGFloat(CVPixelBufferGetHeight(frame.capturedImage))//1440
        
        let factorH = viewSize.height / imageWidth
        let factorW = viewSize.width / imageHeight
        let factor = CGFloat.minimum(factorH, factorW)
        
        return features.reduce(into: [QRResponse]()) { (responses, feature) in
            var cgpointsInImage = [feature.bottomLeft,feature.bottomRight,feature.topRight,feature.topLeft]
            
            
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
            
            
            // convert to View coor
            let cgpointsInView = cgpointsInImage.map { (cgpointInImage) -> CGPoint in
                let cgpointInView = CGPoint(x: (cgpointInImage.y - imageHeight * 0.5)*factor + viewSize.width * 0.5, y: (cgpointInImage.x - imageWidth * 0.5)*factor + viewSize.height * 0.5)
                return cgpointInView
            }
            
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
                
                
                if let worldT = hitResult.first?.worldTransform {
                    let position3D = simd_float3(worldT.columns.3.x, worldT.columns.3.y, worldT.columns.3.z)
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
                    points.append(position3D)
                }
            }
            if points.count < 4 {return}
            
            var planeT = computeBestFitPlane(points: points)
            let quat = simd_quatf(from: simd_float3(x: 0, y: 1, z: 0), to: simd_float3(x: 0, y: 0, z: 1))
            let normalT = matrix_float4x4(quat)
            let planeInXZ = simd_mul(planeT, normalT)
            
            
            // The plane is the xz-plane of the local coordinate space this transform defines.
            let bottomLeft = frame.camera.unprojectPoint(bottomLeftInView, ontoPlane: planeInXZ, orientation: orientation, viewportSize: viewSize) ?? bottomLeftRough
            let bottomRight = frame.camera.unprojectPoint(bottomRightInView, ontoPlane: planeInXZ, orientation: orientation, viewportSize: viewSize) ?? bottomRightRough
            let topRight = frame.camera.unprojectPoint(topRightInView, ontoPlane: planeInXZ, orientation: orientation, viewportSize: viewSize) ?? topRightRough
            let topLeft = frame.camera.unprojectPoint(topLeftInView, ontoPlane: planeInXZ, orientation: orientation, viewportSize: viewSize) ?? topLeftRough
            
            
            
            let positionRough = simd_float3(planeT.columns.3.x, planeT.columns.3.y, planeT.columns.3.z)
            let position = frame.camera.unprojectPoint(centerInView, ontoPlane: planeInXZ, orientation: orientation, viewportSize: viewSize) ?? positionRough
            planeT.columns.3 = simd_float4(position, 1)
            
            let size = CGSize(width: CGFloat(simd_distance(bottomLeft, bottomRight) * 0.5 + simd_distance(topLeft, topRight) * 0.5), height: CGFloat(simd_distance(bottomLeft, topLeft) * 0.5 + simd_distance(topRight, bottomRight) * 0.5))
            
            
            let response = QRResponse(feature: feature, position: position, transform: planeT, accuracy: .transformAndSizeApprox, size: size)
            
            responses.append(response)
        }
    }
    
    /// Return a list of QR Codes and transform, size
    ///
    /// - Parameter view: ARSCNView provided by ARKit
    /// - Parameter viewSize: ARSCNView's size
    /// - Returns: A QRResponse array containing the estimated transform, feature and accuracy
    @available(iOS 12.0, *)
    public static func findQRTransform(view:ARSCNView ,viewSize:CGSize) -> [QRResponse] {
        guard let capturedImage = view.session.currentFrame?.capturedImage else { return [QRResponse]() }
        let features = QRScanner.findQR(in: capturedImage)
        let imageWidth = CGFloat(CVPixelBufferGetWidth(capturedImage))//1920
        let imageHeight = CGFloat(CVPixelBufferGetHeight(capturedImage))//1440
        
        let factorH = viewSize.height / imageWidth
        let factorW = viewSize.width / imageHeight
        let factor = CGFloat.minimum(factorH, factorW)
        
        
        
        return features.reduce(into: [QRResponse]()) { (responses, feature) in
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
            
            // convert to View coor
            let cgpointsInView = cgpointsInImage.map { (cgpointInImage) -> CGPoint in
                let cgpointInView = CGPoint(x: (cgpointInImage.y - imageHeight * 0.5)*factor + viewSize.width * 0.5, y: (cgpointInImage.x - imageWidth * 0.5)*factor + viewSize.height * 0.5)
                return cgpointInView
            }
            
            if cgpointsInView.count < 9 {return}
            
            let bottomLeftInView = cgpointsInView[0]
            let bottomRightInView = cgpointsInView[1]
            let topRightInView = cgpointsInView[2]
            let topLeftInView = cgpointsInView[3]
            let centerInView = cgpointsInView[8]
            
            // rough position by hitTest
            var bottomLeftRough = simd_float3(repeating: 0)
            var bottomRightRough = simd_float3(repeating: 0)
            var topRightRough = simd_float3(repeating: 0)
            var topLeftRough = simd_float3(repeating: 0)
            
            
            let points = cgpointsInView.reduce(into: [simd_float3]()) { (points, cgpointInView) in
                let hitResult = view.hitTest(cgpointInView,
                                              types: [.estimatedVerticalPlane, .estimatedHorizontalPlane, .existingPlane, .featurePoint, .existingPlaneUsingExtent, .existingPlaneUsingGeometry])
                if let worldT = hitResult.first?.worldTransform {
                    let position3D = simd_float3(worldT.columns.3.x, worldT.columns.3.y, worldT.columns.3.z)
                    if cgpointInView == bottomLeftInView {
                        bottomLeftRough = position3D
                    }
                    if cgpointInView == bottomRightInView {
                        bottomRightRough = position3D
                    }
                    if cgpointInView == topRightInView {
                        topRightRough = position3D
                    }
                    if cgpointInView == topLeftInView {
                        topLeftRough = position3D
                    }
                    points.append(position3D)
                }
            }
            // maybe no enough featurePoint, hitTest will be less than 4
            if points.count < 4 {return}
            
            var planeT = computeBestFitPlane(points: points)
            let positionRough = simd_float3(planeT.columns.3.x, planeT.columns.3.y, planeT.columns.3.z)
            
            
            
            let quat = simd_quatf(from: simd_float3(x: 0, y: 1, z: 0), to: simd_float3(x: 0, y: 0, z: 1))
            let normalT = matrix_float4x4(quat)
            let planeInXZ = simd_mul(planeT, normalT)
            
            // The plane is the xz-plane of the local coordinate space this transform defines.
            let bottomLeft = view.unprojectPoint(bottomLeftInView, ontoPlane: planeInXZ) ?? bottomLeftRough
            let bottomRight = view.unprojectPoint(bottomRightInView, ontoPlane: planeInXZ) ?? bottomRightRough
            let topRight = view.unprojectPoint(topRightInView, ontoPlane: planeInXZ) ?? topRightRough
            let topLeft = view.unprojectPoint(topLeftInView, ontoPlane: planeInXZ) ?? topLeftRough
            
            
            
            let position = view.unprojectPoint(centerInView, ontoPlane: planeInXZ) ?? positionRough
            planeT.columns.3 = simd_float4(position, 1)
            
            let size = CGSize(width: CGFloat(simd_distance(bottomLeft, bottomRight) * 0.5 + simd_distance(topLeft, topRight) * 0.5), height: CGFloat(simd_distance(bottomLeft, topLeft) * 0.5 + simd_distance(topRight, bottomRight) * 0.5))
            
            let response = QRResponse(feature: feature, position: position, transform: planeT, accuracy: .transformAndSizeApprox, size: size)
            
            responses.append(response)
        }
    }
    static func computeBestFitPlane(points: [simd_float3]) -> simd_float4x4 {
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
        
        let quat = simd_quatf(from: simd_float3(x: 0, y: 0, z: 1), to: normal)
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
                let hitResult = frame.hitTest(posInFrame,
                    types: [.estimatedVerticalPlane, .estimatedHorizontalPlane, .existingPlane, .featurePoint])
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
}
