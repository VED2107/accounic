# Deployment

How each of the four pieces gets from this repository to something a person can use.

Nothing here is automated. There is no CI, and releases are cut by hand from a clean
`main`.

---

## 1. Configuration

Three values, and every client takes them differently:

| Value | Web | Flutter |
|---|---|---|
| Supabase URL | `NEXT_PUBLIC_SUPABASE_URL` | `--dart-define=SUPABASE_URL` |
| Anon key | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `--dart-define=SUPABASE_ANON_KEY` |
| Service-role key | `SUPABASE_SERVICE_ROLE_KEY` — server only | never |

`web/.env.local` is gitignored and holds all of them locally. **The service-role key
never reaches a client** — it is read only inside server actions
(`web/src/lib/admin-actions.ts`).

The Flutter values are baked in **at compile time**. There is no config file to ship
and none to lose. A build made without them starts and says so rather than failing
later with a network error.

---

## 2. Database

Migrations are numbered and must run in sequence:

```bash
cd db/tools && npm install && cd ../..
node db/tools/run-sql.mjs migrate       # 0001 … 0009
node db/tools/run-sql.mjs test          # 82 assertions, rolled back
node db/tools/smoke-api.mjs             # the real anon-key path
```

The runner reads `DATABASE_URL` from the environment or from `web/.env.local`.
Without it, paste each file into the Supabase SQL editor in filename order.

Then promote the first administrator, from the SQL editor or with the service role:

```sql
select public.grant_admin('you@example.com');
```

**The demo users are gone.** `db/seed.sql` creates two demo workspaces
(`demo@example.com`, `friend@example.com`) whose password — `Demo@12345` — is written
into `db/tools/smoke-api.mjs`. That was survivable while the repository was private and
became a live credential in a public repository the moment it was not, so both users were
deleted from the live project on 2026-08-26, before visibility changed. `demo@example.com`
also held a row in `public.app_admins`, so the published password would have opened the
admin surface.

Re-seeding is fine on a throwaway project. **Do not re-seed the live one**, and if you
ever do, delete the users again before publishing anything.

---

## 3. Web

Vercel, or anything that runs Next.js 15. Set the three environment variables in the
host's dashboard — not in a committed file — and deploy `web/`.

```bash
cd web && npm run typecheck && npm test && npm run build
```

The build must be clean before deploying; there is no CI to catch it afterwards.

---

## 4. Windows

```bash
cd app
flutter build windows --release \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
```

**Stop any running instance first.** A running `accounic.exe` locks the executable and
the build fails with a bare "Build process failed" that names no cause.

### Installer

Inno Setup 6, installed with `winget install --id JRSoftware.InnoSetup`. It lands in
`%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` — *not* Program Files, so `where iscc`
will not find it.

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" `
    app\windows\installer\accounic.iss /DAppVersion=1.0.4
```

It installs per-user into Local AppData, so there is no UAC prompt.

The script packages the **whole** `build\windows\x64\runner\Release` directory,
recursively. Shipping `accounic.exe` on its own produces a binary that will not start:
the engine DLL and `data\` — ICU data, assets, the AOT snapshot — are all required.

### Portable zip

```powershell
Compress-Archive -Path app\build\windows\x64\runner\Release\* `
    -DestinationPath app\build\installer\Accounic-1.0.4-windows-x64-portable.zip
```

---

## 5. Android

```bash
cd app
flutter build apk --release \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
```

**Bump `version:` in `app/pubspec.yaml` first.** The number after `+` is Android's
`versionCode`, and an APK that does not raise it cannot install over a copy already on
the device. It sat at `1.0.0+1` through three releases before this was noticed.

> **The release APK is debug-signed.** `android/app/build.gradle.kts` still points its
> release build at `signingConfigs.getByName("debug")`. That is fine for sideloading
> and wrong for the Play Store or any public distribution. Fixing it means generating
> a keystore and a gitignored `key.properties` — and losing that keystore permanently
> blocks updates to every installed copy. Say this whenever the APK is handed to
> anyone.

---

## 5b. Before any migration: take a snapshot

A migration that loses a row is the one failure this product cannot come back from, so
"nothing was deleted" is a comparison rather than a claim:

```bash
node db/tools/snapshot.mjs before     # counts, ids, and every person's net balance
node db/tools/run-sql.mjs file db/migrations/00NN_….sql
node db/tools/snapshot.mjs after
node db/tools/snapshot.mjs diff       # exits non-zero if anything moved
```

`diff` fails on a count that dropped, a person id that disappeared, or a net balance that
changed. Run it before tagging, and read it before believing a release is safe.

The currency feature also has an end-to-end check that runs as an ordinary signed-in user
over real HTTP and cleans up after itself:

```bash
node db/tools/smoke-currency.mjs      # creates a throwaway user, then deletes it
```

---

## 6. Cutting a release

`app/build/installer/` is gitignored. Artifacts are release assets, not repository
contents.

1. `cd app && flutter analyze && flutter test` — both must be clean.
0. `node db/tools/snapshot.mjs diff` — clean, if a migration went out with this release (§5b).
2. Bump `version:` in `app/pubspec.yaml`, commit as `chore(release): X.Y.Z`.
3. Build both binaries (§4, §5).
4. Compile the installer and the portable zip (§4).
5. **Install the installer and launch what it installed.** Compiling proves nothing
   about whether the result starts.
6. `git push`, tag `vX.Y.Z`, push the tag.
7. `gh release create vX.Y.Z --title … --notes-file … <the three assets>`.

Releases live at https://github.com/VED2107/accounic/releases.

### What a release now does to installed copies

Since v1.3.0 the Flutter client checks GitHub Releases on launch
(`app/lib/data/update_repository.dart`) and shows a banner when the newest published
release is a higher semantic version than the running binary. Nothing needs doing per
release beyond publishing it: the check reads `tag_name` from
`/repos/{owner}/{repo}/releases/latest`, so any future release is detected on its own.

Three things it depends on, all of them decisions rather than code:

* **The repository must be public**, or the release must be. The API path the client
  uses is unauthenticated — a private repository answers `404`, which the client
  correctly reads as "no update" and stays silent. `VED2107/accounic` was made public
  on 2026-08-26 for exactly this reason, and the anonymous endpoint was checked
  afterwards: it returns `v1.3.0` and all three assets.
* **Tags must be semantic versions.** `v1.3.0` and `1.3.0` both work; a tag that does
  not parse compares as `0.0.0` and can never claim to be an upgrade.
* **Drafts and pre-releases are skipped**, so a draft cannot notify anyone early.

Assets are matched by extension — `.exe`/`.msi`/`.msix` on Windows, `.apk` on Android —
and the release page is the fallback when none matches, so a release with no assets is
still openable. Build with `--dart-define=UPDATE_CHECK=off` to disable the check (a
store build that updates itself), or `--dart-define=RELEASE_REPO=owner/repo` for a fork.
