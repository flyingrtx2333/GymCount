# SVG catalog acceptance — 2026-10-09

- 43 distinct SVG geometries: 40 training actions and 3 collection categories.
- Every icon has a 64 × 64 viewBox, transparent exterior and transparent outline interiors; contains real Bézier paths and no embedded image, base64, mask or external image dependency.
- SVG rendering compared against normalized source line art: minimum exact ink IoU 0.9220; all contour deviations satisfy the one-pixel tolerance check at 512 px. Full per-action evidence is generated in build/ExerciseIcons/verification.json.
- No cell-boundary clipping detected. All 43 normalized render bounds remain inside the reserved canvas margins.
- ZIP integrity and all 43 included SVG byte contents verified.
- Watch simulator Release target and iPhone simulator Debug scheme builds passed. Existing HealthKit deprecation and AppIntents metadata warnings remain unrelated to icon assets.
- Installed native iPhone preview and 40mm Watch sensor-free layout fixture rendered the new resources correctly. Screenshots are in build/ExerciseIcons/phone-preview.png and watch-40-preview.png. Real-device behavior is not claimed.
- Offline gallery contains 43 independent cards; JavaScript syntax checked. Browser UI interaction was not verified: direct file URLs were rejected by browser security policy, and current native browser windows were unavailable.
- Full generated SVG overview was visually inspected for all 43 actions. The diagrams are static exercise identifiers, not animated technique demonstrations.
- iOS and Watch 1.1.3 (10) uploaded to internal TestFlight on 2026-10-09. Apple reports BUILD-STATUS: VALID and IN_BETA_TESTING; membership in the flyingrtx internal group verified. Both signed archive asset catalogs contain all 43 resources. Release evidence: build/TestFlight-1.1.3-10/. No new counting algorithm deployment in this change.
