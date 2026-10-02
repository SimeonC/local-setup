package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/yosuke-furukawa/json5/encoding/json5"
)

const (
	workspacesDirName    = "workspaces"
	developmentDirName   = "Development"
	nestedWorkspacesName = ".worktrees"
	workspaceSuffix      = ".code-workspace"
)

type workspaceFolder struct {
	Path string `json:"path"`
}

type workspaceConfig struct {
	Folders  []workspaceFolder `json:"folders"`
	Matching string            `json:"matching"`
}

// codeFile is one candidate entry before it is rendered as an Alfred Item.
type codeFile struct {
	isWorkspace bool
	name        string
	location    string
	arg         string
	match       string
	// folderPath is the plain directory this entry covers. A Development folder
	// with the same path is folded into this entry rather than listed twice.
	folderPath string
	// isAdded marks a workspace that a Development folder already covers, so it
	// is not listed twice.
	isAdded bool
}

// CodeFiles lists code-workspaces and Development project folders for Alfred.
func CodeFiles() (Output, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return zero, err
	}
	return codeFiles(home)
}

func codeFiles(home string) (Output, error) {
	workspacesDir := filepath.Join(home, workspacesDirName)
	developmentDir := filepath.Join(home, developmentDirName)

	workspaces, err := loadWorkspaces(home, workspacesDir)
	if err != nil {
		return zero, err
	}

	names, err := topLevelDirs(developmentDir)
	if err != nil {
		return zero, err
	}

	nestedDir := filepath.Join(developmentDir, nestedWorkspacesName)
	if _, err := os.Stat(nestedDir); err == nil {
		names = append(names, findGitProjectPaths(nestedDir, nestedWorkspacesName)...)
	}

	folders := make([]codeFile, 0, len(names))
	for _, name := range names {
		folders = append(folders, buildFolderEntry(home, developmentDir, name, workspaces))
	}
	for _, w := range workspaces {
		if !w.isAdded {
			folders = append(folders, w)
		}
	}

	// Alfred keys its ordering knowledge off uid, so it must be unique. Names
	// are readable but can repeat (e.g. the same project checked out in several
	// worktrees), so fall back to the location for those.
	nameCounts := make(map[string]int, len(folders))
	for _, folder := range folders {
		nameCounts[folder.name]++
	}

	out := Output{Items: make([]Item, 0, len(folders))}
	for _, folder := range folders {
		item := folder.item()
		if nameCounts[folder.name] > 1 {
			item.UID = folder.location
		}
		out.Items = append(out.Items, item)
	}
	return out, nil
}

// loadWorkspaces reads every *.code-workspace file in dir. A workspace that
// cannot be read is kept, with the error in its location, rather than dropped.
func loadWorkspaces(home, dir string) ([]codeFile, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var workspaces []codeFile
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), workspaceSuffix) {
			continue
		}
		workspaces = append(workspaces, readWorkspace(
			home,
			dir,
			strings.TrimSuffix(entry.Name(), workspaceSuffix),
			filepath.Join(dir, entry.Name()),
		))
	}
	return workspaces, nil
}

func readWorkspace(home, workspacesDir, name, arg string) codeFile {
	entry := codeFile{name: name, arg: arg}
	data, err := os.ReadFile(arg)
	if err != nil {
		entry.location = "Error reading config, " + err.Error()
		return entry
	}
	var config workspaceConfig
	if err := json5.Unmarshal(data, &config); err != nil {
		entry.location = "Error reading config, " + err.Error()
		return entry
	}
	if len(config.Folders) == 0 {
		entry.location = "Error reading config, no folders"
		return entry
	}
	entry.isWorkspace = len(config.Folders) == 1
	entry.match = config.Matching
	if entry.isWorkspace {
		entry.location = tildePath(home, workspacesDir, config.Folders[0].Path)
		entry.folderPath = entry.location
	} else {
		var root string
		root, entry.location = worktreeLocation(home, workspacesDir, config.Folders)
		entry.folderPath = root
	}
	return entry
}

// worktreeLocation names a multi-folder workspace after its common parent
// directory, listing each folder with the parent's name suffix stripped:
// "~/Development/free-sizing [svg-floor-plan, monolith]". It also returns that
// parent directory, which covers the workspace for deduplication.
func worktreeLocation(home, workspacesDir string, folders []workspaceFolder) (root, location string) {
	root = filepath.Dir(tildePath(home, workspacesDir, folders[0].Path))
	strip := regexp.MustCompile(`(?i)-` + regexp.QuoteMeta(filepath.Base(root)) + `$`)
	names := make([]string, 0, len(folders))
	for _, folder := range folders {
		names = append(names, strip.ReplaceAllString(filepath.Base(folder.Path), ""))
	}
	return root, root + " [" + strings.Join(names, ", ") + "]"
}

// tildePath resolves p against base and expresses the result relative to home,
// prefixed with "~/".
func tildePath(home, base, p string) string {
	abs := p
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(base, p)
	}
	abs = filepath.Clean(abs)
	rel, err := filepath.Rel(home, abs)
	if err != nil {
		return abs
	}
	return "~/" + rel
}

// findGitProjectPaths walks dir and returns the relative path of every
// directory that directly contains a .git entry, skipping node_modules.
func findGitProjectPaths(dir, relativePath string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	for _, entry := range entries {
		if entry.Name() == ".git" {
			return []string{relativePath}
		}
	}
	var found []string
	for _, entry := range entries {
		if entry.IsDir() && entry.Name() != "node_modules" {
			found = append(found, findGitProjectPaths(
				filepath.Join(dir, entry.Name()),
				filepath.Join(relativePath, entry.Name()),
			)...)
		}
	}
	return found
}

func topLevelDirs(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, entry := range entries {
		if entry.IsDir() && entry.Name() != ".idea" && entry.Name() != nestedWorkspacesName {
			names = append(names, entry.Name())
		}
	}
	return names, nil
}

// buildFolderEntry turns a Development-relative path into an entry, reusing the
// workspace (and marking it added) when one covers exactly that directory.
func buildFolderEntry(home, developmentDir, relativePath string, workspaces []codeFile) codeFile {
	location := tildePath(home, developmentDir, relativePath)
	for i := range workspaces {
		if workspaces[i].folderPath == location {
			workspaces[i].isAdded = true
			return workspaces[i]
		}
	}
	return codeFile{
		name:     filepath.Base(relativePath),
		location: location,
		arg:      filepath.Join(developmentDir, relativePath),
	}
}

func (f codeFile) item() Item {
	subtitle := f.location
	if f.isWorkspace {
		subtitle += " [workspace]"
	}
	return Item{
		UID:      f.name,
		Title:    startCase(f.name),
		Subtitle: subtitle,
		Arg:      f.arg,
		Match:    f.match + " " + startCase(f.name) + " " + f.name + " " + f.location,
		Mods: &Mods{Alt: &Modifier{
			Subtitle: "Open in Terminal " + f.location,
			Arg:      "terminal " + f.location,
		}},
	}
}

var (
	wordSeparator = regexp.MustCompile(`[-_]`)
	camelBoundary = regexp.MustCompile(`([A-Z])`)
)

// startCase title-cases a name the way the Alfred script does: short words and
// already-uppercase words are kept upper, everything else is capitalised.
func startCase(str string) string {
	var out []string
	for _, word := range strings.Split(wordSeparator.ReplaceAllString(str, " "), " ") {
		if word == strings.ToUpper(word) || utf8.RuneCountInString(word) <= 2 {
			out = append(out, strings.ToUpper(word))
			continue
		}
		for _, w := range strings.Split(camelBoundary.ReplaceAllString(word, " $1"), " ") {
			out = append(out, capitalise(w))
		}
	}
	return strings.Join(out, " ")
}

func capitalise(word string) string {
	if utf8.RuneCountInString(word) <= 2 {
		return strings.ToUpper(word)
	}
	r := []rune(word)
	return strings.ToUpper(string(r[0])) + strings.ToLower(string(r[1:]))
}
