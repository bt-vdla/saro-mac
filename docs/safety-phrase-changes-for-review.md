# Phrase-gate changes awaiting clinician review (SR-32)

The overnight safety testing (27–28 Oct 2026) changed layer 1 of the SafetyGate, the phrase gate. Every changed line in
`SaroKit/Sources/SaroKit/Safety/PhraseGate.swift` is marked `DRAFT: clinician review (SR-32), safety-2`. Nothing here is
final until a clinician has read it; the corpus tests pin today's behaviour so any change is deliberate.

## What changed

- **English phrasings that were missed.** 49 additions in families such as: wishing never to have been born; nothing left
  to live for; "better off / happier if I were gone"; "no one would miss me if…"; "part of me wants to die"; wanting to
  stop existing; "life isn't worth living"; asking how many pills it would take; stockpiling or swallowing pills; planning
  an overdose; painless or quick ways to die; jumping from or throwing oneself in front of a named place or vehicle;
  self-harm "on purpose"; common misspellings ("myslef", "kms", "unalive").
- **Idioms now spared.** 7 guards so venting isn't held: "suicide mission / door / sprint / drill", "no point going on
  about…", "tired of living out of a suitcase", and "wake up late / with…" style continuations.
- **Hinglish (romanised) and Devanagari lines.** Wishes to die, khudkhushi, not wanting to live, "kaash main paida na
  hota", "mere bina sab behtar", taking one's own life, hanging, cutting, never waking, jumping, swallowing all the pills.
  Nukta and chandrabindu fold, so one spelling covers both.
- **Normaliser behaviour.** Commas, semicolons, colons and ellipses read through (a phrase split by one still matches;
  a guard across one does not); stretched letters ("diiie") fold; variation selectors and odd apostrophes are handled.

## How to review

- Read the DRAFT lines in `PhraseGate.swift` (search for `SR-32`).
- `SaroKit/Tests/SaroKitTests/SafetyCorpusTests.swift` lists 134 synthetic lines that must be held and 136 that must not;
  `SafetyGuardTests.swift` adds 32 and 25 more. Disagree with a line? Move it between the lists and run `make test`.
- The layer-2 classifier eval (`ClassifierEvalTests.swift`, live on-device) prints recall and false positives for the
  tuned, held-out and fresh sets on every full test run: 58/60 risk lines caught, 8/64 venting lines over-flagged.
  Layer 1 catches what it misses.

All test text is synthetic (SR-28). No real journal text was used.
