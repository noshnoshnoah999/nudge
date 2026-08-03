# Claude Code Prompt — Widget text overflow fix, attempt 3 (mask-based) — 2026-07-24c

## Context: this bug has now failed to fix TWICE on-device

File: `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`.

The Today widget (medium + large) shows a Dumb-Phone list of reminder titles. Long titles were overflowing BOTH left and right edges (e.g. "...mp focus modes...") instead of cutting cleanly on the right with no ellipsis.

- Commit `6e6bffa` tried to fix it (failed on-device).
- Commit `eff939c` tried again with `.fixedSize` + `.frame(alignment:.leading)` + `.clipped()` (failed on-device — Noah confirmed full rebuild + reinstall, still identical).

Both failures came from `.fixedSize(horizontal: true)` + `.clipped()`: fixedSize lets the text ignore the frame width, and WidgetKit's clip landed symmetrically.

## What is in the file now (attempt 3, edited in Cowork — NOT yet built)

A new private view `WidgetRowTitle` (defined just above the `@main` bundle) replaces the inline row. It uses a **GeometryReader + explicit-pixel-width mask**:

```swift
GeometryReader { geo in
    Text(title)
        .font(.system(size: size, weight: .bold, design: design))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        .mask(Rectangle().frame(width: geo.size.width, height: geo.size.height, alignment: .leading))
}
.frame(height: size * 1.15)
.contentShape(Rectangle())
```

Rationale: a `.mask` clips to its own explicit geometry (concrete pixel width from GeometryReader), so it can't center/spill the way `.clipped()` did.

## Your job — BUILD AND VERIFY, do not just commit blind

1. **Build the widget target.** Confirm it compiles.
2. If it builds, commit:
   `fix(widget): mask-clip Today reminder titles to row width (attempt 3, no ellipsis)`
   then push.
3. **Verify the render if you can** (simulator or on-device): long title should cut cleanly on the RIGHT only, no "…", no left/centre spill. Also confirm row spacing still looks right (the `size * 1.15` row height is a guess — adjust if rows look too tight or too loose).

## Fallback if the mask STILL overflows or spacing breaks

If GeometryReader/mask misbehaves in WidgetKit, replace the `WidgetRowTitle` body with the one thing that physically cannot overflow — plain tail truncation WITH the ellipsis:

```swift
Text(title)
    .font(.system(size: size, weight: .bold, design: design))
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .truncationMode(.tail)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
```

Noah's preference is NO ellipsis, but a working "…" beats a fourth broken build. Use judgment: if the mask works, keep it; if not, ship the ellipsis and note it.

## After committing/pushing

Remove any git locks / stale locks (`.git/index.lock`, `.git/*.lock`) so the next session is smoother.
