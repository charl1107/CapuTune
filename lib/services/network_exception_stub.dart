/// Web variant: dart:io does not exist here, so nothing can ever match
/// [Never]; web errors are never classified as socket failures.
typedef NetworkSocketException = Never;
