# Clutter Clear

A Mac menu bar app that checks your inboxes every morning, finds promotional, repetitive and spam senders, and lets you decide on each one:

- **Keep**: the email stays, and that sender is never flagged again.
- **Unsubscribe**: the app unsubscribes for you, then removes nothing, the flagged emails, or every email from that sender (to Trash, so it can be undone).
- **Move to Junk** (likely spam only): the app never clicks spam links, because that confirms your address is real. It moves the mail to Junk and blocks the sender, so their future mail goes to Junk automatically.

Review senders one at a time as **cards** (swipe right to keep, left to unsubscribe, or use ← → and ↓ for later), or switch to a **list** in Settings or with the toggle at the top of Review.

## Install

```bash
./scripts/build-app.sh --install
```

This builds `Clutter Clear.app`, copies it to `/Applications`, and opens it. Look for the envelope icon in the menu bar. The app shows a Dock icon only while its window is open.

## Connect your inboxes

| Provider | Password to use |
|---|---|
| Gmail | An [app password](https://myaccount.google.com/apppasswords) (needs 2-Step Verification) |
| AT&T / SBC Global | A *secure mail key* from att.com → Profile → Sign-in info |

Passwords are stored in the macOS Keychain. Mail is read over IMAP (port 993) and unsubscribe emails are sent over SMTP (port 465).

## How unsubscribing works

The app tries these methods in order:

1. **One-click** (RFC 8058): a background request to the sender. Most big senders support it.
2. **Unsubscribe email**: sent from your own account to the list's unsubscribe address.
3. **Web page**: opened in a hidden, cookie-free browser, where the app presses the unsubscribe/confirm button.
4. **Link in the email body**: used when the email has no unsubscribe header.

If none can be confirmed, the sender appears under **Activity → Needs you to finish** with a button that opens the page.

## Daily check and pausing

- The check runs at the time you set (8:00 AM by default). If the Mac is asleep then, it runs when the Mac wakes.
- Turning **Daily Check** off stops all checks. Turning it back on immediately checks every email since the last check. Emails that were already reviewed are tracked by Message-ID and never shown twice.

## Optional: Claude classification

Add an Anthropic API key in Settings to have Claude decide which senders are worth keeping, such as bank alerts and receipts versus marketing. Only sender names, addresses and subject lines are sent, and only for senders that already look automated. With prepaid credits on console.anthropic.com, a $5 balance lasts a long time at this volume, especially on Haiku.

## Development

```bash
swift build
.build/debug/ClutterClear --selftest
.build/debug/ClutterClear --nettest
.build/debug/ClutterClear --snapshot /tmp/snaps
```

- `--selftest` runs the parser and rule checks.
- `--nettest` connects to Gmail and AT&T with a fake login to exercise IMAP.
- `--snapshot` renders each tab with sample data to PNG files.

App data lives in `~/Library/Application Support/ClutterClear/state.json`.
