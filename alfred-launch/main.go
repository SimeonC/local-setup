package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

var zero Output

func parseArgs(args []string) (method, query string, err error) {
	if len(args) >= 1 {
		return args[0], strings.Join(args[1:], " "), nil
	}
	return "", "", fmt.Errorf("First argument must be one of npm/npmx/mdn/code")
}

func run(args []string) (Output, error) {
	method, query, argsError := parseArgs(args)
	if argsError != nil {
		return zero, argsError
	}
	switch method {
	case "npm", "npmx":
		return NPMX(query)
	case "mdn":
		return MDN()
	case "code":
		return CodeFiles()
	default:
		return zero, fmt.Errorf("First argument must be one of npm/npmx/mdn")
	}
}

func main() {
	enc := json.NewEncoder(os.Stdout)
	output, err := run(os.Args[1:])
	if err != nil {
		enc.Encode(Output{Items: []Item{{Title: err.Error()}}})
	} else {
		enc.Encode(output)
	}
}
