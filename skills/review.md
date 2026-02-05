# Code Review Skill

Review code against clean code principles and project standards.

## Instructions

When invoked, perform a thorough code review:

1. **Identify the target**: If a file path or code snippet is provided, review that. Otherwise, review recently modified files or ask for clarification.

2. **Check against standards**: Review the code against these categories:

### Naming
- Are names intention-revealing?
- Do booleans have is/has/can/should prefixes?
- Are functions named with verbs describing actions?
- Are there any magic numbers that should be named constants?

### Functions
- Is each function doing one thing? (Single Responsibility)
- Are functions under 30 lines?
- Do functions have 3 or fewer parameters?
- Is nesting depth 3 levels or less?
- Are there any side effects?

### Classes/Modules
- Does each class have a single responsibility?
- Are dependencies injected rather than created internally?
- Is state immutable where possible?
- Is the class under 200 lines?

### Error Handling
- Are errors handled explicitly (not swallowed)?
- Are exceptions specific and actionable?
- Is null handled safely (no force unwraps)?

### Code Smells
- Duplicate code
- Long methods
- Large classes
- Long parameter lists
- Feature envy
- Dead code

3. **Output format**: Present findings as:

```
## Review: [filename]

### Critical Issues
- [Issue]: [Location] - [Explanation] - [Suggested fix]

### Improvements
- [Suggestion]: [Location] - [Explanation]

### Positive Observations
- [What's done well]

### Summary
[Overall assessment and priority recommendations]
```

4. **Be constructive**: Focus on actionable feedback. Explain WHY something is an issue, not just WHAT.

5. **Prioritize**: Critical issues (bugs, security) > Code smells > Style suggestions

## Allowed Prompts
- Read files to review
- Search for related code patterns
- Check project standards files

## Example Usage

```
/review src/services/UserService.kt
/review (reviews staged changes)
/review --strict (includes minor style issues)
```
