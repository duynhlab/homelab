# Research: Refactor AGENTS.md for Conciseness

**Task ID:** refactor-agents-md
**Date:** 2025-12-25
**Status:** Complete

---

## Executive Summary

Current `AGENTS.md` is 619 lines, containing essential agent instructions mixed with detailed reference material. Analysis shows the file can be reduced to ~200-250 lines by extracting detailed sections into separate guide files while maintaining quick reference functionality. Best practices from AI agent documentation patterns suggest a "quick start + deep links" approach: keep critical workflow and patterns in main file, move detailed references to topic-specific guides.

**Primary Recommendation:** Split `AGENTS.md` into:
1. **AGENTS.md** (main, ~200-250 lines) - Essential workflow, critical patterns, quick navigation
2. **docs/guides/RESEARCH_PATTERNS.md** (~150 lines) - Research patterns (API, APM, Database)
3. **docs/guides/COMMAND_REFERENCE.md** (~100 lines) - All command tables
4. **docs/guides/CONVENTIONS.md** (~150 lines) - Naming conventions, standards, build verification

This maintains discoverability while dramatically improving readability and maintainability.

---

## Codebase Analysis

### Current AGENTS.md Structure

**File:** `AGENTS.md` (619 lines)

**Section Breakdown:**
- Critical notices (6 lines) - **KEEP** (essential)
- Overview (3 lines) - **KEEP** (essential)
- Research and Learning Patterns (127 lines) - **EXTRACT** to `docs/guides/RESEARCH_PATTERNS.md`
- Agent Workflow (19 lines) - **KEEP** (essential)
- Documentation Standards (39 lines) - **KEEP** (Mermaid requirement critical)
- Development Commands (20 lines) - **CONDENSE** (keep brief, link to detailed docs)
- Architecture Overview (35 lines) - **KEEP** (diagram + brief summary)
- Key Design Patterns (8 lines) - **KEEP** (brief summary)
- Technology Stack (13 lines) - **KEEP** (brief summary)
- Observability (14 lines) - **CONDENSE** (brief summary, link to docs/apm/)
- Project Structure (14 lines) - **KEEP** (essential reference)
- API Endpoints (20 lines) - **CONDENSE** (brief table, link to API_REFERENCE.md)
- Important Notes (44 lines) - **CONDENSE** (brief bullets, link to SETUP.md)
- Command Reference (49 lines) - **EXTRACT** to `docs/guides/COMMAND_REFERENCE.md`
- Quick Navigation (48 lines) - **CONDENSE** (key links only)
- Conventions and Standards (60 lines) - **EXTRACT** to `docs/guides/CONVENTIONS.md`
- Local Build Verification (45 lines) - **EXTRACT** to `docs/guides/CONVENTIONS.md`
- Troubleshooting (20 lines) - **CONDENSE** (brief, link to TROUBLESHOOTING.md)
- Changelog (6 lines) - **KEEP** (essential note)

**Total Extractable:** ~370 lines (60% of file)
**Target Main File:** ~200-250 lines (40% of current)

### Existing Documentation Structure

**Pattern Found:** Project already uses modular documentation:
- `docs/guides/` - Detailed guides (SETUP.md, CONFIGURATION.md, DATABASE.md, etc.)
- `docs/apm/` - APM-specific documentation
- `docs/monitoring/` - Monitoring-specific documentation
- `docs/slo/` - SLO-specific documentation

**Consistency:** Following this pattern for agent guides maintains consistency with existing structure.

### References to AGENTS.md

**Files referencing AGENTS.md:**
- `docs/README.md` - Links to AGENTS.md
- `docs/guides/CONFIGURATION.md` - References AGENTS.md
- `docs/guides/SETUP.md` - References AGENTS.md for build verification
- `docs/monitoring/METRICS.md` - References AGENTS.md

**Impact:** Need to update references after refactoring, but structure supports this change.

---

## External Solutions

### Option 1: Hierarchical Documentation (Recommended)

**What it is:** Main quick-reference file with detailed guides in subdirectories

**Pros:**
- ✅ Fast initial read for agents (200-250 lines vs 619)
- ✅ Detailed information still accessible via links
- ✅ Better maintainability (update guides independently)
- ✅ Follows existing project pattern (`docs/guides/` structure)
- ✅ Scalable (add new guides without bloating main file)

**Cons:**
- ⚠️ Requires updating references in other docs
- ⚠️ Agents need to follow links for details

**Implementation complexity:** Medium
**Team familiarity:** High (matches existing docs structure)

**Examples:**
- Similar to how `docs/README.md` links to detailed guides
- Matches pattern used in `docs/guides/` directory

### Option 2: Single File with Collapsible Sections

**What it is:** Keep everything in AGENTS.md but use HTML details/summary tags

**Pros:**
- ✅ All content in one place
- ✅ Can collapse sections for quick scan

**Cons:**
- ❌ Markdown doesn't support native collapsible sections well
- ❌ Still 619 lines when expanded
- ❌ Doesn't solve maintainability issue
- ❌ Not standard Markdown pattern

**Implementation complexity:** Low
**Team familiarity:** Low (non-standard approach)

### Option 3: Minimalist Quick Reference Only

**What it is:** Reduce AGENTS.md to absolute essentials (~100 lines), remove all details

**Pros:**
- ✅ Very fast to read
- ✅ Forces agents to read detailed docs

**Cons:**
- ❌ Loses critical patterns that agents need immediately
- ❌ Too minimal - agents might miss important conventions
- ❌ Research patterns are critical for quality code

**Implementation complexity:** Low
**Team familiarity:** Medium

---

## Comparison Matrix

| Criteria | Option 1: Hierarchical | Option 2: Collapsible | Option 3: Minimalist |
|----------|----------------------|----------------------|---------------------|
| **Readability** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Maintainability** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Discoverability** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Consistency** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Agent Efficiency** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Scalability** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |

---

## Recommendations

### Primary Recommendation: Option 1 - Hierarchical Documentation

**Structure:**
```
AGENTS.md (~200-250 lines)
├── Critical notices
├── Overview
├── Agent Workflow (Before Starting, Code Quality)
├── Documentation Standards (Mermaid requirement)
├── Quick Reference (condensed)
│   ├── Architecture (diagram + brief)
│   ├── Key Patterns (summary)
│   ├── Tech Stack (summary)
│   └── Project Structure
└── Links to detailed guides

docs/guides/
├── RESEARCH_PATTERNS.md (new, ~150 lines)
│   ├── API Design and Architecture
│   ├── APM Patterns
│   └── Database and System Design Patterns
├── COMMAND_REFERENCE.md (new, ~100 lines)
│   ├── Deployment Scripts
│   ├── Helm Commands
│   ├── kubectl Shortcuts
│   └── Access Points
└── CONVENTIONS.md (new, ~150 lines)
    ├── Namespace Conventions
    ├── Script Naming
    ├── File Organization
    ├── Metric Naming
    ├── Label Requirements
    ├── Go Code Conventions
    ├── Dashboard Conventions
    └── Local Build Verification
```

**Key Principles:**
1. **AGENTS.md = Quick Start** - Essential workflow and critical patterns only
2. **Detailed Guides = Deep Dive** - Comprehensive reference material
3. **Clear Links** - Easy navigation between files
4. **Consistent Structure** - Follows existing `docs/guides/` pattern

### Content Distribution Strategy

**Keep in AGENTS.md:**
- Critical notices (must-read warnings)
- Agent Workflow (5-step checklist)
- Code Quality Standards (brief bullets)
- Documentation Standards (Mermaid requirement - critical)
- Architecture diagram (visual reference)
- Key Design Patterns (brief summary)
- Technology Stack (brief summary)
- Project Structure (essential reference)
- Quick Navigation (condensed with links)

**Extract to Guides:**
- Research Patterns → `docs/guides/RESEARCH_PATTERNS.md`
- Command Reference → `docs/guides/COMMAND_REFERENCE.md`
- Conventions → `docs/guides/CONVENTIONS.md`

**Condense in AGENTS.md:**
- Development Commands → Brief summary + link to CONFIGURATION.md
- Observability → Brief summary + link to docs/apm/
- API Endpoints → Brief table + link to API_REFERENCE.md
- Important Notes → Brief bullets + link to SETUP.md
- Troubleshooting → Brief bullets + link to TROUBLESHOOTING.md

### Best Practices Applied

**From AI Agent Documentation Patterns:**
1. **Quick Start First** - Critical information in first 50 lines
2. **Progressive Disclosure** - Details available via links
3. **Scannable Structure** - Clear headings, bullet points, tables
4. **Consistent Formatting** - Follows existing docs patterns
5. **Maintainability** - Separate concerns into focused files

**From Project Patterns:**
1. **Follows `docs/guides/` structure** - Consistent with existing organization
2. **Matches `docs/README.md` approach** - Index with links to detailed guides
3. **Preserves all content** - Nothing lost, just reorganized

---

## Open Questions

1. **Should Research Patterns be split further?**
   - Option A: Single file with 3 sections (API, APM, Database)
   - Option B: Three separate files (RESEARCH_API.md, RESEARCH_APM.md, RESEARCH_DATABASE.md)
   - **Recommendation:** Option A - Related content, easier to maintain

2. **Should Command Reference include examples?**
   - Current: Tables only
   - **Recommendation:** Keep tables, add brief usage examples for common tasks

3. **Should CONVENTIONS.md include troubleshooting?**
   - Current: Build verification in AGENTS.md
   - **Recommendation:** Yes, move to CONVENTIONS.md for consistency

---

## Next Steps

1. **Review findings** - Confirm hierarchical approach
2. **Create new guide files** - Extract content to RESEARCH_PATTERNS.md, COMMAND_REFERENCE.md, CONVENTIONS.md
3. **Refactor AGENTS.md** - Condense to ~200-250 lines with links
4. **Update references** - Fix links in docs/README.md, CONFIGURATION.md, SETUP.md
5. **Update CHANGELOG.md** - Document refactoring
6. **Verify** - Ensure all content preserved, links work, structure clear

---

*Research completed with SDD 2.0*

