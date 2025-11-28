# AnyGym iOS App

iOS application for the AnyGym platform with Auth0 authentication.

## Setup Instructions

### 1. Create Xcode Project

You have two options to create the Xcode project:

#### Option A: Using XcodeGen (Recommended)

1. Install XcodeGen if you haven't already:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open AnyGym.xcodeproj
   ```

#### Option B: Manual Setup in Xcode

1. Open Xcode and create a new project:
   - Choose "App" template
   - Product Name: `AnyGym`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Bundle Identifier: `com.anygym.app`

2. Replace the default files with the files in this directory

3. Add Auth0 SDK:
   - File → Add Packages...
   - Enter: `https://github.com/auth0/Auth0.swift`
   - Select version 2.0.0 or later
   - Add to target: `AnyGym`

4. Copy `Info.plist` settings to your project's Info.plist

### 2. Install Dependencies

This project uses Swift Package Manager. The Auth0 SDK will be added automatically when you open the project in Xcode (if using Option B) or is already configured (if using Option A).

### 2. Configure Auth0

1. Create an Auth0 account at [auth0.com](https://auth0.com) if you don't have one
2. Create a new application in your Auth0 dashboard
3. Set the application type to "Native"
4. Configure the following:
   - **Allowed Callback URLs**: `{YOUR_BUNDLE_IDENTIFIER}://{YOUR_AUTH0_DOMAIN}/ios/{YOUR_BUNDLE_IDENTIFIER}/callback`
   - **Allowed Logout URLs**: `{YOUR_BUNDLE_IDENTIFIER}://{YOUR_AUTH0_DOMAIN}/ios/{YOUR_BUNDLE_IDENTIFIER}/callback`

### 3. Update Configuration

Update the `Info.plist` file with your Auth0 credentials:

- Replace `YOUR_AUTH0_DOMAIN` with your Auth0 domain (e.g., `your-tenant.auth0.com`)
- Replace `YOUR_AUTH0_CLIENT_ID` with your Auth0 client ID

Alternatively, you can create a `Config.plist` file for better security (and add it to `.gitignore`).

### 4. Update Bundle Identifier

1. Open the project in Xcode
2. Select your target
3. Update the Bundle Identifier to match your Auth0 callback URL configuration

### 5. Update API Audience (Optional)

If you're using an API with Auth0, update the audience in `AuthManager.swift`:

```swift
.audience("https://your-api-audience.com")
```

## Project Structure

- `AnyGymApp.swift` - Main app entry point
- `ContentView.swift` - Root view that switches between login and main views
- `AuthManager.swift` - Auth0 authentication manager
- `LoginView.swift` - Login screen
- `MainView.swift` - Main app content (shown after authentication)
- `Info.plist` - App configuration and Auth0 settings

## Features

- ✅ Auth0 authentication integration
- ✅ Secure credential storage
- ✅ User profile display
- ✅ Logout functionality
- ✅ Modern SwiftUI interface

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.9+

## Next Steps

1. Set up your Auth0 account and configure the app
2. Customize the UI to match your brand
3. Add your app's main features to `MainView.swift`
4. Implement additional Auth0 features as needed (e.g., social logins, MFA)

