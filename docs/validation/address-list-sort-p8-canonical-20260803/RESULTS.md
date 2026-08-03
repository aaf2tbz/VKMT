# x64 address-list sort — prepared P8 prefix receipt

Date: 2026-08-03

The address-list sort probe now supports `--prefix PATH` and was run against
the existing canonical graphics prefix. It did not create, reset, stage, or
run Wineboot on a prefix.

## Result

```text
VKMT_X64_ADDRESS_LIST_SORT_OK
status=0
```

The probe first ran the read-only prefix verifier, compiled the x86_64 guest
fixture, launched it with all FEX TSO controls set to zero, and stopped only
the supplied prefix's wineserver. The supplied prefix was not deleted or
reinitialized.

Evidence:

- `status.txt` — `status=0`;
- `environment.txt` — prepared-prefix identity and zero-TSO settings;
- `prefix-receipt.json` — canonical P8 receipt;
- `address-list-sort.log` — runtime diagnostic log and marker source.

The fresh-prefix behavior remains available with `--fresh` (or no mode
argument), preserving the historical bootstrap probe.
