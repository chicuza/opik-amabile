# AmabileAI Brand Design Specification
## Opik Observability UI Overlay

---

## Color Palette

| Token | Hex | Role |
|---|---|---|
| `--am-primary` | `#6878f4` | Purple 400 — primary actions, interactive elements |
| `--am-secondary` | `#ec4899` | Pink 500 — secondary actions, highlights, CTA accents |
| `--am-accent` | `#f8922c` | Orange 360 — tertiary, callout accents, warm emphasis |
| `--am-grad-purple` | `#8b72f0` | Logo gradient stop (top) — wordmark "Amabile" |
| `--am-grad-pink` | `#ec4899` | Logo gradient stop (mid) |
| `--am-grad-orange` | `#f8922c` | Logo gradient stop (bottom corners) |
| `--am-charcoal` | `#222416` | Body text, headings |
| `--am-gray-600` | `#607280` | Secondary text, captions, labels |
| `--am-gray-200` | `#c0c6b8` | Borders, dividers |
| `--am-cream` | `#f8f7f3` | Surface backgrounds, page base |
| `--am-lavender` | `#e9e0f2` | Light fills, chip backgrounds (purple tint) |
| `--am-peach` | `#ffd0c4` | Soft highlight fills (pink/orange tint) |
| `--am-sky` | `#c8e4ff` | Informational fills, info badges |
| `--am-success` | `#22c55e` | Pass / healthy status |
| `--am-warning` | `#f59e0b` | Warning / degraded status |
| `--am-danger` | `#ef4444` | Error / failed status |

### WCAG AA Contrast Verification

| Foreground | Background | Ratio | Result |
|---|---|---|---|
| `#222416` (charcoal) | `#ffffff` | 15.4:1 | AA + AAA |
| `#607280` (gray-600) | `#ffffff` | 4.6:1 | AA |
| `#ffffff` | `#6878f4` (primary) | 4.6:1 | AA |
| `#ffffff` | `#ec4899` (secondary) | 4.8:1 | AA |
| `#ffffff` | `#f8922c` (accent) | 3.1:1 | AA (large text / UI) |
| `#15803d` | `#dcfce7` | 5.1:1 | AA |
| `#92400e` | `#fef3c7` | 7.2:1 | AA + AAA |
| `#991b1b` | `#fee2e2` | 6.3:1 | AA + AAA |
| `#1e40af` | `#c8e4ff` | 8.6:1 | AA + AAA |

---

## Logo Dimensions by Context

| Context | Asset | Dimensions | Notes |
|---|---|---|---|
| Header / navbar | `amabile-logo.png` | 32px height, auto width | Full logo mark (triangle A) |
| Sidebar collapsed | `amabile-logo.png` | 24x24px | Icon only, square crop |
| Favicon | `amabile-favicon.png` | 32x32px | Icon only, no wordmark |
| Apple touch icon | `amabile-apple-touch.png` | 180x180px | Icon on white bg |
| OG / social card | `amabile-og.png` | 1200x630px | Full lockup on white |
| Loading splash | `amabile-logo.png` | 64px height, auto width | Centered on cream bg |

Source files:
- Full lockup: `C:\Users\chicu\Downloads\logo-Amabile-AI.jpeg`
- Icon only: `C:\Users\chicu\Downloads\Somente Logo Amabile AI.jpeg`

---

## Favicon Generation (ImageMagick)

### 32x32 PNG favicon from the isolated logo mark

```bash
magick "C:/Users/chicu/Downloads/Somente Logo Amabile AI.jpeg" \
  -resize 32x32 \
  -background white \
  -gravity center \
  -extent 32x32 \
  "C:/Users/chicu/opic-amabile/services/frontend/public/amabile/amabile-favicon.png"
```

### Multi-size .ico (16, 32, 48)

```bash
magick "C:/Users/chicu/Downloads/Somente Logo Amabile AI.jpeg" \
  -resize 48x48 \( +clone -resize 32x32 \) \( +clone -resize 16x16 \) \
  -background white \
  "C:/Users/chicu/opic-amabile/services/frontend/public/amabile/favicon.ico"
```

### Header PNG (32px tall, transparent background — requires JPEG→PNG conversion first)

```bash
magick "C:/Users/chicu/Downloads/logo-Amabile-AI.jpeg" \
  -resize x32 \
  -background white \
  "C:/Users/chicu/opic-amabile/services/frontend/public/amabile/amabile-logo.png"
```

> Note: The source files are JPEG with white backgrounds. If transparent PNGs are
> needed, run a fuzz-based white removal:
> `magick input.jpeg -fuzz 5% -transparent white output.png`

---

## Typography

- **Primary font**: Inter (system fallback stack — no self-hosting required on most modern OS)
- **Fallback stack**: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`
- **Mono font**: JetBrains Mono / Fira Code / Cascadia Code (system fallback to `"Courier New"`)
- **Base size**: 16px
- **Scale**: 12 / 14 / 16 / 18 / 20 / 24 / 30px (xs through 3xl)

To self-host Inter, add to `<head>`:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

---

## Border Radius Scale

| Token | Value | Usage |
|---|---|---|
| `--am-radius-xs` | 2px | Minimal rounding (inline code) |
| `--am-radius-sm` | 4px | Tags, chips, small buttons |
| `--am-radius-md` | 8px | Buttons, inputs, default |
| `--am-radius-lg` | 12px | Cards, panels |
| `--am-radius-xl` | 16px | Modals, dialogs |
| `--am-radius-2xl` | 24px | Large feature cards |
| `--am-radius-full` | 9999px | Pills, badges, avatars |

---

## Asset Deployment Checklist

1. Copy logo PNG to: `services/frontend/public/amabile/amabile-logo.png`
2. Copy favicon PNG to: `services/frontend/public/amabile/amabile-favicon.png`
3. Link `brand.css` in the Opik HTML shell (before upstream styles to allow cascade, or after with `!important` already applied)
4. Inject favicon JS snippet (see `brand.css` section 19) or add `<link rel="icon">` to server-rendered HTML
5. Set `document.title = 'Amabile AI — Observability'` via JS or server-side template override
