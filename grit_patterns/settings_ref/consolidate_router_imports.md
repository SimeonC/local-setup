---
title: Change imports from moving files around in the shell script
---

```grit
or {
  import_statement(source=`$file_path`),
  export_statement(source=`$file_path`)
} where {
  $file_path <: contains r"'~\/Pages\/([^\/]+)\/(.*)'"($folder, $rest) where {
    if ($folder <: "Example") {
      $new_folder = `examples`
    } else {
      to_kebab($new_folder, $folder)
    }
  } => `'~/screens/$new_folder/_/$rest'`
}
```

## Test

```ts
import { upsertExampleAudience } from '~/screens/Messaging/api/audience';
import { getDefaultAudienceFormData } from '~/screens/Messaging/AudienceForm/getInitialAudienceFormData';
import { getForm } from '~/screens/Messaging/AudienceForm/getOptions';
import { type ExampleFormData } from '~/screens/Example/types';
export { getOptions } from '~/screens/ExampleResources/ExampleResourceForm/getOptions';
```

```ts
import { upsertExampleAudience } from '~/screens/messaging/_/api/audience';
import { getDefaultAudienceFormData } from '~/screens/messaging/_/AudienceForm/getInitialAudienceFormData';
import { getForm } from '~/screens/messaging/_/AudienceForm/getOptions';
import { type ExampleFormData } from '~/screens/examples/_/types';
export { getOptions } from '~/screens/resources/_/ExampleResourceForm/getOptions';
```
