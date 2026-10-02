package main

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"
)

const (
	mdnBaseURL  = "https://developer.mozilla.org"
	mdnIndexURL = mdnBaseURL + "/en-US/search-index.json"
	mdnCacheAge = 24 * time.Hour
)

func MDN() (Output, error) {
	result, err := loadIndex(CachePath("mdn-cache.json"), mdnIndexURL, mdnCacheAge)
	if err != nil {
		return zero, err
	}
	return indexItems(result, mdnBaseURL), nil
}

func indexItems(data []mdnIndexEntry, baseURL string) Output {
	output := Output{Items: make([]Item, 0, len(data))}
	for _, r := range data {
		arg, _ := url.JoinPath(baseURL, r.URL)
		output.Items = append(output.Items, Item{
			UID:   r.URL,
			Title: r.Title,
			Arg:   arg,
		})
	}
	return output
}

type mdnIndexEntry struct {
	Title string `json:"title"`
	URL   string `json:"url"`
}

func loadFile(cacheFile string) ([]mdnIndexEntry, error) {
	body, err := os.ReadFile(cacheFile)
	if err != nil {
		return nil, err
	}
	var v []mdnIndexEntry
	err = DecodeJson(body, &v)
	if err != nil {
		return nil, err
	}
	return v, nil
}

func loadIndex(cacheFile, indexURL string, maxAge time.Duration) ([]mdnIndexEntry, error) {
	info, err := os.Stat(cacheFile)
	isStale := err != nil || time.Since(info.ModTime()) >= maxAge
	if !isStale {
		v, err := loadFile(cacheFile)
		if err == nil {
			return v, nil
		} else {
			fmt.Fprintf(os.Stderr, "Failed to load cache file @%s\nFalling through to API load\n\nErr: %s", cacheFile, err)
		}
	}
	body, err := GetUrlBytes(indexURL)
	if err != nil {
		return nil, err
	}

	var v []mdnIndexEntry
	err = DecodeJson(body, &v)
	if err != nil {
		return nil, err
	}

	dir := filepath.Dir(cacheFile)
	err = os.MkdirAll(dir, 0o755)
	if err != nil {
		return nil, err
	}
	err = os.WriteFile(cacheFile, body, 0o644)
	if err != nil {
		return nil, err
	}
	return v, nil
}
