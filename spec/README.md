# Specification-Driven Development System

This system combines the best practices from Context Engineering (Cole Medin), 3-File PRD (Ryan Carson), and Linear workflow (Pedram Navid) to create an efficient, AI-friendly development process.

## Quick Start

1. **Create a specification**
   ```bash
   mkdir -p spec/my-feature
   cp spec/template.md spec/my-feature/spec.md
   # Edit spec.md with your requirements
   ```

2. **Generate implementation plan**
   ```
   /csw:plan my-feature
   # or just: /csw:plan (auto-detects if only one spec)
   ```

3. **Build the feature**
   ```
   /csw:build
   # Auto-detects the spec with plan.md
   ```

4. **Validate readiness**
   ```
   /csw:check
   ```

5. **Ship it**
   ```
   /csw:ship
   # Auto-detects the spec ready to ship
   ```

## Directory Structure

```
spec/
├── README.md          # This file
├── template.md        # Specification template
├── stack.md           # Validation commands for your tech stack
├── auth/              # Flat organization
│   ├── spec.md
│   ├── plan.md
│   └── log.md
├── frontend/          # Nested by layer
│   ├── dashboard/
│   │   ├── spec.md
│   │   └── plan.md
│   └── settings/
│       └── spec.md
├── team-a/            # Nested by team
│   └── feature-x/
│       └── spec.md
├── backlog/           # Optional: Future specs not ready to work on
│   └── onboarding-bootstrap/
│       └── spec.md
```

**Note**: Organize specs however makes sense for your project. The system supports arbitrary nesting after `spec/`.

**Optional**: Use `spec/backlog/` for future specs that aren't ready to work on yet. Move them to `spec/` when ready to `/csw:plan`.

**Note**: The slash commands (`/csw:plan`, `/csw:build`, `/csw:check`, `/csw:ship`, `/csw:spec`) are installed via `csw install` (global) or `csw init` (project scope).

## Philosophy

This system is built on three core principles:

1. **Context is King** - Provide comprehensive context to enable autonomous execution
2. **Progressive Validation** - Validate continuously, fix immediately
3. **Clear Workflow** - Separate planning from execution for better results

## Workflow Overview

### 1. Specification (Human writes)
Define WHAT needs to be built, not HOW. Include:
- Clear outcome and success criteria
- Examples and references
- Constraints and context

### 2. Planning (AI generates)
AI analyzes the spec and creates detailed implementation plan:
- Task breakdown
- Risk assessment
- Validation steps

### 3. Building (AI executes)
AI implements based on plan with:
- Continuous validation
- Progress tracking
- Error recovery

### 4. Shipping (AI completes)
Final validation and PR preparation:
- Comprehensive checks
- Documentation updates
- Clean git history

## Command Reference

| Command | Purpose | Notes |
|---------|---------|-------|
| `/csw:spec` | Create specification from conversation | Cleans completed specs first |
| `/csw:plan` | Generate implementation plan | Auto-detects spec or accepts fragment |
| `/csw:build` | Execute implementation | Validates continuously; full suite at end |
| `/csw:check` | Validate PR readiness (optional) | /csw:ship runs this automatically |
| `/csw:ship` | Complete and ship | Creates PR; runs /csw:check first |

## Feature Lifecycle

### Linear History Workflow

CSW uses **rebase workflow** (linear history), not merge commits.

**When you run `/csw:ship`**:
1. Creates PR from feature branch
2. Commits and pushes to remote
3. PR is ready for review and merge

**When you start next feature (`/csw:spec`)**:
1. Dirty-tree guard ensures clean working tree
2. Completed specs (with `log.md`) are automatically deleted and committed
3. Proceeds to create new spec

### Automatic Cleanup

Cleanup is integrated into `/csw:spec`:
1. Scans `spec/` for directories with `log.md` (proof of completion)
2. Skips `spec/backlog/`
3. **DELETES** completed spec directories
4. Commits as "chore: clean completed specs from previous cycle"

**Truth**: If a spec has `log.md`, it means `/csw:build` succeeded and the feature is complete.

**Source of record**: Use `gh pr list --state merged` to see shipped features. GitHub PRs are the canonical source of truth.

**Important**: There is no `spec/archive/` directory. Specs are deleted from working tree but preserved in git history.

### Workflow Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant F as Feature Branch
    participant M as Main

    U->>F: /csw:build (creates log.md)
    U->>F: /csw:ship (creates PR)
    F->>F: Commit all changes
    F->>M: Merge PR
    U->>M: /csw:spec (next feature)
    M->>M: Auto-clean completed specs
    M->>F: /csw:plan creates feature branch
```

### Arbitrary Nesting

After `spec/`, organize however you want:
- **Flat**: `spec/auth/`, `spec/dashboard/`
- **By layer**: `spec/frontend/auth/`, `spec/backend/users/`
- **By team**: `spec/team-a/feature-x/`, `spec/team-b/feature-y/`

**Feature identity** = full relative path under spec/:
- `spec/auth/` → feature: `"auth"`
- `spec/frontend/auth/` → feature: `"frontend/auth"`
- `spec/team-a/feature-x/` → feature: `"team-a/feature-x"`

### Smart Path Resolution

Commands accept fragments, not full paths:

**Zero arguments** (auto-detect):
```bash
/csw:plan          # Auto-detects if only 1 spec exists
/csw:build         # Auto-detects if only 1 plan exists
```

**Fragment matching** (Claude fuzzy matches):
```bash
/csw:plan auth                    # Matches spec/auth/ or spec/frontend/auth/
/csw:plan frontend                # Matches spec/frontend/auth/
/csw:plan authentication          # Typo-tolerant, matches "auth"
```

**How it works** (separation of concerns):
1. **Bash layer**: Runs `find spec/ -name "spec.md"`, returns ALL matches
2. **Claude layer**: Fuzzy matches your fragment, handles disambiguation

**Command-specific filtering**:
- `/csw:plan` → Looks for `spec.md` files (specs ready to plan)
- `/csw:build` → Looks for `plan.md` files (specs ready to build)
- `/csw:ship` → Looks for `plan.md` files (specs ready to ship)

**Interactive disambiguation**: Multiple matches show numbered list:
```
I found 2 specs matching "auth":
  1. frontend/auth
  2. backend/auth
Which one?
```

You can respond with: `1`, `frontend`, or `the frontend one`.

### Zero-Arg Sequential Workflow

Solo development with single feature needs zero path arguments:
```bash
/csw:spec my-feature      # Create spec/my-feature/
/csw:plan                 # Auto-detect (only 1 spec)
/csw:build                # Auto-detect (only 1 plan)
/csw:ship                 # Auto-detect (only 1 plan)
# Merge PR
/csw:spec next-feature    # Cleans up my-feature, creates next-feature
```

## Best Practices

### DO:
- ✅ Write clear, specific requirements
- ✅ Include examples from the codebase
- ✅ Reference documentation
- ✅ Define validation criteria
- ✅ Use semantic commit messages

### DON'T:
- ❌ Mix multiple features in one spec
- ❌ Skip validation steps
- ❌ Ignore failing tests
- ❌ Ship without running /csw:check
- ❌ Leave console.logs in code

## Validation Standards

All features must pass validation commands defined in `spec/stack.md`:
- **Lint** - No linting errors
- **Typecheck** - No type errors (if applicable to your stack)
- **Test** - All tests passing
- **Build** - Successful build

The specific commands depend on your tech stack. See `spec/stack.md` for your project's validation commands.

## Git Workflow

1. Features are developed on `feature/{name}` branches
2. Linear history via rebase workflow (no merge commits)
3. Each feature gets semantic commits
4. Specs are cleaned up automatically (preserved in git history)
5. Clean history with meaningful commit messages

## Troubleshooting

**Build fails validation?**
- Check log.md for specific errors
- Fix the code, not the tests
- Re-run validation

**Can't ship?**
- Run `/csw:check` for detailed report
- Fix all critical issues
- Try again

**Lost context?**
- Check log.md for progress
- Plan.md has the full strategy
- Resume from last completed task
