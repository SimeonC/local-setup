package main

import "testing"

func TestRunWithoutSourceIsAnError(t *testing.T) {
	if _, err := run([]string{}); err == nil {
		t.Fatal("expected an error when no source is given")
	}
}

func TestRunWithUnknownSourceIsAnError(t *testing.T) {
	if _, err := run([]string{"bing", "flexbox"}); err == nil {
		t.Fatal("expected an error for an unknown source")
	}
}

func TestRunWithEmptyQueryPromptsToType(t *testing.T) {
	// mdn is absent on purpose: it takes no query, so there is no empty-query
	// case to prompt for, and MDN() reaches the network rather than a fixture.
	cases := [][]string{
		{"Type to search npmx", "npm"},
		{"Type to search npmx", "npmx", "   "},
	}
	for _, args := range cases {
		want, args := args[0], args[1:]
		out, err := run(args)
		if err != nil {
			t.Fatalf("run(%q) returned error: %v", args, err)
		}
		if len(out.Items) != 1 || out.Items[0].Title != want {
			t.Errorf("run(%q) = %+v, want a single item titled %q", args, out.Items, want)
		}
	}
}
