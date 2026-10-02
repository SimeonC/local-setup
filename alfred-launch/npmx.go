package main

import (
	"net/url"
	"strings"
)

const (
	npmBaseUrl  = "https://registry.npmjs.org"
	npmxBaseUrl = "https://npmx.dev"
)

type packageResult struct {
	Package struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		Version     string `json:"version"`
	} `json:"package"`
}

type searchResults struct {
	Objects []packageResult `json:"objects"`
}

func searchNpmx(baseURL, query string) (Output, error) {
	var search searchResults
	err := GetUrl(baseURL+"/-/v1/search?"+url.Values{"text": {query}}.Encode(), &search)
	if err != nil {
		return zero, err
	}
	v := Output{Items: make([]Item, 0, len(search.Objects))}
	for _, p := range search.Objects {
		v.Items = append(v.Items, Item{
			Title:    p.Package.Name,
			Subtitle: p.Package.Description,
			Arg:      npmxBaseUrl + "/package/" + p.Package.Name,
		})
	}
	return v, nil
}

func emptyReturn() (Output, error) {
	return Output{
		Items: []Item{
			{Title: "Type to search npmx"},
		},
	}, nil
}

func NPMX(query string) (Output, error) {
	if strings.TrimSpace(query) == "" {
		return emptyReturn()
	}
	return searchNpmx(npmBaseUrl, query)
}
