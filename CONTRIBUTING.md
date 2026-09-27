# Contributing to Gust

Thanks for helping out!

## Reporting bugs

Open an [issue](https://github.com/thecmdrunner/gust/issues/new/choose) and include:

- Mac model (`sysctl -n hw.model`) and macOS version
- What you did, what you expected, what happened
- Output of `app/build/Gust.app/Contents/Helpers/GustHelper --probe` if fan readings are involved

Different Macs expose slightly different SMC keys, so the read-only probe output (see README) is gold for hardware issues.

## Pull requests

1. Fork, branch from `main`.
2. `./app/build.sh` and `bun app/scripts/test.ts` must pass. For the site: `cd web && bun run build`.
3. Test on real hardware when touching fan control, and say which Mac you tested on.
4. Keep PRs focused; match the surrounding style.

Security-sensitive changes (the root helper, the socket protocol, the installer) get extra review — please explain the reasoning.

By contributing you agree your work is licensed under the [MIT License](LICENSE).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
