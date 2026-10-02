package main

import (
	"os"
	"path"
)

type Item struct {
	UID      string `json:"uid,omitempty"`
	Title    string `json:"title"`
	Subtitle string `json:"subtitle,omitempty"`
	Arg      string `json:"arg,omitempty"`
	Match    string `json:"match,omitempty"`
	Mods     *Mods  `json:"mods,omitempty"`
}

type Mods struct {
	Alt *Modifier `json:"alt,omitempty"`
}

type Modifier struct {
	Subtitle string `json:"subtitle,omitempty"`
	Arg      string `json:"arg,omitempty"`
}

type Output struct {
	Items []Item `json:"items"`
}

func CachePath(fileName string) string {
	return path.Join(os.Getenv("alfred_workflow_cache"), fileName)
}
