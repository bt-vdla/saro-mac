## 15. Canvas interaction model (borrowed from Spatial)

Saro adopts Spatial's object model and motion vocabulary: every item opens by morphing out of its card, groups behave like physical piles and pockets, and a selection always raises one contextual toolbar. These findings come from hands-on use of Spatial's demo Space on the founder's Mac on 26 Oct 2026. Timings are estimates from screenshots taken 80-150 ms apart.

### What Spatial does

| Mechanic | What happens in Spatial | Observed timing |
| --- | --- | --- |
| Open an item | The card grows from its spot into a centred detail view; the rest of the canvas fades out | Mostly open by 150 ms, settled by about 450 ms, with a soft spring |
| Close an item | The detail shrinks back into its card, with a slight overshoot as it lands | Back by about 120 ms |
| Image detail | Extracted colour palette on the left, metadata in mono caps on the right, a floating action bar (duplicate, download, delete), and a "Write a note…" area under the image | Instant on open |
| Note on an image | The image's note shows on the canvas as a dark card pinned over the lower part of the image | Static |
| Note editor | Full-window, distraction-free; the first line becomes a title and "- " becomes a bullet as you type | Live formatting |
| Sticky | Spawns as a small card and edits inline; colour from a radial "flower" picker (saturated outer ring, tints inside, white centre) | Colour change is instant |
| Marquee select | Dragging on empty canvas draws a grey box; selected items get a thin white outline | Live |
| Contextual toolbar | A pill rises at the bottom centre for any selection: Stack ⌘S, Grid ⌘G, Download, Colour ⇧C; tooltips are mono-caps pills with the shortcut | About 150 ms |
| Stack | Selected cards fly to one point and settle as a loose pile with slight rotations; a toast says "Created a Stack" | About 80 ms |
| Open a stack | The pile fans out in place into a tidy row; the canvas behind dims to about 10% and steps back | About 300 ms |
| Grid | Selected items glide into a packed, bottom-aligned row with even gaps | About 100 ms |
| Folder | A pastel folder with coloured sheets peeking out, an item count and an optional lock | Static |
| Drop into a folder | The folder grows about 10% when an item hovers over it; on release the item slides down into the folder's front pocket; a toast says "Dropped on Folder" | About 200 ms |
| Open a folder | Contents rise out of the pocket and fan in an arc above the folder, newest raised in the middle; the canvas dims | About 350 ms |
| Nesting rule | Space → Folders and Stacks → items; folders can't go inside folders | Fixed |
| Create menu | Right-click or the + button: Note ⌘N, Sticky ⇧⌘N, Folder, Webclip, Import, New Space | Dims the canvas |
| Spaces | Separate canvases switched with ⌘1, ⌘2 | Instant |
| Search | A resizable side panel: "Describe what you're looking for", type and scope filters, results as full cards in two columns | Slides in |
| Quick capture | A floating Scratch Pad on ⌥Space or the menu bar icon, saved with ⌘↵ | Floating panel |
| Teaching | A "Learn the basics" checklist (03/10) that ticks itself as the user tries each mechanic | Live |

### What Saro takes

| ID | Requirement | Saro adaptation |
| --- | --- | --- |
| FR-CAN-01 | Every entry opens by morphing from its card and closes back into it | Moment, voice note, reflection and still detail views |
| FR-CAN-02 | A selection raises one contextual toolbar with shortcut tooltips | Stack, Grid, add to collection, export, delete |
| FR-CAN-03 | A recording session is a Stack: its turns pile together and fan out in place when opened | Background dims while a stack is open |
| FR-CAN-04 | A reflection can be pinned to a moment or a still and shows as a card over it | The "note to an image" pattern |
| FR-CAN-05 | Collections are folders: entries from any day drop into them with the pocket animation; one level only | e.g. "About Dad"; the self-model reads them as user-made themes |
| FR-CAN-06 | Marquee selection, Grid arrange and free placement on the spatial canvas | A short press-and-hold starts a card drag so it never fights the marquee |
| FR-CAN-07 | The image detail shows the still's colour palette and metadata | Stills only |
| FR-CAN-08 | Search is a side panel that takes a described query and returns full cards | Lexical first, semantic later |
| FR-CAN-09 | A floating quick-capture panel opens from anywhere | Default ⌃⌘J, because ⌥Space is taken by Raycast on the founder's Mac |
| FR-CAN-10 | First-run teaching is a checklist that ticks itself as each mechanic is tried | Capture, stacks, collections, canvas gestures |
| FR-CAN-11 | Toasts confirm structural changes in a short pill from the top | "Saved to Tuesday", "Added to About Dad", with Undo |

### What Saro does differently

- Days, not Spaces: Saro's unit is the local day; the time lens replaces a Space switcher.
- Hover feedback stays: a subtle lift so pointer users know what is interactive.
- Reduce Motion: every morph, fan and pocket animation falls back to a 150 ms crossfade.
- No imports from social sites.
- Safety overrides delight: a safety-held entry never animates into a collection or a stack summary.

### Native build notes

- Morphs within one SwiftUI hierarchy use `matchedGeometryEffect`; flights across canvas hosting views use a window-level Core Animation layer with `CASpringAnimation` (the zoom navigation transition is unavailable on macOS 27).
- Starting springs: open response 0.35 s / damping 0.85; close response 0.22 s / damping 0.75; stack and grid response 0.18 s / damping 0.9.
- Open question: does Spatial require the press-and-hold before a drag, or was that an artefact of synthetic input in testing? Check on a real trackpad.
