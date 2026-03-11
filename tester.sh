LOGIN=${1:?Usage: $0 <username> [luks-uuid]}
LUKS=${2:-}

check_sudo_logging() {
  sudo echo "test message 1" > /dev/null 2>&1
  while IFS= read -r file; do
    before=$(tail -1 "$file" 2>/dev/null)
    sudo echo "test message 2" > /dev/null 2>&1
    after=$(tail -1 "$file" 2>/dev/null)
    printf "%-32s  " "log in $file:"
    if [ "$before" != "$after" ] && echo "$after" | grep -q "test message"; then
        echo -e "\e[32mOK!\e[0m"
    else
        echo -e "\e[31mERROR!\e[0m"
    fi
  done < <(find /var/log -maxdepth 2 -type f | grep "sudo/")
}

check_string() {
  local mode=$1
  local result=$2
  if [ "$mode" = "is" ]; then
    [ -n "$result" ] && echo -e "\e[32mOK!\e[0m" || echo -e "\e[31mERROR!\e[0m"
  elif [ "$mode" = "absent" ]; then
    [ -z "$result" ] && echo -e "\e[32mOK!\e[0m" || echo -e "\e[31mERROR...\e[0m"
  fi
}

# -- SYSTEM INFO --
echo -e "\n=== SYSTEM INFO ==="
echo -n "No graphics:                    "; check_string absent $(rpm -qa | grep -iE "xorg|wayland")
echo -n "OS is Rocky Linux:              "; check_string is $(grep -F 'NAME="Rocky Linux"' /etc/os-release)

lsblk
#[ -n "$LUKS" ] && cryptsetup status $LUKS

# -- SYSTEM --
echo -e "\n=== SERVICES ==="
echo -n "SELinux enabled:                "; check_string is $(sestatus | grep -i "SELinux status" | grep -i "enabled")
echo -n "SELinux enforcing (config):     "; check_string is $(cat /etc/selinux/config | grep -E "SELINUX=enforcing")
echo -n "Firewall running:               "; check_string is $(firewall-cmd --state)
aureport -a

# -- SSH / NETWORK --
echo -e "\n=== SSH / NETWORK ==="
echo -n "Hostname correct:               "; check_string is $(hostname | grep ${LOGIN}42)
echo -n "Hosts entry:                    "; check_string is $(cat /etc/hosts | grep ${LOGIN}42)

echo -n "Port other than 4242 not open:  "; check_string absent $(firewall-cmd --list-ports | grep -v 4242)
echo -n "Port 4242 open:                 "; check_string is $(firewall-cmd --query-port=4242/tcp)
echo -n "Port 4242 listening:            "; check_string is $(ss -tlnp | grep 4242)
echo -n "SELinux label for 4242:         "; check_string is $(semanage port -l | grep ssh_port_t | grep 4242)
echo -n "PermitRootLogin no:             "; check_string is $(cat /etc/ssh/sshd_config | grep "PermitRootLogin" | grep "no")

# -- PASSWORD AGING --
echo -e "\n=== PASSWORD AGING ==="
echo -e "\n--- current users (chage) ---"
echo -n "chage min days=2:               "; check_string is $(chage -l $LOGIN | grep -i "minimum" | grep 2)
echo -n "chage max days=30:              "; check_string is $(chage -l $LOGIN | grep -i "maximum" | grep 30)
echo -n "chage warn days=7:              "; check_string is $(chage -l $LOGIN | grep -i "expires" | grep 7)

echo -e "\n--- future users (login.defs) ---"
echo -n "login.defs PASS_MAX_DAYS=30:    "; check_string is $(grep -E "^[[:space:]]*PASS_MAX_DAYS[[:space:]]+30" /etc/login.defs)
echo -n "login.defs PASS_MIN_DAYS=2:     "; check_string is $(grep -E "^[[:space:]]*PASS_MIN_DAYS[[:space:]]+2" /etc/login.defs)
echo -n "login.defs PASS_WARN_AGE=7:     "; check_string is $(grep -E "^[[:space:]]*PASS_WARN_AGE[[:space:]]+7" /etc/login.defs)

# -- PASSWORD QUALITY --
echo -e "\n=== PASSWORD QUALITY ==="
echo -n "pwquality minlen=10:            "; check_string is $(echo "Aa1\!bcd" | pwscore 2>&1 | grep -i "shorter")
echo -n "pwquality ucredit:              "; check_string is $(echo "aa1\!bcdefgh" | pwscore 2>&1 | grep -i "upper")
echo -n "pwquality lcredit:              "; check_string is $(echo "AA1\!BCDEFGH" | pwscore 2>&1 | grep -i "lower")
echo -n "pwquality dcredit:              "; check_string is $(echo "Aa\!bcdefghij" | pwscore 2>&1 | grep -i "digit")
echo -n "pwquality maxrepeat=3:          "; check_string is $(echo "Aa1\!bccccde" | pwscore 2>&1 | grep -i "same")
echo -n "pwquality usercheck:            "; check_string is $(echo "Aa1\!${LOGIN}xyz" | pwscore $LOGIN 2>&1 | grep -i "user")
echo -n "pwquality difok=7:              "; check_string is $(grep -E "^[[:space:]]*difok[[:space:]]*=[[:space:]]*7" /etc/security/pwquality.conf)
echo -n "pwquality enforce_for_root:     "; check_string is $(grep -E "^[[:space:]]*enforce_for_root" /etc/security/pwquality.conf)


# -- SUDO --
echo -e "\n=== SUDO ==="
echo -n "sudo secure_path:               "; check_string is $(sudo -V | grep -i "override" | grep "\$PATH")
echo -n "sudo passwd_tries=3:            "; check_string is $(sudo -V | grep -i "Number of tries" | grep 3)
echo -n "sudo badpass_message:           "; check_string is $(sudo -V | grep -v "Sorry, try again." | grep -i "Incorrect password message")
echo -n "sudo requiretty:                "; check_string is $(sudo -V | grep -i "Only" | grep -i "allow" | grep -i "tty")
echo -n "sudo log dir setting:           "; check_string is $(sudo -V | grep -i "log file" | grep "/var/log/sudo/")
echo -n "sudo log exists:                "; check_string is $(find /var/log -maxdepth 2 -type f | grep "sudo/")
echo -e "\n--- checking sudo log is written to ---"
check_sudo_logging                                                                                                                                                         

# -- CRON --
echo -e "\n=== CRON ==="
echo -n "cron monitoring.sh */10:        "; check_string is $(crontab -l | grep "monitoring.sh" | grep -F "*/10 * * * *")
