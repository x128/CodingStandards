# Document Skill

Generate clear, useful documentation following clean code principles.

## Instructions

When invoked, generate appropriate documentation:

1. **Identify scope**:
   - Specific file/function if provided
   - Public API if documenting a module
   - Architecture if documenting system

2. **Apply documentation principles**:

### Document WHY, Not WHAT
Code shows WHAT; docs explain WHY:
```
// BAD: Restates the code
/// Sets the timeout to 30 seconds
timeout = 30

// GOOD: Explains the reason
/// iOS background tasks terminate after 30s; this ensures completion
timeout = 30
```

### Document Public APIs
Every public interface needs docs:
```
/**
 * Exports project to video file.
 *
 * Combines all video and audio tracks, applies effects,
 * and encodes to the specified format.
 *
 * @param project Project to export (must have at least one track)
 * @param options Export configuration
 * @returns Path to exported file
 * @throws InsufficientStorageError if disk space < estimated size
 * @throws InvalidProjectError if project has no tracks
 *
 * @example
 * val path = exporter.export(project, ExportOptions(format = MP4))
 */
fun export(project: Project, options: ExportOptions): Path
```

### Keep Docs Close to Code
- Inline docs in source files
- Update docs when code changes
- Delete docs for deleted code

### Use Examples
Show, don't just tell:
```
/**
 * Formats duration as human-readable string.
 *
 * @example
 * formatDuration(90)    // "1:30"
 * formatDuration(3661)  // "1:01:01"
 * formatDuration(0)     // "0:00"
 */
fun formatDuration(seconds: Int): String
```

3. **Documentation types**:

### Function/Method Documentation
```
/**
 * [Brief one-line description]
 *
 * [Longer explanation if needed - when to use, caveats, etc.]
 *
 * @param name Description of parameter
 * @returns Description of return value
 * @throws ExceptionType When/why this is thrown
 *
 * @example
 * [Usage example]
 */
```

### Class/Module Documentation
```
/**
 * [One-line purpose]
 *
 * [Responsibilities - what this class does]
 * [Usage context - when to use this]
 * [Dependencies - what it needs]
 *
 * @example
 * val service = UserService(repository)
 * val user = service.findById(id)
 */
class UserService
```

### Architecture Documentation
```
# [Component Name]

## Purpose
[Why this exists, what problem it solves]

## Responsibilities
- [What it does]
- [What it doesn't do]

## Dependencies
- [What it depends on]
- [What depends on it]

## Data Flow
[How data moves through]

## Key Decisions
- [Decision]: [Rationale]
```

4. **Avoid**:
- Redundant comments (code already clear)
- Commented-out code (use version control)
- TODO comments without tickets
- Outdated documentation
- Documentation for private implementation details

5. **Output format**:

For code documentation:
```
## Documentation: [target]

### Public API
[Generated docs for public methods/classes]

### Usage Examples
[Code examples showing common usage]

### Notes
[Any important caveats or context]
```

For architecture docs:
```
# [Component/System Name]

## Overview
[High-level description]

## Architecture
[Structure and relationships]

## Key Concepts
[Domain terms and their meaning]

## Usage
[How to use/interact with this]
```

## Allowed Prompts
- Read source files
- Analyze code structure
- Write documentation

## Example Usage

```
/document src/services/ExportService.kt
/document --api (generates API reference)
/document --architecture (generates architecture overview)
```
