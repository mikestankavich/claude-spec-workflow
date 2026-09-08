# Contributing to Claude Ship Workflow

Thank you for your interest in contributing! This project is one person's idiosyncratic
ticket-to-merged-PR workflow, packaged as a Claude Code plugin, and we welcome improvements
and feedback.

## Ways to Contribute

### 1. Report Issues
- Found a bug? [Open an issue](https://github.com/mikestankavich/claude-ship-workflow/issues)
- Have a feature request? Describe your use case
- Documentation unclear? Let us know what's confusing

### 2. Submit Pull Requests
- Fix bugs or typos
- Improve a `bin/csw-*` tool or a `skills/` skill
- Improve documentation
- Enhance skills or tools with better error handling

### 3. Share Your Experience
- How are you using the workflow?
- What works well? What doesn't?
- Share your `.claude/csw.json` configuration or workflow tweaks

## Development Setup

### Prerequisites
- Git 2.30+
- `gh` 2.x, authenticated
- `jq` 1.6+
- `python3` 3.9+ (for `/csw:batch`)
- Claude Code installed; [Superpowers](https://github.com/obra/superpowers) recommended

**Windows developers**: Use Git Bash or WSL2 for development and testing.

### Testing Your Changes

1. **Clone and run the test suite**
   ```bash
   git clone https://github.com/mikestankavich/claude-ship-workflow
   cd claude-ship-workflow
   bash tests/run-tests.sh
   ```

   **Windows**: Run in Git Bash or WSL2 terminal.

2. **Test the plugin end-to-end**

   Install it as a local plugin in a scratch repository with a `.claude/csw.json`, then
   exercise the skills directly: `/csw:work <ticket>`, "go for merge", "clean up the
   worktree", `/csw:batch`.

3. **Add or extend tests before changing behavior**

   Every bash tool under `bin/` has a matching `tests/test-<name>.sh`. `tests/run-tests.sh`
   runs every `tests/test-*.sh` file and fails the suite if any of them fail.

   **`csw-services` needs more than the suite.** CSW runs no services of its own — no dev
   server, no watcher, no database — so `tests/test-csw-services.sh` works against fixtures:
   real processes `cd`'d into temporary directories, a real listener on a kernel-picked port,
   a fake `docker` on `CSW_SERVICES_DOCKER`, and a fake `/proc` tree on `CSW_SERVICES_PROC`
   for the supervised-unit exclusion, which cannot be created in a test at all. Those two env
   vars exist for the tests and are not part of the tool's interface.

   **You do not need a real project to dogfood the host arm — background something from the
   worktree you are standing in.** That is the one shape the fixtures cannot reproduce,
   because it puts a real session process tree above the tool, which is exactly what the
   self-and-ancestor exclusion has to survive:

   ```bash
   wt=$(git rev-parse --show-toplevel)
   bin/csw-services report "$wt"                       # expect: nothing running
   ( cd "$wt" && setsid python3 -m http.server 8099 & ) # a dev-server-shaped process
   bin/csw-services report "$wt"                       # expect: pid, pgid, :8099, command
   bin/csw-services stop "$wt" --grace 2               # expect: the port frees, your shell lives
   ```

   What that still cannot reach is the **compose arm** — no containers here — and a
   multi-level process tree of the kind `pnpm` builds. So the fixtures prove the selection
   rules, the loop above proves the host arm against a live worktree, and **a session in a
   repo with a real stack is what proves the rest**. Worth doing before trusting a change to
   either arm.

## Hacking on CSW Skills

Skills are plain markdown under `skills/<name>/SKILL.md` (`work`, `merge`, `cleanup`,
`batch`). Edit them directly — there is no build or install step for skill content while
testing this repo's own checkout. Test a change by invoking the skill in a scratch
repository (`/csw:work TEST-1`, "go for merge", "clean up the worktree", `/csw:batch`) and
reading the transcript for whether it followed the updated instructions.

The `bin/csw-*` tools are separate: they are plain executables (four bash, one Python), so
changes there take effect immediately with no reinstall step either — run them straight from
`bin/` or through the test suite.

See [docs/design.md](docs/design.md) for the rationale behind the current shape of the
skills and tools.

## Contribution Guidelines

### Code Style
- **Shell scripts**: Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html); `shellcheck --severity=warning` must be clean on every bash tool under `bin/` and every file under `tests/`.
- **Markdown**: Use consistent formatting, clear headings
- **Skills**: Keep instructions clear, concise, and actionable

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add priority tie-break to csw-batch-filter
fix: correct branch pattern token substitution
docs: clarify gate glob semantics
chore: update dependencies
```

### Pull Request Process

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Keep changes focused and atomic
   - Update documentation as needed
   - Add examples if introducing new features

4. **Test thoroughly**
   - Run `bash tests/run-tests.sh` and confirm every test file passes
   - Test on both Unix and Windows if applicable
   - Verify skills and `bin/csw-*` tools work end-to-end
   - Check for broken links in documentation

5. **Submit PR**
   - Provide clear description of changes
   - Link to related issues
   - Explain the "why" behind your changes

6. **Respond to feedback**
   - Address review comments
   - Be open to suggestions
   - Ask questions if anything is unclear

### The changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and its
guiding principle here is the one that is easy to get wrong: **a `## [Unreleased]` section is
kept at the top, and a notable change is written into it by the pull request that makes the
change.** Not afterwards, and never into the most recent released section — that section is
dated and tagged, and a later entry inside it says the work shipped on a day it did not.

That is not hypothetical. Of the eight pull requests that made up 1.2.0, exactly one wrote a
changelog entry, and it wrote it into the released `## [1.1.0]` section — dating a September
change to 4 August. There was no `[Unreleased]` heading to write into, so appending to the
changelog landed on the newest release by construction.

Not every PR earns an entry. A refactor with no behaviour change, a test, a typo — nothing to
say. The test is whether someone upgrading would want to know.

**A release pull request** then does two things and nothing else: move what is actually
shipping from `## [Unreleased]` into a new `## [X.Y.Z] - YYYY-MM-DD` section, and flip
`VERSION`, `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to `X.Y.Z`.
`tests/run-tests.sh` fails if `VERSION` names a release with no matching section, so a bump
without its notes cannot merge.

Borrowed from `trakrf/platform`, which enforces the same rule in
`scripts/assert-changelog-section.sh`. One difference: platform's `VERSION` carries `X.Y.Z-dev`
between releases, so its gate is inert on ordinary pull requests and fires only on the release
one. CSW's `VERSION` always holds the last released number, so the check is always on and
ordinarily satisfied by the section already there. The `-dev` phase is deliberately not
adopted: it exists on platform because the merge build *is* the release build and the version
has to be a property of the commit, and CSW tags after the fact instead.

## Adding a Config Key or Gate

New `.claude/csw.json` keys are always welcome when they earn their keep. Follow this
structure:

1. **Add the key and its default**: `DEFAULTS` in `bin/csw-config`
2. **Wire it up**: wherever the tool or skill that reads it needs to change
3. **Document it**: `docs/configuration.md`'s key table, including its default
4. **Test it**: extend `tests/test-csw-config.sh` (or the relevant tool's test file) to
   cover the new key, including a malformed-value case if one is plausible

## Documentation Improvements

Documentation is critical for this project:
- **Clarity**: Use simple, direct language
- **Examples**: Show real-world usage
- **Completeness**: Cover edge cases and gotchas
- **Accuracy**: Keep in sync with code changes — every documented command or example
  should be something you actually ran, not something that looks plausible

## Questions?

- Open a discussion in [GitHub Issues](https://github.com/mikestankavich/claude-ship-workflow/issues)
- Check existing issues for similar questions
- Be patient - this is a community-driven project

## Code of Conduct

- Be respectful and constructive
- Focus on the work, not the person
- Welcome newcomers and different perspectives
- Assume good intentions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make Claude Ship Workflow better! 🚀
