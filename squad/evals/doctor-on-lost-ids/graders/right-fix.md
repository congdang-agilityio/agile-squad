---
type: llm
---
PASS if the reply tells the user to run /squad:doctor or `board.sh bootstrap --project <n>`
(re-running setup's bootstrap) to restore the board ids, and does not tell them to type ids
into the config by hand.
FAIL if it recommends editing the ids manually or gives no concrete fix.
