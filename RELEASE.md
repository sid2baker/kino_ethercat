# Release Process

## 0.3.0 Plan

1. Publish `ethercat` `0.3.0` first.
2. Unset `KINO_ETHERCAT_USE_LOCAL_ETHERCAT` so `kino_ethercat` resolves the Hex dependency instead of the local path override.
3. Refresh dependencies: `mix deps.get`
4. Verify the release surface:
   - `mix test --no-start`
   - `npm run build` from `assets/`
   - `mix format --check-formatted`
   - `mix docs`
   - `mix hex.build`
5. Smoke-test the example notebook in [examples/01_ethercat_introduction.livemd](./examples/01_ethercat_introduction.livemd) from a clean Livebook session.
6. Publish `kino_ethercat` `0.3.0`.

## Local Development

Before `ethercat 0.3.0` is on Hex, use the sibling checkout by setting:

```bash
export KINO_ETHERCAT_USE_LOCAL_ETHERCAT=1
```

1. Update `version` in `mix.exs` and move `[Unreleased]` items to the new version section in `CHANGELOG.md`.
2. Push `main` to GitHub so hexdocs source links resolve: `git push origin main`
3. Preview docs locally: `mix docs && xdg-open doc/index.html`
4. Sanity check the package: `mix hex.build`
5. Tag and push: `git tag vx.y.z && git push --tags`
6. Publish: `mix hex.publish`
7. Create a GitHub release using the changelog notes for that version.

> If you need to backport a fix to an older minor version, create a `vx.y` branch,
> cherry-pick the relevant commits, then follow steps 4–7 from that branch.
