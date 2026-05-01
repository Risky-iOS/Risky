//
//  iOS_WidgetsLiveActivity.swift
//  iOS Widgets
//
//  Created by Tim Morgan on 5/1/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct iOS_WidgetsAttributes: ActivityAttributes {
  // Fixed non-changing properties about your activity go here!
  var name: String

  public struct ContentState: Codable, Hashable {
    // Dynamic stateful properties about your activity go here!
    var emoji: String
  }
}

struct iOS_WidgetsLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: iOS_WidgetsAttributes.self) { context in
      // Lock screen/banner UI goes here
      VStack {
        Text("Hello \(context.state.emoji)")
      }
      .activityBackgroundTint(Color.cyan)
      .activitySystemActionForegroundColor(Color.black)
    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded UI goes here. Compose the expanded UI through
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

extension iOS_WidgetsAttributes {
  fileprivate static var preview: iOS_WidgetsAttributes {
    iOS_WidgetsAttributes(name: "World")
  }
}

extension iOS_WidgetsAttributes.ContentState {
  fileprivate static var smiley: iOS_WidgetsAttributes.ContentState {
    iOS_WidgetsAttributes.ContentState(emoji: "😀")
  }

  fileprivate static var starEyes: iOS_WidgetsAttributes.ContentState {
    iOS_WidgetsAttributes.ContentState(emoji: "🤩")
  }
}

#Preview("Notification", as: .content, using: iOS_WidgetsAttributes.preview) {
  iOS_WidgetsLiveActivity()
} contentStates: {
  iOS_WidgetsAttributes.ContentState.smiley
  iOS_WidgetsAttributes.ContentState.starEyes
}
