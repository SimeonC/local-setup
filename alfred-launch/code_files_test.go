package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fakeHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	for _, dir := range []string{workspacesDirName, developmentDirName} {
		if err := os.MkdirAll(filepath.Join(home, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return home
}

func mkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	mkdir(t, filepath.Dir(path))
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func itemByUID(t *testing.T, out Output, uid string) Item {
	t.Helper()
	for _, item := range out.Items {
		if item.UID == uid {
			return item
		}
	}
	t.Fatalf("no item with uid %q in %+v", uid, out.Items)
	return Item{}
}

func countUID(out Output, uid string) int {
	n := 0
	for _, item := range out.Items {
		if item.UID == uid {
			n++
		}
	}
	return n
}

func TestDevelopmentFoldersBecomeItems(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", "accounting_app"))

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	item := itemByUID(t, out, "accounting_app")
	if item.Title != "Accounting App" {
		t.Errorf("title = %q, want %q", item.Title, "Accounting App")
	}
	if item.Subtitle != "~/Development/accounting_app" {
		t.Errorf("subtitle = %q, want %q", item.Subtitle, "~/Development/accounting_app")
	}
	if want := filepath.Join(home, "Development", "accounting_app"); item.Arg != want {
		t.Errorf("arg = %q, want %q", item.Arg, want)
	}
	if strings.Contains(item.Subtitle, "[workspace]") {
		t.Errorf("plain folder should not be marked as a workspace: %q", item.Subtitle)
	}
}

func TestIgnoredDirectoriesAreSkipped(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", ".idea"))
	mkdir(t, filepath.Join(home, "Development", ".worktrees", "loose"))

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	for _, uid := range []string{".idea", ".worktrees"} {
		if countUID(out, uid) != 0 {
			t.Errorf("uid %q should not be listed: %+v", uid, out.Items)
		}
	}
}

// node_modules is only skipped while walking .worktrees; a top-level
// Development/node_modules is listed, matching the original script.
func TestTopLevelNodeModulesIsListed(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", "node_modules"))
	mkdir(t, filepath.Join(home, "Development", ".worktrees", "repo", "node_modules"))

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	if countUID(out, "node_modules") != 1 {
		t.Errorf("top-level node_modules should be listed once: %+v", out.Items)
	}
}

func TestSingleFolderWorkspaceReplacesItsFolder(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", "booking-form"))
	writeFile(t, filepath.Join(home, workspacesDirName, "booking-form.code-workspace"),
		`{"folders":[{"path":"../Development/booking-form"}]}`)

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	if n := countUID(out, "booking-form"); n != 1 {
		t.Fatalf("booking-form listed %d times, want 1: %+v", n, out.Items)
	}
	item := itemByUID(t, out, "booking-form")
	if want := "~/Development/booking-form [workspace]"; item.Subtitle != want {
		t.Errorf("subtitle = %q, want %q", item.Subtitle, want)
	}
	if want := filepath.Join(home, workspacesDirName, "booking-form.code-workspace"); item.Arg != want {
		t.Errorf("arg = %q, want %q", item.Arg, want)
	}
}

func TestMultiFolderWorkspaceUsesWorktreeLocation(t *testing.T) {
	home := fakeHome(t)
	base := filepath.Join(home, "Development", "free-sizing")
	for _, name := range []string{"svg-floor-plan-free-sizing", "monolith-free-sizing"} {
		mkdir(t, filepath.Join(base, name))
	}
	writeFile(t, filepath.Join(home, workspacesDirName, "free-sizing.code-workspace"),
		`{"folders":[`+
			`{"path":"../Development/free-sizing/svg-floor-plan-free-sizing"},`+
			`{"path":"../Development/free-sizing/monolith-free-sizing"}]}`)

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	item := itemByUID(t, out, "free-sizing")
	// A multi-folder workspace is not flagged [workspace] — only single-folder
	// ones are, matching the original script.
	if want := "~/Development/free-sizing [svg-floor-plan, monolith]"; item.Subtitle != want {
		t.Errorf("subtitle = %q, want %q", item.Subtitle, want)
	}
	// The Development folder "free-sizing" is covered by the workspace.
	if n := countUID(out, "free-sizing"); n != 1 {
		t.Errorf("free-sizing listed %d times, want 1: %+v", n, out.Items)
	}
}

func TestWorkspaceMatchingFeedsMatchString(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", "tablekit"))
	writeFile(t, filepath.Join(home, workspacesDirName, "tablekit.code-workspace"),
		`{"folders":[{"path":"../Development/tablekit"}],"matching":"table kit"}`)

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	item := itemByUID(t, out, "tablekit")
	if !strings.HasPrefix(item.Match, "table kit Tablekit tablekit ") {
		t.Errorf("match = %q, want it to lead with the workspace matching value", item.Match)
	}
}

func TestNestedWorktreeProjectsAreFound(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", ".worktrees", "fish", ".git"))
	mkdir(t, filepath.Join(home, "Development", ".worktrees", "monorepo", "pkg", ".git"))
	mkdir(t, filepath.Join(home, "Development", ".worktrees", "not-a-repo", "nested"))

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	fish := itemByUID(t, out, "fish")
	if want := "~/Development/.worktrees/fish"; fish.Subtitle != want {
		t.Errorf("fish subtitle = %q, want %q", fish.Subtitle, want)
	}
	if want := filepath.Join(home, "Development", ".worktrees", "fish"); fish.Arg != want {
		t.Errorf("fish arg = %q, want %q", fish.Arg, want)
	}
	// The git dir is nested one level down; the location keeps the full
	// .worktrees-relative path while the uid is just the leaf name.
	if pkg := itemByUID(t, out, "pkg"); pkg.Subtitle != "~/Development/.worktrees/monorepo/pkg" {
		t.Errorf("pkg subtitle = %q, want %q", pkg.Subtitle, "~/Development/.worktrees/monorepo/pkg")
	}
	if pkg := itemByUID(t, out, "pkg"); pkg.Arg != filepath.Join(home, "Development", ".worktrees", "monorepo", "pkg") {
		t.Errorf("pkg arg = %q", pkg.Arg)
	}
	if countUID(out, "not-a-repo") != 0 {
		t.Errorf("a .worktrees dir without a git repo should not be listed")
	}
}

func TestUnreadableWorkspaceShowsError(t *testing.T) {
	home := fakeHome(t)
	writeFile(t, filepath.Join(home, workspacesDirName, "broken.code-workspace"), `{{{`)

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	item := itemByUID(t, out, "broken")
	if !strings.HasPrefix(item.Subtitle, "Error reading config, ") {
		t.Errorf("subtitle = %q, want error text", item.Subtitle)
	}
}

// A folder whose name is a prefix of another workspace's name must only fold
// into the workspace covering that exact directory.
func TestFolderPrefixDoesNotStealAnotherWorkspace(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, "Development", "booking-form"))
	mkdir(t, filepath.Join(home, "Development", "booking-form-demo"))
	writeFile(t, filepath.Join(home, workspacesDirName, "booking-form.code-workspace"),
		`{"folders":[{"path":"../Development/booking-form"}]}`)
	writeFile(t, filepath.Join(home, workspacesDirName, "booking-form-demo.code-workspace"),
		`{"folders":[{"path":"../Development/booking-form-demo"}]}`)

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	booking := itemByUID(t, out, "booking-form")
	if want := "~/Development/booking-form [workspace]"; booking.Subtitle != want {
		t.Errorf("booking-form subtitle = %q, want %q", booking.Subtitle, want)
	}
	demo := itemByUID(t, out, "booking-form-demo")
	if want := "~/Development/booking-form-demo [workspace]"; demo.Subtitle != want {
		t.Errorf("booking-form-demo subtitle = %q, want %q", demo.Subtitle, want)
	}
	if len(out.Items) != 2 {
		t.Errorf("got %d items, want 2: %+v", len(out.Items), out.Items)
	}
}

// Worktrees of the same project share a leaf name, so their uids must fall
// back to something unique or Alfred cannot tell them apart.
func TestRepeatedNamesGetUniqueUIDs(t *testing.T) {
	home := fakeHome(t)
	for _, worktree := range []string{"alpha", "beta"} {
		mkdir(t, filepath.Join(home, "Development", ".worktrees", worktree, "settings-frontend", ".git"))
	}

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	var uids []string
	for _, item := range out.Items {
		if item.Title == "Settings Frontend" {
			uids = append(uids, item.UID)
		}
	}
	if len(uids) != 2 {
		t.Fatalf("got %d settings-frontend items, want 2: %+v", len(uids), out.Items)
	}
	if uids[0] == uids[1] {
		t.Errorf("both items share uid %q, want unique uids", uids[0])
	}
	for _, uid := range uids {
		if !strings.Contains(uid, ".worktrees/") {
			t.Errorf("uid %q should fall back to the location", uid)
		}
	}
}

func TestWorkspaceWithTrailingCommasParses(t *testing.T) {
	home := fakeHome(t)
	mkdir(t, filepath.Join(home, ".talon", "user"))
	writeFile(t, filepath.Join(home, workspacesDirName, "talon-user.code-workspace"),
		"{\n  \"folders\": [\n    {\"path\": \"../.talon/user\",},\n  ],\n}")

	out, err := codeFiles(home)
	if err != nil {
		t.Fatal(err)
	}
	item := itemByUID(t, out, "talon-user")
	if want := "~/.talon/user [workspace]"; item.Subtitle != want {
		t.Errorf("subtitle = %q, want %q", item.Subtitle, want)
	}
}

func TestItemRendersModsAndUid(t *testing.T) {
	file := codeFile{
		name:     "ci-toolbox",
		location: "~/Development/ci-toolbox",
		arg:      "/home/me/Development/ci-toolbox",
	}
	got, err := json.Marshal(file.item())
	if err != nil {
		t.Fatal(err)
	}
	want := `{"uid":"ci-toolbox","title":"CI Toolbox","subtitle":"~/Development/ci-toolbox",` +
		`"arg":"/home/me/Development/ci-toolbox","match":" CI Toolbox ci-toolbox ~/Development/ci-toolbox",` +
		`"mods":{"alt":{"subtitle":"Open in Terminal ~/Development/ci-toolbox","arg":"terminal ~/Development/ci-toolbox"}}}`
	if string(got) != want {
		t.Errorf("\n got: %s\nwant: %s", got, want)
	}
}

func TestStartCase(t *testing.T) {
	cases := map[string]string{
		"booking-form-demo":     "Booking Form Demo",
		"ci-toolbox":            "CI Toolbox",
		"accounting_app":        "Accounting App",
		"free-sizing":           "Free Sizing",
		"in-meeting-automation": "IN Meeting Automation",
		"tablekit":              "Tablekit",
		"API":                   "API",
		"sdk":                   "Sdk",
	}
	for in, want := range cases {
		if got := startCase(in); got != want {
			t.Errorf("startCase(%q) = %q, want %q", in, got, want)
		}
	}
}
