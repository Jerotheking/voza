# V01 review evidence — commit 9bc65724389f328f84cd5d32772224a536667a43

Reviewer: buffy (owner-authorized in-session review, 2026-09-09)

## Commands and results (real, unedited)

```
$ .build/debug/VozaSmoke v01
[PASS] v01 ac01 construct+read creates nothing
[PASS] v01 ac01 config write inside root
[PASS] v01 ac01 config write did not touch history
[PASS] v01 ac01 history write inside root
[PASS] v01 ac02 trial starts at 14 days — trial(daysLeft: 14)
[PASS] v01 ac02 trial over after 15 simulated days
[PASS] v01 ac02 trial state in isolated defaults
[PASS] v01 ac02 elapsed independent of wall jump
[PASS] v01 ac03 qa root removed
[PASS] v01 ac03 sibling sentinel intact
[PASS] v01 ac04 prod config path unchanged
[PASS] v01 ac04 prod history path unchanged
[PASS] v01 ac04 legacy Config anchor unchanged
[PASS] v01 ac04 real config.toml untouched by run
[INFO] v01: original smoke suites intentionally NOT executed (real-profile protection, V01-AC05)
V01 hermetic checks passed.  (exit=0)

$ defaults read com.jerotherey.voza | grep -c "voza.tests"
0   (no test keys leaked into the real defaults domain)

$ python3 -B docs/plan-glm/tools/plan.py validate
ok: true (1,489 links, 0 errors)
```

## AC verdicts

- V01-AC01 PASS — construction/reads create nothing; writes stay inside QA root (ac01 checks).
- V01-AC02 PASS — FixedClock drives trial dates + elapsed with zero sleeps (ac02 checks).
- V01-AC03 PASS — teardown removes only its root/suite; sibling sentinel intact (ac03 checks).
- V01-AC04 PASS — production paths byte-identical to baseline; legacy anchor unchanged; real config untouched (ac04 checks).
- V01-AC05 PASS — original smoke suites intentionally skipped; real profile untouched (AC05 notice + 0 leaked keys).

Note: post-review commits (9bc6572) touched V01-adjacent files (Config injection default, session record) without breaking any AC — re-verified with the same commands at this revision.
