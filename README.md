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

## pip

A thin Python wrapper is included under `packaging/python/`. It bundles the Node client and launches it with the local `node` runtime.

Local install test:

```bash
cd ops/lcl-command-client/packaging/python
python3 -m pip install .
lcl-command help
```

## Homebrew

A formula is included under `packaging/homebrew/lcl-command.rb`.

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
