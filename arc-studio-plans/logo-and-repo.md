## Implementation Plan: Platform logo and GitHub repository

### Summary
Put the user's logo on the header, browser tab and link preview, then publish the whole project to a new public GitHub repository named kgiwa-launchpad. Both need something from the user first.

### What I need from the user
1. Attach the logo image in chat. The path sandbox:/mnt/data/1000034016.png points to a different environment; no such file exists here. Square PNG, about 512x512 or larger.
2. Connect GitHub from the Integrations menu (or the + menu in the chat toolbar), then reply "push to GitHub".

### Architecture
- Logo: header brand mark replaced by the logo (public/logo.png); favicons generated (32, 180 Apple touch, 512); 1200x630 share image (public/og.png) with the logo centred on the app's dark background; Open Graph and Twitter card tags in index.html using the absolute live URL https://arc-studio-91ae6801bd494a2f8926109f.vercel.app/og.png. Static assets only; no contract or wallet changes.
- GitHub: repository kgiwa-launchpad, public. Includes src/, contracts/, remix/, scripts, config, lockfile, README, AGENTS.md, license. Never includes .env, keys, node_modules, dist, contracts/out, contracts/cache. Scan files for private keys and secrets before pushing and stop if anything looks sensitive. Add .env.example with variable names only. README documents setup, tests, deploy, contract addresses, and that v2.2 (fundraise vesting) is built and tested but needs the Remix redeploy. One clean initial commit on main, push, report URL.

### Files to Create/Modify
1. public/logo.png, public/favicon-32.png, public/apple-touch-icon.png, public/icon-512.png, public/og.png
2. index.html: icon links, title, description, Open Graph and Twitter card tags
3. src/components/Nav.tsx: logo in the header brand area
4. .gitignore: confirm coverage
5. .env.example: variable names only
6. README.md: public setup/test/deploy docs
7. LICENSE: MIT

### Build Sequence
1. Receive and check the logo.
2. Generate favicon, touch-icon and share-image versions.
3. Update index.html and header; lint, typecheck, build.
4. Redeploy to Vercel.
5. After GitHub is connected: secret scan, prepare files, create public kgiwa-launchpad, push, report URL.

### Done When
- [ ] Logo shows in the header.
- [ ] Browser tab shows the icon.
- [ ] Sharing the live link in Telegram or X shows the logo as preview.
- [ ] Lint, typecheck and build pass; app redeployed.
- [ ] Public kgiwa-launchpad repository exists with the full project.
- [ ] No .env, keys or secrets in the repository; .env.example included.

## Ready to build?
