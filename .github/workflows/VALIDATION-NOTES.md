# [DO NOT MERGE] Concurrency validation notes

Scratch record for the throwaway PR. Deleted with the branch.

Five arms, each fired with five pull request events within about a second.

| Arm | Group | `cancel-in-progress` | Cancelled, before | Cancelled, after |
| -- | -- | -- | -- | -- |
| Per-run group | `…-github.run_id` | literal `false` | 0 of 5 | 0 of 5 |
| Shared group | `…-github.ref` | literal `false` | 3 of 5 | 3 of 5 |
| Retry workflow, default | `…-github.ref` | `${{ inputs.… }}` | 3 of 6 | 0 of 5 |
| Retry workflow, explicit `false` | `…-github.ref` | `${{ inputs.… }}` | 2 of 5 | 0 of 5 |

"Before" is the workflow as PR #145 first fixed it, with the input defaulted to `false`.
"After" is with the concurrency block removed.

The shared-group arm calls nothing and reads no input — it is the same group shape with a
hardcoded `false` — and it cancels in both columns. That is what rules out `cancel-in-progress`
as the lever: GitHub cancels a previously pending run in a shared group whatever it says.
It also stays live in the "after" column, which is what stops the zeroes beside it from being
an artifact of events that never overlapped.
