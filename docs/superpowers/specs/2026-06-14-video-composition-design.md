# Video Composition Design

## Goal

Add a local video composition feature that lets users combine multiple video clips into one exported video. The first version supports local and library/task videos, per-clip trimming, ordering, optional transitions, original audio controls, and BGM.

## Scope

In scope:

- Add a primary bottom tab for video editing/composition.
- Let users create a composition from local videos, uploaded library videos, or task result videos.
- Download remote library/task videos before editing when no local file is available.
- Let each clip define start and end times.
- Let users reorder, delete, and duplicate clips.
- Let users choose built-in transitions between clips.
- Let users choose output ratio/resolution, defaulting to the first clip.
- Let users choose audio mode: keep original audio, mute, original audio plus BGM, or BGM only.
- Let users pick BGM from local audio files or library audio.
- Let users set original audio volume, BGM volume, and whether BGM loops to output length.
- Export locally on Android through a service abstraction backed by FFmpeg capability.
- After export, let users import the result into the app library or save it to the system gallery/files.

Out of scope for the first version:

- Multi-track timeline editing.
- Subtitles.
- Per-frame visual filters.
- Sharing from the export result.
- iOS export implementation.
- AI-based video fusion or generation from multiple reference videos.

## Information Architecture

Add a new bottom navigation tab named `剪辑` between the existing creative/library/task/settings destinations. The tab is the main entry for video composition.

The `剪辑` page shows a new composition entry point. The first version may keep draft management minimal: one active composition is enough, with room to add recent drafts or recent exports later.

Secondary entry points:

- Library multi-select can send selected videos into a new composition.
- Task result actions can send a task video into the composition flow.
- The composition page itself can add videos from local files, library videos, and task result videos.

## UI/UX Design Direction

Use the existing Flutter Material styling and extend it with a video-first editing surface. The composition workspace should feel like a focused mobile editing tool: dark preview-first surfaces, clear timeline hierarchy, and strong action contrast.

UI/UX constraints:

- Keep the bottom navigation at five items maximum, with both icon and text labels.
- Use the new `剪辑` tab only for top-level navigation, not nested workflow steps.
- Keep all tappable targets at least 44×44pt, with at least 8dp spacing between adjacent controls.
- Avoid gesture-only actions; reorder, trim, delete, duplicate, and transition changes must have visible controls.
- Preserve predictable back behavior and unsaved composition state when navigating away.
- Use semantic theme colors instead of ad-hoc raw colors in widgets.
- Support light and dark themes, with dark preview surfaces optimized for video editing.
- Maintain text contrast of at least 4.5:1 for primary text and 3:1 for secondary text.
- Use Material icons consistently; do not use emoji as structural icons.
- Use 150–300ms motion for sheets, selection changes, and list transitions, and respect reduced-motion settings.
- Reserve safe-area and bottom navigation padding so timeline controls and export CTAs are never hidden.
- Support Dynamic Type/text scaling without clipping critical labels or controls.

## Composition Workspace

The workspace is centered on an ordered clip list. Each clip contains:

- Stable clip id.
- Source type and source id when applicable.
- Local video URI/path.
- Display label.
- Clip start time.
- Clip end time.
- Whether to use original audio for that clip.
- Transition after the clip.

Each clip card provides:

- Video preview with reserved aspect-ratio space to avoid layout jumps.
- Timeline scrubber with large handles and non-overlapping trim controls.
- Start/end point controls.
- Move up/down or drag reorder, with visible non-drag alternatives.
- Delete clip, separated from primary actions and confirmed or undoable.
- Duplicate clip.
- Transition picker for the transition after that clip.
- Clear pressed, selected, disabled, and error states.

Supported transition choices:

- None.
- Fade.
- Cross dissolve.
- Black transition.
- White flash.

The transition belongs to the clip before the cut. The final clip has no outgoing transition.

## Output Settings

Output settings include:

- Output ratio/resolution.
- Audio mode.
- Original audio volume.
- BGM source.
- BGM volume.
- Whether BGM loops to the full video length.

The default output format follows the first clip. Users may override it with common presets such as 720p/1080p and 16:9/9:16/1:1.

Audio modes:

- Keep original audio.
- Mute all original audio.
- Original audio plus BGM.
- BGM only.

BGM can come from a local audio file or an uploaded library audio attachment.

## Local Media Preparation

All clips entering the composition workspace must resolve to local files.

Rules:

- Local video files enter directly.
- Library videos with `localResourceUri` enter directly.
- Library videos without a local file are downloaded before being added.
- Task videos with a local file enter directly.
- Task videos without a local file are downloaded before being added.
- Remote URL-only videos are downloaded to app-managed local storage before editing.

If media cannot be downloaded or localized, the clip is not added and the UI shows which source failed.

## Video Processing Architecture

Introduce a video composition service abstraction on the Flutter side. UI/state code passes a composition project to the service; it does not build FFmpeg commands directly.

The Android implementation uses FFmpeg capability for the first version. The service is responsible for:

- Validating source files.
- Trimming each clip by start/end time.
- Normalizing clip resolution, ratio, and frame rate.
- Building transition filter graphs.
- Handling audio mode, BGM loop/crop, and volume settings.
- Producing an MP4 output file in app-managed storage.
- Reporting stage changes; numeric progress is optional if the execution layer exposes it.
- Supporting cancellation on platforms where the execution layer exposes cancel semantics.

The iOS implementation can return a platform unsupported error for the first version while keeping the interface portable.

## Export Flow

The export action validates the composition before starting. The export CTA should be the single primary action on the workspace and should remain reachable without covering timeline content. During export, the UI shows:

- Current stage: preparing media, trimming, composing, writing output.
- Numeric progress when the execution layer exposes it; otherwise stage-only progress.
- Cancel action on Android if the chosen FFmpeg execution layer supports cancellation.
- Disabled editing controls that could invalidate the running export.
- Clear recovery action after failure, such as retry, edit settings, or copy technical details.

On success, the app creates an export result with:

- Local output path.
- Display file name.
- Duration, using media metadata when available and otherwise the sum of clip durations.
- Dimensions, using media metadata when available and otherwise the selected output preset.

The result screen offers:

- Import to library.
- Save to system gallery/files.

Sharing is intentionally excluded from the first version.

## Validation and Errors

Composition validation:

- At least one clip is required.
- Every clip must resolve to an existing local file.
- Clip end time must be greater than clip start time.
- Transition duration must fit within adjacent available clip durations.
- BGM source is required when audio mode needs BGM.

User-facing failures:

- Download failure identifies the failed media source.
- Unsupported file formats ask the user to choose another video/audio.
- Storage shortage asks the user to free space.
- Processing failures show a short message and offer copyable technical details.

The export button is disabled while validation fails or an export is already running.

## Testing and Verification

Automated tests:

- Unit tests for composition validation.
- Unit tests for default output setting derivation.
- Unit tests for transition and audio option mapping into service requests.
- Widget tests for the new bottom tab.
- Widget tests for adding clips, setting trim ranges, and export button enabled/disabled states.
- Widget tests for key accessibility labels, disabled states, and text scaling-critical controls.

Manual Android verification:

- Create a composition from local videos.
- Create a composition from library videos that already have local files.
- Create a composition from online library/task videos that must download first.
- Trim clips and reorder them.
- Export with no transition.
- Export with each built-in transition type.
- Export with original audio.
- Export muted.
- Export with BGM from a local audio file.
- Export with BGM from library audio.
- Import export result to library.
- Save export result to gallery/files.
- Verify small phone layout around 375px width.
- Verify landscape orientation.
- Verify dark and light theme contrast.
- Verify large text scaling does not hide primary controls.
- Verify touch targets for timeline handles, clip actions, and bottom CTA.

## Implementation Notes

The feature should reuse existing app concepts where possible:

- `AttachmentKind.video` and `AttachmentKind.audio` for library media.
- Existing local resource fields for downloaded media.
- Existing task video local/remote handling where possible.
- Existing video preview widgets as the basis for clip preview.
- Existing storage provider upload flow when importing an exported video to the library.

Keep the FFmpeg integration behind a focused service boundary so the UI and state model do not depend on command-string details.
