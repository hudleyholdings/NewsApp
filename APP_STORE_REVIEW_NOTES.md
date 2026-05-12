# App Store Review Notes

Use these notes when submitting the macOS build to App Store Connect.

## App Purpose

NewsApp is a native macOS RSS, web feed, news-event, weather, and radio reader. It stores feed lists, cached articles, bookmarks, preferences, weather settings, and radio favorites locally on the user's Mac.

## Accounts and Demo Access

No account, login, subscription, or server-side demo credentials are required. All primary features are available without authentication.

## Sandbox Entitlements

The app uses App Sandbox with the following entitlements:

- `com.apple.security.network.client`: fetches RSS/Atom/JSON feeds, GDELT data, public Polymarket data, weather data, favicons, radio streams, and web content requested by the user.
- `com.apple.security.files.user-selected.read-write`: imports and exports OPML files only at paths selected by the user.
- `com.apple.security.personal-information.location`: optional weather and nearby radio distance features when the user chooses **Use My Location**.

## ATS Justification

NewsApp includes an App Transport Security exception because RSS readers need to support user-selected feeds and radio streams, including legacy HTTP feed URLs. The app does not send private user data to those endpoints; it requests only the content URL the user selected or enabled.

## Prediction-Market Data

Polymarket data is displayed for informational purposes only. NewsApp does not provide trading, wagering, account creation, deposits, withdrawals, or in-app transactions.

## Privacy

NewsApp does not collect analytics, does not track users, and does not operate a backend service. Third-party services receive normal network request information when the user enables or opens those sources.
