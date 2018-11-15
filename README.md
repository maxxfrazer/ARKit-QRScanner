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
		let (qrCodes, pos) = findQR(in: frame)
		for code in qrCodes {
			print(code.messageString ?? "no message found")
		}
	}
}

```
The messageString can be text, URL, or any other commands following the standards outlined here:
[Barcode Content Standards](https://github.com/zxing/zxing/wiki/Barcode-Contents)