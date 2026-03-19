---
name: translation-management
description: Add missing translations using the Lokalise CLI based on Figma designs or code requirements.
---

Add missing translations using Lokalise CLI: $ARGUMENTS

## Prerequisites

- Lokalise CLI (`lokalise2`) must be installed and configured
- Access to the appropriate Lokalise project
- Figma design screenshots or clear translation requirements

## Process Steps

### 1. Identify Missing Translation Keys

- Analyze the component code for translation keys with red squiggly lines
- Cross-reference with Figma designs to understand required text
- Verify keys don't already exist in other sections of the translation files
- Focus only on truly missing keys, not existing ones in different sections

### 2. Determine Correct Key Format

- Lokalise uses double colons (`::`) as separators, not dots
- Format: `section::subsection::key_name`
- Example: `tables::layout::sidebar::reset_turnovers`

### 3. Add Translations via Lokalise CLI

Check the project for existing project-id

```bash
# Add single translation key
lokalise2 key create \
  --config="$(echo ~)/lokalise-config.yml" \
  --project-id=<project id> \
  --key-name="section::subsection::key_name" \
  --platforms=web \
  --translations='[{"language_iso":"en","translation":"Your Translation Text"}]'
```

Note about the key: In Javascript/Typescript projects sometimes the key will be prefixed with `settings:` - double check if this matches the root of the json file as in some cases this indicates the file and should be omitted from the lokalise key

### 4. Download and Merge Translations

Examine the project for existing download scripts.

### 5. Verify Implementation

- Check that translations appear in the English settings file
- Verify red squiggly lines are resolved in the IDE
- Test that translations display correctly in the component

## Key Guidelines

### Translation Key Naming

- Use descriptive, hierarchical naming
- Follow existing patterns in the codebase
- Use snake_case for key names
- Group related keys under common prefixes

### Translation Content

- Match the exact text from Figma designs
- Use proper line breaks (`\n\n`) for multi-line content
- Maintain consistency with existing translation style
- Consider context and user experience

### Project-Specific Settings

- **Settings Project ID**: `312319895ee1e0eb0d1c03.67047114`
- **Config File**: `$(echo ~)/lokalise-config.yml` (auto-expands to absolute path)
- **Platform**: `web`
- **File Format**: JSON with i18next_v4 plural format

## Common Patterns

### Form Field Labels
- Pattern: `section::subsection::field_name`
- Example: `tables::layout::sidebar::start_time`

### Action Buttons
- Pattern: `section::subsection::action_name`
- Example: `tables::layout::sidebar::reset_turnovers`

### Messages and Descriptions
- Pattern: `section::subsection::message_type`
- Example: `tables::layout::sidebar::reset_turnovers_message`

## Troubleshooting

### Key Already Exists
- Check if key exists in different section
- Verify the exact key path being used
- Use existing key if appropriate

### Translation Not Appearing
- Ensure download script completed successfully
- Check that key was added to correct project
- Verify project ID is correct (312319895ee1e0eb0d1c03.67047114 for settings)
- Ensure config file path expands correctly with `$(echo ~)`

### Format Issues
- Double-check key naming uses `::` separators
- Ensure JSON format is correct for translations
- Verify platform is set to `web`
