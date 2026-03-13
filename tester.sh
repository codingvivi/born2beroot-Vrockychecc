LOGIN=
SUDO_LOG=
LUKS=
PWQUALITY_CONF=/etc/security/pwquality.conf
OVERRIDE=

while [[ "$1" == -* ]]; do
  case "$1" in
    --login)      LOGIN="$2";          shift 2 ;;
    --sudo-log)   SUDO_LOG="$2";       shift 2 ;;
    --luks)       LUKS="$2";           shift 2 ;;
    --pwquality)  PWQUALITY_CONF="$2"; shift 2 ;;
    -o|--override) OVERRIDE="$2";      shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

override() { [[ "$OVERRIDE" == *"$1"* ]] && echo "-o"; }

[ -z "$LOGIN" ] && { echo "Usage: $0 --login <username> [--sudo-log <path>] [--luks <uuid>] [--pwquality <path>]"; exit 1; }

mkdir -p /var/log/shallowthought
exec 2>/var/log/shallowthought/errors_$(date +%Y-%m-%d-%H-%M-%S).log

OK="\e[32mOK!\e[0m"
WARN="\e[38;5;208mWARN...\e[0m"
ERROR="\e[31mERROR...\e[0m"

print_label() { printf "%-34s  " "$1"; }

check_sudo_logging() {
  local file=$1
  before=$(tail -1 "$file" 2>/dev/null)
  sudo echo "test message" > /dev/null 2>&1
  after=$(tail -1 "$file" 2>/dev/null)
  print_label "log in $file:"
  if [ "$before" != "$after" ] && echo "$after" | grep -q "test message"; then
    echo -e "$OK"
  else
    echo -e "$ERROR"
  fi
}

check_string() {
  local fail_msg="$ERROR"
  local override=0
  while [[ "$1" == -* ]]; do
    case "$1" in
      -s|--severity) case "$2" in
          warn) fail_msg="$WARN" ;;
          error) fail_msg="$ERROR" ;;
        esac; shift 2 ;;
      -o) override=1; shift ;;
    esac
  done
  [ "$override" = 1 ] && { echo -e "$OK"; return; }
  local mode=$1
  local result=$2
  if [ "$mode" = "is" ]; then
    [ -n "$result" ] && echo -e "$OK" || echo -e "$fail_msg"
  elif [ "$mode" = "absent" ]; then
    [ -z "$result" ] && echo -e "$OK" || echo -e "$fail_msg"
  fi
}

# -- SYSTEM INFO --
echo -e "\n=== SYSTEM INFO ==="
print_label "No graphics:";                check_string absent $(rpm -qa | grep -iE "xorg|wayland")
print_label "OS is Rocky Linux:";          check_string is $(grep -F 'NAME="Rocky Linux"' /etc/os-release)

lsblk
#[ -n "$LUKS" ] && cryptsetup status $LUKS

# -- SYSTEM --
echo -e "\n=== SERVICES ==="
print_label "SELinux enforcing (config):"; check_string -s warn is $(cat /etc/selinux/config | grep -E "SELINUX=enforcing")
print_label "SELinux enabled: (running)";  check_string is $(sestatus | grep -i "SELinux status" | grep -i "enabled")
print_label "Firewall running:";           check_string is $(firewall-cmd --state)
aureport -a

# -- SSH / NETWORK --
echo -e "\n=== SSH / NETWORK ==="
print_label "Hostname correct:";           check_string is $(hostname | grep ${LOGIN}42)
print_label "Hosts entry:";               check_string is $(cat /etc/hosts | grep ${LOGIN}42)

print_label "Port other than 4242 not open:"; check_string absent $(firewall-cmd --list-ports | grep -v 4242)
print_label "Port 4242 open:";            check_string is $(firewall-cmd --query-port=4242/tcp)
print_label "Port 4242 listening:";       check_string is $(ss -tlnp | grep 4242)
print_label "SELinux label for 4242:";    check_string is $(semanage port -l | grep ssh_port_t | grep 4242)
print_label "PermitRootLogin no:";        check_string is $(sshd -T | grep -i "^permitrootlogin no")

# -- USERS & GROUPS --
echo -e "\n=== USERS & GROUPS ==="
print_label "User $LOGIN exists:";         check_string is $(id)
print_label "User $LOGIN in wheel group:";  check_string is $(groups $LOGIN | grep wheel)
print_label "User $LOGIN in user42 group:"; check_string is $(groups $LOGIN | grep user42)
print_label "Group wheel exists:";         check_string is $(getent group wheel)
print_label "Group user42 exists:";       check_string is $(getent group user42)

# -- PASSWORD AGING --
echo -e "\n=== PASSWORD AGING ==="
echo -e "\n--- current users (chage) ---"
print_label "chage min days=2:";          check_string is $(chage -l $LOGIN | grep -i "minimum" | grep 2)
print_label "chage max days=30:";         check_string is $(chage -l $LOGIN | grep -i "maximum" | grep 30)
print_label "chage warn days=7:";         check_string is $(chage -l $LOGIN | grep -i "expires" | grep 7)

echo -e "\n--- future users (login.defs) ---"
print_label "login.defs PASS_MAX_DAYS=30:"; check_string is $(grep -E "^[[:space:]]*PASS_MAX_DAYS[[:space:]]+30" /etc/login.defs)
print_label "login.defs PASS_MIN_DAYS=2:";  check_string is $(grep -E "^[[:space:]]*PASS_MIN_DAYS[[:space:]]+2" /etc/login.defs)
print_label "login.defs PASS_WARN_AGE=7:";  check_string is $(grep -E "^[[:space:]]*PASS_WARN_AGE[[:space:]]+7" /etc/login.defs)

# -- PASSWORD QUALITY --
echo -e "\n=== PASSWORD QUALITY ==="
print_label "pwquality minlen=10:";       check_string is $(echo "Aa1\!bcd" | pwscore 2>&1 | grep -i "shorter")
print_label "pwquality ucredit:";         check_string is $(echo "aa1\!bcdefgh" | pwscore 2>&1 | grep -i "upper")
print_label "pwquality lcredit:";         check_string is $(echo "AA1\!BCDEFGH" | pwscore 2>&1 | grep -i "lower")
print_label "pwquality dcredit:";         check_string is $(echo "Aa\!bcdefghij" | pwscore 2>&1 | grep -i "digit")
print_label "pwquality maxrepeat=3:";     check_string is $(echo "Aa1\!bccccde" | pwscore 2>&1 | grep -i "same")
print_label "pwquality usercheck:";       check_string is $(echo "Aa1\!${LOGIN}xyz" | pwscore $LOGIN 2>&1 | grep -i "user")
# These cant be checked by pwscore
print_label "pwquality difok=7:";         check_string $(override pwquality) -s warn is $(cat $PWQUALITY_CONF | grep -E "^[[:space:]]*difok[[:space:]]*=[[:space:]]*7")
print_label "pwquality enforce_for_root:"; check_string $(override pwquality) -s warn is $(cat $PWQUALITY_CONF | grep -E "^[[:space:]]*enforce_for_root")


# -- SUDO --
echo -e "\n=== SUDO ==="
print_label "sudo secure_path:";          check_string is $(sudo -V | grep -i "override" | grep "\$PATH")
print_label "sudo passwd_tries=3:";       check_string is $(sudo -V | grep -i "Number of tries" | grep 3)
print_label "sudo badpass_message:";      check_string is $(sudo -V | grep -v "Sorry, try again." | grep -i "Incorrect password message")
print_label "sudo requiretty:";           check_string is $(sudo -V | grep -i "Only" | grep -i "allow" | grep -i "tty")
print_label "sudo log dir setting:";      check_string is $(sudo -V | grep -i "log file" | grep "/var/log/sudo/")
print_label "sudo log exists:";           check_string is $(find /var/log -maxdepth 2 -type f | grep "sudo/")
print_label "sudo log path valid:";       check_string is $([[ "$SUDO_LOG" == /var/log/sudo/* ]] && echo yes)
echo -e "\n--- checking sudo log is written to ---"
[ -n "$SUDO_LOG" ] && check_sudo_logging "$SUDO_LOG" || echo "(skipped — pass sudo log path as arg 2 to enable)"

# -- CRON --
echo -e "\n=== CRON ==="
print_label "cron monitoring.sh */10:";   check_string -s warn is $(crontab -l | grep "monitoring.sh" | grep -F "*/10 * * * *")
