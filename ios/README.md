# Zemer iOS prototype

This directory contains the first iOS implementation of Zemer, targeting **iOS 15+** so it can run on the 1st-generation iPhone SE as well as newer iPhones.

## Current prototype

- SwiftUI interface
- Music search
- Music result list with artwork and duration
- Audio playback through AVPlayer
- Background audio session
- Mini-player with play/pause
- Piped-backed stream resolution

## Open in Xcode

Open `ios/ZemerIOS.xcodeproj` in Xcode 15 or newer, select the **Zemer** target, choose your Apple development team under Signing & Capabilities, and run on an iPhone or simulator.

The stream resolver is intentionally isolated in `PipedClient.swift` so it can later be replaced by a more direct Zemer/InnerTube implementation without rewriting the UI or player.
