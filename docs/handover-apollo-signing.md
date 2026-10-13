# Handover: sign the Lodestar agent on apollo

Prompt for a coding agent on **apollo** (personal MacBook Pro M1 Pro, macOS 26,
user `thijsvw`, flake at `~/.flake`). Paste everything below the line.

---

On this Mac (apollo) the Lodestar agent at
`/var/lib/lodestar-agent/bin/lodestar-agent` stays ad-hoc signed. Get it signed
with the shared certificate and confirm it. Read `~/.flake/AGENTS.md` first.

## How signing works now

- All Macs sign the agent with one certificate,
  `modules/lodestar/lodestar-agent-signing.pem` (SHA-1
  `f546f94d49ec2d267e04f47ad78181c70d282d02`, CN "Lodestar Agent Code Signing").
  `modules/lodestar/agent.nix` sets it as
  `services.lodestar-agent.macos.stableSigning.certificate`.
- The private key is not in the repo. It's the 1Password document **Lodestar
  Agent Signing Key** (vault Personal; it's atlas's existing key). On each Mac it
  lives at `/var/lib/lodestar-agent/signing/key.pem` (root, 0600, dir 0700).
- On every switch, `extraActivation` (from `github:Waayway/lodestar`,
  `nix/modules/agent/install-binary.nix`) checks the key against the certificate,
  signs the copy at `binaryPath` in a throwaway keychain, and prints
  `lodestar-agent: signed …`, or a `lodestar-agent: warning: …` and leaves the
  binary ad-hoc signed. It never creates a key when a certificate is configured.
- Placing the key: `sudo lodestar-agent-signing-key < key.pem` (installed by the
  module; use the full path `/run/current-system/sw/bin/lodestar-agent-signing-key`
  if sudo can't find it), or by hand:
  `sudo install -d -m 700 /var/lib/lodestar-agent/signing` and
  `sudo install -m 600 key.pem /var/lib/lodestar-agent/signing/key.pem`.
  `op` isn't installed on apollo; save the document from the 1Password app.

## Likely cause of the failure

The signing step packs key and certificate into a PKCS#12 file for
`security import`. OpenSSL 3's default (AES-256, SHA-256 MAC) is rejected by
`security import` on older macOS ("MAC verification failed … wrong password?").
atlas (macOS 27) accepts it; apollo (macOS 26) apparently doesn't. lodestar
commit "fix(agent): PKCS#12 that older macOS can import" switches to
`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`. Make sure the
flake's `lodestar` input includes it (`grep -A12 '"lodestar": {' flake.lock`,
compare with `git ls-remote https://github.com/Waayway/lodestar main`).

## Steps

1. `git -C ~/.flake pull` (branch `unstable`); check `flake.lock` has the lodestar
   fix above.
2. Check the key is placed: `sudo ls -l /var/lib/lodestar-agent/signing/`. If
   `key.pem` is missing, ask Thijs to save the 1Password document to
   `~/Downloads/key.pem`, then place it (see above) and remove the download.
3. Switch: `sudo darwin-rebuild switch --flake ~/.flake#apollo`. Look for the
   `lodestar-agent:` lines in the output.
4. Verify: `codesign -dr - /var/lib/lodestar-agent/bin/lodestar-agent` must print
   `designated => identifier "org.lodestar.agent" and certificate leaf =
   H"f546f94d49ec2d267e04f47ad78181c70d282d02"`. Then
   `sudo launchctl kickstart -k system/org.lodestar.agent`.

## If it still fails

Reproduce the signing by hand as root with the same steps as `sign_file` in
`install-binary.nix` (temp dir, `openssl pkcs12 -export …`,
`security create-keychain`, `security import … -T /usr/bin/codesign`,
`security set-key-partition-list -S apple-tool:,apple: -s -k <pw> <kc>`,
`codesign --force --keychain <kc> -s <sha1> -i org.lodestar.agent …` on a copy
of the binary), and find the step that fails. The activation hides some stderr
(`>/dev/null` on import and partition-list). Never import into the System or
login keychain; always `security delete-keychain` the temp one. Fix it in
`~/lodestar` (clone `github:Waayway/lodestar` if absent): change
`install-binary.nix`, run `nix build .#checks.aarch64-darwin.agent-module`,
commit, and ask before pushing. Then `nix flake update lodestar` here and
commit with `git commit -m "…" -- flake.lock`.

Report: the `lodestar-agent:` lines from the switch, the `codesign -dr` output,
and what you changed.
