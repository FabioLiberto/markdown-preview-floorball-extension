<h1 align="center">Markdown Preview Floorball</h1>

<p align="center">
  <img src="docs/markdown-logo.svg" width="128" alt="Markdown Preview Floorball logo" />
</p>

<p align="center">
  A native macOS app for floorball coaches: write training plans and playbooks in Markdown,<br />
  draw tactics right in the document, and keep them in sync with your team on GitHub.
</p>

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-MIT-green" />&nbsp;<img alt="Latest release" src="https://img.shields.io/github/v/release/FabioLiberto/markdown-preview-floorball-extension" /></p>

<p align="center">
  <a href="https://github.com/FabioLiberto/markdown-preview-floorball-extension/releases/latest"><b>⬇︎ Download the latest version</b></a>
</p>

---

> Based on [**Markdown Preview**](https://github.com/pluk-inc/markdown-preview) by Pluk, a fast, native Markdown reader and editor for macOS. This project adds floorball tactics diagrams and a GitHub-synced Team Space, and ships as its own app.

## Download

1. Open the [latest release](https://github.com/FabioLiberto/markdown-preview-floorball-extension/releases/latest) and download `Markdown-Preview-Floorball-<version>.zip`.
2. Open the zip and drag **Markdown Preview Floorball** to your Applications folder.
3. Open the app. macOS says it cannot verify the developer, because the app is not notarized by Apple. Click **Done**, then open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Markdown Preview Floorball. You need to do this once for each version you download.

The app has no automatic updates. For a new version, download it again from [Releases](https://github.com/FabioLiberto/markdown-preview-floorball-extension/releases) and replace the app in Applications. It installs next to the original Markdown Preview without sharing its settings.

Requires macOS 15 or later, on Apple Silicon or Intel.

## Floorball tactics diagrams

A fenced code block with the info string `floorball` draws a floorball rink (full, half, or blank) with players, goalkeepers, balls, cones, goals, markers, text, and run, pass, shot, dribble, and freehand arrows.

````markdown
```floorball
{
  "version": 1,
  "rink": { "layout": "half" },
  "elements": [
    { "id": "p1", "type": "player", "team": "attack", "number": 7, "x": 0.35, "y": 0.65 },
    { "id": "b1", "type": "ball", "x": 0.37, "y": 0.68 }
  ],
  "paths": [
    { "id": "r1", "type": "pass", "points": [[0.35, 0.65], [0.6, 0.4]] }
  ]
}
```
````

You never have to write the JSON yourself. In Edit Mode (<kbd>⌘E</kbd>), **Format → Insert Floorball Diagram** adds an empty rink and opens the diagram editor; click any diagram to edit it again, or use **Edit Diagram** on a diagram in Read Mode. The editor has a tool palette, drag to move, handles to bend arrows, a property bar for team, number, label, style, and color, and keyboard shortcuts (Delete, ⌘Z / ⇧⌘Z, ⌘D, Esc, and a letter per tool).

The diagram is stored in the Markdown file itself, so there is no image file to keep track of. Every change is an ordinary edit to the document: it saves automatically and undoes like typing. Diagrams show in Read Mode, Quick Look, printing, and PDF, PNG, HTML, and EPUB export. One that is not valid JSON, or comes from a newer version, shows an error above its unchanged source.

See [docs/floorball.md](docs/floorball.md) for the format and [samples/floorball.md](samples/floorball.md) for an example.

## Team Space: a playbook shared through GitHub

A Team Space is a folder that stays in sync with a GitHub repository, so a coaching staff can keep one playbook of training plans, match notes, and diagrams.

1. Open **Settings → Team Space** and click **Sign in with GitHub…**. A browser page opens with a code already copied: paste it and allow access.
2. Enter the repository as `owner/name` (or paste its github.com URL) and click **Connect**. Your account needs push access to it.
3. Click **Show in Sidebar**. From then on, the app opens on the Team Space when you start it without a file, and the sidebar's folder menu lists it at the top.

The app checks GitHub every 15 seconds to 5 minutes (you choose), and whenever it comes to the front. Your saved changes go up as one commit per round. When someone else changed the same file, edits to different lines are combined; diagrams keep one player or arrow per line, so two coaches moving different players merge cleanly. When the same lines changed, the app asks whether to keep your version, GitHub's, or both. A push never overwrites someone else's commit.

Signing in gives the app access to your repositories; the token stays in your Keychain. Hidden files such as `.github/` are not synced. See [docs/team-space.md](docs/team-space.md) for the details.

## Automatic saving

Edits save on their own, 2 seconds after you stop typing, so you don't need <kbd>⌘S</kbd>. Change this in **Settings → General → Automatic saving** (Instant, 30 seconds, a few minutes, or Never).

## Everything from Markdown Preview

The rest of the app is Markdown Preview, so it also has:

- **Read and Edit Mode** — a clean preview with a document outline, and in-place editing with a formatting toolbar, task checkboxes, tables, and a plain-text Markdown source view (<kbd>⇧⌘E</kbd>).
- **Mermaid diagrams and math** — fenced `mermaid` blocks and LaTeX math render offline.
- **File navigator** — browse, create, and filter Markdown files in the sidebar, with favorite folders. Right-click a file or folder and choose **Move to Trash** to delete it; you can put it back from the Trash. A file inside a favorite or the Team Space opens with that whole folder in the sidebar. Started without a file, the app opens on the Team Space, or else on a start page with New Document, Open File or Folder…, the Team Space, and your recent files and folders.
- **Search** — find text in a document (<kbd>⌘F</kbd>), or find a document by name (<kbd>⇧⌘O</kbd>).
- **Export and print** — PDF, PNG, HTML, and EPUB, with font size and scale in the print dialog.
- **Quick Look** — press Space on a `.md` file in Finder for a preview, diagrams included.
- **Share as Link** — upload a document encrypted and copy a link anyone can read in a browser (see [Privacy](#privacy)).
- **Open With and Open in LLM** — hand the file to your editor, or to Codex, Claude, or ChatGPT.
- **Command line tools and URL scheme** — `mdp README.md` from a shell, or `md-preview://file/<path>` from a link.

The [Markdown Preview README](https://github.com/pluk-inc/markdown-preview#features) describes each of these in full.

Supported file types: `.md`, `.markdown`, `.mdown`, `.mdx`, `.txt` (UTI `net.daringfireball.markdown`).

## Screenshots

<p align="center">
  <img src="docs/screenshot-main.png" width="820" alt="Main window with document outline sidebar" />
</p>

<p align="center">
  <em>Edit Markdown directly with a native formatting toolbar:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode with document outline and Markdown formatting toolbar" />
</p>

## Privacy

- **No crash reports, no analytics, no update checks.** The app has no Sentry DSN and no PostHog token, and Sparkle never starts. Settings → Privacy still shows those switches from the original app, but there is nothing behind them.
- **Team Space** talks only to GitHub, with your own account.
- **Share as Link** uses the original project's server, `md-preview.app`, on Cloudflare. The document is encrypted on your Mac (AES-256-GCM) before upload, and the key is only in the part of the link after `#`, which browsers never send to a server, so the server cannot read the document, its title, or its images. It does see who connects (IP address), how large each share is, and when it was made and expires. Anyone with the full link can read the document until it expires after 7 days or you stop sharing it.

## Building from source

```sh
git clone https://github.com/FabioLiberto/markdown-preview-floorball-extension.git
cd markdown-preview-floorball-extension
open md-preview.xcodeproj
```

Build and run the `md-preview` scheme. Swift Package Manager resolves [swift-markdown](https://github.com/swiftlang/swift-markdown), [Sparkle](https://github.com/sparkle-project/Sparkle), and [Sentry](https://github.com/getsentry/sentry-cocoa) on the first build. The project's signing team belongs to the original project; without its certificate, build from the command line with ad hoc signing:

```sh
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual build
```

Run the tests with `swift test --package-path tests/swift-tests --parallel`.

## Making a release

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Version.xcconfig`.
2. Run `scripts/package-fork.sh`. It builds a Release copy signed ad hoc and prints the path of the zip, `build/Markdown-Preview-Floorball-<version>.zip`.
3. Publish it with a tag of the form `v<version>`, which What's New in the app reads:

   ```sh
   gh release create v<version> build/Markdown-Preview-Floorball-<version>.zip --title "Markdown Preview Floorball <version>"
   ```

The `release.sh` and `rollback-release.sh` scripts in `scripts/` belong to the original project's release process (Amore, notarization, Sparkle appcast) and are not used here.

## Project layout

```
md-preview/                   Main app target (AppKit, WKWebView)
md-preview/Features/TeamSpace GitHub sync
scripts/editor-bundle/floorball/  Floorball diagram renderer and editor
quick-look/                   Quick Look extension (.appex)
tests/swift-tests/            Swift tests (SPM package over the app's sources)
docs/                         Floorball format and Team Space docs
Version.xcconfig              Marketing & build version
```

## Credits

Markdown Preview Floorball is built on [Markdown Preview](https://github.com/pluk-inc/markdown-preview) by [Pluk](https://pluk.sh) and its contributors. If the original app is useful to you, consider [buying them a coffee](https://buymeacoffee.com/pluk).

It also uses:

- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Pele](https://pele.run/) — bundled renderer for Mermaid diagrams
- [KaTeX](https://katex.org/) — bundled math typesetter
- [Sparkle](https://sparkle-project.org) and [Sentry](https://sentry.io) — included from the original app, switched off in this one

## License

[MIT](LICENSE), as the original project.
