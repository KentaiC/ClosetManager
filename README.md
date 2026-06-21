# Closet Manager · Smart Local Wardrobe

**English** | [中文](README.zh-CN.md)

A fully **local, offline** iOS wardrobe app built with SwiftUI + SwiftData. All intelligence runs on Apple's native frameworks (Vision, CoreImage, Swift Charts) — no network services of any kind.

## Features
- **Item capture**: pick from Photos → on-device Vision background removal → CoreImage dominant/secondary color extraction & auto-naming; batch import wizard.
- **Outfit engine**: layering algorithm based on "sum of warmth matches the weather", with base-layer rule, same-type exclusion, scenario purity, and rain/snow waterproof constraints.
- **Lifecycle**: in-wardrobe / in-laundry / in-luggage state machine; a "currently wearing" widget with one-tap take-off flow; laundry retention warning.
- **Travel capsule**: packing list by trip length & temperature, with a hard-capped underwear count.
- **Analytics**: Swift Charts inventory breakdown, color preference, activity heatmap, and color treemap.
- **Utilities**: similar-item detection (Vision feature prints), advanced filtering, UI customization, and local backup import/export.

## Stack
SwiftUI · SwiftData · Vision · CoreImage · Swift Charts · PhotosUI

## Run
Xcode 26+ / iOS 17+. Open in Xcode and select your own Team under `Target → Signing & Capabilities` to run on a device (the repo ships no development team ID). Vision background removal is best tested on a real device — the Simulator may not support it.
