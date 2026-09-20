# File roles

Read this when a LOC figure looks wrong for a path, when adding role rules to
`.contributorkit.yml`, or when deciding which bucket a new kind of file belongs in.
`SKILL.md` does not need it for ordinary use.

## The principle: location beats type

The rules are **ordered, first match wins**, and the order is not arbitrary:

| Order | Role | Says | Basis |
|---|---|---|---|
| 1 | `vendor` | code we did not write | **location** |
| 2 | `test` | test tree and test-named files | **location**, plus a few names |
| 3 | `build` | Makefiles, CMake, autoconf, project files, CI, shell | type |
| 4 | `docs` | prose | type, plus `docs/` and `doc/` |
| 5 | `source` | everything else | fallback |

**Location wins over type.** The question the tool answers is *what part of the tree did
this change touch*, not *what kind of file is it*. So a Makefile inside `tests/` is
test-harness growth, and a test inside `third_party/` is somebody else's code.

`vendor` is the role that is easy to forget and it is a third of a typical C project.
Folding it into `source` makes an upstream dependency bump read as your own bloat.

## Consequences

Every row is asserted by `RoleTests.documentedConsequencesHold`, which **reads this
table out of this file**. A path here that stops classifying this way fails the build —
prose and rules cannot drift apart.

| Path | Role | Why |
|---|---|---|
| `tests/automated/Makefile` | `test` | in the test tree; location beats the `Makefile` type rule |
| `tests/run.sh` | `test` | same — a script that runs the tests is test harness |
| `tests/CMakeLists.txt` | `test` | same |
| `third_party/webrtc_aec3/test/x.cc` | `vendor` | somebody else's tests are still somebody else's code |
| `third_party/webrtc_aec3/src/x.cc` | `vendor` | — |
| `pjlib/src/pjlib-test/ssl_sock.c` | `test` | `**/*-test/**` |
| `CMakeLists.txt` | `build` | at the repo root, outside any test tree |
| `Makefile` | `build` | same |
| `pjlib/build/Makefile` | `build` | same |
| `.github/workflows/ci.yml` | `build` | CI is build machinery |
| `pjlib/src/pj/ssl_sock_darwin.c` | `source` | the fallback, and the only role with no rule of its own |
| `docs/Preview Content/notes.md` | `docs` | paths with spaces are read from JSON keys, never split on whitespace |
| `README.md` | `docs` | a bare name at the repo root |

## Two matching rules worth knowing

**`**/x` also matches a bare `x` at the repo root.** `**/CMakeLists.txt` matches
`CMakeLists.txt` with nothing in front of it. Naïve glob matching does not do this, and
without it every root-level build file falls through to `source`.

**`README*` does not match `docs/README.md`.** A pattern with no `**/` prefix is anchored
at the repo root. That is deliberate: `CHANGES*` at the root is the project changelog,
while a `CHANGES` file deep in a vendored tree is not yours to count.

## Changing them

The shipped list lives in `Sources/ContributorKit/Resources/contributorkit.default.yml`,
which is a byte-identical copy of the fixtures' file — itself generated from the script
that measured the role distribution, so the shipped defaults and the measured numbers
cannot drift. A test asserts the copy.

`.contributorkit.yml` in a repository root overrides it. **The `roles:` key is replaced
whole, never merged**, because the order is the contract and a merged order is nobody's.
If you want `build` to win over `test`, move it up — that is the one line.

The classifier only ever sees paths `cloc` emitted, and `cloc` emits only files whose
language it recognises. Images and binaries never reach it, so there is no `asset` role
and there does not need to be.
