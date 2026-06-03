---
name: character-portraits
description: >-
  Batch create style-consistent character portraits for games.
  Use when users need to create multiple character illustrations,
  character designs, or character art with unified visual style.
---

# Character Portraits - Batch Generation

Generate style-consistent, visually distinct character portraits.
Two mechanisms: Style Anchor + Per-character Traits + Single Reference Image.

## Workflow

Three phases, in order. Defaults described below; deviations noted.

### Phase 1: Requirements Discussion

Confirm with user BEFORE generating. Ask progressively.

> **Fast mode**: If user says just generate, confirm only style + count, then defaults:
> game bust portrait, 2:3, 512x1024, transparent, bright.

**Round 1**: How many? Art style? Purpose?
**Round 2**: Color tone? Composition? Background? Size?
**Round 3**: Character definitions (1-5: one by one; 6-12: batch table; 13+: theme + one-liners).
Use character card template from style-guide.md.

**Exit**: Style anchor AND character cards confirmed.

### Phase 2: Generation

#### Step 1: Build Style Anchor

Write as **natural language sentences** (not tag lists) per style-guide.md.
Append negative constraints. Determine: aspect_ratio, target_size, transparent.

**Mandatory Dimension Checklist** (style anchor MUST explicitly address ALL 6):

| # | Dimension | What to specify | Bad example | Good example |
|---|-----------|----------------|-------------|--------------|
| 1 | **Rendering method** | Flat/cel-shaded OR painterly/soft-shaded OR semi-realistic | "anime style" | "Flat cel-shaded coloring with no gradient blending" |
| 2 | **Linework** | Presence, weight, color | "clean lines" | "Medium-weight black outlines (approx 2px at 1024h), consistent on all characters" |
| 3 | **Color temperature** | Warm/cool bias, saturation band | "vivid colors" | "Warm-leaning palette (yellow-shifted highlights), saturation 60-80%" |
| 4 | **Lighting model** | Direction, softness, shadow style | "soft lighting" | "Single top-left key light, soft drop shadows, no hard rim light" |
| 5 | **Proportions** | Head-to-body ratio, build standard | (omitted) | "Proportions: 6.5-head tall standard anime figure" |
| 6 | **Composition framing** | Crop line, centering rule | "bust portrait" | "Bust crop at mid-chest, subject centered, 15% headroom" |

> If any dimension is missing, the style anchor is incomplete.
> Re-draft before proceeding.

#### Step 2: Generate Anchor Character

**Anchor selection**: Pick representative, middle-ground design.
Avoid extremes (unique silhouettes, heavy palettes, stylized poses).

Generate with generate_image:

```
generate_image(
  prompt = style_anchor + char_traits + avoid_list,
  name = "character_name",
  target_size = "512x1024", aspect_ratio = "2:3", transparent = true
)
```

Show result to user. **Record anchor_image_path** from response.

> **Anchor override**: If anchor skews other characters, try a different
> character as anchor, or adjust the style anchor text.

#### Step 3: Batch Generate Remaining Characters

Use `batch_generate_images`. Each prompt repeats the full style anchor,
full character card, and requests style consistency with reference:

```
batch_generate_images(
  images = [
    {
      prompt = "[style anchor]\n[consistency note]\n[char N traits]\n[avoid list]",
      name = "char_N_name",
      target_size / aspect_ratio / transparent = same_as_anchor,
      reference_images = [anchor_image_path],
    },
    ...
  ]
)
```

> For >10 characters, split into batches of 10. Every batch carries anchor as reference.

**Pose/Angle Scatter Rule** (mandatory for 6+ characters):

Before generating, pre-assign pose and camera angle from the scatter pools
in style-guide.md section 2.2. Rules:
- No two adjacent characters (by batch order) share the same pose.
- At least 3 distinct camera angles across any 10-character batch.
- Record assignments in the batch table BEFORE generation.

**Mandatory Pose Assignment Table** (fill BEFORE writing any prompt):

```
| # | Character  | Pose (from P1-P12) | Angle (from A1-A6) | Verified unique? |
|---|------------|--------------------|--------------------|------------------|
| 1 | [name]     | P[?]               | A[?]               | -                |
| 2 | [name]     | P[?]               | A[?]               | ✓ ≠ row 1       |
| 3 | [name]     | P[?]               | A[?]               | ✓ ≠ row 2       |
| ...                                                                         |
```

> This table is **not optional**. If you skip it, adjacent characters WILL converge
> to the same 3/4 view pose. Fill it, then write prompts that match the assignments.

#### Step 4: Variant Generation — Text-Driven, Single Reference

When the project requires variants of each character (e.g. different expressions,
ages, outfits, seasons, weapons, lighting moods, etc.), generate them AFTER
all base portraits are approved.

**Variant dimensions are user-defined.** During Phase 1, confirm what variant
dimensions are needed. Common examples:

| Dimension | Example values | Description hint |
|-----------|---------------|------------------|
| Expression | angry, happy, sad, fear, hurt | Facial muscle changes (FACS-level preferred) |
| Age | young, mid, old | Anatomical aging cues |
| Outfit | casual, formal, battle, festival | Clothing swap, keep face identical |
| Season | spring, summer, autumn, winter | Background + clothing color shift |
| Weapon/Item | sword, staff, bow, shield | Held item swap, keep character identical |
| Lighting | day, dusk, night, dramatic | Lighting mood change |

The skill does NOT prescribe which dimensions to use. The user decides.
The generation principle is always the same: **single reference + text delta**.

##### Architecture: Text-Driven Single Reference

Each variant uses ONLY the character's own base portrait as reference image.
The variation is driven entirely by detailed text descriptions.

```
For each character x variant combination:
  Character Base Image (single reference)
    + Detailed text description of what changes
    --> Character Variant

NO variant anchor images.
NO dual-reference mixing.
Identity preservation = single reference only.
```

**Why single reference?**
Dual-reference (character base + another image) causes identity leakage:
the second image's features bleed into the target character.
Text-only driving eliminates this entirely.

##### Step 4A: Preparing Variant Descriptions

For each variant dimension, write a **detailed physical description** of what
changes and what stays the same. The more anatomically/visually specific,
the more consistent the results.

**Good variant description** (specific, physical):
> Brow lowerer contracts creating vertical furrows between eyebrows,
> upper eyelids tighten making gaze sharp, lips press together thinning...

**Bad variant description** (vague, label-only):
> Angry expression.

Store reusable variant descriptions in style-guide.md for the project.
When the same variant value applies to all characters (e.g. "angry"),
use the SAME text description for all of them to ensure cross-character consistency.

##### Step 4B: Generating Variants

For each character x variant, generate using **single reference** + **text delta**:

```
generate_image(
  prompt = "[style anchor]\n"
         + "This is the SAME character as in the reference image.\n"
         + "Keep ALL identity features EXACTLY: same hairstyle, hair color,\n"
         + "eye color, skin tone, facial bone structure, outfit, accessories,\n"
         + "body type, head-to-body proportions, art style, linework weight.\n"
         + "Keep the same pose, angle, composition, and background.\n\n"
         + "ONLY change [what varies]:\n"
         + "[detailed variant description]\n\n"
         + "[char N traits]\n[avoid list]",
  name = "char_N_[variant_value]",
  reference_images = [char_N_base_image_path],  // SINGLE reference only
  ...same dimensions as base...
)
```

**Identity lock sentence** — always include for variants that change appearance:
> "This is the SAME character. Keep ALL identity features EXACTLY:
> same hairstyle, hair color, eye color, skin tone, facial bone structure,
> outfit (unless outfit is the variant), accessories, body type,
> head-to-body proportions, art style, linework weight."

Omit the "same X" clause only for the dimension being varied
(e.g., if varying outfit, remove "same outfit" from the lock sentence).

**Batch strategy**:
- Group by variant value: generate ALL characters' variant-X first, then variant-Y.
- Use `batch_generate_images` with up to 10 characters per call.
- Every character uses its OWN base portrait as the sole reference.

```
// Example: all characters' "variant_X"
batch_generate_images(
  images = [
    {
      prompt = "...[variant_X description]...[char_01 traits]...",
      name = "c01_variant_x",
      reference_images = [c01_base_path],
      ...
    },
    {
      prompt = "...[variant_X description]...[char_02 traits]...",
      name = "c02_variant_x",
      reference_images = [c02_base_path],
      ...
    },
  ]
)
```

**Chained variants** (e.g. age: young -> mid -> old):
Always reference the original base, not the previous stage.
Chaining (mid as reference for old) causes drift accumulation.

##### Step 4C: Cross-Character Consistency Check

After generating all characters' variants for a given value, visually compare:
1. Does the variant look like the same type/intensity of change across all characters?
2. If one character's variant is noticeably weaker or different, regenerate with
   a more specific description.

The shared text description serves as the consistency anchor across characters.

#### Output Management

**File naming**: `name` param = character name in snake_case (e.g. `silver_knight`).
Generated files follow `{name}_{timestamp}.png`. Maintain a mapping:

```
| # | Character | name param     | File                          | Status   |
|---|-----------|----------------|-------------------------------|----------|
| 1 | silver_knight | silver_knight  | silver_knight_20260409.png    | approved |
| 2 | fire_mage     | fire_mage      | fire_mage_20260409.png        | redo     |
```

**Status values**: `approved` / `redo` / `pending`

**Batch retry rules**:
- Only regenerate items marked `redo`. Never touch `approved` items.
- On regeneration, use same `name` param -- new timestamp distinguishes versions.
- If anchor changes, mark all non-approved items as `pending` and re-run.

**Failure recovery** (generation error or timeout):
- Retry the failed item alone with `generate_image` (not batch).
- If repeated failure, simplify prompt (remove one accessory/detail), then iterate back.


**File cleanup** (mandatory after each generation round):

After a batch is complete and results are reviewed, clean up stale files:

1. **Superseded versions**: When a character is regenerated (same `name`, new timestamp),
   the old file is stale. Delete old versions once the new one is `approved`.
2. **Orphan thumbnails/previews**: Check the `preview/` subdirectory for thumbnails
   that no longer correspond to any file in the main directory. Delete them.
3. **Abandoned intermediate artifacts**: If the workflow produced temporary images
   (e.g., test anchors, discarded experiments), delete them before final delivery.

```
Cleanup checklist (run after each generation round):
- [ ] For each name, only ONE file (the latest approved) remains
- [ ] preview/ contains no orphan thumbnails
- [ ] No temporary/experimental files remain
- [ ] File mapping table matches actual files on disk
```

> Do not defer cleanup to the end. Clean after EACH round to avoid accumulation.

### Phase 3: Review and Iterate

Show all results. Run consistency checklist:

- [ ] Rendering method uniform (all flat OR all painterly -- no mix)
- [ ] Line weight / outline style consistent across all characters
- [ ] Light direction and shadow style uniform
- [ ] Saturation and color temperature in same range
- [ ] Head-to-body proportions consistent (within +/-0.5 head)
- [ ] No same-face problem
- [ ] No anchor trait leakage (hair, accessories, pose not copied)
- [ ] Poses sufficiently varied (no 2 adjacent characters identical)
- [ ] Background treatment uniform
- [ ] Variants preserve character identity (single-reference check)
- [ ] Same variant value looks comparable across all characters (text-anchor check)
- [ ] Stale/duplicate files cleaned up after each generation round

**Cross-batch Consistency Gate** (for >10 characters):

After each batch of 10, before proceeding to the next batch:
1. Place the latest batch side-by-side with 3 samples from earlier batches.
2. Check rendering method, line weight, color temperature, and proportions.
3. If any dimension drifts, adjust the style anchor text or swap anchor image before continuing.

**Remediation Decision Tree** (follow in order):

| Symptom | Diagnosis | Action |
|---------|-----------|--------|
| **Rendering method mismatch** (some flat, some painterly in same batch) | Style anchor rendering dimension too vague | 1. Strengthen rendering sentence: specify exact technique (e.g., "flat cel-shaded, NO gradient blending, NO painterly strokes"). 2. Regenerate outliers with reinforced anchor. |
| **Line weight mismatch** (some thick outlines, some lineless) | Mixed rendering interpretation | 1. Add explicit line spec: "consistent N-px black outlines" or "lineless with color-edge separation". 2. If one outlier, `edit_image` to fix that character only. |
| **Color temperature drift** (warm/cool inconsistency) | Style anchor too weak on color | 1. Add explicit temp: "warm-shifted highlights, avoid blue-grey shadows". 2. Use `edit_image` with "Match color temperature and saturation to reference." |
| **Proportion inconsistency** (different head-body ratios) | No proportion spec in anchor | 1. Add "X-head tall proportions" to style anchor. 2. Regenerate outliers. |
| **Trait leakage** (hair/accessory/pose copied from anchor) | Reference image dominance | 1. Drop `reference_images`, regenerate with style anchor text only. 2. If persists, add explicit contrast in prompt: "Unlike the reference, this character has..." |
| **Same-face** (two+ characters look like the same person) | Insufficient facial differentiation | 1. Add unique facial markers in prompt (eye shape, jawline, brow). 2. If persists, swap to a different character as anchor. |
| **Pose repetition** (multiple characters in identical stance) | Prompt reuse / model convergence | 1. Rewrite pose sentence with more specific action verb. 2. Change camera angle for one of the duplicates. |
| **Variant identity drift** (character looks different across variants) | Single reference too weak | 1. Strengthen identity lock: repeat ALL identity features in prompt. 2. Add "This is the SAME person" emphasis. 3. If persists, use `edit_image` on the base portrait instead of `generate_image`. |
| **Variant inconsistency across characters** (same variant value looks different on different characters) | Variant description not specific enough | 1. Make the shared variant description more physically specific (e.g., exact muscle actions, color values, material details). 2. Regenerate the weaker variants with strengthened description. |
| **Variant too aggressive** (character becomes unrecognizable) | Variant description changes too much | 1. Soften the variant description: reduce the degree of change. 2. Strengthen identity markers: "SAME person, same bone structure, same distinguishing marks". |

**When to replace the anchor**:
- 2+ characters exhibit trait leakage even after dropping reference
- Anchor itself scored lowest in consistency review
- Rendering method of anchor doesn't match majority
- Procedure: pick new anchor -> regenerate it solo -> re-run failed characters with new reference

**Regeneration rules**:
- Fix one issue per round (small-step iteration)
- Default: regenerate with `reference_images = [anchor_image_path]`
- Exception: drop reference if trait leakage (see table row 5)
- All variants: always use single reference (character's own base)
- Already-approved characters are never re-generated unless anchor changes

## Guidelines

Defaults, not hard rules. Override when needed.

1. **Discussion first** - Exception: fast mode on explicit request
2. **Style anchor stays stable** - Exception: adjust if it skews results
3. **Style anchor must pass 6-dimension checklist** - No shortcuts
4. **Reference image for consistency** - Exception: drop if trait leakage
5. **Uniform dimensions** - same aspect_ratio, target_size, transparent
6. **Natural language prompts** - sentences, not tag lists. Default Chinese,
   may mix English for specific style terms (e.g. "cel-shaded")
7. **Unique names** - each character name param must be distinct
8. **Repeat full character card** - every prompt includes full identity
9. **Pose scatter** - pre-assign in mandatory table before generation for 6+ characters
10. **Single-reference variants** - all variants use ONLY the character's
    own base portrait as reference; detailed text descriptions drive the change
11. **No variant anchor images** - do NOT generate shared archetype variant images;
    using another character's image as reference causes identity leakage

## Reference

Style presets, character cards, prompt structure, edit templates, negative constraints,
pose/angle scatter pools, variant description examples (FACS expressions, aging cues, etc.)
-> [references/style-guide.md](references/style-guide.md)
