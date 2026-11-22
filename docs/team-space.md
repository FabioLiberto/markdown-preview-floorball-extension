# Team Space

A Team Space is a folder that syncs with a GitHub repository, so a coaching
staff can keep one playbook of Markdown files and floorball diagrams.

## Setting it up

1. *Settings → Team Space → Sign in with GitHub…* opens github.com with a
   code already copied. Paste it and allow access. The token is stored in
   the Keychain (service `doc.md-preview.github`).
2. Enter the repository as `owner/name`, or paste its github.com URL, and
   click **Connect**. Your account needs push access.
3. **Show in Sidebar** opens the folder. Later, the sidebar's folder menu
   lists it at the top, under *Team Space*, and a file inside it opens with
   the whole Team Space in the sidebar, as a file in a favorite does.

The folder is
`~/Library/Containers/io.github.fabioliberto.md-preview-floorball/Data/Library/Application Support/Team Space/<name>`.
The app keeps its sync state next to it, in `Team Space State/`. Sign Out
and Disconnect stop syncing but leave the files where they are.

## How syncing works

Every sync round, the app compares three versions of each file: the last
synced commit, the folder, and the default branch on GitHub.

- **Changed on one side only:** the change is copied to the other side.
- **Changed on both sides:** edits to different lines are combined, as
  `git merge-file` would combine them. Diagrams store one element per line,
  so two people moving different players combine cleanly. Changes to the
  same or adjacent lines are a conflict. The app asks whether to keep
  **Mine**, **GitHub's**, or **Both**. *Both* saves GitHub's version next to
  yours as `<name> (GitHub).md`. Until you choose, the file stays as it is
  on both sides. *Settings → Team Space* lists open conflicts.

Local changes go up as one commit per round, named after the files and the
Mac. A commit only moves the branch forward. If someone pushed in the
meantime, the round reads the branch again and retries, so it never
overwrites their commit.

Rounds run on the interval set in Settings (15 seconds to 5 minutes), and
when the app comes to the front. A round where nothing changed costs one
request, and GitHub does not count it against the rate limit.

Unsaved edits in an open document are not synced. The file syncs once it
is saved. Automatic saving is on by default (Instant: 2 seconds after you
stop typing), so edits reach GitHub within one sync round. If a sync round
changes a file that is open with unsaved edits, automatic saving skips that
file, and ⌘S shows the usual "changed on disk" choice.

## Not synced

- Hidden files and folders (any name starting with `.`, such as
  `.github/` or `.gitignore`). They stay on GitHub untouched.
- Files over 50 MB.
- Symbolic links and submodules.

An empty repository starts with the first file you add to the folder.
