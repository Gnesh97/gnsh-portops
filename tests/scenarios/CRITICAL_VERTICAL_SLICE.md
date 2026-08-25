# Critical vertical slice

Use this scenario on `dev` before expanding production scope:

1. Player A reserves `qc-01`, binds a move/container, and consumes a validated attach token.
2. Player A hands the container to a terminal trailer; the server persists `ON_TERMINAL_TRAILER`.
3. Player B claims the terminal tractor step and reaches the reserved Yard C slot.
4. Player C claims the yard-handler step and submits distance/heading/vertical snap metrics.
5. The server rechecks slot and container versions, commits the canonical slot transform, and completes the move.
6. Restart the resource, reload the same records, and verify the container remains at the same canonical slot.

Pass criteria: no direct client event can complete an out-of-order step, a second reservation/claim loses its version race, and observers receive the same canonical container location.
