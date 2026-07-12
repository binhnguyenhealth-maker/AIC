# Chicago IUCR mapping — methodology reference

The single machine-readable source of truth is
[`../../pipeline/iucr_mapping.json`](../../pipeline/iucr_mapping.json). Its
schema-v3 launch hash is:

```text
SHA-256 3b7b0b6f8ffca3bdb33e09dae149b099b748e2252a22755330834bea32018072
```

The reviewed human-readable table, including official primary/secondary
descriptions, index flags, active flags, and all 86 frozen codes, is
[`../../pipeline/IUCR_MAPPING.md`](../../pipeline/IUCR_MAPPING.md). This file is
intentionally a pointer rather than a copied table so the two documents cannot
diverge.

Binding rules:

1. Every four-character IUCR key is unique and maps to exactly one product
   category.
2. The only product categories are assault/battery, robbery, theft, and
   motor-vehicle theft.
3. `ASSAULT` and `BATTERY` both map to assault/battery.
4. The official IUCR source must contain exactly the frozen selected-primary
   code set with matching descriptions/index/active fields, or the build fails.
5. The frozen-period crime source is separately queried for any selected
   primary type whose IUCR is absent from the mapping; any nonzero result fails
   the build. The schema-v3 source window produced zero unmapped rows.
6. IUCR codes and incident rows remain build-only and never enter the iOS pack.

Do not infer subcategories such as “phone theft” from free text. Product labels
must remain at the four approved category levels.
