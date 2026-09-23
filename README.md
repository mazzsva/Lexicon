# Lexicon

[![CI](https://github.com/mazzsva/Lexicon/actions/workflows/ci.yml/badge.svg)](https://github.com/mazzsva/Lexicon/actions/workflows/ci.yml)

A vocabulary app for iOS that never loses a word.

<img src="https://github.com/user-attachments/assets/28ce5ec8-3945-4bb9-84c2-1fc7a53645e4" alt="The sign-in screen, with the Sign in with Apple button" width="32%"> <img src="https://github.com/user-attachments/assets/c4140c3d-24bc-459e-8d50-6440c17ccb20" alt="The home screen, with the list of entry cards and the sync status" width="32%"> <img src="https://github.com/user-attachments/assets/42c3037b-10ab-4204-aec1-811261fd6bc9" alt="An entry detail screen, with the term and its definition" width="32%">

## Technologies

<table>
  <tr><td><b>Platform</b></td><td>iOS 26</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI</td></tr>
  <tr><td><b>Architecture</b></td><td><a href="https://github.com/pointfreeco/swift-composable-architecture">The Composable Architecture</a></td></tr>
  <tr><td><b>Backend</b></td><td>Firebase</td></tr>
  <tr><td><b>Database</b></td><td>Cloud Firestore</td></tr>
  <tr><td><b>Authentication</b></td><td>Sign in with Apple</td></tr>
  <tr><td><b>Testing</b></td><td><a href="https://github.com/swiftlang/swift-testing">Swift Testing</a></td></tr>
</table>

## Engineering

**One reducer tree.** Every screen pairs a reducer with a view of the same name, and the app holds them in a single tree instead of scattering state across views. Navigation is a property on that state, not a flag a view owns, so the whole navigation graph can be inspected and tested from one place.

**No view touches Firebase.** Every effect crosses a client that has a live implementation and a preview one, so previews render with no network and any effect can be swapped out under test.

**Offline reads and writes.** The entry list has one source of truth: a live Firestore listener backed by its local cache. Reads keep working when the connection drops, writes queue on-device, and both sync the moment it returns.

**Account deletion.** Deleting an account reauthenticates the user with Apple, revokes the Apple token, then deletes the account and its Firestore data.

## Quality

- **Tests:** 86 tests cover every reducer, and none touch the network.
- **CI:** GitHub Actions lints and runs the full suite on every push and pull request.
- **Accessibility:** Every control has a VoiceOver label, each entry card reads as one element, and the sync status is announced.
- **Localization:** Every string the app shows is ready for translation.
