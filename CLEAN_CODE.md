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

### No Abbreviations

Use full words in all identifiers — classes, functions, variables, modules,
packages, file names, document titles. If a concept has a recognized full
name, spell it out.

```
// BAD: Abbreviated names
cfg
btn
nav
msg
doc
ctrl
mgr
repo

// GOOD: Full names
config
button
navigation
message
document
controller
manager
repository
```

Abbreviations that are industry-standard terms in their own right are fine:
`URL`, `HTTP`, `JSON`, `PDF`, `HTML`, `API`, `ID`, `iOS`. The test: would
a colleague type the full expansion in conversation? Nobody says "Uniform
Resource Locator" — so `URL` is the real name, not an abbreviation.

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
DatabaseUserService (an implementation of UserService, named after what makes it this one)
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

### One Thing per Function

A function does one thing: each step in it is one level of abstraction below its name. A part that can get a name which does not just restate its code becomes a function with that name. A function whose body says no more than its name is put back where it is called; a use case under option (b) of row D-002 stays (ARCHITECTURE.md, "A request with no rules"). Size is not counted in lines, for functions, classes, files or tests.

**CRAP score.** Each function is measured by its CRAP score: complexity² × (1 − coverage)³ + complexity. Complexity is the number of decisions in the function plus one. Coverage is the share of the function that the project's automated tests run, from 0 to 1. The score is 8 or below: a fully tested function may have up to 8 paths, an untested one two. Above 8 the function is split into named parts or covered by tests. A function that reads better whole, such as one `when` over the options of a command line or a flat list of checks in the order of the rules, each returning its refusal, may stay above 8; it is not wrapped in a helper type only to lower the score, and the exception is recorded in the Decisions Log of the implementation plan. (The formula is Savoia's and Evans' crap4j; 8 is the limit at which R. C. Martin's crap4java fails a build. crap4j's own limit of 30 was set for old, untested code.)

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

// GOOD: Or use builder pattern for many optional params
User.builder()
    .name("Alice")
    .email("alice@example.com")
    .role(ADMIN)
    .build()
```

### No Side Effects

```
// BAD: Hidden side effect: validatePassword() also initializes the session
validatePassword(password) {
    if (isValid(password)) {
        Session.initialize()
        return true
    }
    return false
}

// GOOD: Do what the name says, nothing more; the session has its own function
validatePassword(password) {
    return isValid(password)
}

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

// GOOD: Separate commands from queries: add() is a command that changes state, count() is a query that returns data
add(item) {
    list.add(item)
}

count() {
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

// GOOD: Focused classes; Employee holds only employee data and behavior
class Employee {
    ...
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

// BAD: External code manipulates directly
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
// BAD: Multiple reasons to change: user, validation, email, persistence and reporting logic
class UserManager {
    createUser()
    validateEmail()
    sendWelcomeEmail()
    saveToDatabase()
    generateReport()
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
// BAD: Must modify class to add new shape: each new shape adds another else-if
class AreaCalculator {
    calculate(shape) {
        if (shape.type == "circle") {
            return PI * shape.radius * shape.radius
        } else if (shape.type == "rectangle") {
            return shape.width * shape.height
        } else if (shape.type == "triangle") {
            return 0.5 * shape.base * shape.height
        }
    }
}

// GOOD: Extend without modifying: adding a new shape doesn't touch existing code
interface Shape {
    area()
}

class Circle implements Shape {
    area() { return PI * radius * radius }
}

class Rectangle implements Shape {
    area() { return width * height }
}

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
// BAD: Square violates Rectangle contract: its setWidth() and setHeight() change both sides, which breaks expectations
class Rectangle {
    setWidth(w) { width = w }
    setHeight(h) { height = h }
    area() { return width * height }
}

class Square extends Rectangle {
    setWidth(w) { width = w; height = w }
    setHeight(h) { width = h; height = h }
}

// BAD: This assertion fails, area() returns 100
r = new Square()
r.setWidth(5)
r.setHeight(10)
assert(r.area() == 50)

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

// BAD: Robot can work, but can't eat or sleep, and is forced to implement both
class Robot implements Worker {
    work() { }
    eat() { throw NotSupported }
    sleep() { throw NotSupported }
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
// BAD: High-level depends on low-level: OrderService creates its concrete database and mailer itself
class OrderService {
    constructor() {
        this.database = new MySQLDatabase()
        this.mailer = new SmtpMailer()
    }
}

// GOOD: Depend on abstractions: the dependencies are injected, so a test can inject mocks
class OrderService {
    constructor(database: Database, mailer: Mailer) {
        this.database = database
        this.mailer = mailer
    }
}

orderService = new OrderService(
    new MySQLDatabase(),
    new SmtpMailer()
)

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
// BAD: Building for imaginary future: a cache "we might need", a load balancer "for scale", plugins "for extensibility"
class UserService {
    constructor() {
        this.cache = new DistributedCache()
        this.loadBalancer = new LoadBalancer()
        this.plugins = new PluginSystem()
    }
}

// GOOD: Build what you need now; add caching when you need it, not before
class UserService {
    constructor(repository) {
        this.repository = repository
    }

    getUser(id) {
        return repository.find(id)
    }
}
```

---

## Comments

Code has no comments. What you want to write in a comment becomes code that says it:

| The comment would say | Write instead |
|---|---|
| what the next line already says | nothing more: write the line plainly, `counter++` or `users.filter(user => user.isActive)`; the line itself says it |
| what a block of code does | a function named after what the block is for |
| what a function is for | a better name for the function |
| what a value means, or its unit | a name, a named constant or a type |
| what must be true here | a type that allows nothing else, or a check that fails: `require`, `check`, an assertion |
| why the obvious way is not used, or a warning | a name at that place in the code that says it, such as `deleteTripRowFirst()`, and a test whose name gives the whole reason and that fails when the code is changed the obvious way |
| which outside specification, law or algorithm the code follows | the name of the function, and of its test |
| which rule of the project's requirements the code follows | the name of its test; the name in the code says the rule in words |
| what a function promises: what it does with a row that is missing, what it never throws | the name of the function, such as `deleteIfPresent`, a type for each outcome, and a test |
| work still to do | a task in the tracker |
| who changed what, what was tried | the commit message |
| old code that might come back | the commit message that deletes it, saying what it did; the history keeps the code |

Tests follow the same rule, with one fixed exception: every test marks its three parts with `// Arrange`, `// Act`, `// Assert` or with `// Given`, `// When`, `// Then`, in capitals or in lower case. A project keeps to one set. Everything else a test has to say goes into its name, its helpers and its assertions.

**A comment is never just deleted.** What an existing comment says first moves where the table says. A reason, a warning, a unit, an outside source or a promise goes into the code where its reader looks — a name, a type, a check — and a test pins it; a test, a plan or a tracker alone is not where the reader of the code looks. The number of a rule of the project's requirements goes into the test name. Only work still to do goes to the tracker, and only history to the commit message. Only then does the comment go. If nothing in the table carries it, the comment stays until something does. Information is not lost.

**Where there is no comment, the same holds.** A reason, a warning, a unit, an outside source or a promise that only a test name, the plan or the tracker gives gets a name in the code it explains, as the table shows, and a review reports each one it finds.

**A project may allow a kind of comment.** Row D-003 of the Decisions Log of the implementation plan records the choice: (a) no comments besides the test markers, or (b) the kinds named there, such as a license header that a contract requires or reference documentation of a library that other teams use, and where they go. Only those kinds are written, and only there.

**The lint step checks it.** The project's lint step fails when the source holds a comment other than the test markers and the kinds that the Decisions Log allows (`templates/review/project/gates.sh` has the commands). A directive that a tool reads from a comment, such as `// swiftlint:disable:next`, is not a comment to a reader; it is used only where an annotation cannot do the same.

```
// BAD: comments repeat what the code says
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

// GOOD: the code says it itself
counter++

activeUsers = users.filter(user => user.isActive)

// BAD: comments give a unit and a reason, say what the code does, and keep dead code
// Timeout in seconds. iOS ends a background task after 30 s and terminates the app
t = 30

// Skip files that are too big to upload.
// file.size is 0 for files over 2 GB (library issue #412), so read the size from disk
if (fileSystem.sizeOf(file.path) > 5000000) {
    return
}
// size = file.size

// GOOD: names say what the code does and where it leaves the obvious way; each reason is a test that fails if the code goes the obvious way
IOS_BACKGROUND_TASK_LIMIT_SECONDS = 30
MAX_UPLOAD_BYTES = 5000000

if (isTooBigToUpload(file)) {
    return
}

isTooBigToUpload(file) {
    return fileSystem.sizeOf(file.path) > MAX_UPLOAD_BYTES
}

test("a background task ends within the 30 s that iOS gives it; after that iOS terminates the app") { ... }
test("a file over 2 GB is too big to upload, although the library gives its size as 0 (library issue #412)") { ... }

// BAD: the comments describe the condition, and give the business rule and its source
// Check if user is admin
// Only admins can access financial reports (SOX compliance)
if (user.role == "admin") { }

// GOOD: the name says the rule and the law it comes from; its test names the source too
if (canSeeFinancialReportsUnderSox(user)) { }

canSeeFinancialReportsUnderSox(user) {
    return user.role == ADMIN
}

test("only an admin can see financial reports, as SOX compliance requires") { ... }

// BAD: the documentation comment holds the contract of the function
/**
 * Exports project to specified format.
 * @param project - Project to export. Must have at least one track.
 * @param options.format - Output format (mp4, mov, webm)
 * @param options.quality - Quality preset (low, medium, high)
 * @returns Promise resolving to exported file path
 * @throws InvalidProjectError if project has no tracks
 * @throws InsufficientStorageError if disk space < estimated output size
 */
export(project, options)

// GOOD: the types hold the contract, and the compiler checks it
ExportFormat = MP4 | MOV | WEBM
ExportQuality = LOW | MEDIUM | HIGH
ExportResult = Exported(file) | ProjectHasNoTracks | NotEnoughStorage(estimatedBytes, freeBytes)

async exportProject(project, format: ExportFormat, quality: ExportQuality): ExportResult

// BAD: the comment points to the specification
// RFC 9110, section 14.4
header = "bytes " + first + "-" + last + "/" + total

// GOOD: the name of the function and of its test point to it
header = rfc9110ContentRangeHeader(first, last, total)

test("the Content-Range header is written as RFC 9110, section 14.4 defines it") { ... }
```

---

## Error Handling

### Fail Fast

```
// BAD: Continue with bad state: missing data is "fixed" with defaults and the function goes on with questionable data
processOrder(order) {
    if (order == null) {
        order = new Order()
    }
    if (order.items == null) {
        order.items = []
    }
    ...
}

// GOOD: A bug is thrown at once; an outcome the requirements name is returned; after the checks the function can trust the order
processOrder(order): ProcessOrderResult {
    if (order == null) throw InvalidArgumentError("Order required")
    if (order.items == null) throw InvalidStateError("Order has no items")
    if (order.items.isEmpty()) return ProcessOrderResult.EmptyOrder

    ...
}
```

### Use Specific Exceptions

This is for the code that touches the storage, network or platform. It catches the library's own exception types, never everything, and throws an exception type that the application declares, with the original as the cause.

```
// BAD: Catches everything and throws a generic exception without the cause, so nobody can tell what went wrong
save(user) {
    try {
        database.insert(user)
    } catch (e) {
        throw new Error("Save failed")
    }
}

// GOOD: The library's own types are caught; an outcome the requirements name is returned
save(user): SaveUserResult {
    try {
        database.insert(user)
        return SaveUserResult.Saved
    } catch (DuplicateKeyException e) {
        return SaveUserResult.EmailAlreadyUsed
    } catch (ConnectionException e) {
        throw new StorageException("Cannot save user", e)
    } catch (ValidationException e) {
        return SaveUserResult.InvalidUserData(e.violations)
    }
}
```

### Don't Swallow Exceptions

```
// BAD: Silent failure: the error is lost and an empty config is returned
loadConfig() {
    try {
        return parseConfigFile()
    } catch (e) {
        return {}
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

### Report a Failure by Its Kind

A function reports a failure according to its kind.

- A bug: a broken precondition or invariant. It is thrown as an exception. No code catches it in order to continue. Only the top-level handler catches it, to log it and stop the operation.
- An outcome that the requirements name, such as "book not found" or "no connection". It is returned as a case of the function's result type. The signature names it and the caller must handle it.
- Any other failure of storage, network or the platform. The code that touches the storage, network or platform throws it as an exception type that the application declares, with the library's exception kept as the cause. It wraps only the library's own failure types, never everything. Each side writes its catch once: the code that touches a library catches through one function, and the code that starts operations catches through one function. One place catches it: the code that started the operation. It tells the user and abandons or retries the operation. Code in between does not catch it in order to continue; it may clean up and rethrow.

Cancellation is not a failure. It is passed on as it is: never wrapped, never shown to the user as an error.

```
// BAD: An outcome the requirements name is thrown
getUser(id) {
    user = userRepository.find(id)
    if (user == null) throw UserNotFoundException(id)
    return user
}

// GOOD: The outcome is a case of the function's result type; the code that started the operation handles every case and is the one place that catches StorageException
getUser(id): GetUserResult {
    user = userRepository.find(id)
    if (user == null) return GetUserResult.UserNotFound(id)
    return GetUserResult.Found(user)
}

showUser(id) {
    catchingStorageFailure(onFailure = showGeneralError) {
        match getUser(id) {
            Found(user) => display(user)
            UserNotFound(id) => showUserNotFound(id)
        }
    }
}

catchingStorageFailure(onFailure, operation) {
    try {
        operation()
    } catch (StorageException e) {
        onFailure()
    }
}
```

---

## Testing

### Test Behavior, Not Implementation

```
// BAD: Tests implementation details: it reads the private state _items
test("adds item to internal array") {
    cart = new ShoppingCart()
    cart.add(item)
    assert(cart._items.length == 1)
    assert(cart._items[0] == item)
}

// GOOD: Tests behavior
test("added item appears in cart") {
    // Arrange
    cart = new ShoppingCart()

    // Act
    cart.add(item)

    // Assert
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
test_add_returnsOutOfStock_whenItemOutOfStock()
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
// BAD: Multiple unrelated assertions: the audit log and the welcome email are different concerns
test_user_creation() {
    user = createUser(data)
    assert(user.name == "Alice")
    assert(user.email == "alice@example.com")
    assert(user.createdAt != null)
    assert(auditLog.contains("user created"))
    assert(welcomeEmail.wasSent())
}

// GOOD: Separate tests for separate behaviors
test_createUser_setsNameFromInput() {
    // Arrange
    // Act
    user = createUser(name: "Alice")

    // Assert
    assert(user.name == "Alice")
}

test_createUser_logsToAuditTrail() {
    // Arrange
    // Act
    createUser(data)

    // Assert
    assert(auditLog.contains("user created"))
}

test_createUser_sendsWelcomeEmail() {
    // Arrange
    // Act
    createUser(data)

    // Assert
    assert(welcomeEmail.wasSent())
}
```

### Test Independence

```
// BAD: Tests depend on each other: test_update_user needs the user that test_create_user made
sharedUser = null

test_create_user() {
    sharedUser = createUser()
    assert(sharedUser != null)
}

test_update_user() {
    sharedUser.name = "New Name"
    save(sharedUser)
    assert(sharedUser.name == "New Name")
}

// GOOD: Each test is self-contained: it creates its own test data
test_update_changesUserName() {
    // Arrange
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

### Long Function
**Smell:** Does more than one thing: parts of it could get names of their own, or its CRAP score is above 8 without a recorded exception
**Fix:** Extract the parts as functions named after what they do, or cover the function with tests; a function that reads better whole keeps its form and its exception is recorded ("One Thing per Function")

### Large Class
**Smell:** More than one responsibility: more than one reason to change, a vague name such as `Manager` or `Processor`, fields that only some of its functions use
**Fix:** Split into focused classes. Never split by line count

### Long Parameter List
**Smell:** More than 3 parameters
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
- [ ] No abbreviations — full words everywhere
- [ ] No encodings or prefixes
- [ ] Searchable (no magic numbers)

### Functions
- [ ] Does one thing; CRAP score 8 or below, or a recorded exception
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
- [ ] A bug is thrown at once and not caught in order to continue
- [ ] An outcome the requirements name is returned as a case of the result type, not thrown
- [ ] Storage, network and platform code catches the library's own exception types and throws an exception type the application declares, with the cause
- [ ] Only the code that started the operation catches that exception
- [ ] No swallowed exceptions
- [ ] Cancellation is passed on, never wrapped

### Testing
- [ ] Tests behavior, not implementation
- [ ] Descriptive names
- [ ] Clear AAA structure
- [ ] Independent tests
- [ ] One concept per test
