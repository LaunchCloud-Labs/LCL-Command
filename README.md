# `lcl-command`

Installable LaunchCloud Labs client for employee portal login, Mission Control access, and future SSH handoff.

## Current status

`lcl-command` is now a working MVP:

- `login` authenticates against the employee portal bridge with email + PIN
- `status` validates the saved session
- `shell` can now perform autonomous SSH handoff when the portal bridge is configured with runtime SSH credentials
- `console` is the future Project Arbiter entry point

When the SSH bridge is not configured yet, `shell` falls back to Mission Control guidance.

## Commands

```bash
lcl-command login
lcl-command status
lcl-command shell
lcl-command console
lcl-command logout
lcl-command help
```

## npm

Public release asset install:

```bash
npm install -g https://github.com/LaunchCloud-Labs/LCL-Command/releases/download/v<version>/lcl-command-<version>.tgz
```

Local packaging:

```bash
cd ops/lcl-command-client
npm run check
npm pack
```

Full local release artifact build:

```bash
npm run build:release
```

Global install shape:

```bash
npm install -g lcl-command
```

That plain package-name install is reserved for the npm registry publish step once registry credentials are configured.

## pip

Public release asset install:

```bash
pip install https://github.com/LaunchCloud-Labs/LCL-Command/releases/download/v<version>/lcl_command-<version>-py3-none-any.whl
```

A thin Python wrapper is included under `packaging/python/`. It bundles the Node client and launches it with the local `node` runtime.

Local install test:

```bash
cd ops/lcl-command-client/packaging/python
python3 -m pip install .
lcl-command help
```

## Homebrew

A formula is included under `packaging/homebrew/lcl-command.rb`.

Live repo install:

```bash
brew install LaunchCloud-Labs/LCL-Command/lcl-command
```

It is already pinned to the current `0.2.0` npm tarball checksum. To publish it broadly:

1. Publish the matching `lcl-command@0.2.0` npm tarball.
2. Keep the packaged contents aligned with the checksum in the formula.
3. `brew install ./packaging/homebrew/lcl-command.rb`

## Environment

- Default bridge endpoint:
  `https://www.launchcloudlabs.com/employment/portal/Employee_Portal/lcl_command_bridge.php`
- Local session file:
  `~/.config/lcl-command/session.json`

### SSH handoff configuration

For autonomous employee login into the company server, configure these on the portal host as runtime environment values rather than committing them into source:

- `LCL_COMMAND_SSH_HOST=100.90.184.23`
- `LCL_COMMAND_SSH_USER=LCL`
- `LCL_COMMAND_SSH_PASSWORD=<shared runtime secret>`
- optional: `LCL_COMMAND_SSH_READY=true`

For employee rollout, the client first uses the built-in macOS `expect` runtime and otherwise falls back to the bundled Python SSH helper when `python3` is already available. The goal is zero extra manual setup for the employee after install.

## Release notes

This packaging layer is intentionally built around the Node reference client so npm, pip, and Homebrew stay aligned while the SSH handoff and employee rollout are finalized.

The GitHub release channel is live now. Public npm and PyPI registry publication still require registry credentials or trusted-publisher setup.

## What employees can use right now

Today, employees can install `lcl-command` immediately with:

```bash
brew install LaunchCloud-Labs/LCL-Command/lcl-command
```

or

```bash
npm install -g https://github.com/LaunchCloud-Labs/LCL-Command/releases/download/v0.2.0/lcl-command-0.2.0.tgz
```

or

```bash
pip install https://github.com/LaunchCloud-Labs/LCL-Command/releases/download/v0.2.0/lcl_command-0.2.0-py3-none-any.whl
```

Plain-name installs are the goal, but they are not live yet:

```bash
npm install -g lcl-command
pip install lcl-command
```

Those two commands start working only after npm/PyPI publication is completed.

## How future updates work

No: a normal GitHub commit does **not** automatically roll out everywhere.

The rollout unit is a **versioned release**. The safe future flow is:

```bash
cd ops/lcl-command-client
python3 scripts/set_version.py 0.2.1
npm run build:release
```

Then publish the new source/release to GitHub:

```bash
gh release create v0.2.1 \
  dist/npm/lcl-command-0.2.1.tgz \
  dist/python/lcl_command-0.2.1-py3-none-any.whl \
  --repo LaunchCloud-Labs/LCL-Command \
  --title "lcl-command v0.2.1"
```

After that:

- Homebrew users get the new version when the tap repo’s formula is updated and they run `brew update && brew upgrade lcl-command`
- npm users get the new version after the npm registry publish step and then run `npm update -g lcl-command`
- pip users get the new version after the PyPI publish step and then run `pip install --upgrade lcl-command`

## What still has to be connected

To make the plain registry installs work, one of these must happen:

- add npm and PyPI credentials
- or configure trusted publishing from `LaunchCloud-Labs/LCL-Command`

Once that is configured, the existing GitHub Actions release workflow can publish npm and PyPI on each tagged release.
