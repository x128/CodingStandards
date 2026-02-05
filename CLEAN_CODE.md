# Clean Code Principles

Language-agnostic principles for writing maintainable, readable, and robust code.

## Table of Contents
1. [Naming](#naming)
2. [Functions](#functions)
3. [Classes & Modules](#classes--modules)
4. [SOLID Principles](#solid-principles)
5. [DRY & KISS](#dry--kiss)
6. [Comments](#comments)
7. [Error Handling](#error-handling)
8. [Testing](#testing)
9. [Code Smells](#code-smells)

---

## Naming

### Intention-Revealing Names

```
// BAD: What does this do?
d = 86400
fn(x, y)
tmp = calc()

// GOOD: Names reveal intent
secondsPerDay = 86400
calculateDistance(origin, destination)
discountedPrice = applyDiscount(originalPrice)
```

### Use Domain Language

```
// BAD: Generic technical names
data = getData()
list = getList()
result = process(input)

// GOOD: Domain-specific vocabulary
customer = fetchCustomer(customerId)
pendingOrders = getOrdersByStatus(PENDING)
invoice = generateInvoice(order)
```

### Consistent Vocabulary

```
// BAD: Multiple words for same concept
fetchUser()
getCustomer()
retrieveClient()
loadAccount()

// GOOD: One word per concept
fetchUser()
fetchCustomer()
fetchClient()
fetchAccount()
```

### Avoid Encodings

```
// BAD: Hungarian notation, type prefixes
strName
intCount
lstUsers
IUserService
UserServiceImpl

// GOOD: Let the type system handle types
name
count
users
UserService
DefaultUserService (or just UserService)
```

### Searchable Names

```
// BAD: Magic numbers and short names
if (s == 4) { ... }
for (i = 0; i < 7; i++) { ... }
t = d * 24 * 60 * 60

// GOOD: Named constants, searchable
STATUS_COMPLETE = 4
DAYS_PER_WEEK = 7

if (status == STATUS_COMPLETE) { ... }
for (day = 0; day < DAYS_PER_WEEK; day++) { ... }
totalSeconds = days * SECONDS_PER_DAY
```

---

## Functions

### Small and Focused

```
// BAD: Function doing multiple things
processOrder(order) {
    // Validate order (20 lines)
    // Calculate totals (15 lines)
    // Apply discounts (20 lines)
    // Update inventory (15 lines)
    // Send confirmation (10 lines)
    // Log transaction (10 lines)
}

// GOOD: One thing per function
processOrder(order) {
    validatedOrder = validateOrder(order)
    pricedOrder = calculateTotals(validatedOrder)
    finalOrder = applyDiscounts(pricedOrder)
    updateInventory(finalOrder)
    sendConfirmation(finalOrder)
}
```

### Single Level of Abstraction

```
// BAD: Mixed abstraction levels
renderPage() {
    html = "<html>"
    user = database.query("SELECT * FROM users WHERE id = " + id)
    html += "<body>"
    for (field in user) {
        html += formatField(field)
    }
    response.setContentType("text/html")
    response.write(html)
}

// GOOD: Consistent abstraction
renderPage() {
    user = fetchUser(id)
    content = renderUserProfile(user)
    sendHtmlResponse(content)
}
```

### Minimal Parameters

```
// BAD: Too many parameters
createUser(name, email, age, address, city, country, phone, role, department)

// GOOD: Group related parameters
createUser(personalInfo, contactInfo, organizationInfo)

// Or use builder pattern for many optional params
User.builder()
    .name("Alice")
    .email("alice@example.com")
    .role(ADMIN)
    .build()
```

### No Side Effects

```
// BAD: Hidden side effect
validatePassword(password) {
    if (isValid(password)) {
        Session.initialize()  // Unexpected side effect!
        return true
    }
    return false
}

// GOOD: Do what the name says, nothing more
validatePassword(password) {
    return isValid(password)
}

// Separate function for session
initializeSession() {
    Session.initialize()
}
```

### Command-Query Separation

```
// BAD: Does both - modifies and returns
addAndReturnCount(item) {
    list.add(item)
    return list.size()
}

// GOOD: Separate commands from queries
add(item) {          // Command: changes state
    list.add(item)
}

count() {            // Query: returns data
    return list.size()
}
```

---

## Classes & Modules

### Single Responsibility

```
// BAD: Class doing too much
class Employee {
    calculatePay()
    saveToDatabase()
    generateReport()
    sendEmail()
    validateData()
}

// GOOD: Focused classes
class Employee {
    // Only employee data and behavior
}

class PayrollCalculator {
    calculatePay(employee)
}

class EmployeeRepository {
    save(employee)
}

class ReportGenerator {
    generate(employee)
}
```

### Cohesion

```
// BAD: Low cohesion - unrelated methods
class Utilities {
    formatDate(date)
    calculateTax(amount)
    sendEmail(message)
    compressImage(image)
    parseJson(text)
}

// GOOD: High cohesion - related methods
class DateFormatter {
    format(date, pattern)
    parse(text, pattern)
    getRelativeTime(date)
}

class TaxCalculator {
    calculate(amount, region)
    getRate(region)
}
```

### Encapsulation

```
// BAD: Exposed internals
class Order {
    public items = []
    public total = 0
}

// External code manipulates directly
order.items.push(item)
order.total = order.total + item.price

// GOOD: Hidden internals, public interface
class Order {
    private items = []
    private total = 0

    addItem(item) {
        items.push(item)
        total += item.price
    }

    getTotal() {
        return total
    }
}
```

### Composition Over Inheritance

```
// BAD: Deep inheritance hierarchy
class Animal
class Mammal extends Animal
class Dog extends Mammal
class GermanShepherd extends Dog
class PoliceGermanShepherd extends GermanShepherd

// GOOD: Composition
class Dog {
    breed: Breed
    training: Training

    constructor(breed, training) {
        this.breed = breed
        this.training = training
    }
}

policeDog = new Dog(
    breed: GermanShepherd(),
    training: PoliceTraining()
)
```

---

## SOLID Principles

### Single Responsibility Principle (SRP)

A class should have only one reason to change.

```
// BAD: Multiple reasons to change
class UserManager {
    createUser()           // User logic
    validateEmail()        // Validation logic
    sendWelcomeEmail()     // Email logic
    saveToDatabase()       // Persistence logic
    generateReport()       // Reporting logic
}

// GOOD: Each class has one responsibility
class UserService {
    create(userData)
}

class EmailValidator {
    validate(email)
}

class UserNotifier {
    sendWelcome(user)
}

class UserRepository {
    save(user)
}
```

### Open/Closed Principle (OCP)

Open for extension, closed for modification.

```
// BAD: Must modify class to add new shape
class AreaCalculator {
    calculate(shape) {
        if (shape.type == "circle") {
            return PI * shape.radius * shape.radius
        } else if (shape.type == "rectangle") {
            return shape.width * shape.height
        } else if (shape.type == "triangle") {
            // Keep adding else-if for each new shape
        }
    }
}

// GOOD: Extend without modifying
interface Shape {
    area()
}

class Circle implements Shape {
    area() { return PI * radius * radius }
}

class Rectangle implements Shape {
    area() { return width * height }
}

// Adding new shapes doesn't touch existing code
class Triangle implements Shape {
    area() { return 0.5 * base * height }
}

class AreaCalculator {
    calculate(shape: Shape) {
        return shape.area()
    }
}
```

### Liskov Substitution Principle (LSP)

Subtypes must be substitutable for their base types.

```
// BAD: Square violates Rectangle contract
class Rectangle {
    setWidth(w) { width = w }
    setHeight(h) { height = h }
    area() { return width * height }
}

class Square extends Rectangle {
    setWidth(w) { width = w; height = w }  // Breaks expectations
    setHeight(h) { width = h; height = h } // Breaks expectations
}

// This breaks:
r = new Square()
r.setWidth(5)
r.setHeight(10)
assert(r.area() == 50)  // Fails! Returns 100

// GOOD: Don't inherit if contract differs
interface Shape {
    area()
}

class Rectangle implements Shape {
    constructor(width, height)
    area() { return width * height }
}

class Square implements Shape {
    constructor(side)
    area() { return side * side }
}
```

### Interface Segregation Principle (ISP)

Clients shouldn't depend on interfaces they don't use.

```
// BAD: Fat interface
interface Worker {
    work()
    eat()
    sleep()
    attendMeeting()
    writeReport()
}

// Robot can't eat or sleep!
class Robot implements Worker {
    work() { /* OK */ }
    eat() { throw NotSupported }    // Forced to implement
    sleep() { throw NotSupported }  // Forced to implement
}

// GOOD: Segregated interfaces
interface Workable {
    work()
}

interface Feedable {
    eat()
}

interface Restable {
    sleep()
}

class Human implements Workable, Feedable, Restable {
    work() { }
    eat() { }
    sleep() { }
}

class Robot implements Workable {
    work() { }
}
```

### Dependency Inversion Principle (DIP)

Depend on abstractions, not concretions.

```
// BAD: High-level depends on low-level
class OrderService {
    constructor() {
        this.database = new MySQLDatabase()  // Concrete dependency
        this.mailer = new SmtpMailer()       // Concrete dependency
    }
}

// GOOD: Depend on abstractions
class OrderService {
    constructor(database: Database, mailer: Mailer) {
        this.database = database
        this.mailer = mailer
    }
}

// Inject dependencies
orderService = new OrderService(
    new MySQLDatabase(),
    new SmtpMailer()
)

// Easy to test with mocks
testOrderService = new OrderService(
    new MockDatabase(),
    new MockMailer()
)
```

---

## DRY & KISS

### DRY (Don't Repeat Yourself)

```
// BAD: Duplicated logic
validateUsername(username) {
    if (username.length < 3) return "Too short"
    if (username.length > 20) return "Too long"
    if (!username.match(/^[a-zA-Z0-9]+$/)) return "Invalid characters"
    return null
}

validateDisplayName(name) {
    if (name.length < 3) return "Too short"
    if (name.length > 20) return "Too long"
    if (!name.match(/^[a-zA-Z0-9]+$/)) return "Invalid characters"
    return null
}

// GOOD: Extract common logic
validateAlphanumericField(value, fieldName, minLen = 3, maxLen = 20) {
    if (value.length < minLen) return fieldName + " too short"
    if (value.length > maxLen) return fieldName + " too long"
    if (!value.match(/^[a-zA-Z0-9]+$/)) return fieldName + " has invalid characters"
    return null
}

validateUsername(username) {
    return validateAlphanumericField(username, "Username")
}

validateDisplayName(name) {
    return validateAlphanumericField(name, "Display name")
}
```

### KISS (Keep It Simple, Stupid)

```
// BAD: Over-engineered
class StringReverserFactory {
    createReverser(type) {
        switch(type) {
            case "recursive": return new RecursiveReverser()
            case "iterative": return new IterativeReverser()
            case "functional": return new FunctionalReverser()
        }
    }
}

class RecursiveReverser implements StringReverser {
    reverse(str) {
        if (str.length <= 1) return str
        return reverse(str.substring(1)) + str[0]
    }
}

// GOOD: Simple solution
reverse(str) {
    return str.split('').reverse().join('')
}
```

### YAGNI (You Aren't Gonna Need It)

```
// BAD: Building for imaginary future
class UserService {
    constructor() {
        this.cache = new DistributedCache()  // "We might need it"
        this.loadBalancer = new LoadBalancer() // "For scale"
        this.plugins = new PluginSystem()     // "For extensibility"
    }
}

// GOOD: Build what you need now
class UserService {
    constructor(repository) {
        this.repository = repository
    }

    getUser(id) {
        return repository.find(id)
    }
}

// Add caching WHEN you need it, not before
```

---

## Comments

### Code Should Be Self-Documenting

```
// BAD: Comment explains obvious code
// Increment counter by one
counter = counter + 1

// Loop through all users
for (user in users) {
    // Check if user is active
    if (user.isActive) {
        // Add to active list
        activeUsers.add(user)
    }
}

// GOOD: Code explains itself
counter++

activeUsers = users.filter(user => user.isActive)
```

### Comment WHY, Not WHAT

```
// BAD: Describes what code does
// Set timeout to 30 seconds
timeout = 30

// GOOD: Explains why
// iOS background task limit is 30s; exceeding causes termination
timeout = 30

// BAD: Describes the code
// Check if user is admin
if (user.role == "admin") { }

// GOOD: Explains business rule
// Only admins can access financial reports (SOX compliance)
if (user.role == "admin") { }
```

### Document Public APIs

```
// BAD: No documentation
export(project, options)

// GOOD: Clear API documentation
/**
 * Exports project to specified format.
 *
 * @param project - Project to export. Must have at least one track.
 * @param options - Export configuration
 * @param options.format - Output format (mp4, mov, webm)
 * @param options.quality - Quality preset (low, medium, high)
 * @returns Promise resolving to exported file path
 * @throws InvalidProjectError if project has no tracks
 * @throws InsufficientStorageError if disk space < estimated output size
 */
export(project, options)
```

### No Commented-Out Code

```
// BAD: Dead code in comments
processVideo(video) {
    // Old implementation - keeping just in case
    // result = legacyProcess(video)
    // if (result.hasError) {
    //     return handleLegacyError(result)
    // }

    return newProcess(video)
}

// GOOD: Delete it (use version control)
processVideo(video) {
    return newProcess(video)
}
```

---

## Error Handling

### Fail Fast

```
// BAD: Continue with bad state
processOrder(order) {
    if (order == null) {
        order = new Order()  // "Fix" the problem
    }
    if (order.items == null) {
        order.items = []     // "Fix" again
    }
    // Continue processing questionable data...
}

// GOOD: Fail immediately on invalid input
processOrder(order) {
    if (order == null) throw InvalidArgumentError("Order required")
    if (order.items == null) throw InvalidStateError("Order has no items")
    if (order.items.isEmpty()) throw BusinessError("Cannot process empty order")

    // Proceed with confidence
}
```

### Use Specific Exceptions

```
// BAD: Generic exceptions
save(user) {
    try {
        database.insert(user)
    } catch (e) {
        throw new Error("Save failed")  // What went wrong?
    }
}

// GOOD: Specific, actionable exceptions
save(user) {
    try {
        database.insert(user)
    } catch (DuplicateKeyException e) {
        throw new UserAlreadyExistsError(user.email)
    } catch (ConnectionException e) {
        throw new ServiceUnavailableError("Database", e)
    } catch (ValidationException e) {
        throw new InvalidUserDataError(e.violations)
    }
}
```

### Don't Swallow Exceptions

```
// BAD: Silent failure
loadConfig() {
    try {
        return parseConfigFile()
    } catch (e) {
        return {}  // Silently return empty config
    }
}

// GOOD: Handle meaningfully or propagate
loadConfig() {
    try {
        return parseConfigFile()
    } catch (FileNotFoundException e) {
        log.info("No config file, using defaults")
        return defaultConfig()
    } catch (ParseException e) {
        throw new ConfigurationError("Invalid config syntax", e)
    }
}
```

### Use Result Types for Expected Failures

```
// BAD: Exceptions for expected cases
getUser(id) {
    user = database.find(id)
    if (user == null) throw UserNotFoundException(id)  // Expected!
    return user
}

// GOOD: Result type for expected failures
getUser(id): Result<User, UserError> {
    user = database.find(id)
    if (user == null) return Failure(UserError.NotFound(id))
    return Success(user)
}

// Caller handles both cases explicitly
result = getUser(id)
match result {
    Success(user) => display(user)
    Failure(error) => showError(error)
}
```

---

## Testing

### Test Behavior, Not Implementation

```
// BAD: Tests implementation details
test("adds item to internal array") {
    cart = new ShoppingCart()
    cart.add(item)
    assert(cart._items.length == 1)  // Testing private state
    assert(cart._items[0] == item)
}

// GOOD: Tests behavior
test("added item appears in cart") {
    cart = new ShoppingCart()
    cart.add(item)
    assert(cart.contains(item))
    assert(cart.itemCount() == 1)
}
```

### Descriptive Test Names

```
// BAD: Vague names
test_add()
test_user()
test_1()

// GOOD: Describes scenario and expectation
test_add_increasesItemCount_whenCartIsEmpty()
test_add_throwsError_whenItemOutOfStock()
test_checkout_appliesDiscount_whenCouponIsValid()
```

### Arrange-Act-Assert

```
// BAD: Mixed concerns
test_order_processing() {
    order = createOrder()
    result = process(order)
    assert(result.success)
    order2 = createAnotherOrder()
    result2 = process(order2)
    assert(result2.total == 100)
}

// GOOD: Clear AAA structure
test_process_returnsSuccess_forValidOrder() {
    // Arrange
    order = OrderBuilder()
        .withItem(product, quantity: 2)
        .withShipping(standard)
        .build()

    // Act
    result = processor.process(order)

    // Assert
    assert(result.isSuccess)
}
```

### One Assertion Per Test (Conceptually)

```
// BAD: Multiple unrelated assertions
test_user_creation() {
    user = createUser(data)
    assert(user.name == "Alice")
    assert(user.email == "alice@example.com")
    assert(user.createdAt != null)
    assert(auditLog.contains("user created"))  // Different concern!
    assert(welcomeEmail.wasSent())             // Different concern!
}

// GOOD: Separate tests for separate behaviors
test_createUser_setsNameFromInput() {
    user = createUser(name: "Alice")
    assert(user.name == "Alice")
}

test_createUser_logsToAuditTrail() {
    createUser(data)
    assert(auditLog.contains("user created"))
}

test_createUser_sendsWelcomeEmail() {
    createUser(data)
    assert(welcomeEmail.wasSent())
}
```

### Test Independence

```
// BAD: Tests depend on each other
sharedUser = null

test_create_user() {
    sharedUser = createUser()
    assert(sharedUser != null)
}

test_update_user() {
    sharedUser.name = "New Name"  // Depends on previous test!
    save(sharedUser)
    assert(sharedUser.name == "New Name")
}

// GOOD: Each test is self-contained
test_update_changesUserName() {
    // Arrange - create own test data
    user = createUser(name: "Old Name")

    // Act
    user.name = "New Name"
    save(user)

    // Assert
    assert(user.name == "New Name")
}
```

---

## Code Smells

### Long Method
**Smell:** Method longer than 20-30 lines
**Fix:** Extract smaller methods

### Large Class
**Smell:** Class with too many responsibilities
**Fix:** Split into focused classes

### Long Parameter List
**Smell:** More than 3-4 parameters
**Fix:** Introduce parameter object or builder

### Duplicate Code
**Smell:** Same code in multiple places
**Fix:** Extract to shared function/class

### Feature Envy
**Smell:** Method uses another class's data more than its own
**Fix:** Move method to the class it envies

### Data Clumps
**Smell:** Same group of data appears together repeatedly
**Fix:** Extract into a class

### Primitive Obsession
**Smell:** Using primitives instead of small objects
**Fix:** Create value objects (Money, Email, PhoneNumber)

### Switch Statements
**Smell:** Same switch on type in multiple places
**Fix:** Replace with polymorphism

### Parallel Inheritance
**Smell:** Creating subclass in one hierarchy requires subclass in another
**Fix:** Merge hierarchies or use composition

### Lazy Class
**Smell:** Class that doesn't do enough
**Fix:** Merge with another class

### Speculative Generality
**Smell:** "We might need this someday"
**Fix:** Remove until actually needed

### Dead Code
**Smell:** Unreachable or unused code
**Fix:** Delete it

---

## Summary Checklist

### Naming
- [ ] Names reveal intent
- [ ] Uses domain vocabulary
- [ ] Consistent terminology
- [ ] No encodings or prefixes
- [ ] Searchable (no magic numbers)

### Functions
- [ ] Small (under 20 lines)
- [ ] Single responsibility
- [ ] Single level of abstraction
- [ ] Few parameters (max 3)
- [ ] No side effects
- [ ] Command-query separation

### Classes
- [ ] Single responsibility
- [ ] High cohesion
- [ ] Proper encapsulation
- [ ] Composition over inheritance
- [ ] Follows SOLID principles

### Error Handling
- [ ] Fails fast on invalid input
- [ ] Specific exceptions
- [ ] No swallowed exceptions
- [ ] Result types for expected failures

### Testing
- [ ] Tests behavior, not implementation
- [ ] Descriptive names
- [ ] Clear AAA structure
- [ ] Independent tests
- [ ] One concept per test
