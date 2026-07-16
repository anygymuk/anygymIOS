# Testing Offline Pass Access

This document outlines test scenarios for the local storage and offline pass access feature.

## Test Scenarios

### 1. Online Pass Generation and Storage
**Steps:**
1. Ensure device has internet connection
2. Navigate to gym map and select a gym
3. Generate a pass for the selected gym
4. Verify pass is created successfully
5. Navigate to "My Passes" tab

**Expected Results:**
- Pass appears in "My Passes" view
- Pass is visible in the bottom sheet overlay on map
- QR code is displayed
- Pass data is saved to UserDefaults
- QR code image is cached to Documents directory

**Verification:**
- Check console logs for: "✅ Active pass saved to local storage"
- Check console logs for: "✅ QR code cached for pass ID"

---

### 2. Offline Pass Retrieval
**Steps:**
1. Generate a pass while online (follow Test Scenario 1)
2. Enable Airplane mode or disconnect from WiFi
3. Force close and reopen the app
4. Navigate to "My Passes" tab

**Expected Results:**
- Orange offline indicator banner displays: "Viewing cached passes (offline)"
- Active pass loads from local storage
- Cached QR code displays correctly
- Pass details (gym name, address, expiration) all display correctly

**Verification:**
- Check console logs for: "📱 Loaded active pass from local storage (offline mode)"
- Check console logs for: "📱 Loaded cached QR image for pass ID"
- Verify no "Error fetching passes" messages

---

### 3. Online Sync After Offline Period
**Steps:**
1. Start in offline mode with cached pass
2. Re-enable internet connection
3. Pull down to refresh or restart app
4. Check "My Passes" tab

**Expected Results:**
- Offline indicator disappears
- Latest pass data fetched from API
- Pass history is updated from API
- Local storage is updated with fresh data

**Verification:**
- Check console logs for: "Active pass loaded: [gym name]"
- Check console logs for: "✅ Pass history saved to local storage"
- Verify `isOffline` flag is false

---

### 4. Pass Expiration Cleanup
**Steps:**
1. Generate a pass with short expiration (or manually test with expired pass in storage)
2. Wait for pass to expire OR modify validUntil date in UserDefaults to past date
3. Restart the app
4. Check if expired pass is cleaned up

**Expected Results:**
- If pass is in history: Active pass is removed from storage
- QR code cache is deleted
- activePass is set to nil

**Verification:**
- Check console logs for: "⚠️ Active pass ID [id] has expired"
- Check console logs for: "✅ Pass ID [id] is in history, removing from active storage"
- Check console logs for: "✅ Cached QR image deleted for pass ID [id]"

---

### 5. Multiple Pass History Storage
**Steps:**
1. Generate passes at multiple gyms (while online)
2. Check "My Passes" tab for pass history section
3. Enable offline mode
4. Restart app
5. Check pass history

**Expected Results:**
- All historical passes are visible offline
- Pass history is grouped by gym chain
- Each pass displays correct gym information

**Verification:**
- Check console logs for: "✅ Pass history saved to local storage: [count] passes"
- Check console logs for: "📱 Loaded [count] passes from local storage (offline mode)"

---

### 6. QR Code Caching
**Steps:**
1. Generate a new pass (online)
2. Wait for QR code to load
3. Navigate away and back to "My Passes"
4. Enable offline mode
5. View the pass again

**Expected Results:**
- QR code loads instantly from cache (no loading spinner)
- QR code displays correctly offline

**Verification:**
- Check app's Documents directory for file: `qr_[passId].png`
- Verify file exists and contains valid image data

---

### 7. Network Transition Handling
**Steps:**
1. Start online with active pass
2. Toggle airplane mode on/off multiple times
3. Navigate between tabs while toggling network

**Expected Results:**
- UI smoothly transitions between online and offline modes
- Offline indicator appears/disappears correctly
- No crashes or data loss
- Pass data remains consistent

---

### 8. Storage Cleanup
**Steps:**
1. Verify storage is working (generate passes, cache QR codes)
2. Log out of the app
3. Log back in

**Expected Results:**
- (Optional) Old cached data could be cleared on logout
- New passes generate correctly after re-login

**Note:** Current implementation persists storage across logins. Consider adding cleanup on logout if desired.

---

## Manual Testing Tools

### View UserDefaults Data
```swift
// Add this temporarily to ContentView.onAppear for debugging
print("Active Pass:", UserDefaults.standard.data(forKey: "activePass") != nil ? "EXISTS" : "NONE")
print("Pass History:", UserDefaults.standard.data(forKey: "passHistory") != nil ? "EXISTS" : "NONE")
```

### View Cached Files
```swift
// Add this to see cached QR codes
let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
if let files = try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) {
    print("Cached files:", files.filter { $0.lastPathComponent.hasPrefix("qr_") })
}
```

### Clear All Storage (for testing)
```swift
// Add temporary button to clear storage
Button("Clear Storage") {
    let storage = PassStorageService()
    storage.clearAllStorage()
}
```

---

## Key Console Log Messages

| Message | Meaning |
|---------|---------|
| ✅ Active pass saved to local storage | Pass successfully written to UserDefaults |
| ✅ QR code cached for pass ID | QR image downloaded and saved to disk |
| 📱 Loaded active pass from local storage | Pass retrieved from cache (offline) |
| 📱 Loaded cached QR image for pass ID | QR image loaded from disk cache |
| ⚠️ Active pass ID [id] has expired | Expiration detected |
| ✅ Pass history saved to local storage | History array saved |
| ❌ Error [operation] | Something failed, check details |

---

## Known Limitations

1. **Network Detection**: Currently uses API reachability check. May have slight delay detecting offline state.
2. **Storage Size**: No limits on pass history size. Consider adding cleanup for very old passes.
3. **QR Code Updates**: If API changes QR code URL, cached image won't update until next online fetch.
4. **Concurrent Access**: PassStorageService uses @MainActor but multiple instances could theoretically conflict.

---

## Recommended Improvements

1. Add network reachability observer using `NWPathMonitor` for real-time offline detection
2. Add timestamp to cached data for cache expiration
3. Implement background sync when app returns from background
4. Add UI feedback when pass is saved to storage
5. Add Settings option to clear cached data
6. Add analytics to track offline usage patterns
