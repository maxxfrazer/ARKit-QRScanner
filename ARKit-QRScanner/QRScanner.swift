//
//  QRScanner.swift
//  ARKit-QRScanner
//
//  Created by Max Cobb on 11/15/18.
//  Copyright © 2018 Max Cobb. All rights reserved.
//

import ARKit

public struct QRScanner {
	/// Return a list of QR Codes and positions
	///
	/// - Parameter frame: ARFrame provided by ARKit
	/// - Returns: A Pair of ([[CIQRCodeFeature](apple-reference-documentation://hsBkcicVHP)], [SCNVector3])
	public static func findQR(in frame: ARFrame) -> ([CIQRCodeFeature], [SCNVector3]) {
		let features = QRScanner.findQR(in: frame.capturedImage)
		let camTransform = frame.camera.transform
		let cameraPosition = SCNVector3(
			camTransform.columns.3.x,
			camTransform.columns.3.y,
			camTransform.columns.3.z
		)
		let qrPositions = features.map { (feature) -> SCNVector3 in
			let posInFrame = CGPoint(
				x: (feature.bottomLeft.x + feature.topRight.x) / 2,
				y: (feature.bottomLeft.y + feature.topRight.y) / 2
			)
			let hitResult = frame.hitTest(posInFrame, types: ARHitTestResult.ResultType.featurePoint)
			guard let col3 = hitResult.first?.worldTransform.columns.3 else {
				// I'm assuming the qr code is about 0.3m in front of the camera for now
				let camForward = SCNVector3(camTransform.columns.2.x,
																		camTransform.columns.2.y,
																		camTransform.columns.2.z).setLength(0.3)
				return SCNVector3(
					cameraPosition.x + camForward.x,
					cameraPosition.y + camForward.y,
					cameraPosition.z + camForward.z
				)
			}
			return SCNVector3(
				col3.x,
				col3.y,
				col3.z
			)
		}
		return (features, qrPositions)
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
