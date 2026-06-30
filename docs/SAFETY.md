# Safety model

This is what separates a safe cleaner from one that breaks the OS. Three
independent layers, each enforced in exactly one place.

## 1. Rules engine — what may even be offered

`SafetyRuleEngine.evaluate(URL) -> SafetyDecision`. Decision precedence
(most cautious wins):

1. **User exclusion list** → always `.protected`. The user said hands-off.
2. **Active matching rules** → strictest disposition wins.
3. **No rule matches** → `.protected` (`default.deny`). *Nothing outside a
   known-safe path is ever auto-selected.* This default-deny is the core invariant.

Dispositions (`SafetyDisposition`, ordered by caution):

| Disposition | Meaning | UI behavior |
|---|---|---|
| `autoSelectable` | known-safe, low-risk | pre-ticked |
| `selectableManually` | removable, but user must opt in | listed, **not** pre-ticked |
| `protected` | system-critical or in-use | never offered |

A `SafetyRule` is declarative — *where* (glob `PathMatcher`), *when*
(`minOS`/`maxOS` range + `requiresApp` bundle id), and the *disposition* + a
human-readable `reason` shown in the UI for auditability.

## 2. Critical-path guard — the hard stop

`CriticalPathGuard.isProtected(URL)` vetoes destructive operations on
system-critical paths **even when the user explicitly confirms** — `/`, `/System`,
`/usr` (except `/usr/local`), `/bin`, `/sbin`, `/Library/Apple`, `~/Library`
itself, etc. The `Remover` consults it before every operation, regardless of which
module asked. The privileged helper enforces its own independent copy
(`SystemPathGuard`) so the root side never blindly trusts the client.

## 3. Disposal — reversible by default

`Remover` is the single destructive engine:

- **Trash by default** (`FileManager.trashItem`) — reversible.
- **Permanent delete is refused unless explicitly confirmed** (`allowPermanent`),
  surfaced in the UI as a separate switch + confirmation dialog.
- **Dry-run** mode reports what *would* happen and changes nothing
  (`RemovalReport.projectedBytes`).
- Every outcome is itemized (`trashed` / `deleted` / `wouldRemove` / `refused` /
  `failed`) so the result is reviewable.

The **user-editable exclusion list** (`ExclusionList`, persisted JSON) is honored
by *every* module, because all scans consult the same `ExclusionMatcher` and the
engine treats exclusions as `.protected`.

## Example rule set (`SafetyCatalog.standard()`)

| Rule id | Path | Disposition | Gating |
|---|---|---|---|
| `user.caches` | `~/Library/Caches/*` | auto | — |
| `user.caches.cloudkit` | `~/Library/Caches/CloudKit*` | manual | stricter override of caches |
| `user.logs` | `~/Library/Logs/*` | auto | — |
| `user.trash` | `~/.Trash/*` | auto | — |
| `xcode.derivedData` | `…/Xcode/DerivedData/*` | auto | requires `com.apple.dt.Xcode` |
| `xcode.deviceSupport` | `…/Xcode/iOS DeviceSupport/*` | manual | requires Xcode |
| `xcode.archives` | `…/Xcode/Archives/*` | manual | requires Xcode (may hold shippable builds) |
| `mail.downloads` | `…/com.apple.mail/…/Mail Downloads/*` | manual | — |
| `app.languages` | `/Applications/*.app/…/*.lproj` | manual | removing localizations can break apps |
| `quicklook.thumbnails.legacy` | old path | auto | `maxOS 25.x` |
| `quicklook.thumbnails.tahoe` | new path | auto | `minOS 26` |
| `protect.iosBackups` | `…/MobileSync/Backup/*` | **protected** | irreplaceable — never removed |

Note the deliberate caution: anything that could hold user-authored or shippable
artifacts (Xcode archives, language files, Mail downloads) is `manual`, never
auto. In production this catalog ships as data so it can update without an app
release. Verified by `Tests/NimbusKitTests/SafetyTests.swift`.
