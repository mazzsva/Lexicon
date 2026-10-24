# Lexicon

Vocabulary app in SwiftUI, TCA, Firestore, and Foundation Models

<img src="https://github.com/user-attachments/assets/43800149-fc55-4539-b365-e42cf97a3088" alt="The sign-in screen, with the Sign in with Apple button" width="32%"> <img src="https://github.com/user-attachments/assets/bb727d29-7bbe-4a07-a633-de88410b48f8" alt="The home screen, with the list of entry cards and the sync status" width="32%"> <img src="https://github.com/user-attachments/assets/ccf6d7e3-ec19-4ebf-bfb5-9a750055804d" alt="An entry detail screen, with the term and its definition" width="32%">

## Technologies

<table>
  <tr><td><b>Platform</b></td><td>iOS 27</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI</td></tr>
  <tr><td><b>Architecture</b></td><td><a href="https://github.com/pointfreeco/swift-composable-architecture">The Composable Architecture</a></td></tr>
  <tr><td><b>Backend</b></td><td>Firebase</td></tr>
  <tr><td><b>Database</b></td><td>Cloud Firestore</td></tr>
  <tr><td><b>Authentication</b></td><td>Sign in with Apple</td></tr>
  <tr><td><b>Intelligence</b></td><td><a href="https://developer.apple.com/documentation/foundationmodels">Foundation Models</a></td></tr>
  <tr><td><b>Testing</b></td><td><a href="https://github.com/swiftlang/swift-testing">Swift Testing</a></td></tr>
</table>

## Engineering

**One reducer tree.** App state lives in a single tree of reducers instead of scattering across views. Navigation is part of that state, so the whole navigation graph can be inspected and tested from one place.

**No view touches Firebase.** Every effect crosses a client with live, preview, and test implementations, so previews render with no network and a test fails on any effect it doesn't override.

**Offline reads and writes.** The entry list has one source of truth: a live Firestore listener backed by its local cache. Reads keep working when the connection drops, writes queue on-device, and both sync the moment it returns.

**Export and import.** Settings exports the entries to a versioned JSON file and imports it back. Each imported entry gets a new ID, so an import never overwrites an entry, and duplicates are skipped.

**Definitions.** On request, the on-device Apple Intelligence model writes a one-sentence definition in simple words for English learners. Online, it reads the Wiktionary senses first, and an unknown term gets a note.

**Apple Account checks.** The app checks the Apple Account credential on launch and each time it becomes active, and it listens for revocations. Only a revoked credential signs the user out.

**Account deletion.** Deleting an account reauthenticates with Apple, deletes the Firestore data, revokes the token, then deletes the account. It times out after 60 seconds, and a failure after the revoke signs out.

## Quality

- **Tests:** 220 tests cover every reducer, and none touch the network.
- **CI:** GitHub Actions lints and runs the full suite on every pull request that is ready for review.
- **Accessibility:** Every control has a VoiceOver label, and each entry card reads as one element.
- **Localization:** Every string the app shows is ready for translation.
