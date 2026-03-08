//
//  cameraViewwrap.swift
//  weary-tracker3
//
//  Created by Leo Nguyen on 3/7/26.
//

import SwiftUI

struct CameraViewRepresentable: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // No updates needed for now
    }
}
