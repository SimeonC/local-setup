package main

import (
	"encoding/json"
	"testing"
)

func TestOutputMarshalsToAlfredJSON(t *testing.T) {
	got, err := json.Marshal(Output{Items: []Item{
		{Title: "Flexbox", Subtitle: "A layout model", Arg: "https://developer.mozilla.org/en-US/docs/Glossary/Flexbox"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	want := `{"items":[{"title":"Flexbox","subtitle":"A layout model","arg":"https://developer.mozilla.org/en-US/docs/Glossary/Flexbox"}]}`
	if string(got) != want {
		t.Errorf("\n got: %s\nwant: %s", got, want)
	}
}

func TestEmptyFieldsAreOmitted(t *testing.T) {
	got, err := json.Marshal(Item{Title: "Type to search"})
	if err != nil {
		t.Fatal(err)
	}
	want := `{"title":"Type to search"}`
	if string(got) != want {
		t.Errorf("\n got: %s\nwant: %s", got, want)
	}
}
