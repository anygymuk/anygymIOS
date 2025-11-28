//
//  PoppinsFont.swift
//  AnyGym
//
//  Shared Poppins font extension for the entire app
//

import SwiftUI
import UIKit

// MARK: - Poppins Font Extension
extension Font {
    static func poppins(_ weight: PoppinsWeight = .regular, size: CGFloat) -> Font {
        let fontName: String
        switch weight {
        case .regular:
            fontName = "Poppins-Regular"
        case .medium:
            fontName = "Poppins-Medium"
        case .semibold:
            fontName = "Poppins-SemiBold"
        case .bold:
            fontName = "Poppins-Bold"
        }
        
        // Check if font is available, fallback to system font if not
        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        } else {
            // Fallback to system font with equivalent weight
            let systemWeight: Font.Weight
            switch weight {
            case .regular:
                systemWeight = .regular
            case .medium:
                systemWeight = .medium
            case .semibold:
                systemWeight = .semibold
            case .bold:
                systemWeight = .bold
            }
            return Font.system(size: size, weight: systemWeight)
        }
    }
    
    enum PoppinsWeight {
        case regular
        case medium
        case semibold
        case bold
    }
}

// MARK: - View Modifier for Poppins
struct PoppinsFont: ViewModifier {
    var weight: Font.PoppinsWeight = .regular
    var size: CGFloat = 16
    
    func body(content: Content) -> some View {
        content.font(.poppins(weight, size: size))
    }
}

extension View {
    func poppins(_ weight: Font.PoppinsWeight = .regular, size: CGFloat = 16) -> some View {
        self.modifier(PoppinsFont(weight: weight, size: size))
    }
}

