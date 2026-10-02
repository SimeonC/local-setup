package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

const npmxFixture = `{
	"objects": [
		{
			"package": {
				"name": "vue",
				"version": "3.5.43",
				"description": "The progressive JavaScript framework"
			},
			"score": {"final": 91.2}
		},
		{
			"package": {
				"name": "@vue/reactivity",
				"version": "3.5.43",
				"description": "Reactivity system for Vue"
			},
			"score": {"final": 64.8}
		}
	],
	"total": 170931,
	"time": "2026-10-02T00:00:00.000Z"
}`

// npmx searches the registry server-side, so unlike code and mdn the query is
// sent to the server and the response is already the result set.
func TestSearchNpmxMapsPackagesToItems(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/-/v1/search" {
			t.Errorf("path = %q, want /-/v1/search", r.URL.Path)
		}
		if q := r.URL.Query().Get("text"); q != "vue" {
			t.Errorf("text = %q, want %q", q, "vue")
		}
		w.Write([]byte(npmxFixture))
	}))
	defer srv.Close()

	out, err := searchNpmx(srv.URL, "vue")
	if err != nil {
		t.Fatal(err)
	}
	want := []Item{
		{
			Title:    "vue",
			Subtitle: "The progressive JavaScript framework",
			Arg:      "https://npmx.dev/package/vue",
		},
		{
			Title:    "@vue/reactivity",
			Subtitle: "Reactivity system for Vue",
			Arg:      "https://npmx.dev/package/@vue/reactivity",
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

func TestSearchNpmxReturnsErrorOnBadStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "upstream down", http.StatusBadGateway)
	}))
	defer srv.Close()

	if _, err := searchNpmx(srv.URL, "vue"); err == nil {
		t.Fatal("expected an error for a 502 response")
	}
}

// A query with spaces must be encoded, not pasted raw into the URL.
func TestSearchNpmxEncodesQuery(t *testing.T) {
	var got string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.RawQuery
		w.Write([]byte(`{"objects":[],"total":0}`))
	}))
	defer srv.Close()

	if _, err := searchNpmx(srv.URL, "vue router"); err != nil {
		t.Fatal(err)
	}
	if got != "text=vue+router" {
		t.Errorf("raw query = %q, want %q", got, "text=vue+router")
	}
}