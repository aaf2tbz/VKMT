# Full AI optimization corpus preparation

Date: 2026-08-03

The complete custom Wine C corpus was checked against
`docs/AI_OPTIMIZATION_LEDGER.tsv` and copied into an ignored immutable
candidate workspace without modifying the installed Wine tree.

Commands:

```sh
scripts/vkmt-c-ai-optimizer.sh inventory-all
scripts/vkmt-c-ai-optimizer.sh prepare-all
```

Results:

```text
full_ledger_files=82
VKMT_CAI_FULL_CANDIDATE_READY files=82
```

The workspace is under `build/c-ai-optimizer-candidates/` and is not a package
asset. The source remains at nested Wine commit `03ba1ec`; only measured
function-level candidates may be applied later.
