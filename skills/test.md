# Test Skill

Generate and improve tests following clean code testing principles.

## Instructions

When invoked, generate or improve tests:

1. **Identify target**:
   - Specific file/function if provided
   - Untested code if reviewing coverage
   - Modified code if reviewing changes

2. **Analyze code under test**:
   - Understand the public API
   - Identify edge cases
   - Note dependencies that need mocking
   - Check existing tests for patterns

3. **Apply testing principles**:

### Test Naming
Use descriptive names that document behavior:
```
// Pattern: [unit]_[scenario]_[expectedResult]

test_calculateTotal_returnsZero_whenCartIsEmpty()
test_calculateTotal_appliesDiscount_whenCouponIsValid()
test_calculateTotal_throwsError_whenItemsAreNull()
```

### Arrange-Act-Assert (AAA)
Structure every test clearly:
```
test_example() {
    // Arrange - Set up test data and dependencies
    cart = ShoppingCart()
    item = Item(price: 100)

    // Act - Execute the behavior under test
    cart.add(item)
    total = cart.calculateTotal()

    // Assert - Verify the result
    assertEquals(100, total)
}
```

### Test One Concept
Each test should verify one behavior:
```
// BAD: Multiple unrelated assertions
test_user() {
    assert(user.name == "Alice")
    assert(user.isActive)
    assert(emailWasSent)
    assert(auditLogUpdated)
}

// GOOD: Separate tests
test_createUser_setsNameFromInput()
test_createUser_activatesUserByDefault()
test_createUser_sendsWelcomeEmail()
test_createUser_logsToAuditTrail()
```

### Test Behavior, Not Implementation
Focus on WHAT, not HOW:
```
// BAD: Tests internal state
assert(cart._items.length == 1)
assert(cart._internalTotal == 100)

// GOOD: Tests observable behavior
assert(cart.contains(item))
assert(cart.getTotal() == 100)
```

### Test Independence
Each test must be self-contained:
```
// Each test creates its own data
test_A() {
    user = createTestUser()
    // test with user
}

test_B() {
    user = createTestUser()  // Fresh user, not shared
    // test with user
}
```

### Edge Cases to Consider
- Empty inputs (null, empty string, empty list)
- Boundary values (0, 1, max-1, max)
- Invalid inputs (wrong type, out of range)
- Error conditions (network failure, timeout)
- Concurrent access (if applicable)

4. **Generate tests**:

For each public method, create tests for:
- Happy path (normal successful operation)
- Edge cases (boundaries, empty, null)
- Error cases (invalid input, failures)
- State changes (if stateful)

5. **Output format**:

```
## Tests for [target]

### Test Cases
| Scenario | Input | Expected |
|----------|-------|----------|
| [case]   | [in]  | [out]    |

### Generated Tests
[Code block with tests]

### Coverage Notes
- Covered: [list]
- Not covered (explain why): [list]
```

## Test File Structure

```
// Imports

// Test class/describe block
describe("ClassName") {

    // Setup/teardown if needed
    beforeEach { }

    // Group related tests
    describe("methodName") {

        test("returns X when Y") {
            // Arrange
            // Act
            // Assert
        }

        test("throws error when Z") {
            // Arrange
            // Act & Assert
        }
    }
}
```

## Allowed Prompts
- Read source files
- Read existing tests
- Write test files
- Run tests

## Example Usage

```
/test src/services/PaymentService.kt
/test --edge-cases processOrder
/test --coverage (identifies untested code)
```
