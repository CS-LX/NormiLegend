# Style Reference Guide

## 1. Style Anchor

The style anchor is a shared visual description prefix for all characters.
Write it as **natural language sentences**, not comma-separated tags.

### Components

| Element | Description | Examples |
|---------|-------------|----------|
| Art style | Overall aesthetic | Cel-shaded anime, semi-realistic, pixel art |
| Rendering | Light and material | Flat shading, soft shadows, painterly |
| Color tone | Palette tendency | Warm bright, cool muted, vivid |
| Linework | Outline style | Thin lines, thick lines, lineless |
| **Proportions** | Head-body ratio | 1:6 chibi, 1:7 standard, 1:8 heroic |
| Composition | Framing | Bust, full-body, headshot |
| Background | BG treatment | Transparent, solid color, scenic |
| Quality | Detail level | High-detail CG, game portrait, chibi |

> **Why Proportions?** Without an explicit head-body ratio in the anchor,
> the model drifts between chibi-like and realistic builds across a batch.
> Locking proportions in the shared anchor eliminates this inconsistency.

### Preset Library

Below are ready-to-use style anchors. Pick one or derive your own.

#### Preset A: Semi-Realistic Gongbi Light-Wash

```
Semi-realistic portrait in Chinese gongbi light-wash style.
Precise iron-wire contour lines with controlled thickness variation.
Layered wash shading using low-saturation mineral pigments (HSV saturation 25-45%).
Palette dominated by qinghui grey-blue, yuebai moon-white, shilv mineral-green,
and yanzhi rouge accents. Head-to-body ratio 1:7 standard proportions.
Soft ambient occlusion, no hard shadows. Bust composition with transparent background.
High-detail CG quality with visible brushstroke texture on clothing and hair.
```

**Negative / Avoid**: oil-painting impasto, neon/fluorescent colors, harsh rim light,
anime cel-shading, gold leaf, heavy black outlines, chibi proportions, full-body.

#### Preset B: Anime Cel-Shaded

```
High-quality anime character portrait in modern Japanese cel-shaded style.
Clean thin outlines with consistent weight. Flat color fills with 2-tone
cel shading (base + shadow). Bright vivid palette with saturated hues.
Head-to-body ratio 1:6.5 slight chibi lean. Soft fill lighting with
minimal shadows. Bust composition, solid pastel background.
Game character portrait quality.
```

**Negative / Avoid**: realistic proportions, oil painting texture, complex lighting,
photorealistic rendering, gradient fills, thick outlines, dark/muted palette.
#### Preset C: Pixel Art

```
Detailed pixel art character portrait at 128x128 native resolution.
Clear readable silhouette with anti-aliased edges. Limited 32-color palette
with deliberate dithering for shading. Head-to-body ratio 1:5 compact
proportions. Front-facing bust composition with flat solid color background.
Sharp pixel-perfect details on key features (eyes, hair, accessories).
```

**Negative / Avoid**: smooth gradients, realistic proportions, thin lines,
blurry/soft rendering, large canvas, photorealistic lighting, 3D perspective.

#### Preset D: Semi-Realistic Western Fantasy

```
Semi-realistic fantasy character portrait in western digital painting style.
Painterly rendering with visible brushwork and soft edge blending. Rich warm
palette with dramatic chiaroscuro lighting. Head-to-body ratio 1:8 heroic
proportions. Detailed fabric and material textures. Bust composition with
atmospheric dark background. Concept art quality with high detail on face
and upper body.
```

**Negative / Avoid**: flat shading, anime style, cel outlines, chibi proportions,
bright/pastel palette, pixel art, clean vector lines, transparent background.

#### Preset E: Chibi / Super-Deformed

```
Adorable chibi character portrait in Japanese super-deformed style.
Oversized head with large expressive eyes (40% of face area).
Head-to-body ratio 1:3 extreme chibi. Round simplified features with
minimal nose/mouth detail. Clean medium-weight outlines. Flat bright
colors with simple 1-tone shading. Full-body composition showing complete
chibi figure. Solid pastel or transparent background.
```

**Negative / Avoid**: realistic proportions, detailed anatomy, complex lighting,
small eyes, defined nose, mature features, dark palette, painterly texture.

#### Preset F: Watercolor Storybook

```
Gentle watercolor character portrait in children storybook illustration style.
Soft wet-on-wet edges with visible paper texture. Delicate linework in
light brown/sepia ink. Muted warm palette with limited saturation.
Head-to-body ratio 1:5 slightly stylized. Soft natural lighting with
watercolor bloom effects. Bust composition with white/cream background
showing paper grain. Whimsical hand-drawn quality.
```

**Negative / Avoid**: digital/clean rendering, sharp edges, neon colors,
realistic proportions, dark themes, heavy outlines, cel shading, metallic textures.

---

## 2. Character Differentiation

Each character needs a **character card** specifying unique visual traits.
Spread characters across multiple visual dimensions to maximize recognizability.

### Differentiation Dimensions

| Dimension | Role | Example Spread |
|-----------|------|---------------|
| Hair style | Primary silhouette | Long/short/braided/bun/ponytail |
| Hair color | Quick ID | Black/silver/red/brown/blue |
| Eye color | Emotional anchor | Amber/green/grey/blue/crimson |
| Skin tone | Ethnic variety | Warm ivory/cool pale/tan/brown/dark |
| Outfit style | Culture/class signal | Robe/armor/casual/formal/uniform |
| Outfit color | Team/faction coding | Blue set/red set/earth tones |
| Accessories | Detail recognition | Earring/scar/tattoo/glasses/hairpin |
| Build / body type | Silhouette variety | Slender/muscular/stocky/petite |
| Age range | Demographic spread | Teen/young adult/middle-aged/elder |
| Facial features | Bone structure | Round face/angular jaw/high cheekbones |

### Character Card Template

```markdown
### Character [ID]: [Name]

**Identity Features (MUST preserve across all variants):**
- Hair: [style], [color]
- Eyes: [color], [shape]
- Skin: [tone]
- Face: [distinctive bone structure features]
- Build: [body type]
- Age: [base age range]

**Outfit & Accessories:**
- Main garment: [description]
- Colors: [primary], [secondary]
- Key accessory: [item that aids recognition]

**Personality Visual Cues:**
- Posture tendency: [upright/relaxed/guarded]
- Default expression: [calm/cheerful/stern]

**Avoid (to prevent confusion with other chars):**
- [Trait that would overlap with Character X]
```

### Batch Differentiation Table

Before generating, fill this comparison table to verify sufficient spread:

| Trait | Char 1 | Char 2 | Char 3 | Char 4 | Char 5 |
|-------|--------|--------|--------|--------|--------|
| Hair style | | | | | |
| Hair color | | | | | |
| Eye color | | | | | |
| Skin tone | | | | | |
| Outfit type | | | | | |
| Outfit color | | | | | |
| Key accessory | | | | | |
| Build | | | | | |

**Rule**: No two characters should share the same value in more than 2 rows.

---

## 3. Prompt Composition

### Structure

Every generation prompt follows this template:

```
[Style Anchor]

[Character-specific traits from card]

[Pose & Angle from section 5 scatter pool]

[Expression / Age description from section 6 if variant]

[Avoid list]
```

### Reference Image Guidelines

1. **Base portraits (Step 3)**: Use the style anchor image as reference to lock art style.
2. **Variants (Step 4)**: Use ONLY the character own base portrait as reference.
3. Keep `reference_images` array to a single entry for variants.
4. The reference image provides identity lock; text provides the delta (the specific change for that variant).
5. **For variants**: Use ONLY the character own base portrait. Never use another character image.

> **IMPORTANT**: Do NOT use a different character face as reference for variants.
> This causes identity leakage (the reference character bone structure
> bleeds into the target character). Always single-reference with own base.

---

## 4. Reference Image Strategy

| Step | Reference Source | Purpose |
|------|-----------------|---------|
| Style Anchor (Step 2) | User-provided or first generation | Lock art style |
| Base Portraits (Step 3) | Style Anchor image | Lock art style for all characters |
| Variants (Step 4) | Character OWN base portrait | Lock identity, text drives the change |

### Rules

1. Style anchor reference ensures all characters share the same art style.
2. For base portraits, the style anchor image is the ONLY reference.
3. Character differentiation comes from TEXT, not from reference images.
4. Never use more than 1 reference image for variant generation.
5. **For variants: Use ONLY the character own base portrait as the single reference.**
   Using a shared variant anchor or another character image causes identity leakage.

---

## 5. Pose & Angle Scatter Pools

To avoid all characters looking identical in composition, assign different
poses and angles from these pools.

### Pose Pool (12 options)

| ID | Pose | Description |
|----|------|-------------|
| P1 | Neutral stand | Relaxed standing, arms at sides |
| P2 | Arms crossed | Arms folded across chest |
| P3 | Hand on hip | One hand resting on hip |
| P4 | Hand raised | One hand near face/hair |
| P5 | Leaning | Slight lean to one side |
| P6 | Sitting | Seated pose, upper body visible |
| P7 | Looking back | Head turned, body at angle |
| P8 | Action ready | Dynamic weight shift, alert stance |
| P9 | Contemplative | Hand on chin or holding object |
| P10 | Salute/Wave | Hand raised in greeting |
| P11 | Reading/Holding | Holding a book, weapon, or item |
| P12 | Back turned | Partial back view, head turned |

### Angle Pool (6 options)

| ID | Angle | Description |
|----|-------|-------------|
| A1 | Front | Direct front-facing |
| A2 | 3/4 Left | Turned ~30-45 degrees left |
| A3 | 3/4 Right | Turned ~30-45 degrees right |
| A4 | Profile Left | Full left side view |
| A5 | Profile Right | Full right side view |
| A6 | Slight high angle | Camera slightly above eye level |

### Mandatory Pose-Angle Assignment Table

**MUST fill this table BEFORE writing any base portrait prompts.**
No two characters may share the same Pose+Angle combination.

| Character | Assigned Pose | Assigned Angle | Combination |
|-----------|--------------|----------------|-------------|
| Char 1 | P? | A? | |
| Char 2 | P? | A? | |
| Char 3 | P? | A? | |
| Char 4 | P? | A? | |
| Char 5 | P? | A? | |

**Rules:**
- Each character MUST have a unique Pose+Angle combination.
- Prefer spreading across different pose categories (don not cluster all in P1-P3).
- The assigned pose and angle are LOCKED for all variants of that character
  (all variants keep the same pose and angle as the base, unless pose is the variant dimension).

---

## 5.5. Clothing Differentiation Pool

Beyond pose and angle, clothing is a major identity signal. Use this pool
to ensure outfit diversity.

### Garment Types

| Category | Options |
|----------|---------|
| Upper body | Robe, armor plate, tunic, vest, jacket, cape, bare chest |
| Neckline | High collar, V-neck, round neck, off-shoulder, scarf |
| Sleeves | Long, short, sleeveless, asymmetric, rolled up |
| Layers | Single layer, layered, cape/cloak overlay |
| Material feel | Silk/satin, leather, metal, cotton/linen, fur |

### Color Assignment Strategy

Assign each character a **primary + secondary** color pair. Avoid overlap:

| Character | Primary | Secondary | Accent |
|-----------|---------|-----------|--------|
| Char 1 | | | |
| Char 2 | | | |
| Char 3 | | | |
| ... | | | |

**Rule**: Primary colors must all be different.
Secondary colors may repeat if primaries are sufficiently distinct.

---

## 6. Variant Description Examples

This section provides **reusable variant description templates** for common dimensions.
Variant dimensions are user-defined (see SKILL.md Step 4). The examples below
demonstrate the level of physical specificity needed for consistent results.
Copy and adapt these templates for your project; add new dimensions as needed.

### 6.1 Example: Expression Variants (FACS-Level)

Facial expressions benefit from FACS (Facial Action Coding System) Action Unit descriptions.
This level of anatomical specificity produces consistent results across characters
without relying on reference images.

| Expression | FACS Action Units | Detailed Description (for prompt) |
|-----------|-------------------|----------------------------------|
| **angry** | AU4 (brow lowerer) + AU7 (lid tightener) + AU23 (lip tightener) + AU24 (lip pressor) | 眉头紧蹙下压（眉间出现纵向褶皱），上眼睑收紧使眼神锐利，双唇紧抿向内压缩（嘴唇变薄），下颌肌肉紧张，鼻翼微微外扩。整体面部肌肉向中心聚拢，呈现紧绷愤怒的状态。 |
| **fear** | AU1 (inner brow raise) + AU2 (outer brow raise) + AU5 (upper lid raise) + AU20 (lip stretch) + AU26 (jaw drop) | 眉头内侧和外侧同时上扬（额头出现横向皱纹），上眼睑大幅撑开露出更多眼白（瞳孔收缩感），嘴角向两侧水平拉扯，下颌微张，面部整体呈现向外扩张的紧张状态，颈部肌肉微微绷紧。 |
| **happy** | AU6 (cheek raise) + AU12 (lip corner pull) + AU25 (lips part) | 颧骨处肌肉上提使脸颊饱满隆起，嘴角向上向外拉伸露出上排牙齿，眼睛因脸颊上推而自然眯起呈弯月形（鱼尾纹区域微皱），整体面部肌肉向上提升，呈现放松愉悦的状态。 |
| **hurt** | AU4 (brow lowerer) + AU6 (cheek raise) + AU7 (lid tightener) + AU10 (upper lip raise) + AU43 (eye closure) | 眉头紧皱但不同于愤怒——眉头中段下压而非整体聚拢，一只眼睛半闭或完全闭合（不对称痛苦表情），上唇上提露出犬齿区域（痛苦咧嘴），鼻唇沟加深，面部肌肉呈现收缩挤压状态。 |
| **sad** | AU1 (inner brow raise) + AU4 (brow lowerer) + AU15 (lip corner depress) + AU17 (chin raise) | 眉头内侧上扬而外侧下垂（形成倒八字眉），上眼睑松弛下垂使目光暗淡无神，嘴角向下拉（法令纹加深），下巴肌肉上推使下唇微微噘起，整体面部肌肉向下松弛，呈现沉郁消沉的状态。 |

#### Expression Variant Prompt Template (Example)

```
[style anchor]

This is the SAME character as in the reference image.
Keep ALL identity features EXACTLY: same hairstyle, hair color,
eye color, skin tone, facial bone structure (cheekbone height,
jawline shape, nose bridge form), outfit, accessories, body type,
head-to-body proportions, art style, and linework weight.
Keep the same pose, angle, composition, and background.

ONLY change the facial expression to [expression_chinese_name]:
[Copy the full FACS detailed description from the table above]

[Character N specific traits from card]
[Avoid list]
```

**Example (angry for character 3):**
```
Semi-realistic portrait in Chinese gongbi light-wash style...

This is the SAME character as in the reference image.
Keep ALL identity features EXACTLY: same hairstyle, hair color,
eye color, skin tone, facial bone structure, outfit, accessories,
body type, head-to-body proportions, art style, and linework weight.
Keep the same pose, angle, composition, and background.

ONLY change the facial expression to angry:
[FACS description for angry from the table above]

Silver-haired scholar with narrow grey eyes, angular jawline...
Avoid: red hair, round face, heavy armor...
```

### 6.2 Example: Age Variants (Anatomical Aging)

Age variants modify physical features to show the character at different life stages.
Like all variants, these are driven by text only, using the base portrait as reference.

| Age Stage | Age Range | Anatomical Description (for prompt) |
|-----------|-----------|-------------------------------------|
| **mid** | ~35-45 | 面部轮廓更加成熟分明，颧骨和下颌线条比基础年龄更锐利。眼角出现细纹（鱼尾纹），法令纹加深但不深刻。肤色略暗沉，面部脂肪微减使骨骼感增强。仅鬓角有极少量灰白发丝（不超过5%），发际线无明显变化。体型保持但肌肉线条更沉稳厚重。眼神更加深邂沉稳。 |
| **old** | ~60-75 | 皱纹密布全脸：额头深横纹、眼角放射状鱼尾纹、法令纹深刻如沟、嘴角木偶纹。皮肤松弛下垂（下颌轮廓模糊、眼袋明显、上眼睑下垂）。头发大面积灰白（60-80%）但保留原发色痕迹，发量减少，发际线后退。肤色偏黄暗，出现老年斑点。体型消瘦，肩膀微塌，脊柱微微前倾。双手关节粗大，皮肤薄而显现血管。 |

#### Age Variant Prompt Template (Example)

```
[style anchor]

This is the SAME character as in the reference image, but aged to [age_stage].
Keep ALL identity features that persist through aging: same eye color,
facial bone structure (cheekbone height, jawline shape, nose bridge form),
hairstyle silhouette (though hair may grey), outfit style, accessories,
body proportions tendency, art style, and linework weight.
Keep the same pose, angle, composition, and background.

Age the character to [age_range]:
[Copy the full anatomical aging description from the table above]

[Character N specific traits from card]
[Avoid list]
```

---

### 6.3 Variant Identity Lock Checklist

Before delivering any variant, verify against this checklist:

**Structural Identity (must be pixel-level consistent):**
- [ ] Hair silhouette matches base (same style, length, parting)
- [ ] Hair color matches base (exception: variants that intentionally change it, e.g. aging)
- [ ] Eye color matches base exactly
- [ ] Skin tone matches base (exception: variants that intentionally change it, e.g. aging)
- [ ] Facial bone structure matches base (cheekbone height, jawline, nose bridge)
- [ ] Outfit design matches base (same garment, patterns, accessories)
- [ ] Head-to-body proportions match base
- [ ] Art style and linework weight match base

**Composition Consistency (must match base):**
- [ ] Same pose as base portrait
- [ ] Same camera angle as base portrait
- [ ] Same composition framing as base portrait
- [ ] Same background treatment as base portrait

**Variant-Specific Checks (example: expression):**
- [ ] Only ONE reference image used (character own base portrait)
- [ ] FACS description specifies which muscles move (not just emotion label)
- [ ] No mention of reference image 2 -- there is no second reference
- [ ] Expression change is limited to face; body pose unchanged

**Variant-Specific Checks (example: age):**
- [ ] Only ONE reference image used (character own base portrait)
- [ ] Aging cues are anatomically consistent (wrinkles, skin, hair greying)
- [ ] Core bone structure still recognizable despite aging
- [ ] Hair greying percentage matches the age stage specification

**Common Failures to Watch:**
- Hair color shifts (e.g., black becomes dark brown)
- Eye color drift (e.g., amber becomes brown)
- Outfit simplification (detail loss in accessories)
- Pose drift (subtle angle/hand position changes)
- Art style inconsistency (linework weight changes)
- Identity leakage from wrong reference image (another character features appear)
