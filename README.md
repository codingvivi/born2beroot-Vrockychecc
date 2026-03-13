# born2beroot tester

A verification script for the 42 born2beroot project on Rocky Linux.
Tried to not rely on checking the config files
but system status queries.
This means you can use .d override files
or have your own syntax in your config files.
As long as the system can read what you set up,
this tester should too!

## Usage

```bash
sudo ./tester.sh <username>
```

Must be run as root or with sudo. The username should be your 42 login.

## What it checks

| Section | Checks |
|---|---|
| System Info | No graphical environment, Rocky Linux OS, block devices |
| Services | SELinux enforcing, firewalld running, audit report |
| SSH / Network | Hostname (`login42`), `/etc/hosts`, port 4242 open and listening, SELinux port label, `PermitRootLogin no` |
| Users & Groups | User exists, belongs to `wheel` and `user42` groups, both groups exist |
| Password Aging | `chage` settings for the user, `login.defs` defaults |
| Password Quality | `pwquality` rules via `pwscore` (length, uppercase, lowercase, digit, repeat, usercheck, difok, enforce_for_root) |
| Sudo | secure_path, passwd_tries, badpass_message, requiretty, log directory, log is written to |
| Cron | `monitoring.sh` runs every 10 minutes |

### What it DOES NOT check

- correctness of your monitoring.sh script's contents
- Your disk layout
- Your encryption (used to but disabled it)

## Output

Each check prints `OK!`, `WARN...`, or `ERROR...` in colour.

Stderr is logged to `/var/log/shallowthought/errors_<timestamp>.log` for debugging.
