# Claude Spec Workflow (CSW)

Specification-driven development workflow for Claude Code. Guides features from idea through specification, planning, implementation, validation, and shipping.

## When to Use

- User wants to start a new feature or project
- User discusses bugs, requirements, or feature ideas
- User asks about the development workflow
- User wants to plan, build, or ship work

## Workflow Stages

1. **Spec** (`/csw:spec`) — Convert conversation into a formal specification
2. **Plan** (`/csw:plan`) — Generate implementation plan with clarifying questions
3. **Build** (`/csw:build`) — Execute plan with continuous validation gates
4. **Check** (`/csw:check`) — Pre-release validation audit (optional, /ship runs this)
5. **Ship** (`/csw:ship`) — Commit, push, and create pull request

## Quick Start

```
/csw:spec my-feature    # Create specification from conversation
/csw:plan               # Generate implementation plan
/csw:build              # Build with validation gates
/csw:ship               # Ship and create PR
```

## Key Concepts

- **Validation Gates**: Lint, typecheck, test, and build must pass at every step
- **Stack Config**: `spec/stack.md` defines validation commands for your tech stack
- **Progress Tracking**: `log.md` tracks build progress and proves completion
- **Complexity Scoring**: `/csw:plan` scores complexity and recommends splitting large features

## Terminal Usage

All commands also work via CLI: `csw spec`, `csw plan`, `csw build`, `csw check`, `csw ship`
