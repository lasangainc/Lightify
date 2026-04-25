import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

private enum Defaults {
    static let outputDirectory = URL(fileURLWithPath: "/Users/benji/Developer stuff/Lightify-Dist-Builds/Finished-DMGs", isDirectory: true)
    static let volumeDisplayName = "Install Lightify"
    /// Copied into the DMG as `.background/<name>`; Finder is told to use this file name.
    static let backgroundCanonicalName = "background.png"
    /// Preferred background when placed next to the CreateRelease sources (Tools/CreateRelease/Sources/).
    static let preferredSourcesBackgroundName = "LightifyBack.png"
    static let appleScriptSleepSeconds: UInt64 = 5
}

// MARK: - Errors

private enum CreateReleaseError: Error, CustomStringConvertible {
    case usage(String)
    case message(String)

    var description: String {
        switch self {
        case .usage(let s): return s
        case .message(let s): return s
        }
    }
}

// MARK: - Terminal UI

/// Refined `… done` / `… error` lines; `--verbose` adds command + process output.
private struct CLIOutput {
    var verbose: Bool

    func logCommand(path: String, arguments: [String]) {
        guard verbose else { return }
        let quoted = ([path] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        fputs("    $ \(quoted)\n", stdout)
    }

    func logProcessOutput(stdout outText: String, stderr errText: String) {
        guard verbose else { return }
        if !errText.isEmpty { fputs(errText, Darwin.stdout) }
        if !outText.isEmpty { fputs(outText, Darwin.stdout) }
    }

    /// `label... done` or `label... error` then rethrows.
    func phase(_ label: String, _ work: () throws -> Void) rethrows {
        fputs("\(label)... ", stdout)
        fflush(stdout)
        do {
            try work()
            fputs("done\n", stdout)
        } catch {
            fputs("error\n", stdout)
            throw error
        }
    }

    /// Same as `phase` but ends with `finally` (used for the fixed sleep before Finder).
    func phaseFinally(_ label: String, _ work: () throws -> Void) rethrows {
        fputs("\(label)... ", stdout)
        fflush(stdout)
        do {
            try work()
            fputs("finally\n", stdout)
        } catch {
            fputs("error\n", stdout)
            throw error
        }
    }
}

// MARK: - Process helpers

private struct SubprocessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runExecutable(_ path: String, arguments: [String]) throws -> SubprocessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()
    process.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: outData, encoding: .utf8) ?? ""
    let err = String(data: errData, encoding: .utf8) ?? ""

    return SubprocessResult(status: process.terminationStatus, stdout: out, stderr: err)
}

@discardableResult
private func runExecutableThrowing(_ path: String, arguments: [String], context: String, log: CLIOutput? = nil) throws -> String {
    log?.logCommand(path: path, arguments: arguments)
    let r = try runExecutable(path, arguments: arguments)
    guard r.status == 0 else {
        throw CreateReleaseError.message("\(context) failed (\(r.status)).\n\(r.stderr)\(r.stdout)")
    }
    log?.logProcessOutput(stdout: r.stdout, stderr: r.stderr)
    return r.stdout
}

// MARK: - Args

private struct Options {
    var appURL: URL?
    var assetsDirectory: URL
    var backgroundFile: URL?
    var outputDirectory: URL
    var forceReplace: Bool
    var skipNotarizationCheck: Bool
    var keepTemporaryFiles: Bool
    var appleScriptSleepSeconds: UInt64
    var verbose: Bool
    var assumeYes: Bool

    static func parse(repoRoot: URL, arguments: [String]) throws -> Options {
        var opts = Options(
            appURL: nil,
            assetsDirectory: repoRoot,
            backgroundFile: nil,
            outputDirectory: Defaults.outputDirectory,
            forceReplace: false,
            skipNotarizationCheck: false,
            keepTemporaryFiles: false,
            appleScriptSleepSeconds: Defaults.appleScriptSleepSeconds,
            verbose: false,
            assumeYes: false
        )

        var i = arguments.makeIterator()
        while let arg = i.next() {
            switch arg {
            case "-h", "--help":
                throw CreateReleaseError.usage(Self.helpText(programName: arguments.first ?? "create-release"))
            case "--verbose", "-v":
                opts.verbose = true
            case "--yes", "-y":
                opts.assumeYes = true
            case "--app":
                guard let v = i.next() else { throw CreateReleaseError.message("--app requires a path") }
                opts.appURL = URL(fileURLWithPath: (v as NSString).expandingTildeInPath)
            case "--assets-dir":
                guard let v = i.next() else { throw CreateReleaseError.message("--assets-dir requires a path") }
                opts.assetsDirectory = URL(fileURLWithPath: (v as NSString).expandingTildeInPath, isDirectory: true)
            case "--background":
                guard let v = i.next() else { throw CreateReleaseError.message("--background requires a path") }
                opts.backgroundFile = URL(fileURLWithPath: (v as NSString).expandingTildeInPath)
            case "--output-dir":
                guard let v = i.next() else { throw CreateReleaseError.message("--output-dir requires a path") }
                opts.outputDirectory = URL(fileURLWithPath: (v as NSString).expandingTildeInPath, isDirectory: true)
            case "--replace":
                opts.forceReplace = true
            case "--skip-notarization-check":
                opts.skipNotarizationCheck = true
            case "--keep-tmp":
                opts.keepTemporaryFiles = true
            case "--applescript-sleep":
                guard let v = i.next(), let n = UInt64(v) else {
                    throw CreateReleaseError.message("--applescript-sleep requires a positive integer")
                }
                opts.appleScriptSleepSeconds = n
            default:
                throw CreateReleaseError.message("Unknown option: \(arg)\n\n\(Self.helpText(programName: arguments.first ?? "create-release"))")
            }
        }
        return opts
    }

    static func helpText(programName: String) -> String {
        """
        Usage: \(programName) [options]

          Produces: <output-dir>/lightify-<version>-dist.dmg
          Mounted volume title: \(Defaults.volumeDisplayName)

          Background resolution (first match wins):
          • --background FILE
          • Tools/CreateRelease/Sources/\(Defaults.preferredSourcesBackgroundName)
          • Tools/CreateRelease/Sources/.background/ (PNG/JPEG)
          • any PNG/JPEG directly in Tools/CreateRelease/Sources/
          • <assets-dir>/.background/

        Options:
          --app PATH               Use this .app (skip file picker)
          --assets-dir DIR         Repo folder containing .background/ fallback (default: Lightify repo root)
          --background FILE        Override all automatic background detection
          --output-dir DIR         Output folder (default: \(Defaults.outputDirectory.path))
          --replace                Overwrite existing output DMG
          --skip-notarization-check
          --keep-tmp               Keep temporary work directory
          --applescript-sleep N    Seconds before Finder layout (default: \(Defaults.appleScriptSleepSeconds))
          --verbose, -v            Log commands and tool stdout/stderr
          --yes, -y                Skip “Looks good?” (non-interactive)
          -h, --help

        Build:  cd Tools/CreateRelease && swift build -c release
        Run:    .build/release/create-release [options]
                (from Tools/CreateRelease), or: swift run create-release [options]
        """
    }
}

// MARK: - Paths & plist

private func stdinIsTTY() -> Bool {
    isatty(STDIN_FILENO) == 1
}

private func confirmLooksGood(assumeYes: Bool) -> Bool {
    if assumeYes || !stdinIsTTY() { return true }
    fputs("Looks good? (Y/n)... ", stdout)
    fflush(stdout)
    guard let raw = readLine() else { return true }
    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if line.isEmpty || line == "y" || line == "yes" { return true }
    if line == "n" || line == "no" { return false }
    return true
}

private func staplerValidationOK(appURL: URL, log: CLIOutput?) throws -> Bool {
    log?.logCommand(path: "/usr/bin/xcrun", arguments: ["stapler", "validate", appURL.path])
    let r = try runExecutable("/usr/bin/xcrun", arguments: ["stapler", "validate", appURL.path])
    log?.logProcessOutput(stdout: r.stdout, stderr: r.stderr)
    return r.status == 0
}

private func developerSignatureSummary(appURL: URL, log: CLIOutput?) -> String {
    log?.logCommand(path: "/usr/bin/codesign", arguments: ["-dvv", appURL.path])
    guard let r = try? runExecutable("/usr/bin/codesign", arguments: ["-dvv", appURL.path]) else {
        return "unknown"
    }
    log?.logProcessOutput(stdout: r.stdout, stderr: r.stderr)
    let blob = (r.stderr + r.stdout).split(separator: "\n").map(String.init)
    for line in blob where line.hasPrefix("Authority=") {
        let v = String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { return v }
    }
    for line in blob where line.hasPrefix("TeamIdentifier=") {
        let v = String(line.dropFirst(15)).trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, v != "not set" { return "team \(v)" }
    }
    return "unknown"
}

/// Strips codesign’s `Authority=` prefix noise for CLI display (e.g. `Developer ID Application: Org (TEAM)` → `Org`).
private func displayDeveloperName(from codesignAuthority: String) -> String {
    var s = codesignAuthority.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "Developer ID Application:"
    if s.hasPrefix(prefix) {
        s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
    if let openParen = s.lastIndex(of: "("), s.last == ")" {
        let innerStart = s.index(after: openParen)
        let innerEnd = s.index(before: s.endIndex)
        if innerStart < innerEnd {
            let inner = s[innerStart..<innerEnd]
            if inner.count == 10, inner.allSatisfy({ $0.isLetter || $0.isNumber }) {
                s = String(s[..<openParen]).trimmingCharacters(in: .whitespaces)
            }
        }
    }
    return s.isEmpty ? codesignAuthority : s
}

private func normalizedAppURL(_ url: URL) throws -> URL {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
        throw CreateReleaseError.message("Not a directory: \(url.path)")
    }
    guard url.pathExtension.lowercased() == "app" else {
        throw CreateReleaseError.message("Expected a .app bundle: \(url.path)")
    }
    return url.resolvingSymlinksInPath().standardizedFileURL
}

private func readMarketingVersion(from appURL: URL) throws -> String {
    let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
    guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any],
          let v = dict["CFBundleShortVersionString"] as? String, !v.isEmpty
    else {
        throw CreateReleaseError.message("Missing CFBundleShortVersionString in \(infoURL.path)")
    }
    return v
}

private func sanitizedVersionForFilename(_ version: String) -> String {
    version
        .replacingOccurrences(of: " ", with: "-")
        .filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
}

private let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]

private func isRegularImageFile(at url: URL, fm: FileManager) -> Bool {
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
    return imageExtensions.contains(url.pathExtension.lowercased())
}

private func firstImageInDirectory(_ dir: URL, fm: FileManager) throws -> URL? {
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    let match = urls.filter { isRegularImageFile(at: $0, fm: fm) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    return match.first
}

/// Picks a background: explicit flag, then CreateRelease `Sources/` conventions, then `<assets-dir>/.background/`.
private func resolveBackgroundImage(assetsDir: URL, explicit: URL?, toolPackageDir: URL?, fm: FileManager = .default) throws -> URL {
    if let explicit {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: explicit.path, isDirectory: &isDir), !isDir.boolValue else {
            throw CreateReleaseError.message("Background file not found: \(explicit.path)")
        }
        return explicit.standardizedFileURL
    }

    if let toolPackageDir {
        let sourcesDir = toolPackageDir.appendingPathComponent("Sources", isDirectory: true)
        let preferred = sourcesDir.appendingPathComponent(Defaults.preferredSourcesBackgroundName)
        if fm.fileExists(atPath: preferred.path), isRegularImageFile(at: preferred, fm: fm) {
            return preferred.standardizedFileURL
        }

        let sourcesDotBg = sourcesDir.appendingPathComponent(".background", isDirectory: true)
        if let found = try firstImageInDirectory(sourcesDotBg, fm: fm) {
            return found.standardizedFileURL
        }

        if let found = try firstImageInDirectory(sourcesDir, fm: fm) {
            return found.standardizedFileURL
        }
    }

    let bgDir = assetsDir.appendingPathComponent(".background", isDirectory: true)
    guard fm.fileExists(atPath: bgDir.path) else {
        throw CreateReleaseError.message(
            """
            No background image found. Do one of the following:
            • Put \(Defaults.preferredSourcesBackgroundName) in Tools/CreateRelease/Sources/, or
            • Add PNG/JPEG files under \(bgDir.path), or
            • Pass --background /path/to/image.png
            """
        )
    }
    guard let first = try firstImageInDirectory(bgDir, fm: fm) else {
        throw CreateReleaseError.message("No PNG/JPEG found in \(bgDir.path)")
    }
    return first.standardizedFileURL
}

// MARK: - hdiutil attach parsing

private func parseHdiutilAttachOutput(_ output: String) -> (devSlice: String, mountPath: String)? {
    for lineSub in output.split(whereSeparator: \.isNewline) {
        let line = String(lineSub)
        guard line.contains("Apple_HFS") else { continue }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard columns.count >= 3 else { continue }
        let devField = columns[0]
        let dev = devField.split(separator: " ").last.map(String.init) ?? devField
        let fsType = columns[1]
        let mount = columns[2]
        guard dev.hasPrefix("/dev/disk"), dev.contains("s"), mount.hasPrefix("/"), fsType.contains("Apple_HFS") else {
            continue
        }
        return (dev, mount)
    }
    return nil
}

// MARK: - Background image metrics

private func pixelSizeOfImage(at url: URL) throws -> (width: Int, height: Int) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw CreateReleaseError.message("Could not open image: \(url.path)")
    }
    guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
        throw CreateReleaseError.message("Could not read image metadata: \(url.path)")
    }
    func intValue(_ key: CFString) -> Int? {
        if let v = props[key] as? Int { return v }
        if let v = props[key] as? CGFloat { return Int(v) }
        if let v = props[key] as? NSNumber { return v.intValue }
        return nil
    }
    guard var w = intValue(kCGImagePropertyPixelWidth), var h = intValue(kCGImagePropertyPixelHeight), w > 0, h > 0 else {
        throw CreateReleaseError.message("Missing pixel dimensions for: \(url.path)")
    }
    if let o = props[kCGImagePropertyOrientation] as? UInt32,
       let orientation = CGImagePropertyOrientation(rawValue: o)
    {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swap(&w, &h)
        default:
            break
        }
    }
    return (w, h)
}

/// Window content size ≈ image pixels; clamp so it fits the main screen; keep icons usable.
private func layoutMetricsForBackgroundImage(width: Int, height: Int) -> (
    winW: Int, winH: Int, winX: Int, winY: Int, iconSize: Int, textSize: Int, appX: Int, appY: Int, appsX: Int, appsY: Int
) {
    let minW = 440
    let minH = 300
    var winW = max(width, minW)
    var winH = max(height, minH)

    if let screen = NSScreen.main {
        let vf = screen.visibleFrame
        let maxW = max(minW, Int(vf.width) - 80)
        let maxH = max(minH, Int(vf.height) - 80)
        winW = min(winW, maxW)
        winH = min(winH, maxH)
    }

    let winX: Int
    let winY: Int
    if let screen = NSScreen.main {
        let vf = screen.visibleFrame
        let cx = Int(vf.midX) - winW / 2
        let cy = Int(vf.midY) - winH / 2
        winX = max(Int(vf.minX) + 24, cx)
        winY = max(Int(vf.minY) + 24, cy)
    } else {
        winX = 120
        winY = 120
    }

    let baseIcon = min(112, max(72, min(winW, winH) / 6))
    // +30% vs the tuned base. Finder’s icon view rejects icon sizes above ~128 (-10000).
    let iconSize = min(128, max(72, Int((Double(baseIcon) * 1.3).rounded())))
    // Text size must stay ≤ 16 or AppleScript reliably fails with err -10000 (e.g. iconSize 104 → 104/6 = 17).
    let textSize = min(16, max(10, iconSize / 8))

    // Row sits in the lower half (arrow / glow). Wider X spread flanks the arrow.
    let bottomMargin = max(80, iconSize + 40)
    let capY = max(120, winH - bottomMargin)
    let rowY = min(Int(Double(winH) * 0.62), capY)
    // Slightly right of old 0.17 so the pair isn’t left-heavy vs the window (see DMG balance).
    let appX = Int(Double(winW) * 0.20)
    let appsX = Int(Double(winW) * 0.72)
    let sharedY = min(rowY, capY)
    let appY = sharedY
    let appsY = sharedY
    return (winW, winH, winX, winY, iconSize, textSize, appX, appY, appsX, appsY)
}

// MARK: - AppleScript (Finder layout only)

private func appleScriptLiteral(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func finderLayoutAppleScript(
    appBundleName: String,
    backgroundFileName: String,
    winX: Int,
    winY: Int,
    winW: Int,
    winH: Int,
    iconSize: Int,
    textSize: Int,
    appX: Int,
    appY: Int,
    appsX: Int,
    appsY: Int
) -> String {
    let appName = appleScriptLiteral(appBundleName)
    let bgName = appleScriptLiteral(backgroundFileName)

    // mountPosix (argv 2) must be the real attach path; -mountrandom volumes are not under /Volumes/.
    // Avoid embedding "\"" in Swift multiline strings — it corrupts AppleScript and triggers osascript -2741.
    return """
    on run argv
      set volumeName to item 1 of argv
      set mountPosix to item 2 of argv
      tell application "Finder"
        tell disk (volumeName as string)
          open
          set theXOrigin to \(winX)
          set theYOrigin to \(winY)
          set theWidth to \(winW)
          set theHeight to \(winH)
          set theBottomRightX to (theXOrigin + theWidth)
          set theBottomRightY to (theYOrigin + theHeight)
          set storePath to mountPosix & "/.DS_Store"
          tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
          end tell
          set opts to the icon view options of container window
          tell opts
            set icon size to \(iconSize)
            set text size to \(textSize)
            set arrangement to not arranged
          end tell
          set bgPOSIX to mountPosix & "/.background/\(bgName)"
          set background picture of opts to POSIX file bgPOSIX
          set position of item "\(appName)" to {\(appX), \(appY)}
          set position of item "Applications" to {\(appsX), \(appsY)}
          close
          open
          delay 1
          tell container window
            set statusbar visible to false
            set the bounds to {theXOrigin, theYOrigin, theBottomRightX - 10, theBottomRightY - 10}
          end tell
          delay 1
          tell container window
            set statusbar visible to false
            set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
          end tell
          delay 3
          set waitTime to 0
          set ejectMe to false
          repeat while ejectMe is false
            delay 1
            set waitTime to waitTime + 1
            if (do shell script "test -f " & quoted form of storePath & "; echo $?") = "0" then set ejectMe to true
            if waitTime > 30 then set ejectMe to true
          end repeat
        end tell
      end tell
    end run
    """
}

// MARK: - Pipeline

@main
enum CreateReleaseCLI {
    static func main() {
        do {
            try run()
        } catch let e as CreateReleaseError {
            FileHandle.standardError.write(Data("\(e.description)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        let allArgs = Array(CommandLine.arguments.dropFirst())
        let programName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "create-release"

        let repoRoot = Self.findRepositoryRoot()

        if allArgs.isEmpty == false, allArgs[0] == "-h" || allArgs[0] == "--help" {
            print(Options.helpText(programName: programName))
            return
        }

        let opts = try Options.parse(repoRoot: repoRoot, arguments: allArgs)
        let out = CLIOutput(verbose: opts.verbose)
        NSApplication.shared.setActivationPolicy(.accessory)

        var appURL: URL!
        try out.phase("Select app binary") {
            if let u = opts.appURL {
                appURL = try normalizedAppURL(u)
            } else {
                guard let picked = chooseAppBundle() else {
                    throw CreateReleaseError.message("No .app selected.")
                }
                appURL = try normalizedAppURL(picked)
            }
        }

        let stapled = try staplerValidationOK(appURL: appURL, log: out)
        let dev = displayDeveloperName(from: developerSignatureSummary(appURL: appURL, log: out))
        let notarized = stapled ? "yes" : "no"
        fputs("App info: \(appURL.lastPathComponent), Notarized: \(notarized), Developer: \(dev)\n", stdout)

        if !confirmLooksGood(assumeYes: opts.assumeYes) {
            fputs("Cancelled.\n", stdout)
            return
        }

        if !opts.skipNotarizationCheck, !stapled {
            throw CreateReleaseError.message(
                "This build has no stapled notarization ticket. Re-run with --skip-notarization-check if you still want a DMG."
            )
        }

        let version = try readMarketingVersion(from: appURL)
        let versionSafe = sanitizedVersionForFilename(version)
        let dmgName = "lightify-\(versionSafe)-dist.dmg"
        let finalDMG = opts.outputDirectory.appendingPathComponent(dmgName)

        try FileManager.default.createDirectory(at: opts.outputDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: finalDMG.path), !opts.forceReplace {
            throw CreateReleaseError.message("Output exists: \(finalDMG.path)\nUse --replace to overwrite.")
        }

        let toolPackageDir = Self.findCreateReleaseToolPackageDirectory()
        let bgSource = try resolveBackgroundImage(
            assetsDir: opts.assetsDirectory,
            explicit: opts.backgroundFile,
            toolPackageDir: toolPackageDir
        )
        fputs("Using background image: \(bgSource.lastPathComponent)\n", stdout)

        let (pxW, pxH) = try pixelSizeOfImage(at: bgSource)
        let layout = layoutMetricsForBackgroundImage(width: pxW, height: pxH)
        fputs("Setting window size: \(layout.winW)×\(layout.winH)\n", stdout)
        if out.verbose {
            fputs(
                "    (source image \(pxW)×\(pxH) px, icons @ (\(layout.appX),\(layout.appY)) & (\(layout.appsX),\(layout.appsY)))\n",
                stdout
            )
        }

        let fm = FileManager.default
        var workRootURL: URL?
        var attachedDev: String?
        defer {
            if let d = attachedDev {
                _ = try? runExecutable("/usr/bin/hdiutil", arguments: ["detach", d, "-quiet"])
                _ = try? runExecutable("/usr/bin/hdiutil", arguments: ["detach", d, "-force"])
            }
            if let wr = workRootURL {
                if !opts.keepTemporaryFiles {
                    try? fm.removeItem(at: wr)
                } else {
                    fputs("keep-tmp: \(wr.path)\n", stderr)
                }
            }
        }

        try out.phase("Getting app ready") {
            let workRoot = fm.temporaryDirectory.appendingPathComponent("lightify-create-release-\(UUID().uuidString)", isDirectory: true)
            workRootURL = workRoot
            try fm.createDirectory(at: workRoot, withIntermediateDirectories: true, attributes: nil)
            let mountRootDir = workRoot.appendingPathComponent("mount_root", isDirectory: true)
            let st = workRoot.appendingPathComponent("staging", isDirectory: true)
            try fm.createDirectory(at: mountRootDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: st, withIntermediateDirectories: true)

            let stagedApp = st.appendingPathComponent(appURL.lastPathComponent)
            _ = try runExecutableThrowing(
                "/usr/bin/ditto",
                arguments: ["--noqtn", appURL.path, stagedApp.path],
                context: "ditto",
                log: out
            )

            let bgDestDir = st.appendingPathComponent(".background", isDirectory: true)
            try fm.createDirectory(at: bgDestDir, withIntermediateDirectories: true)
            let bgDest = bgDestDir.appendingPathComponent(Defaults.backgroundCanonicalName)
            if fm.fileExists(atPath: bgDest.path) { try fm.removeItem(at: bgDest) }
            try fm.copyItem(at: bgSource, to: bgDest)

            let appsLink = st.appendingPathComponent("Applications")
            if fm.fileExists(atPath: appsLink.path) { try fm.removeItem(at: appsLink) }
            try fm.createSymbolicLink(at: appsLink, withDestinationURL: URL(fileURLWithPath: "/Applications"))

            let dsStore = st.appendingPathComponent(".DS_Store")
            if fm.fileExists(atPath: dsStore.path) { try fm.removeItem(at: dsStore) }
        }

        guard let workRoot = workRootURL else {
            throw CreateReleaseError.message("Internal error: work directory missing.")
        }
        let mountRoot = workRoot.appendingPathComponent("mount_root", isDirectory: true)
        let staging = workRoot.appendingPathComponent("staging", isDirectory: true)
        let rwDMG = workRoot.appendingPathComponent("rw.dmg")

        if fm.fileExists(atPath: rwDMG.path) { try fm.removeItem(at: rwDMG) }

        try out.phase("Creating disk image (pre-lock)") {
            _ = try runExecutableThrowing(
                "/usr/bin/hdiutil",
                arguments: [
                    "create", "-srcfolder", staging.path,
                    "-volname", Defaults.volumeDisplayName,
                    "-fs", "HFS+", "-fsargs", "-c c=64,a=16,e=16",
                    "-format", "UDRW", "-ov", rwDMG.path
                ],
                context: "hdiutil create",
                log: out
            )
            let sizeBytes = try fm.attributesOfItem(atPath: rwDMG.path)[.size] as? UInt64 ?? 0
            let sizeMB = max(1, Int(sizeBytes / 1_000_000) + 20)
            _ = try runExecutableThrowing(
                "/usr/bin/hdiutil",
                arguments: ["resize", "-size", "\(sizeMB)m", rwDMG.path],
                context: "hdiutil resize",
                log: out
            )
        }

        var parsedAttach: (devSlice: String, mountPath: String)?
        try out.phase("Mounting (temp)") {
            let attachOut = try runExecutableThrowing(
                "/usr/bin/hdiutil",
                arguments: [
                    "attach", rwDMG.path,
                    "-readwrite", "-noverify", "-noautoopen", "-nobrowse",
                    "-mountrandom", mountRoot.path
                ],
                context: "hdiutil attach",
                log: out
            )
            guard let p = parseHdiutilAttachOutput(attachOut) else {
                throw CreateReleaseError.message("hdiutil attach parse failed:\n\(attachOut)")
            }
            parsedAttach = p
            attachedDev = p.devSlice
            guard fm.fileExists(atPath: p.mountPath) else {
                throw CreateReleaseError.message("Mount path missing: \(p.mountPath)")
            }
            if out.verbose {
                fputs("    \(p.mountPath) on \(p.devSlice)\n", stdout)
            }
        }

        guard let parsed = parsedAttach else {
            throw CreateReleaseError.message("Internal error: mount result missing.")
        }
        let mountDir = parsed.mountPath
        let volumeKey = URL(fileURLWithPath: mountDir, isDirectory: true).lastPathComponent
        let appBundleName = appURL.lastPathComponent

        let waitLabel = "Waiting \(opts.appleScriptSleepSeconds)s before Finder layout is set"
        out.phaseFinally(waitLabel) {
            if opts.appleScriptSleepSeconds > 0 {
                Thread.sleep(forTimeInterval: TimeInterval(opts.appleScriptSleepSeconds))
            }
        }

        try out.phase("Setting Finder layout") {
            let script = finderLayoutAppleScript(
                appBundleName: appBundleName,
                backgroundFileName: Defaults.backgroundCanonicalName,
                winX: layout.winX,
                winY: layout.winY,
                winW: layout.winW,
                winH: layout.winH,
                iconSize: layout.iconSize,
                textSize: layout.textSize,
                appX: layout.appX,
                appY: layout.appY,
                appsX: layout.appsX,
                appsY: layout.appsY
            )
            let scriptURL = workRoot.appendingPathComponent("layout.applescript")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            out.logCommand(path: "/usr/bin/osascript", arguments: [scriptURL.path, volumeKey, mountDir])
            let osa = try runExecutable("/usr/bin/osascript", arguments: [scriptURL.path, volumeKey, mountDir])
            out.logProcessOutput(stdout: osa.stdout, stderr: osa.stderr)
            guard osa.status == 0 else {
                throw CreateReleaseError.message("Finder layout failed:\n\(osa.stderr)\(osa.stdout)")
            }
            try? fm.removeItem(at: scriptURL)
            if out.verbose {
                out.logCommand(path: "/bin/chmod", arguments: ["-Rf", "go-w", mountDir])
            }
            _ = try? runExecutable("/bin/chmod", arguments: ["-Rf", "go-w", mountDir])
            try? fm.removeItem(at: URL(fileURLWithPath: mountDir).appendingPathComponent(".fseventsd"))
        }

        try out.phase("Unmounting") {
            out.logCommand(path: "/usr/bin/hdiutil", arguments: ["detach", parsed.devSlice])
            let detach1 = try runExecutable("/usr/bin/hdiutil", arguments: ["detach", parsed.devSlice])
            out.logProcessOutput(stdout: detach1.stdout, stderr: detach1.stderr)
            if detach1.status != 0 {
                _ = try runExecutableThrowing(
                    "/usr/bin/hdiutil",
                    arguments: ["detach", parsed.devSlice, "-force"],
                    context: "hdiutil detach -force",
                    log: out
                )
            }
            attachedDev = nil
        }

        if opts.forceReplace, fm.fileExists(atPath: finalDMG.path) {
            try fm.removeItem(at: finalDMG)
        }

        try out.phase("Locking") {
            _ = try runExecutableThrowing(
                "/usr/bin/hdiutil",
                arguments: ["convert", rwDMG.path, "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", "-o", finalDMG.path],
                context: "hdiutil convert",
                log: out
            )
        }

        fputs("\nAll set! The disk image is at \(finalDMG.path)\n", stdout)
    }

    /// Resolves the app repository root (for default `--assets-dir`). Override with `CREATE_RELEASE_REPO_ROOT`.
    /// Directory that contains this tool’s `Package.swift` and `Sources/CreateRelease/main.swift` (Tools/CreateRelease).
    private static func findCreateReleaseToolPackageDirectory() -> URL? {
        let fm = FileManager.default
        let starts: [URL] = [
            URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        ]
        for start in starts {
            var url = start.standardizedFileURL
            for _ in 0 ..< 20 {
                let pkg = url.appendingPathComponent("Package.swift")
                let mainSwift = url.appendingPathComponent("Sources/CreateRelease/main.swift")
                if fm.fileExists(atPath: pkg.path), fm.fileExists(atPath: mainSwift.path) {
                    return url
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return nil
    }

    private static func findRepositoryRoot() -> URL {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["CREATE_RELEASE_REPO_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true).standardizedFileURL
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        if let found = walkUpForXcodeproj(from: cwd, fm: fm) { return found }
        let binaryDir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        if let found = walkUpForXcodeproj(from: binaryDir, fm: fm) { return found }
        return cwd.standardizedFileURL
    }

    private static func walkUpForXcodeproj(from start: URL, fm: FileManager) -> URL? {
        var url = start.standardizedFileURL
        for _ in 0 ..< 12 {
            let proj = url.appendingPathComponent("Lightify.xcodeproj", isDirectory: true)
            if fm.fileExists(atPath: proj.path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    private static func chooseAppBundle() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.title = "Select notarized Lightify.app"
        panel.prompt = "Choose"
        if let appType = UTType("com.apple.application-bundle") {
            panel.allowedContentTypes = [appType]
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
