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

### 3. Determine Project ID

Extract the project ID from the download script rather than hardcoding it:

```bash
node -e "const s=require('fs').readFileSync('scripts/download-lokalise-translations.js','utf8'); console.log(s.match(/PROJECT_ID\s*=\s*'([^']+)'/)[1])"
```

If a settings-specific project is needed, check `scripts/` for a separate settings download script.

### 4. Choose Translation Scope

**Ask the user** which languages to provide upfront (before creating keys):

- **"Defined only"** — supply only the languages you have confirmed translations for (typically just `en`). Other locales are left empty for translators to fill in Lokalise.
- **"En and JA"** — supply both English and Japanese. Use this when JA is the primary secondary locale and a JA translation is known or can be confidently derived from existing strings in the codebase.
- **"All languages"** — supply all project locales. Only use this when you have reliable translations for every locale (e.g. derived from very similar existing keys).

### 5. Add Translations via Lokalise CLI

```bash
# Add single (non-plural) translation key — "Defined only" scope (en only)
lokalise2 key create \
  --config="$(echo ~)/lokalise-config.yml" \
  --project-id=<project-id> \
  --key-name="section::subsection::key_name" \
  --platforms=web \
  --translations='[{"language_iso":"en","translation":"Your Translation Text"}]'

# "En and JA" scope
lokalise2 key create \
  --config="$(echo ~)/lokalise-config.yml" \
  --project-id=<project-id> \
  --key-name="section::subsection::key_name" \
  --platforms=web \
  --translations='[{"language_iso":"en","translation":"English Text"},{"language_iso":"ja","translation":"日本語テキスト"}]'
```

Note about the key: In Javascript/Typescript projects sometimes the key will be prefixed with `settings:` - double check if this matches the root of the json file as in some cases this indicates the file and should be omitted from the lokalise key

### Plural Keys

For keys that require plural forms (e.g. model names like "Allocation / Allocations"), use `--is-plural=true` and pass the `translation` value as a CLDR plural **object** (not a string or array):

```bash
# Plural key — "En and JA" scope
lokalise2 key create \
  --config="$(echo ~)/lokalise-config.yml" \
  --project-id=<project-id> \
  --key-name="models::key_name" \
  --platforms=web \
  --is-plural=true \
  --translations='[{"language_iso":"en","translation":{"one":"Singular Form","other":"Plural Form"}},{"language_iso":"ja","translation":{"other":"日本語形式"}}]'
```

- The `translation` field must be a JSON **object** keyed by CLDR category (`one`, `other`, `few`, `many`, `zero`). For English, `one` + `other` is sufficient; for Japanese, `other` only.
- Lokalise creates the locale-appropriate plural category slots for each target language automatically.
- The exported JSON uses `{"one": "...", "other": "..."}` for English and `{"other": "..."}` for languages with one plural form (e.g. Japanese).
- Before providing a JA translation, search the codebase for the same concept in existing JA strings to ensure consistent terminology.

### 6. Download and Merge Translations

Examine the project for existing download scripts.

### 7. Verify Implementation

- Check that translations appear in the locale files
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

- **Project ID**: extract from `scripts/download-lokalise-translations.js` (`PROJECT_ID` constant)
- **Config File**: `$(echo ~)/lokalise-config.yml` (auto-expands to absolute path)
- **Platform**: `web`
- **File Format**: JSON with CLDR plural object shape

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
- Verify project ID by reading `scripts/download-lokalise-translations.js`
- Ensure config file path expands correctly with `$(echo ~)`

### Format Issues
- Double-check key naming uses `::` separators
- Ensure JSON format is correct for translations
- Verify platform is set to `web`
