//
//  ContentView.swift
//  weary-tracker3
//
//  Created by Leo Nguyen on 3/7/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraViewRepresentable()
            .navigationBarTitle("Weary Tracker")
    }
}

#Preview {
    ContentView()
}
