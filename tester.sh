LOGIN=
SUDO_LOG=
LUKS=
PWQUALITY_CONF=/etc/security/pwquality.conf
CRON_FILE=
OVERRIDE=

while [[ "$1" == -* ]]; do
  case "$1" in
    -l|--login)     LOGIN="$2";          shift 2 ;;
    -s|--sudo-log)  SUDO_LOG="$2";       shift 2 ;;
    -k|--luks)      LUKS="$2";           shift 2 ;;
    -p|--pwquality) PWQUALITY_CONF="$2"; shift 2 ;;
    -c|--cronfile)  CRON_FILE="$2";      shift 2 ;;
    -o|--override)  OVERRIDE="$2";       shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

override() { [[ "$OVERRIDE" == *"$1"* ]] && echo "-o"; }

[ -z "$LOGIN" ] && { echo "Usage: $0 -l|--login <username> [-s|--sudo-log <path>] [-k|--luks <uuid>] [-p|--pwquality <path>] [-c|--cronfile <path>] [-o|--override <string>]"; exit 1; }

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

print_result() {
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
  "$@" && echo -e "$OK" || echo -e "$fail_msg"
}

# -- SYSTEM INFO --
echo -e "\n=== SYSTEM INFO ==="
print_label "No graphics:";                  print_result [ -z "$(rpm -qa | grep -iE 'xorg|wayland')" ]
print_label "OS is Rocky Linux:";            print_result [ -n "$(grep -F 'NAME="Rocky Linux"' /etc/os-release)" ]

lsblk
#[ -n "$LUKS" ] && cryptsetup status $LUKS

# -- SERVICES --
echo -e "\n=== SERVICES ==="
print_label "SELinux enforcing (config):";   print_result -s warn [ -n "$(cat /etc/selinux/config | grep -E 'SELINUX=enforcing')" ]
print_label "SELinux enabled (running):";    print_result [ -n "$(sestatus | grep -i 'SELinux status' | grep -i 'enabled')" ]
print_label "Firewall running:";             print_result [ -n "$(firewall-cmd --state)" ]
aureport -a

# -- SSH / NETWORK --
echo -e "\n=== SSH / NETWORK ==="
print_label "Hostname correct:";             print_result [ -n "$(hostname | grep ${LOGIN}42)" ]
print_label "Hosts entry:";                  print_result [ -n "$(cat /etc/hosts | grep ${LOGIN}42)" ]
print_label "No port other than 4242 open:"; print_result [ -z "$(firewall-cmd --list-ports | grep -v 4242)" ]
print_label "Port 4242 open:";               print_result [ -n "$(firewall-cmd --query-port=4242/tcp)" ]
print_label "Port 4242 listening:";          print_result [ -n "$(ss -tlnp | grep 4242)" ]
print_label "SELinux label for 4242:";       print_result [ -n "$(semanage port -l | grep ssh_port_t | grep 4242)" ]
print_label "PermitRootLogin no:";           print_result [ -n "$(sshd -T | grep -i '^permitrootlogin no')" ]

# -- USERS & GROUPS --
echo -e "\n=== USERS & GROUPS ==="
print_label "User $LOGIN exists:";           print_result [ -n "$(id $LOGIN)" ]  
print_label "User $LOGIN in wheel group:";   print_result [ -n "$(groups $LOGIN | grep wheel)" ]
print_label "User $LOGIN in user42 group:";  print_result [ -n "$(groups $LOGIN | grep user42)" ]
print_label "Group wheel exists:";           print_result [ -n "$(getent group wheel)" ]
print_label "Group user42 exists:";          print_result [ -n "$(getent group user42)" ]

# -- PASSWORD AGING --
echo -e "\n=== PASSWORD AGING ==="
echo -e "\n--- current users (chage) ---"
print_label "chage min days=2:";             print_result [ -n "$(chage -l $LOGIN | grep -i 'minimum' | grep 2)" ]
print_label "chage max days=30:";            print_result [ -n "$(chage -l $LOGIN | grep -i 'maximum' | grep 30)" ]
print_label "chage warn days=7:";            print_result [ -n "$(chage -l $LOGIN | grep -i 'expires' | grep 7)" ]

echo -e "\n--- future users (login.defs) ---"
print_label "login.defs PASS_MAX_DAYS=30:";  print_result [ -n "$(grep -E '^[[:space:]]*PASS_MAX_DAYS[[:space:]]+30' /etc/login.defs)" ]
print_label "login.defs PASS_MIN_DAYS=2:";   print_result [ -n "$(grep -E '^[[:space:]]*PASS_MIN_DAYS[[:space:]]+2' /etc/login.defs)" ]
print_label "login.defs PASS_WARN_AGE=7:";   print_result [ -n "$(grep -E '^[[:space:]]*PASS_WARN_AGE[[:space:]]+7' /etc/login.defs)" ]

# -- PASSWORD QUALITY --
echo -e "\n=== PASSWORD QUALITY ==="
print_label "pwquality minlen=10:";          print_result [ -n "$(echo 'Aa1\!bcd' | pwscore 2>&1 | grep -i 'shorter')" ]
print_label "pwquality ucredit:";            print_result [ -n "$(echo 'aa1\!bcdefgh' | pwscore 2>&1 | grep -i 'upper')" ]
print_label "pwquality lcredit:";            print_result [ -n "$(echo 'AA1\!BCDEFGH' | pwscore 2>&1 | grep -i 'lower')" ]
print_label "pwquality dcredit:";            print_result [ -n "$(echo 'Aa\!bcdefghij' | pwscore 2>&1 | grep -i 'digit')" ]
print_label "pwquality maxrepeat=3:";        print_result [ -n "$(echo 'Aa1\!bccccde' | pwscore 2>&1 | grep -i 'same')" ]
print_label "pwquality usercheck:";          print_result [ -n "$(echo "Aa1\!${LOGIN}xyz" | pwscore $LOGIN 2>&1 | grep -i 'user')" ]
# These cant be checked by pwscore
print_label "pwquality difok=7:";            print_result $(override pwquality) -s warn [ -n "$(cat $PWQUALITY_CONF | grep -E '^[[:space:]]*difok[[:space:]]*=[[:space:]]*7')" ]
print_label "pwquality enforce_for_root:";   print_result $(override pwquality) -s warn [ -n "$(cat $PWQUALITY_CONF | grep -E '^[[:space:]]*enforce_for_root')" ]

# -- SUDO --
echo -e "\n=== SUDO ==="
print_label "sudo secure_path:";             print_result [ -n "$(sudo -V | grep -i 'override' | grep '\$PATH')" ]
print_label "sudo passwd_tries=3:";          print_result [ -n "$(sudo -V | grep -i 'Number of tries' | grep 3)" ]
print_label "sudo badpass_message:";         print_result [ -n "$(sudo -V | grep -v 'Sorry, try again.' | grep -i 'Incorrect password message')" ]
print_label "sudo requiretty:";              print_result [ -n "$(sudo -V | grep -i 'Only' | grep -i 'allow' | grep -i 'tty')" ]
print_label "sudo log dir setting:";         print_result [ -n "$(sudo -V | grep -i 'log file' | grep '/var/log/sudo/')" ]
print_label "sudo log exists:";              print_result [ -n "$(find /var/log -maxdepth 2 -type f | grep 'sudo/')" ]
print_label "sudo log path valid:";          print_result [ -n "$(echo "$SUDO_LOG" | grep '^/var/log/sudo/')" ]
echo -e "\n--- checking sudo log is written to ---"
[ -n "$SUDO_LOG" ] && check_sudo_logging "$SUDO_LOG" || echo "(skipped — pass --sudo-log to enable)"

# -- CRON --
CRON_SCRIPT=$(awk '!/^#/ && NF {print $NF}' "$CRON_FILE" 2>/dev/null)

echo -e "\n=== CRON ==="
print_label "cron monitoring.sh */10:";      print_result [ -n "$(cat $CRON_FILE | grep 'monitoring.sh' | grep -E '^\*/10[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*')" ]
print_label "cron script exists:";           print_result [ -f "$CRON_SCRIPT" ]
print_label "cron script is monitoring.sh:"; print_result [ "$(basename $CRON_SCRIPT)" = "monitoring.sh" ]
print_label "cron syntax valid:";            print_result [ -n "$(crontab -T $CRON_FILE 2>&1 | grep -i 'No syntax')" ]
