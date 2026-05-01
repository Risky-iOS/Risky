//
//  macOS_WidgetsBundle.swift
//  macOS Widgets
//
//  Created by Tim Morgan on 5/1/26.
//

import WidgetKit
import SwiftUI

@main
struct macOS_WidgetsBundle: WidgetBundle {
  var body: some Widget {
    macOS_Widgets()
    macOS_WidgetsControl()
  }
}
