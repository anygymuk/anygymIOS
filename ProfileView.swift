//
//  ProfileView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .poppins(.regular, size: 80)
                        .foregroundColor(.blue)
                    
                    if let user = authManager.user {
                        Text(user.name ?? "User")
                            .poppins(.semibold, size: 22)
                        
                        if let email = user.email {
                            Text(email)
                                .poppins(.regular, size: 14)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("User")
                            .poppins(.semibold, size: 22)
                    }
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Logout Button
                Button(action: {
                    authManager.logout()
                }) {
                    Text("Log Out")
                        .poppins(.semibold, size: 16)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
}

