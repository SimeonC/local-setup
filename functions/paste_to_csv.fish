function paste_to_csv
    # Get the filename argument
    set filename $argv[1]

    if test -z "$filename"
        echo "Usage: paste_to_csv <filename>"
        echo "Example: paste_to_csv semaphore"
        return 1
    end

    # Get JSON data from clipboard using pbpaste
    set json_data (pbpaste)

    if test -z "$json_data"
        echo "No data found in clipboard"
        return 1
    end

    # Parse JSON array and convert to CSV
    # Use node to parse JSON and output as CSV
    echo $json_data | node -e "
        const fs = require('fs');
        const path = require('path');
        const os = require('os');

        let rawData = require('fs').readFileSync(0, 'utf8').trim();

        // Remove outer quotes if present (common when copying from certain applications)
        if ((rawData.startsWith('\"') && rawData.endsWith('\"')) ||
            (rawData.startsWith(\"'\") && rawData.endsWith(\"'\"))) {
            rawData = rawData.slice(1, -1);
        }

        let data;
        try {
            data = JSON.parse(rawData);
        } catch (e) {
            console.error('Invalid JSON in clipboard:', e.message);
            console.error('Raw data:', rawData);
            process.exit(1);
        }

        if (!Array.isArray(data)) {
            console.error('Clipboard data is not an array');
            process.exit(1);
        }

        // Convert array to CSV (one item per line)
        const csvContent = data.join('\n');

        // Create output path
        const homeDir = os.homedir();
        const outputPath = path.join(homeDir, 'Downloads', process.argv[1] + '.csv');

        // Write to file
        fs.writeFileSync(outputPath, csvContent, 'utf8');
        console.log('CSV saved to:', outputPath);
    " $filename
end
