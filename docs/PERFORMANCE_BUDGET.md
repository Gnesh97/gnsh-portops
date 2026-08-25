# Performance budget

Record idle client, active operator, observer, and dense-yard profiles using
resmon/profiler. The evidence must include client frame time, server tick time,
network bytes, and query latency at the LOAD baseline. A release is blocked by
unbounded broadcasts, sustained frame spikes, or missing measurements.
