BIN := workflow/alfred

.PHONY: build test clean

# Alfred runs the Script Filter with the workflow folder as its working
# directory, so the binary is built next to info.plist and called as ./alfred.
build:
	go build -o $(BIN) .

test:
	go test ./...

clean:
	rm -f $(BIN)