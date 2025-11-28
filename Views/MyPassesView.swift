//
//  MyPassesView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI

struct MyPassesView: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "rectangle.stack.fill")
                .poppins(.regular, size: 60)
                .foregroundColor(.gray)
            Text("My Passes")
                .poppins(.semibold, size: 22)
                .padding(.top, 16)
            Text("Your passes will appear here")
                .poppins(.regular, size: 14)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

#Preview {
    MyPassesView()
}

