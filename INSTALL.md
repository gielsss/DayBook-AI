# Installing DayBook AI

DayBook AI looks at your classes, calendar and email, finds what's due, and plans time in your week to get it done. This guide walks you through setup one click at a time. You don't need to know anything about computers or AI.

> [!NOTE]
> **What you need**
>
> - **A Mac with an Apple chip.** To check: click the Apple logo in the top-left corner of the screen → **About This Mac**. Next to **Chip** it should say **Apple M1**, M2, M3, M4 or newer. (If it says "Intel", this app won't run on that Mac.)
> - **macOS 14 Sonoma or newer** (shown in the same window).
> - **About 10 GB of free space** and an internet connection.
> - **About 30 minutes.** Most of it is waiting for a download.

There are three parts: **(1)** put the app on your Mac, **(2)** install the free AI helper, **(3)** connect your classes and calendar. If you get stuck, see **"If something goes wrong"** at the end.

## 1. Put DayBook AI on your Mac

1. **Get the installer.** If someone sent you **DayBook-AI.zip**, use that. Otherwise download **DayBook-AI.zip** from the [latest release](https://github.com/gielsss/DayBook-AI/releases/latest).
2. Double-click **DayBook-AI.zip**. A file called **DayBook AI Installer** appears next to it. Double-click that too.
3. A window opens with the **DayBook AI** icon, a blue **Applications** folder, and this guide.
4. **Drag the DayBook AI icon onto the Applications folder** and let go. That copies it onto your Mac.
5. Open your **Applications** folder (in Finder's sidebar on the left, or press <kbd>⌘ Command</kbd> <kbd>⇧ Shift</kbd> <kbd>A</kbd>) and **double-click DayBook AI**.

> [!WARNING]
> **macOS will show a warning the first time. This is expected.**
>
> Apple warns about any app that isn't sold through the App Store or registered with Apple. DayBook AI is a free app made by a student, so you have to tell your Mac once that it's OK to open:
>
> 1. When the message says *"DayBook AI" Not Opened* or *Apple could not verify…*, click **Done** (not "Move to Trash").
> 2. Click the Apple logo (top-left) → **System Settings**.
> 3. In the list on the left, click **Privacy & Security**.
> 4. Scroll all the way down. Under **Security** you'll see *"DayBook AI" was blocked…*. Click **Open Anyway**.
> 5. Type your Mac password (the one you use to log in) and click **OK**, then click **Open Anyway** once more.
>
> You only do this once. After that, DayBook AI opens like any other app.

When DayBook AI opens, it's filled with **example tasks** so you can look around. You'll remove them in Part 3.

Tip: to keep DayBook AI in your Dock, right-click its icon in the Dock → **Options** → **Keep in Dock**.

<!-- pagebreak -->
## 2. Install the AI helper (free)

DayBook AI uses a free program called **Ollama** to read your emails, announcements and screenshots. The AI runs **entirely on your own Mac**: nothing is sent to an AI company, and there's no account or payment.

You can skip this part for now. The planner, calendar and Canvas due dates all work without it; only the "read my emails and messages for tasks" features need it.

### 2a. Download and install Ollama

1. Open Safari (or Chrome) and go to **[ollama.com/download](https://ollama.com/download)**. (Or, in DayBook AI: **Settings → Local AI (Ollama) → Get Ollama…**)
2. Click **Download for macOS**.
3. When it finishes, open your **Downloads** folder and double-click the Ollama file. Drag **Ollama** into **Applications** if it asks you to.
4. Open **Ollama** from Applications. If it asks to install its command-line tool, click **Install** and enter your Mac password.
5. You'll now see a small **llama icon** at the top of your screen, near the clock. That means it's running. (If a chat window opens, you can close it; the llama stays.)

### 2b. Download the AI "brain" (one time, about 5 GB)

1. In DayBook AI, click **Settings** in the sidebar on the left.
2. Scroll down to **Local AI (Ollama)**. It says the model "isn't on this Mac yet".
3. Click **Download Model**. A progress bar appears. It can take 10–30 minutes depending on your internet; you can keep using the app meanwhile.
4. When it says **The AI features are ready**, you're done.

If it says "Ollama isn't running or isn't installed yet", do step 2a first (or open Ollama from Applications), then click **Check Again**. If the download stops (for example your Mac went to sleep), just click **Download Model** again; it continues where it left off.

> [!TIP]
> **Good to know**
>
> - Ollama has to be running for the AI features. It starts by itself when you log in; if you ever see "Ollama isn't running", just open Ollama from Applications.
> - The AI works best on Macs with **16 GB of memory** or more (check in Apple logo → About This Mac). On 8 GB Macs it works, but slowly.

### 2c. Check that it works

Still in **Settings → Local AI (Ollama)**, click **Test Connection**. The first test can take a minute. A green check mark means everything's ready.

<!-- pagebreak -->
## 3. Make it yours

### Clear out the example tasks

**Settings** → scroll down → **Remove All Demonstration Tasks**.

### Set your hours

In **Settings → Weekday Working Hours**, choose when you're free to do schoolwork. DayBook AI only plans work inside those hours.

### Connect your Apple Calendar

**Settings → Apple Calendar → Connect Apple Calendar**, then click **Allow** when your Mac asks. DayBook AI plans around your classes and events. It never changes your calendar unless you press **Publish**, and even then it only writes to its own separate "DayBook AI" calendar.

### Connect Canvas (your school's class website)

1. Open Canvas in **Safari, Chrome or Arc** and log in like you normally do. Leave that tab open.
2. In DayBook AI: **Settings → Canvas**. Type your school's Canvas address (the start of the web address you see in the browser, for example `canvas.yourschool.edu`).
3. Click **Find my Canvas tab**.
4. Your Mac asks if DayBook AI may control your browser. Click **OK / Allow**. This is how it reads your due dates through the tab you're already logged into. It never submits or changes anything, and it doesn't save your password.

### Connect Gradescope (if your classes use it)

Log in to Gradescope in your browser, then **Settings → Gradescope → Find my Gradescope tab**.

### Gmail (optional, a bit technical)

Google makes every user do a one-time setup in Google's developer website before an app like this can read email. It takes about 15 minutes; follow the [Gmail setup steps](https://github.com/gielsss/DayBook-AI#gmail) on the DayBook AI GitHub page. You can skip it: everything else works without Gmail.

## Using it every day

- **Today** shows what to work on right now. Press **Sync Everything** to pull in anything new from your calendar, Canvas and email. It also does this by itself at 8 AM, 1 PM and 6 PM while your Mac is on.
- Check off a work session when you finish it. If you didn't get to something, mark it **Not Done Yet** and it'll be given time again, first in line.
- **Week** shows your next two weeks. Drag sessions to move them.
- **Tasks** lists everything you have to do. You can add your own there too, or use **Quick Capture** to paste a message or screenshot and let the AI turn it into a task.
- Always double-check important deadlines on Canvas. The AI is helpful, but it can misread a date.

<!-- pagebreak -->
## If something goes wrong

| What you see | What to do |
| --- | --- |
| "DayBook AI can't be opened" / "Apple could not verify…" | Follow the warning box in Part 1 (System Settings → Privacy & Security → Open Anyway). |
| "Ollama isn't running" | Open **Ollama** from Applications. Look for the llama icon near the clock. |
| "Model … isn't downloaded" | Settings → Local AI (Ollama) → **Download Model** (step 2b). |
| The download stopped or failed | Click **Download Model** again. It continues where it left off. If it says there isn't enough space, free up about 10 GB first. |
| A box asks to use the "keychain" or saved passwords | Type your Mac password and click **Always Allow**. That's where DayBook AI keeps your logins safely. |
| A box asks if DayBook AI can control Safari / Chrome | Click **OK**. That's how it reads Canvas and Gradescope. If you clicked "Don't Allow" by accident: System Settings → Privacy & Security → Automation → DayBook AI → turn your browser on. |
| Canvas says "sign in" | Log in to Canvas again in your browser, keep the tab open, and press Sync Everything. |
| The AI is really slow | That's normal on the first run and on Macs with 8 GB of memory. Leave it running; it gets quicker after the first few. |

> [!NOTE]
> **Your privacy**
>
> Everything stays on your Mac. Your planner is saved on your computer (with automatic daily backups), your logins are kept in your Mac's secure Keychain, and the AI runs locally through Ollama. DayBook AI has no account, no ads and no tracking, and only reads your classes and email; it never posts, submits or sends anything.
>
> DayBook AI is an independent student project and isn't affiliated with Canvas, Gradescope, Google or Apple.
