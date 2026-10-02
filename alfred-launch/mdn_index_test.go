package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

const mdnIndexFixture = `[
	{"title": "HTML: HyperText Markup Language", "url": "/en-US/docs/Web/HTML"},
	{"title": "Flexbox", "url": "/en-US/docs/Glossary/Flexbox"}
]`

// indexServer serves the fixture and counts how many times it was hit.
func indexServer(t *testing.T) (*httptest.Server, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.Write([]byte(mdnIndexFixture))
	}))
	t.Cleanup(srv.Close)
	return srv, &hits
}

func TestLoadIndexDownloadsAndWritesCacheFile(t *testing.T) {
	srv, hits := indexServer(t)
	// The directory doesn't exist yet, just like Alfred's cache dir on first run.
	cacheFile := filepath.Join(t.TempDir(), "not-yet-created", "mdn-index.json")

	entries, err := loadIndex(cacheFile, srv.URL, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if hits.Load() != 1 {
		t.Errorf("server hit %d times, want 1", hits.Load())
	}
	if len(entries) != 2 || entries[1].Title != "Flexbox" || entries[1].URL != "/en-US/docs/Glossary/Flexbox" {
		t.Errorf("unexpected entries %+v", entries)
	}
	if _, err := os.Stat(cacheFile); err != nil {
		t.Errorf("cache file was not written: %v", err)
	}
}

func TestLoadIndexUsesFreshCacheWithoutDownloading(t *testing.T) {
	srv, hits := indexServer(t)
	cacheFile := filepath.Join(t.TempDir(), "mdn-index.json")

	for range 2 {
		if _, err := loadIndex(cacheFile, srv.URL, time.Hour); err != nil {
			t.Fatal(err)
		}
	}
	if hits.Load() != 1 {
		t.Errorf("server hit %d times, want 1 (second call should read the cache file)", hits.Load())
	}
}

func TestLoadIndexRefetchesStaleCache(t *testing.T) {
	srv, hits := indexServer(t)
	cacheFile := filepath.Join(t.TempDir(), "mdn-index.json")

	if _, err := loadIndex(cacheFile, srv.URL, time.Hour); err != nil {
		t.Fatal(err)
	}
	// Backdate the file past maxAge without touching its contents.
	old := time.Now().Add(-2 * time.Hour)
	if err := os.Chtimes(cacheFile, old, old); err != nil {
		t.Fatal(err)
	}
	if _, err := loadIndex(cacheFile, srv.URL, time.Hour); err != nil {
		t.Fatal(err)
	}

	if hits.Load() != 2 {
		t.Errorf("server hit %d times, want 2 (stale cache should be refetched)", hits.Load())
	}
}

func TestLoadIndexRefetchesCorruptCache(t *testing.T) {
	srv, hits := indexServer(t)
	cacheFile := filepath.Join(t.TempDir(), "mdn-index.json")
	if err := os.WriteFile(cacheFile, []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}

	entries, err := loadIndex(cacheFile, srv.URL, time.Hour)
	if err != nil {
		t.Fatalf("corrupt cache should heal itself, got: %v", err)
	}
	if hits.Load() != 1 {
		t.Errorf("server hit %d times, want 1 (corrupt cache should be refetched)", hits.Load())
	}
	if len(entries) != 2 || entries[1].Title != "Flexbox" {
		t.Errorf("unexpected entries %+v", entries)
	}

	// The bad file must have been replaced with something parseable.
	var cached []mdnIndexEntry
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &cached); err != nil {
		t.Errorf("cache file still unparseable after refetch: %v", err)
	} else if len(cached) != 2 {
		t.Errorf("cache holds %d entries, want 2", len(cached))
	}
}

func TestLoadIndexErrorsOnCorruptResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("<html>maintenance</html>"))
	}))
	t.Cleanup(srv.Close)
	cacheFile := filepath.Join(t.TempDir(), "mdn-index.json")

	entries, err := loadIndex(cacheFile, srv.URL, time.Hour)
	if err == nil {
		t.Errorf("corrupt API response should be an error, got entries %+v", entries)
	}
	// A failed download must not leave a bogus cache behind.
	if _, statErr := os.Stat(cacheFile); statErr == nil {
		t.Error("cache file was written from a corrupt response")
	}
}

func indexedFixture() []mdnIndexEntry {
	return []mdnIndexEntry{
		{Title: "HTML: HyperText Markup Language", URL: "/en-US/docs/Web/HTML"},
		{Title: "Flexbox", URL: "/en-US/docs/Glossary/Flexbox"},
		{Title: "CSS Flexible Box Layout", URL: "/en-US/docs/Web/CSS/CSS_flexible_box_layout"},
	}
}

// Alfred does the filtering, so indexItems drops nothing: every entry becomes
// an item, in index order. UID is the docs path because it is unique and lets
// Alfred learn the user's ordering.
func TestIndexItemsMapsEveryEntry(t *testing.T) {
	out := indexItems(indexedFixture(), "https://developer.mozilla.org")

	want := []Item{
		{
			UID:   "/en-US/docs/Web/HTML",
			Title: "HTML: HyperText Markup Language",
			Arg:   "https://developer.mozilla.org/en-US/docs/Web/HTML",
		},
		{
			UID:   "/en-US/docs/Glossary/Flexbox",
			Title: "Flexbox",
			Arg:   "https://developer.mozilla.org/en-US/docs/Glossary/Flexbox",
		},
		{
			UID:   "/en-US/docs/Web/CSS/CSS_flexible_box_layout",
			Title: "CSS Flexible Box Layout",
			Arg:   "https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_flexible_box_layout",
		},
	}
	if len(out.Items) != len(want) {
		t.Fatalf("got %d items, want %d: %+v", len(out.Items), len(want), out.Items)
	}
	for i := range want {
		if out.Items[i] != want[i] {
			t.Errorf("item %d:\n got: %+v\nwant: %+v", i, out.Items[i], want[i])
		}
	}
}

func TestIndexItemsJoinsBaseURLWithoutDoublingSlash(t *testing.T) {
	out := indexItems(indexedFixture(), "https://developer.mozilla.org/")

	if got := out.Items[0].Arg; got != "https://developer.mozilla.org/en-US/docs/Web/HTML" {
		t.Errorf("arg = %q, want a single slash between host and path", got)
	}
}

// A nil Items slice marshals as null, which Alfred cannot parse as a result
// list. An index that parses to zero entries must still emit [].
func TestIndexItemsWithNoEntriesMarshalsAsEmptyArray(t *testing.T) {
	got, err := json.Marshal(indexItems(nil, "https://developer.mozilla.org"))
	if err != nil {
		t.Fatal(err)
	}
	if want := `{"items":[]}`; string(got) != want {
		t.Errorf("\n got: %s\nwant: %s", got, want)
	}
}
