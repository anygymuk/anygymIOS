//
//  liveActivityLiveActivity.swift
//  liveActivity
//
//  Created by Naaman Hudson on 11/12/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct liveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct liveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: liveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension liveActivityAttributes {
    fileprivate static var preview: liveActivityAttributes {
        liveActivityAttributes(name: "World")
    }
}

extension liveActivityAttributes.ContentState {
    fileprivate static var smiley: liveActivityAttributes.ContentState {
        liveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: liveActivityAttributes.ContentState {
         liveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: liveActivityAttributes.preview) {
   liveActivityLiveActivity()
} contentStates: {
    liveActivityAttributes.ContentState.smiley
    liveActivityAttributes.ContentState.starEyes
}
