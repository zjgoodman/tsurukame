// Copyright 2025 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// -----------------------------------------------------
// IMPORTANT: When modifying this file, make sure to
//            increment the version number at the very
//            bottom of the file to notify users about
//            the new SnapshotHelper.swift
// -----------------------------------------------------

import Foundation
import XCTest

var deviceLanguage = ""
var locale = ""

func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
  Snapshot.setupSnapshot(app, waitForAnimations: waitForAnimations)
}

func snapshot(_ name: String, waitForLoadingIndicator: Bool) {
  if waitForLoadingIndicator {
    Snapshot.snapshot(name)
  } else {
    Snapshot.snapshot(name, timeWaitingForIdle: 0)
  }
}

/// - Parameters:
///   - name: The name of the snapshot
///   - timeout: Amount of seconds to wait until the network loading indicator disappears. Pass `0`
/// if you don't want to wait.
func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
  Snapshot.snapshot(name, timeWaitingForIdle: timeout)
}

enum SnapshotError: Error, CustomDebugStringConvertible {
  case cannotDetectUser
  case cannotFindHomeDirectory
  case cannotFindSimulatorHomeDirectory
  case cannotAccessSimulatorHomeDirectory(String)
  case cannotRunOnPhysicalDevice

  var debugDescription: String {
    switch self {
    case .cannotDetectUser:
      return "Couldn't find Snapshot configuration files - can't detect current user "
    case .cannotFindHomeDirectory:
      return "Couldn't find Snapshot configuration files - can't detect `Users` dir"
    case .cannotFindSimulatorHomeDirectory:
      return "Couldn't find simulator home location. Please, check SIMULATOR_HOST_HOME env variable."
    case let .cannotAccessSimulatorHomeDirectory(simulatorHostHome):
      return "Can't prepare environment. Simulator home location is inaccessible. Does \(simulatorHostHome) exist?"
    case .cannotRunOnPhysicalDevice:
      return "Can't use Snapshot on a physical device."
    }
  }
}

@objcMembers
open class Snapshot: NSObject {
  static var app: XCUIApplication?
  static var waitForAnimations = true
  static var cacheDirectory: URL?
  static var screenshotsDirectory: URL? {
    cacheDirectory?.appendingPathComponent("screenshots", isDirectory: true)
  }

  open class func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
    Snapshot.app = app
    Snapshot.waitForAnimations = waitForAnimations

    do {
      let cacheDir = try pathPrefix()
      Snapshot.cacheDirectory = cacheDir
      setLanguage(app)
      setLocale(app)
      setLaunchArguments(app)
    } catch {
      NSLog(error.localizedDescription)
    }
  }

  class func setLanguage(_ app: XCUIApplication) {
    guard let cacheDirectory = cacheDirectory else {
      NSLog("CacheDirectory is not set - probably running on a physical device?")
      return
    }

    let path = cacheDirectory.appendingPathComponent("language.txt")

    do {
      let trimCharacterSet = CharacterSet.whitespacesAndNewlines
      deviceLanguage = try String(contentsOf: path, encoding: .utf8)
        .trimmingCharacters(in: trimCharacterSet)
      app.launchArguments += ["-AppleLanguages", "(\(deviceLanguage))"]
    } catch {
      NSLog("Couldn't detect/set language...")
    }
  }

  class func setLocale(_ app: XCUIApplication) {
    guard let cacheDirectory = cacheDirectory else {
      NSLog("CacheDirectory is not set - probably running on a physical device?")
      return
    }

    let path = cacheDirectory.appendingPathComponent("locale.txt")

    do {
      let trimCharacterSet = CharacterSet.whitespacesAndNewlines
      locale = try String(contentsOf: path, encoding: .utf8)
        .trimmingCharacters(in: trimCharacterSet)
    } catch {
      NSLog("Couldn't detect/set locale...")
    }

    if locale.isEmpty, !deviceLanguage.isEmpty {
      locale = Locale(identifier: deviceLanguage).identifier
    }

    if !locale.isEmpty {
      app.launchArguments += ["-AppleLocale", "\"\(locale)\""]
    }
  }

  class func setLaunchArguments(_ app: XCUIApplication) {
    guard let cacheDirectory = cacheDirectory else {
      NSLog("CacheDirectory is not set - probably running on a physical device?")
      return
    }

    let path = cacheDirectory.appendingPathComponent("snapshot-launch_arguments.txt")
    app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]

    do {
      let launchArguments = try String(contentsOf: path, encoding: String.Encoding.utf8)
      let regex = try NSRegularExpression(pattern: "(\\\".+?\\\"|\\S+)", options: [])
      let matches = regex
        .matches(in: launchArguments, options: [],
                 range: NSRange(location: 0, length: launchArguments.count))
      let results = matches.map { result -> String in
        (launchArguments as NSString).substring(with: result.range)
      }
      app.launchArguments += results
    } catch {
      NSLog("Couldn't detect/set launch_arguments...")
    }
  }

  open class func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
    if timeout > 0 {
      waitForLoadingIndicatorToDisappear(within: timeout)
    }

    NSLog("snapshot: \(name)") // more information about this, check out
    // https://docs.fastlane.tools/actions/snapshot/#how-does-it-work

    if Snapshot.waitForAnimations {
      sleep(1) // Waiting for the animation to be finished (kind of)
    }

    #if os(OSX)
      guard let app = app else {
        NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
        return
      }

      app.typeKey(XCUIKeyboardKeySecondaryFn, modifierFlags: [])
    #else

      guard self.app != nil else {
        NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
        return
      }

      let screenshot = XCUIScreen.main.screenshot()
      guard var simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"],
            let screenshotsDir = screenshotsDirectory else { return }

      do {
        // The simulator name contains "Clone X of " inside the screenshot file when running
        // parallelized UI Tests on concurrent devices
        let regex = try NSRegularExpression(pattern: "Clone [0-9]+ of ")
        let range = NSRange(location: 0, length: simulator.count)
        simulator = regex.stringByReplacingMatches(in: simulator, range: range, withTemplate: "")

        let path = screenshotsDir.appendingPathComponent("\(simulator)-\(name).png")
        try screenshot.pngRepresentation.write(to: path)
      } catch {
        NSLog("Problem writing screenshot: \(name) to \(screenshotsDir)/\(simulator)-\(name).png")
        NSLog(error.localizedDescription)
      }
    #endif
  }

  class func waitForLoadingIndicatorToDisappear(within timeout: TimeInterval) {
    #if os(tvOS)
      return
    #endif

    guard let app = app else {
      NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
      return
    }

    let networkLoadingIndicator = app.otherElements.deviceStatusBars.networkLoadingIndicators
      .element
    let networkLoadingIndicatorDisappeared =
      XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                object: networkLoadingIndicator)
    _ = XCTWaiter.wait(for: [networkLoadingIndicatorDisappeared], timeout: timeout)
  }

  class func pathPrefix() throws -> URL? {
    let homeDir: URL
    // on OSX config is stored in /Users/<username>/Library
    // and on iOS/tvOS/WatchOS it's in simulator's home dir
    #if os(OSX)
      guard let user = ProcessInfo().environment["USER"] else {
        throw SnapshotError.cannotDetectUser
      }

      guard let usersDir = FileManager.default.urls(for: .userDirectory, in: .localDomainMask)
        .first else {
        throw SnapshotError.cannotFindHomeDirectory
      }

      homeDir = usersDir.appendingPathComponent(user)
    #else
      #if arch(i386) || arch(x86_64)
        guard let simulatorHostHome = ProcessInfo().environment["SIMULATOR_HOST_HOME"] else {
          throw SnapshotError.cannotFindSimulatorHomeDirectory
        }
        guard let homeDirUrl = URL(string: simulatorHostHome) else {
          throw SnapshotError.cannotAccessSimulatorHomeDirectory(simulatorHostHome)
        }
        homeDir = URL(fileURLWithPath: homeDirUrl.path)
      #else
        throw SnapshotError.cannotRunOnPhysicalDevice
      #endif
    #endif
    return homeDir.appendingPathComponent("Library/Caches/tools.fastlane")
  }
}

private extension XCUIElementAttributes {
  var isNetworkLoadingIndicator: Bool {
    if hasWhiteListedIdentifier { return false }

    let hasOldLoadingIndicatorSize = frame.size == CGSize(width: 10, height: 20)
    let hasNewLoadingIndicatorSize = frame.size.width.isBetween(46, and: 47) && frame.size.height
      .isBetween(2, and: 3)

    return hasOldLoadingIndicatorSize || hasNewLoadingIndicatorSize
  }

  var hasWhiteListedIdentifier: Bool {
    let whiteListedIdentifiers = ["GeofenceLocationTrackingOn", "StandardLocationTrackingOn"]

    return whiteListedIdentifiers.contains(identifier)
  }

  func isStatusBar(_ deviceWidth: CGFloat) -> Bool {
    if elementType == .statusBar { return true }
    guard frame.origin == .zero else { return false }

    let oldStatusBarSize = CGSize(width: deviceWidth, height: 20)
    let newStatusBarSize = CGSize(width: deviceWidth, height: 44)

    return [oldStatusBarSize, newStatusBarSize].contains(frame.size)
  }
}

private extension XCUIElementQuery {
  var networkLoadingIndicators: XCUIElementQuery {
    let isNetworkLoadingIndicator = NSPredicate { evaluatedObject, _ in
      guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

      return element.isNetworkLoadingIndicator
    }

    return containing(isNetworkLoadingIndicator)
  }

  var deviceStatusBars: XCUIElementQuery {
    guard let app = Snapshot.app else {
      fatalError("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
    }

    let deviceWidth = app.windows.firstMatch.frame.width

    let isStatusBar = NSPredicate { evaluatedObject, _ in
      guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

      return element.isStatusBar(deviceWidth)
    }

    return containing(isStatusBar)
  }
}

private extension CGFloat {
  func isBetween(_ numberA: CGFloat, and numberB: CGFloat) -> Bool {
    numberA ... numberB ~= self
  }
}

// Please don't remove the lines below
// They are used to detect outdated configuration files
// SnapshotHelperVersion [1.21]
