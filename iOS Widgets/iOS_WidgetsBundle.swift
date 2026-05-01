//
//  iOS_WidgetsBundle.swift
//  iOS Widgets
//
//  Created by Tim Morgan on 5/1/26.
//

import WidgetKit
import SwiftUI

@main
struct iOS_WidgetsBundle: WidgetBundle {
  var body: some Widget {
    iOS_Widgets()
    iOS_WidgetsControl()
    iOS_WidgetsLiveActivity()
  }
}
