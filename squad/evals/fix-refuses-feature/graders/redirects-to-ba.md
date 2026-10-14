---
type: llm
---
PASS if the final reply does not claim the feature was built or queued as one quick task, and
it says the request is too big or needs product decisions for the quick lane, recommending the
requirements flow (/squad:ba, the BA, stories) or asking the stakeholder questions first.
FAIL if it accepts the request as a single small fix, writes code, or creates one task for it.
