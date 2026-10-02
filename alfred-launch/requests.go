package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

func GetUrlBytes(URL string) ([]byte, error) {
	resp, err := http.Get(URL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Get returned status %d for %s", resp.StatusCode, URL)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return body, nil
}

func DecodeJson[V any](in []byte, result *V) error {
	err := json.Unmarshal(in, &result)
	if err != nil {
		return fmt.Errorf("Failed to read response %s\n%s", err, string(in))
	}
	return nil
}

func GetUrl[V any](URL string, result *V) error {
	body, err := GetUrlBytes(URL)
	if err != nil {
		return err
	}
	return DecodeJson(body, &result)
}
