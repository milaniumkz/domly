# Catalogue and address migration

Applications read only the backend API. Firestore access in `import-firestore-catalog.ts` is a manual, read-only migration tool, not a runtime dependency.

After deploying checked main, run the Deploy workflow with `mode=import-catalog`. It creates a private PostgreSQL backup before the import. The import validates the catalogue and commits packages, groups, services, zones, house addresses and pricing settings in a single transaction. Existing records and admin edits are retained on repeat imports.

Legacy `customer_packages` contains the five catalogue products, not customer purchases. Its price is KZT per square metre per cleaning. Import to `price_per_m2`, with `base_price=0`; retain quarterly discount and choices of 2, 4 or 8 visits per month. Current grouped addon configuration takes priority over older standalone entries.

House records must have an actual street and house number. Unnumbered places, mislabeled cities and invalid addresses are skipped. Duplicate street/house records are merged. Imported activation status comes from Firestore; adding a city to the directory does not activate service there.

The city directory includes 90 Kazakhstan cities from https://ru.wikipedia.org/wiki/Список_городов_Казахстана (retrieved 2026-10-06), including Alatau and Kosshy, with Kazakh names and historical aliases. This is a city directory, not a complete official national address register. The imported Astana address dataset is incomplete; additional suggestions use backend geocoding. Do not claim complete address coverage without an authoritative address registry.
