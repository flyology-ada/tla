# Flyology TLA+ harness repository

- Preserve the versioned trace and result contracts. Reject unknown versions instead of guessing.
- Keep `flyology_json` use isolated to the private `Flyology_TLA.JSON` child so a future serde migration does not
  change the public replay API.
- A materialized trace contains every choice needed by the implementation adapter. Replay must use no ambient
  randomness.
- Compare semantic outcomes and post-transition state. Do not compare representation details outside the model's
  reviewed abstraction boundary.
- Do not claim arbitrary trace deletion is model-valid shrinking. Preserve the exact reproduction artifact and the
  same property plus stable failure fingerprint for every accepted reduction.
- TLA+ Tools and TLAPS are exact hash-pinned inputs. Temurin resolves the latest Java 21 GA build at installation and
  the resolved version and archive digest become run provenance.
- Run `gh` outside the sandbox. Repository: `flyology-ada/tla`.
