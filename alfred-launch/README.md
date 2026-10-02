# alfred-launch

Go rewrite of `~/workspaces/alfred.mjs`, plus the Alfred workflow that runs it.

## Layout

| Path | What it is |
| --- | --- |
| `main.go` | Subcommand dispatch: `code`, `mdn`, `npm`/`npmx` |
| `code_files.go` | The `code` source — `.code-workspace` files + `~/Development` folders |
| `mdn.go` | The `mdn` source |
| `alfred.go` | Shared `Output`/`Item` JSON shapes |
| `workflow/` | Alfred Launch workflow source (`info.plist`, icons) |

## Build

```sh
cd ~/.config/fish/alfred-launch
go build -o workflow/alfred .     # or: make build
```

The binary is built **into `workflow/`** because Alfred runs a Script Filter with
the workflow folder as its working directory, so the filter can call it as
`./alfred`. The binary is gitignored — only sources and the workflow definition
are committed.

`./setup.sh` builds it and links the workflow automatically (see below).

## Alfred setup

`setup.sh` symlinks `alfred-launch/workflow` into Alfred's workflows directory,
under whatever folder Alfred syncs its preferences to:

```
~/.config/fish/alfred-launch/workflow
  -> ~/Documents/Alfred.alfredpreferences/workflows/user.workflow.1C804719-BF45-4D7A-B15F-4C7C1C0880C3
```

The link keeps the workflow's UUID directory name so Alfred retains the
workflow's identity and bindings.

### Editing the workflow

The link goes both ways, so there is nothing to export or re-import:

- Change the workflow in Alfred's GUI → the files change in this repo. `git diff`
  shows the edit; commit it like any other file.
- `git checkout` / `git restore` a file → Alfred picks the change up on its next
  run of the workflow.

The only step is the initial `./setup.sh` (or `make build` plus the symlink).
`setup.sh` makes no backup and no check: it runs `ln -sfn` straight at the
workflow path. If a real directory is already there, `ln -sfn` *succeeds*
silently but creates `…/user.workflow.1C804719-…/workflow` inside it, and Alfred
keeps loading the old directory — so move any pre-existing real workflow out of
the way yourself before the first install. The commit history is the safety net.

Alfred may rewrite `info.plist` in its own key order or as a binary plist after a
GUI edit, which shows up as a noisy diff. That is expected; keep the semantic
change and let the reformatting ride along.

### The `Launch` workflow

Alfred's preferences are synced to `~/Documents/Alfred.alfredpreferences`
(`syncfolder` in `com.runningwithcrayons.Alfred-Preferences`); `setup.sh` reads
that setting and falls back to `~/Library/Application Support/Alfred`. The
workflow is `user.workflow.1C804719-…`, bundle id `com.simeonc.Launch`.

| Script Filter | Keyword | Script | Connects to |
| --- | --- | --- | --- |
| `38821287-…` | `cd` | `./alfred code` | Run Script `code "$1"` |
| `910E4B2F-…` | `npm` | `./alfred npmx "{query}"` | Open URL |
| `5E572E80-…` | `mdn` | `./alfred mdn "{query}"` | Open URL |

The `cd` filter **ignores** the query: it returns every workspace and folder and
Alfred does the fuzzy filtering (its `alfredfiltersresults` is `true`), matching
on each item's `match` string. The selected item's `arg` (a `.code-workspace`
path or project folder) is what the Run Script action receives as `$1`.

The `npm`/`mdn` filters do their own searching, so `alfredfiltersresults` is
`false` and the query is passed through. `alfred mdn` works; `alfred npmx` is
still a `TODO` stub in `main.go` and returns a single "TODO" item until it is
implemented.

### Modifier

Items carry `mods.alt` (`Open in Terminal ~/Development/…`). To use it, add an
alt-modifier connection from the Script Filter to an action — the committed
workflow does not wire one up.

## Test

```sh
make test        # or: go test ./...
```

`code_files_test.go` covers the `code` source. The two `mdn_index_test.go` tests
fail: `loadIndex` in `mdn.go` does not implement its caching arguments yet.