# Pointrans project instructions

Pointrans is a native macOS menu-bar application with a Cloudflare Worker. Web/PWA platform defaults do not apply
unless a task explicitly adopts them.

- For platform or cross-application work, read only `~/.local/share/cuostudio/kb/SUMMARY.md`, then let the relevant
  skill load one directly related standard. Do not edit the platform knowledge base from this application task.
- Preserve the bundle identity, UserDefaults, Keychain data, and macOS permission identity.
- Never send screenshots or application identity to the Worker, and never commit production secrets.
- Run the hostless `PointransCoreTests` command documented in `README.md` for Swift changes. For Worker changes, run
  `npm run check` and `npm test` inside `Worker/`.
- `build.sh` and `package.sh` install or replace the local application; run them only when the user requests a build,
  installation, or package.
