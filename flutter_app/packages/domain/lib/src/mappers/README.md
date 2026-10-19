# mappers — the shock absorber

One file per resource. Each maps a **generated DTO** (from `api_scheduler` /
`api_jobportal`) → an app model in `../models/`. When a backend renames a field,
you fix it HERE and nowhere else.

`enum_parsers.dart` is already wired (string → domain enum, unknown-safe).
The DTO mappers land after the first `make gen`, once the generated types exist.

Pattern (add e.g. `batch_mapper.dart` after gen):

```dart
import 'package:api_scheduler/api_scheduler.dart';   // generated DTO
import '../models/batch_summary.dart';
import 'enum_parsers.dart';

BatchSummary batchFromDto(BatchDto dto) => BatchSummary(
      id: dto.id,
      name: dto.name,
      status: parseBatchStatus(dto.status),
      facultyName: dto.facultyName,
      // ...backend rename? change ONLY this line.
    );
```

Then export it from `domain.dart`. UI keeps importing `BatchSummary`, unaware
the wire shape moved.
