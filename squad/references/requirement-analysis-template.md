# Requirement analysis: <Product or feature name>

<!-- Signed-off: <YYYY-MM-DD> by <stakeholder>   ← written by the PM at GATE 1 only -->
- Slug: `<slug>`
- Status: Draft | Clarifying (round <n>) | Clear | Signed off
- Sources: see the table below

## Changelog
| Date | Round | Change |
|---|---|---|
| YYYY-MM-DD | 1 | Initial analysis |

## Sources
| ID | File (in `sources/`) | Origin | Retrieved | Notes |
|---|---|---|---|---|
| SRC-1 | `brief.md` | stakeholder-brief / path / URL | YYYY-MM-DD | |

## 1. Business goal and problem statement
<Why this exists, for whom, and what success looks like. Cite sources.>

## 2. Actors / personas
| Actor | Description | Goals |
|---|---|---|

## 3. Functional requirements
| ID | Requirement | Source | Status |
|---|---|---|---|
| FR-01 | The system shall … | SRC-1 §Login | confirmed / provisional (A-01) / disputed (C-01) |

## 4. Non-functional requirements
| ID | Category | Requirement | Source |
|---|---|---|---|
| NFR-01 | Performance / Security / Platform / i18n / Accessibility / Data | … | SRC-2 p.1 |

## 5. Scope
- **In:** …
- **Out:** … (and why)

## 6. Business rules and data entities
- BR-01: …
- Entities: `<Entity>` (fields, relations; business terms keep the original in parentheses,
  e.g. `household registration book (sổ hộ khẩu)`)

## 7. Gaps (missing information)
- G-01: … → Q-xx

## 8. Ambiguities (more than one reading)
- AMB-01: … readings: (a) … (b) … → Q-xx

## 9. Conflicts (sources disagree)
- C-01: SRC-1 says "…" vs SRC-2 says "…" → Q-xx

## 10. Assumptions (provisional until confirmed)
- A-01: … → Q-xx

## 11. Risks and external dependencies
- R-01: … (third-party API, data, legal, deadline)
