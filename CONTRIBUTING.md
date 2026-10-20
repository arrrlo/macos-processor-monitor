# Contributing

Thanks for helping. The project holds itself to a few hard rules, all enforced by `make` targets
and CI.

## Setup

- A Mac with Apple Silicon and macOS 14 or later.
- The Xcode **Command Line Tools** with Swift 6.4 (`xcode-select --install`). Xcode itself is not
  needed. If Xcode is installed, run `sudo xcode-select --switch /Library/Developer/CommandLineTools`.
- Run everything through `make` (`make help` lists the targets). Plain `swift test` fails with the
  Command Line Tools because the Swift Testing macro plugin is not on the default search path;
  the Makefile adds it.

## Workflow: test first

1. Write a failing [Swift Testing](https://developer.apple.com/documentation/testing) test and
   watch it fail: `make test FILTER=<SuiteName>`.
2. Write the least code that makes it pass.
3. Refactor with the tests green.

## Before you open a pull request

| Command | Requirement |
|---|---|
| `make gate` | All tests pass; **100% line, function and region coverage** of `Sources/` (only the two `main.swift` entry points are excluded); **CRAP ≤ 16** for every function. Also checks the `Tools/` package. |
| `make mutate CHANGED=origin/main` | Every mutant in the files you changed is killed. Run plain `make mutate` for the whole package (about 20 minutes). |
| `make run`, then `make overhead SECONDS=60` | No CPU or memory regression against the numbers in [README › Overhead](README.md#how-it-works), measured with the menu and dashboard closed. Compare the physical footprint, not resident memory. |
| `CHANGELOG.md` | Every change adds a line under **Unreleased** (`Added`, `Changed`, `Fixed`, `Removed`, or `Internal` for tooling and tests). Doc comments, the README and SECURITY.md are updated wherever they describe what you changed. |

## Writing code that can be fully covered

Swift compiles some constructs into hidden closures that only run in rare cases, so they cannot
reach 100% coverage. Avoid them:

- No messages in `precondition` or `assert`, and no interpolated log messages.
- No `#available` checks (the deployment target is macOS 14).
- Use `@available(*, unavailable)` for `init?(coder:)` and similar.
- Use `?? fallback` only when tests exercise both sides. For a fallback that can never happen on
  a real system, prefer `if let` without `else`.
- Keep system calls behind small injectable `Source` structs so tests can make them fail.
- Code that only the running app can execute (quitting, the About panel, the run loop) belongs in
  `main.swift`.

## Equivalent mutants

Sometimes a mutant cannot change behaviour. For example, a sort comparator over unique keys never
sees ties, so `<` and `<=` sort identically. First try to restructure the code so the operator
disappears (`max(a, b) - b` instead of `a > b ? a - b : 0`). If that isn't possible, suppress the
mutant on the line above with a reason:

```swift
// mutation:disable-next-line PIDs are unique, so two entries never compare equal and `<=` sorts identically
let ranked = usage.sorted { ($1.cpuPercent, $0.pid) < ($0.cpuPercent, $1.pid) }
```

A suppression without a reason is ignored and reported as a warning.
