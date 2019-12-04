# ARKit-QRScanner

This class `QRScanner` contains a few functions for scanning QR codes with ARKit.
The positioning isn't working quite right yet, open to contributions to get it to work!

Include this pod in your project:

`pod 'QRScanner', :git => 'https://github.com/maxxfrazer/ARKit-QRScanner.git'`

Example use (not suggested to run every frame as in example though):

```
func session(_ session: ARSession, didUpdate frame: ARFrame) {
	// background thread improves the lag a bit
	DispatchQueue.global(qos: .background).async {
		let qrResponses = QRScanner.findQR(in: frame)
		for response in qrResponses {
			print(response.feature.messageString ?? "no message found")
		}
	}
}

```
or 
```swift
func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    // background thread improves the lag a bit
    DispatchQueue.global(qos: .background).async {
        let qrResponses = QRScanner.findQRTransform(view: self.sceneView)
        for response in qrResponses {
            print(response.feature.messageString ?? "no message found")

            let planeNode = SCNNode(geometry: SCNBox(width: response.size.width, height: 0.001, length: response.size.height, chamferRadius: 0))
            planeNode.simdTransform = response.transform // qrcode in transform's xz plane
            planeNode.geometry?.firstMaterial?.diffuse.contents = UIColor.green
            planeNode.geometry?.firstMaterial?.isDoubleSided = false
            self.sceneView.scene.rootNode.addChildNode(planeNode)

        }
    }
    
}
```
The messageString can be text, URL, or any other commands following the standards outlined here:
[Barcode Content Standards](https://github.com/zxing/zxing/wiki/Barcode-Contents)
