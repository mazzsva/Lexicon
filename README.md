# Lexicon

Offline-first vocabulary app in SwiftUI, TCA, and Firestore.

<img src="https://github.com/user-attachments/assets/e9d250fa-a8c3-4cdb-9690-edea475f64be" alt="The sign-in screen, with the Sign in with Apple button" width="32%"> <img src="https://github.com/user-attachments/assets/4301c0fd-4196-4493-8207-9794eff2f3ee" alt="The home screen, with the list of entry cards and the sync status" width="32%"> <img src="https://github.com/user-attachments/assets/b846a87b-dcd8-4e94-a0f5-5018607b727c" alt="An entry detail screen, with the term and its definition" width="32%">

## Technologies

<table>
  <tr><td><b>Platform</b></td><td>iOS 26</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI</td></tr>
  <tr><td><b>Architecture</b></td><td><a href="https://github.com/pointfreeco/swift-composable-architecture">The Composable Architecture</a></td></tr>
  <tr><td><b>Backend</b></td><td>Firebase</td></tr>
  <tr><td><b>Database</b></td><td>Cloud Firestore</td></tr>
  <tr><td><b>Authentication</b></td><td>Sign in with Apple</td></tr>
  <tr><td><b>Intelligence</b></td><td>Foundation Models</td></tr>
  <tr><td><b>Testing</b></td><td><a href="https://github.com/swiftlang/swift-testing">Swift Testing</a></td></tr>
</table>

## Engineering

**One reducer tree.** App state lives in a single tree of reducers instead of scattering across views. Navigation is part of that state, so the whole navigation graph can be inspected and tested from one place.

**No view touches Firebase.** Every effect crosses a client with live, preview, and test implementations, so previews render with no network and a test fails on any effect it doesn't override.

**Offline reads and writes.** The entry list has one source of truth: a live Firestore listener backed by its local cache. Reads keep working when the connection drops, writes queue on-device, and both sync the moment it returns.

**Export and import.** Settings exports the entries to a versioned JSON file and imports it back. Each imported entry gets a new ID, so an import never overwrites an entry, and duplicates are skipped.

**Definitions.** On request, the on-device Apple Intelligence model writes a definition for English learners: one short sentence in simple, everyday words, like a learner's dictionary. Online, it reads the term's Wiktionary senses first, and a term it doesn't know gets a note.

**Apple Account checks.** The app checks the Apple Account credential on launch and each time it becomes active, and it listens for revocations. Any state other than authorized signs the user out.

**Account deletion.** Deleting an account reauthenticates the user with Apple, deletes their Firestore data, revokes the Apple token, then deletes the account. The whole sequence times out after 60 seconds, and a failure after the revoke signs the user out.

## Quality

- **Tests:** 139 tests cover every reducer, and none touch the network.
- **CI:** GitHub Actions lints and runs the full suite on every pull request that is ready for review.
- **Accessibility:** Every control has a VoiceOver label, and each entry card reads as one element.
- **Localization:** Every string the app shows is ready for translation.
