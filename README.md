# Lexicon

The iOS app that keeps the words you want to remember.

<img src="https://github.com/user-attachments/assets/f97afda5-c1ca-423c-b9a3-a2eaa232d328" alt="signinview" width="32%"> <img src="https://github.com/user-attachments/assets/ed8f7277-bd7a-42f6-9919-530ba40cd93c" alt="homeview" width="32%"> <img src="https://github.com/user-attachments/assets/de03152e-59f6-4235-af6c-f825ec5e0977" alt="entrydetailview" width="32%">


## Features

- Write a term with its definition, then edit or delete it later
- Bookmark the ones that matter most
- Search as you type, across both terms and definitions
- See at a glance when your entries are syncing, and when you're offline
- Sign in with Apple, then sign out or delete your account and its data from Settings

## Technologies

| Area | Choice |
| :--- | :--- |
| **Platform** | iOS 26 |
| **Language** | Swift 6 |
| **Interface** | SwiftUI |
| **Architecture** | [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) |
| **Backend** | Firebase |
| **Database** | Cloud Firestore |
| **Authentication** | Sign in with Apple |

## Structure

| Folder | Contents |
| :--- | :--- |
| `App/` | Entry point, session state machine, root view, welcome sheet, loading window |
| `Features/` | SignIn, Home, EntryForm, EntryDetail, Settings |
| `Models/` | Entry, User |
| `Dependencies/` | Auth, SignInWithApple, Entries, NetworkMonitor, Haptics |
| `Support/` | Logging, app version, shared view modifier |

Each screen is a reducer and a view of the same name, and `AppFeature` holds whichever one the session calls for. Navigation comes from state too, so `Home` owns the stack of entry details and each sheet it presents, and no view drives its own presentation.

Every side effect crosses a client with live and preview values, so no view touches Firebase and previews run without a network. A snapshot listener on `users/{uid}/entries/{id}` is the only source of truth for the list. That listener keeps reading from Firestore's local cache when the connection drops, and writes queue there until it returns, so the list stays readable and editable offline.

## Requirements

The repository carries the app but not the accounts behind it, so running Lexicon means supplying your own:

- Paid Apple Developer account, since Sign in with Apple rules out a personal team
- Team and bundle identifier in place of the ones committed in the project
- Firebase project with Apple enabled as a sign-in provider, plus Firestore
- Apple sign-in key and Services ID, which Firebase needs to revoke tokens on deletion
- `GoogleService-Info.plist` added to the `Lexicon/` folder, where git ignores it
- Firestore rules scoped so a signed-in user reaches only their own `users/{uid}`
