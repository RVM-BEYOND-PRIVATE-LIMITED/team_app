# Device checks

Checks of team_app #52 that only a real phone (or an emulator, where noted)
can show. Whoever has the phone runs the steps, writes the result in the
table at the end of the check, and ticks item 13 in team_app #52 when every
row that can be run says yes.

What you need: a computer with `adb` (Android SDK platform-tools), Flutter
3.35.7, this repository, and an Android phone with USB debugging on
(Settings → About phone → tap "Build number" seven times → Developer
options → USB debugging). `adb devices` must list the phone as `device`.

This is an Android check only. The block is Android's `FLAG_SECURE`; iOS
has no such flag, so on iOS the app sends nothing
(`lib/platform/secure_window.dart`) and an iOS screenshot of these screens
is not blocked.

## Check 1: sensitive screens cannot be captured; other screens can

> A screenshot and a screen recording of a sensitive screen come out black,
> and its app-switcher (Recents) preview is blank. Home, the Wall and every
> other screen can still be captured.

How it works, so the steps make sense:

- `MainActivity.kt` sets `FLAG_SECURE` on the window when the Dart side
  asks on the `team_rvm/secure_window` channel, and clears it when asked.
  This happens in every build mode, debug included.
- A sensitive screen holds the block through `SecureScope`
  (`lib/widgets/secure_scope.dart`): from its first frame, under a dialog or
  a bottom sheet (the screen still shows behind it), and on again when you
  come back to it. An opaque screen on top of it, or leaving it, lets go.
- Which screens are sensitive is decided in one place:
  `lib/router/sensitive_routes.dart` (`isSensitiveLocation`). That is every
  route of a module marked `sensitive: true` in
  `lib/router/module_routes.dart` (`/crm`, `/fees`, `/desk`, `/placement`,
  `/complaints`), and the class roster, `/work/batch/:id/mark`, while the
  `SECURE_ROSTER` switch is on.
- The roster's switch is off unless a build passes
  `--dart-define=SECURE_ROSTER=true`. No module screen exists yet, so today
  the roster is the one screen to check.

### Build

Install a debug build with the roster switch on, with the phone connected:

```bash
cd flutter_app/rvm_team_app
flutter run --dart-define=SECURE_ROSTER=true
```

A debug build is the one to use: the block is the same in every build mode
(it is set natively), and a release build needs the release key
(`android/key.properties`, see the README). Leave `flutter run` running;
step 10 stops it.

If the phone already has a Team RVM build signed with another key,
`flutter run` cannot install over it, so it uninstalls that build and
installs again ("Uninstalling old version..."); that build's data, its
sign-in included, goes with it. To remove it yourself first:
`adb uninstall com.rvm.rvmteam`.

With no `SCHEDULER_BASE_URL` or `ESS_BASE_URL` define, a debug build talks
to the live servers, so use a faculty **test** account: a portal sign-in
(User ID / phone / email and password, not the attendance sign-in code)
whose role is faculty or HOD, with at least one batch. The roster shows
that batch's students.

### Steps

Run the `adb` commands from any folder on the computer, in a second
terminal while `flutter run` keeps the first. Each file lands in that
folder.

1. On the phone, sign in as the faculty test account. Home opens.
2. Before: Home can be captured.

   ```bash
   adb exec-out screencap -p > 1-home.png
   ```

   Open `1-home.png`: it shows Home.
3. Open a class roster: tap the **Attendance** tab, then a class under
   "Mark attendance" (or **Open all my batches**, then a batch). The
   roster lists the students with a tick box each.
4. Screenshot of the roster:

   ```bash
   adb exec-out screencap -p > 2-roster.png
   ```

   Open `2-roster.png`: the app's area is black (the status bar may still
   show).
5. Screen recording of the roster (5 seconds; touch nothing):

   ```bash
   adb shell screenrecord --time-limit 5 /sdcard/3-roster.mp4
   adb pull /sdcard/3-roster.mp4
   adb shell rm /sdcard/3-roster.mp4
   ```

   Play `3-roster.mp4`: the app's area is black for the whole clip.
6. App switcher (Recents) preview of the roster:

   ```bash
   adb shell input keyevent KEYCODE_APP_SWITCH
   ```

   (or press the phone's Recents button, or swipe up and hold). The Team
   RVM card is blank or black, not a picture of the roster. The phone's own
   screenshot (power + volume down) is refused or black too. Tap the card to
   go back to the app.
7. Under a sheet (only if the roster has a student saved absent: that row
   has a note icon, "Absent reason"): tap the note icon. The absent-reason
   sheet opens over the roster. Then:

   ```bash
   adb exec-out screencap -p > 4-sheet.png
   ```

   Open `4-sheet.png`: black. Close the sheet without saving. If no student
   is saved absent, write "not run" for this step.
8. After leaving: tap the back arrow, then the **Wall** tab. Capture works
   again.

   ```bash
   adb exec-out screencap -p > 5-wall.png
   adb shell screenrecord --time-limit 5 /sdcard/6-wall.mp4
   adb pull /sdcard/6-wall.mp4
   adb shell rm /sdcard/6-wall.mp4
   adb shell input keyevent KEYCODE_APP_SWITCH
   ```

   `5-wall.png` and `6-wall.mp4` show the Wall, and the Recents card shows
   it too. Tap the card to go back.
9. Back to the foreground: open the roster again (step 3), press the
   phone's Home button, reopen Team RVM from the launcher, then take a new
   screenshot:

   ```bash
   adb exec-out screencap -p > 7-roster-again.png
   ```

   Open `7-roster-again.png`: the app's area is black again.
10. The switch is off by default: stop the app (press `q` where
    `flutter run` is running), then, in that same terminal, which is still
    in `flutter_app/rvm_team_app`, install the same build without the
    define:

    ```bash
    flutter run
    ```

    `flutter run` works only in `flutter_app/rvm_team_app`: from any other
    terminal, `cd` there first (from the repository's root,
    `cd flutter_app/rvm_team_app`, as in Build).

    Open the roster (step 3) and capture it:

    ```bash
    adb exec-out screencap -p > 8-roster-off.png
    ```

    Open `8-roster-off.png`: it shows the roster, because the roster blocks
    capture only in a build made with `SECURE_ROSTER=true`.

Steps 2 to 9 also work on an emulator, but the result to record is the
phone's: an emulator's screen capture can differ from a real phone's.

The black files (`2-roster.png`, `3-roster.mp4`, `4-sheet.png`,
`7-roster-again.png`) are the evidence; keep them with the result. The
others show staff or student data (`8-roster-off.png` shows the students'
names): look at them, record the result, then delete them. Never attach a
capture to a GitHub issue or a pull request: this repository is public.

### Result: the class roster

| Field | Value |
| --- | --- |
| Date | _to fill in_ |
| Phone, Android version | _to fill in_ (`adb shell getprop ro.product.model`, `adb shell getprop ro.build.version.release`) |
| App commit | _to fill in_ (`git rev-parse --short HEAD`) |
| Home captured before (step 2) | _yes / no_ |
| Screenshot of the roster black (step 4) | _yes / no_ |
| Recording of the roster black (step 5) | _yes / no_ |
| Recents card blank (step 6) | _yes / no_ |
| Black under the absent-reason sheet (step 7) | _yes / no / not run_ |
| Wall captured, recorded and previewed after leaving (step 8) | _yes / no_ |
| Black again after returning from Home (step 9) | _yes / no_ |
| Roster captured in a build without the define (step 10) | _yes / no_ |
| Who ran it | _to fill in_ (a role) |

### Result: every sensitive screen

One row per screen and phone. A module's screens are always sensitive, with
no switch: run steps 4 to 9 on the module's own list instead of the
roster, in a plain `flutter run` build, signed in as a test account whose
module switch is open (`GET /api/me/features`, see
[team-modules.md](team-modules.md)); with the switch closed, the route
falls back to Home. Fill a module's row once its screen exists.

| Screen | Route | Phone | Android version | Date | Result |
| --- | --- | --- | --- | --- | --- |
| Class roster (`SECURE_ROSTER=true`) | `/work/batch/:id/mark` | _to fill in_ | _to fill in_ | _to fill in_ | _pass / fail_ |
| CRM | `/crm` | | | | when the module screen exists |
| Fees follow-up | `/fees` | | | | when the module screen exists |
| Ops (pending counts, branch health) | `/ops` | | | | when the module screen exists |
| Student desk | `/desk` | | | | when the module screen exists |
| Placement checks | `/placement` | | | | when the module screen exists |
| Complaints | `/complaints` | | | | when the module screen exists |

A row passes when its screen's screenshot, recording and Recents preview
are black or blank, and Home or the Wall captures normally after leaving
it. A new module marked `sensitive: true` in `module_routes.dart` gets a row
here in the same pull request: `test/device_checks_doc_issue52_test.dart`
fails until it has one.

## Dark-mode pass (#122)

Run this on a low-cost Android phone (3–4 GB RAM, Android 11–13, 720p) and,
if one is at hand, on the OnePlus 12R that showed the issue14 regression.

1. Open Me → Appearance and pick **Dark**. Repeat with **System** while the
   phone's quick-settings dark toggle is on and off. System must follow the
   phone without a restart.
2. Walk Home, the punch screen (each punch state), Inbox, Requests,
   Approvals, Helpdesk, Wall, My Team, Me, the Work section, sign-in, the
   biometric lock, the version gate and offline. Record a screenshot of each
   main screen in Light and Dark.
3. A cold start and a warm start in both themes must show the Ironwood
   launch window, never a white flash.
4. Turn on the phone's own force-dark option (OnePlus, Xiaomi and others):
   the app must keep the colours it chose.
5. In Dark, check every text pair against 4.5:1 (body) and 3:1 (large text,
   icons, control borders). `core_ui/test/palette_contrast_test.dart` covers
   the palette pairs; this step covers real screens.
6. The 320 px and 360 px layouts at 1.3x text are covered by
   `test/theme_dark_widgets_test.dart`. Confirm the same on the phone.
7. Close the `theme` switch (or sign out) and confirm the next start is
   Light. Rollback is closing the switch; no deploy is needed.

Write the phone model, Android version and pass/fail for each step here.
This row cannot pass until someone runs it on a physical phone.
