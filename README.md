![taurine](docs/assets/banner.png)

[![checks](https://github.com/christianfurr/taurine/actions/workflows/checks.yml/badge.svg)](https://github.com/christianfurr/taurine/actions/workflows/checks.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-191919?style=flat-square&logo=apple&logoColor=white)
![swift](https://img.shields.io/badge/swift-native-F05138?style=flat-square&logo=swift&logoColor=white)
![mcp](https://img.shields.io/badge/mcp-included-D3EE42?style=flat-square&labelColor=191919)

wanted to close my macbook and still have codex running on it. so i made this little menu bar app that keeps it awake.

named after the stuff in energy drinks.

click the lightning bolt, turn it on, approve the macOS prompt. then you can close the lid and keep working remotely. the screen can turn off and the mac can stay locked.

the menu has the timer, switch, about, check for updates, and quit. the extra info lives in About Taurine.

Check for Updates checks the latest github release and opens the right download for your mac. you replace the app yourself when youre ready. it wont restart taurine halfway through your tasks.

theres an mcp server and a skill too, so you can ask codex to turn it off when youre done.

## get it

[download for apple silicon](https://github.com/christianfurr/taurine/releases/latest/download/Taurine-macOS-arm64.zip)

unzip it, move `Taurine.app` to Applications, open it. thats it.

macOS 13+. the download is arm64, locally signed, and not notarized. if macOS blocks it, build from source. havent tested intel.

## or build it

needs Apple's Command Line Tools.

```sh
git clone https://github.com/christianfurr/taurine.git
cd taurine
./scripts/build.sh
```

the script tells you where the app is and drops a zip in `build/Taurine.zip`.

## mcp stuff

you need [Codex CLI](https://developers.openai.com/codex/cli/) and Python 3.11+ for this part. the app itself doesnt need python.

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install 'mcp>=2.1.1,<3'
./scripts/build-automation.sh
python scripts/install-automation.py
```

that adds the `taurine` mcp server and `$taurine-control` skill. start a new codex task to pick up the tools. keep the venv around, the registration uses its python.

then just ask it to check taurine, keep your mac awake, or turn taurine off and allow sleep.

- `taurine_status` checks the app, sleep setting, lid and battery
- `taurine_enable` turns it on, or leaves it alone if its already on
- `taurine_disable` needs `confirm_allow_sleep=true`. it waits 3 seconds before asking the app to quit so you have time to get the reply

heres a preview that **wont actually turn it off**:

```sh
python "$HOME/.local/share/taurine/taurine-control/control.py" disable \
  --confirm-allow-sleep --dry-run
```

turning it off lets the mac sleep. that can disconnect you and suspend whatever codex is doing, so dont do it halfway through something you need running. this doesnt shut down your mac or wake it back up later. starting a new awake session can still need admin approval on the mac.

if youre using the old Caffeine version, the controls recognize that too. installing this doesnt restart an active old session.

## few things

- it stops at 10% battery when unplugged
- it restores your previous sleep setting when you turn it off, quit, or the app crashes
- the helper also restores it if the app stops sending heartbeats for 15 seconds
- leave the mac somewhere it can breathe. dont put it in a bag while its awake
- killing the privileged helper itself or losing power can leave sleep disabled. [recovery + other details](docs/OPERATIONS.md)

## tests

```sh
./scripts/test.sh
python3 tests/automation_test.py
```

checks for the watchdog, update versions/download links, and automation previews. github runs them too.

also checked the lid-closed state on a real mac while remote commands kept working. checked mcp status and previews without restarting the running app. havent tested an actual remote disable or a fresh privileged enable end to end yet. [more detail if you want it](docs/OPERATIONS.md#verification)
