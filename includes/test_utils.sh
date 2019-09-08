#!/bin/env bash

YUM_CONF='/etc/yum.conf'
GRUB_CFG='/boot/grub2/grub.cfg'
GRUB_DIR='/etc/grub.d'
SELINUX_CFG='/etc/selinux/config'
NTP_CONF='/etc/ntp.conf'
SYSCON_NTPD='/etc/sysconfig/ntpd'
NTP_SRV='/usr/lib/systemd/system/ntpd.service'
CHRONY_CONF='/etc/chrony.conf'
CHRONY_SYSCON='/etc/sysconfig/chronyd'
LIMITS_CNF='/etc/security/limits.conf'
SYSCTL_CNF='/etc/sysctl.conf'
CENTOS_REL='/etc/centos-release'
HOSTS_ALLOW='/etc/hosts.allow'
HOSTS_DENY='/etc/hosts.deny'
CIS_CNF='/etc/modprobe.d/CIS.conf'
RSYSLOG_CNF='/etc/rsyslog.conf'
SYSLOGNG_CONF='/etc/syslog-ng/syslog-ng.conf'
AUDITD_CNF='/etc/audit/auditd.conf'
AUDIT_RULES='/etc/audit/audit.rules'
AUDIT_RULES_ORI='/etc/audit/rules.d/audit.rules'
LOGR_SYSLOG='/etc/logrotate.d/syslog'
ANACRONTAB='/etc/anacrontab'
CRONTAB='/etc/crontab'
CRON_HOURLY='/etc/cron.hourly'
CRON_DAILY='/etc/cron.daily'
CRON_WEEKLY='/etc/cron.weekly'
CRON_MONTHLY='/etc/cron.monthly'
CRON_DIR='/etc/cron.d'
AT_ALLOW='/etc/at.allow'
AT_DENY='/etc/at.deny'
CRON_ALLOW='/etc/cron.allow'
CRON_DENY='/etc/cron.deny'
SSHD_CFG='/etc/ssh/sshd_config'
SYSTEM_AUTH='/etc/pam.d/system-auth'
PWQUAL_CNF='/etc/security/pwquality.conf'
PASS_AUTH='/etc/pam.d/password-auth'
PAM_SU='/etc/pam.d/su'
GROUP='/etc/group'
LOGIN_DEFS='/etc/login.defs'
PASSWD='/etc/passwd'
SHADOW='/etc/shadow'
GSHADOW='/etc/gshadow'
BASHRC='/etc/bashrc'
PROF_D='/etc/profile.d'
MOTD='/etc/motd'
ISSUE='/etc/issue'
ISSUE_NET='/etc/issue.net'
GDM_PROFILE='/etc/dconf/profile/gdm'
GDM_BANNER_MSG='/etc/dconf/db/gdm.d/01-banner-message'
RESCUE_SRV='/usr/lib/systemd/system/rescue.service'

if [[ "$BENCH_SKIP_SLOW" == "1" ]]; then
  DO_SKIP_SLOW=1
else
  DO_SKIP_SLOW=0
fi

test_module_disabled() {
  local module="${1}"
  modprobe -n -v ${module} 2>&1 | grep -q "install \+/bin/true" || echo "install ${module} /bin/true" >> ${CIS_CNF} || return 
  lsmod | grep -qv "${module}" || return
}

test_separate_partition() {
  local target="${1}"
  if [ $target = '/tmp' ]; then
    findmnt -n ${target} | grep -q "${target}" || systemctl unmask tmp.mount && systemctl enable tmp.mount 2>/dev/null && sed -i 's/^Options=.*/Options=mode=1777,strictatime,noexec,nodev,nosuid/' /usr/lib/systemd/system/tmp.mount && systemctl daemon-reload && systemctl start tmp.mount
  fi
  findmnt -n ${target} | grep -q "${target}" || return
}

test_mount_option() {
  local target="${1}"
  local mnt_option="${2}"
  if [ "${target}" = "/dev/shm" ]; then
    mount -o remount,${mnt_option} ${target}
  else
    findmnt -nlo options ${target} | grep -q "${mnt_option}" || return
  fi
}

test_system_file_perms() {
  local dirs="$(rpm -Va --nomtime --nosize --nomd5 --nolinkto)"
  [[ -z "${dirs}" ]] || return
}

test_sticky_wrld_w_dirs() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \))"
  [[ -z "${dirs}" ]] || return
}

test_wrld_writable_files() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type f -perm -0002)"
  [[ -z "${dirs}" ]] || return
}

test_unowned_files() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -nouser)"
  [[ -z "${dirs}" ]] || return
}

test_ungrouped_files() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -nogroup)"
  [[ -z "${dirs}" ]] || return
}

test_suid_executables() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type f -perm -4000)"
  [[ -z "${dirs}" ]] || return
}

test_sgid_executables() {
  local dirs="$(df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type f -perm -2000)"
  [[ -z "${dirs}" ]] || return
}

test_service_disable() {
  local service="$1" 
  systemctl is-enabled "${service}" 2>&1 | egrep -q 'disabled|Failed|indirect' || return
}

test_service_enabled() {
  local service="$1" 
  systemctl is-enabled "${service}" 2>&1 | grep -q 'enabled' || return
}

test_yum_gpgcheck() {
  if [[ -f ${YUM_CONF} ]]; then
    grep -q ^gpgcheck ${YUM_CONF} 2>/dev/null || return
  fi
  ! grep ^gpgcheck /etc/yum.repos.d/* | grep 0$ || return
}

test_rpm_installed() {
  local rpm="${1}"
  if [ ${rpm} = 'aide' ]; then
    rpm -q ${rpm} | egrep -q "^${rpm}" || ( yum -q -y install $rpm && /usr/sbin/aide --init -B 'database_out=file:/var/lib/aide/aide.db.gz' >/dev/null 2>&1)
  fi
  rpm -q ${rpm} | grep -qe "^${rpm}" || return
}

test_rpm_not_installed() {
  local rpm="${1}"
  rpm -q ${rpm} | grep -q "not installed" || return
}

test_aide_cron() {
  crontab -u root -l 2>/dev/null | cut -d\# -f1 | grep -q "aide \+--check" || echo '0 5 * * * /usr/sbin/aide --check' >> /var/spool/cron/root || return
}

test_file_perms() {
  local file="${1}"
  local pattern="${2}"  
  stat -L -c "%a" ${file} | grep -qE "^${pattern}$" || chmod ${pattern} ${file} || return
}

test_root_owns() {
  local file="${1}"
  stat -L -c "%u %g" ${file} | grep -q '0 0' || chown root:root ${file} || return
}

test_grub_permissions() {
  test_root_owns ${GRUB_CFG}
  test_file_perms ${GRUB_CFG} 600
}

test_boot_pass() {
  grep -q 'set superusers=' "${GRUB_CFG}"
  if [[ "$?" -ne 0 ]]; then
    grep -q 'set superusers=' ${GRUB_DIR}/* || return
    file="$(grep 'set superusers' ${GRUB_DIR}/* | cut -d: -f1)"
    grep -q 'password' "${file}" || return
  else
    grep -q 'password' "${GRUB_CFG}" || return
  fi
}

test_auth_rescue_mode() {
  grep -q /sbin/sulogin ${RESCUE_SRV} || return
}

test_sysctl() {
  local flag="$1"
  local value="$2"
  sysctl "${flag}" | cut -d= -f2 | tr -d '[[:space:]]' | grep -q "${value}" || return
}

test_restrict_core_dumps() {
  egrep -q "\*{1}[[:space:]]+hard[[:space:]]+core[[:space:]]+0" "${LIMITS_CNF}" /etc/security/limits.d/* || echo '* hard core 0' >> ${LIMITS_CNF} || return
  test_sysctl fs.suid_dumpable 0 || (echo 'fs.suid_dumpable = 0' >> ${SYSCTL_CNF}; sysctl -p >/dev/null) || return 
}

test_xd_nx_support_enabled() {
  dmesg | egrep -q "NX[[:space:]]\(Execute[[:space:]]Disable\)[[:space:]]protection:[[:space:]]active" || return
}

test_selinux_grubcfg() {
  local grep_out1
  grep_out1="$(grep selinux=0 ${GRUB_CFG})"
  [[ -z "${grep_out1}" ]] || return
  local grep_out2
  grep_out2="$(grep enforcing=0 ${GRUB_CFG})"
  [[ -z "${grep_out2}" ]] || return
}

test_selinux_state() {
  cut -d \# -f1 ${SELINUX_CFG} | grep 'SELINUX=' | tr -d '[[:space:]]' | grep -q 'SELINUX=enforcing' || return
}

test_selinux_policy() {
  cut -d \# -f1 ${SELINUX_CFG} | grep 'SELINUXTYPE=' | tr -d '[[:space:]]' | grep -q 'SELINUXTYPE=targeted' || return
}

test_unconfined_procs() {
  local ps_out
  ps_out="$(ps -eZ | egrep 'initrc' | egrep -vw 'tr|ps|egrep|bash|awk' | tr ':' ' ' | awk '{ print $NF }')"
  [[ ${ps_out}X == 'X' ]] || return
}

test_warn_banner() {
  local banner
  banner="$(egrep '(\\v|\\r|\\m|\\s)' ${1})"
  [[ -z "${banner}" ]] || echo '*********************************************************************
* This is an COMPANY system, restricted  to authorized individuals. *
* This system is subject to monitoring. By logging into this system *
* you agree to have all your communications monitored. Unauthorized *
* users, access, and/or  modification will be prosecuted.           *
*********************************************************************' > ${1} || return
}

test_permissions_0644_root_root() {
  local file=$1
  test_root_owns ${file} || return
  test_file_perms ${file} 644 || return
}

test_permissions_0600_root_root() {
  local file=$1
  test_root_owns ${file} || return
  test_file_perms ${file} 600 || return
}

test_permissions_0700_root_root() {
  local file=$1
  test_root_owns ${file} || return
  test_file_perms ${file} 700 || return
}

test_permissions_0000_root_root() {
  local file=$1
  test_root_owns ${file} || return
  test_file_perms ${file} 0 || return
}

test_rsyslog_file_perssion() {
  egrep -q '^\$FileCreateMode[[:space:]]+0640' /etc/rsyslog.conf /etc/rsyslog.d/*.conf \
 || sed -i '/GLOBAL/a\$FileCreateMode 0640' /etc/rsyslog.conf || return
}

test_gdm_banner_msg() {
  if [[ -f "${BANNER_MSG}" ]] ; then
    egrep '[org/gnome/login-screen]' ${BANNER_MSG} || return
    egrep 'banner-message-enable=true' ${BANNER_MSG} || return
    egrep 'banner-message-text=' ${BANNER_MSG} || return
  fi
}

test_gdm_banner() {
  if [[ -f "${GDM_PROFILE}" ]] ; then
    egrep 'user-db:user' ${GDM_PROFILE} || return
    egrep 'system-db:gdm' ${GDM_PROFILE} || return
    egrep 'file-db:/usr/share/gdm/greeter-dconf-defaults' ${GDM_PROFILE} || return
    test_gdm_banner_msg || return
  fi
}

test_yum_check_update() {
  yum -q check-update &>/dev/null || return
}

test_dgram_stream_services_disabled() {
  local service=$1
  test_service_disable ${service}-dgram || return
  test_service_disable ${service}-stream || return
}

test_time_sync_services_enabled() {
  test_service_enabled ntpd && return
  test_service_enabled chronyd && return
  return 1
}

test_ntp_cfg() {
  cut -d\# -f1 ${NTP_CONF} | egrep "restrict{1}[[:space:]]+default{1}" ${NTP_CONF} | grep kod | grep nomodify | grep notrap | grep nopeer | grep -q noquery || return
  cut -d\# -f1 ${NTP_CONF} | egrep "restrict{1}[[:space:]]+\-6{1}[[:space:]]+default" | grep kod | grep nomodify | grep notrap | grep nopeer | grep -q noquery || return
  cut -d\# -f1 ${NTP_CONF} | egrep -q "^[[:space:]]*server" || return
  cut -d\# -f1 ${SYSCON_NTPD} | grep "OPTIONS=" | grep -q "ntp:ntp" && return
  cut -d\# -f1 ${NTP_SRV} | grep "^ExecStart" | grep -q "ntp:ntp" && return
  return 1
}

test_chrony_cfg() {
  cut -d\# -f1 ${CHRONY_CONF} | egrep -q "^[[:space:]]*server" || return
  cut -d\# -f1 ${CHRONY_SYSCON} | grep "OPTIONS=" | grep -q "\-u chrony" || sed -i '/OPTIONS=/s/""/"-u chrony"/' ${CHRONY_SYSCON} || return
}

test_nfs_rpcbind_services_disabled() {
  test_service_disable nfs || return
  test_service_disable rpcbind || return
}

test_mta_local_only() {
  netstat_out="$(netstat -an | grep "LIST" | grep ":25[[:space:]]")"
  if [[ "$?" -eq 0 ]] ; then
    ip=$(echo ${netstat_out} | cut -d: -f1 | cut -d" " -f4)
    [[ "${ip}" = "127.0.0.1" ]] || return    
  fi
}

test_rsh_service_disabled() {
  test_service_disable rsh.socket || return
  test_service_disable rlogin.socket || return
  test_service_disable rexec.socket || return
}

test_net_ipv4_conf_all_default() {
  local suffix=$1
  local value=$2
  test_sysctl "net.ipv4.conf.all.${suffix}" ${value} || (echo "net.ipv4.conf.all.${suffix} = ${value}" >> ${SYSCTL_CNF} && sysctl -p >/dev/null) || return
  test_sysctl "net.ipv4.conf.default.${suffix}" ${value} || (echo "net.ipv4.conf.default.${suffix} = ${value}" >> ${SYSCTL_CNF} && sysctl -p >/dev/null) || return
}

test_net_ipv6_conf_all_default() {
  local suffix=$1
  local value=$2
  test_sysctl "net.ipv6.conf.all.${suffix}" ${value} || (echo "net.ipv6.conf.all.${suffix} = ${value}" >> ${SYSCTL_CNF} && sysctl -p >/dev/null) || return
  test_sysctl "net.ipv6.conf.default.${suffix}" ${value} || (echo "net.ipv6.conf.default.${suffix} = ${value}" >> ${SYSCTL_CNF} && sysctl -p >/dev/null) || return
}

test_ipv6_disabled() {
  grep_grub="$(grep "^[[:space:]]*linux" ${GRUB_CFG} | grep -v 'ipv6.disable=1')"
  [[ -z "${grep_grub}" ]] || (sed -i -e '/^GRUB_CMDLINE_LINUX/s/"$//;/^GRUB_CMDLINE_LINUX/s/$/ ipv6.disable=1"/' /etc/default/grub; \
  grub2-mkconfig -o ${GRUB_CFG} 2>/dev/null) || return
}

test_tcp_wrappers_installed() {
  test_rpm_installed tcp_wrappers
  test_rpm_installed tcp_wrappers-libs
}

test_hosts_deny_content() {
  cut -d\# -f1 ${HOSTS_DENY} | grep -q "ALL[[:space:]]*:[[:space:]]*ALL" || return
}

test_firewall_policy() {
  iptables -L | egrep -q "Chain[[:space:]]+INPUT[[:space:]]+" | egrep -q "policy[[:space:]]+DROP" || return
  iptables -L | egrep -q "Chain[[:space:]]+FORWARD[[:space:]]+" | egrep -q "policy[[:space:]]+DROP" || return
  iptables -L | egrep -q "Chain[[:space:]]+OUTPUT[[:space:]]+" | egrep -q "policy[[:space:]]+DROP" || return
}

test_loopback_traffic_conf() {
  local accept="ACCEPT[[:space:]]+all[[:space:]]+--[[:space:]]+lo[[:space:]]+\*[[:space:]]+0\.0\.0\.0\/0[[:space:]]+0\.0\.0\.0\/0"
  local drop="DROP[[:space:]]+all[[:space:]]+--[[:space:]]+\*[[:space:]]+\*[[:space:]]+127\.0\.0\.0\/8[[:space:]]+0\.0\.0\.0\/0"
  iptables -L INPUT -v -n | egrep -q ${accept} || return
  iptables -L INPUT -v -n | egrep -q ${drop} || return
  iptables -L OUTPUT -v -n | egrep -q ${accept} || return
}

test_wireless_if_disabled() {
  for i in $(iwconfig 2>&1 | egrep -v "no[[:space:]]*wireless" | cut -d' ' -f1); do
    ip link show up | grep "${i}:"
    if [[ "$?" -eq 0 ]]; then
    return 1
    fi
  done
}

test_audit_log_storage_size() {
  cut -d\# -f1 ${AUDITD_CNF} | egrep -q "max_log_file[[:space:]]|max_log_file=" || return
}

test_dis_on_audit_log_full() {
  cut -d\# -f2 ${AUDITD_CNF} | grep 'space_left_action' | cut -d= -f2 | tr -d '[[:space:]]' | grep -q 'email' || sed -i '/^space_left_action/s/space_left_action = [[:alpha:]]*/space_left_action = email/' ${AUDITD_CNF} || return
  cut -d\# -f2 ${AUDITD_CNF} | grep 'action_mail_acct' | cut -d= -f2 | tr -d '[[:space:]]' | grep -q 'root' || sed -i '/^action_mail_acct/s/action_mail_acct = [[:alpha:]]*/action_mail_acct = root/' ${AUDITD_CNF} || return
  cut -d\# -f2 ${AUDITD_CNF} | grep 'admin_space_left_action' | cut -d= -f2 | tr -d '[[:space:]]' | grep -q 'halt' || sed -i '/^admin_space_left_action/s/admin_space_left_action = [[:alpha:]]*/admin_space_left_action = halt/' ${AUDITD_CNF} || return
}

test_keep_all_audit_info() {
  cut -d\# -f2 ${AUDITD_CNF} | grep 'max_log_file_action' | cut -d= -f2 | tr -d '[[:space:]]' | grep -q 'keep_logs' || sed -i '/^max_log_file_action/s/max_log_file_action = [[:alpha:]]*/max_log_file_action = keep_logs/' ${AUDITD_CNF} || return
}

test_audit_procs_prior_2_auditd() {
  grep_grub="$(grep "^[[:space:]]*linux" ${GRUB_CFG} | grep -v 'audit=1')"
  [[ -z "${grep_grub}" ]] || (sed -i -e '/^GRUB_CMDLINE_LINUX/s/"$//;/^GRUB_CMDLINE_LINUX/s/$/ audit=1"/' /etc/default/grub; \
 grub2-mkconfig -o ${GRUB_CFG} 2>/dev/null) || return
}

update_audit_config() {
  local parameter="${1}"
  for file in ${AUDIT_RULES} ${AUDIT_RULES_ORI}; do
    echo "${parameter}" >> ${file}
  done
}

test_audit_date_time() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+time-change" | egrep "\-S[[:space:]]+settimeofday" \
  | egrep "\-S[[:space:]]+adjtimex" | egrep "\-F[[:space:]]+arch=b64" | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 ||  update_audit_config '-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+time-change" | egrep "\-S[[:space:]]+settimeofday" \
  | egrep "\-S[[:space:]]+adjtimex" | egrep "\-F[[:space:]]+arch=b32" | egrep "\-S[[:space:]]+stime" \
 | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" || \
 update_audit_config '-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+time-change" | egrep "\-F[[:space:]]+arch=b64" \
  | egrep "\-S[[:space:]]+clock_settime" | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b6    4 -S clock_settime -k time-change' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+time-change" | egrep "\-F[[:space:]]+arch=b32" \
  | egrep "\-S[[:space:]]+clock_settime" | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b3    2 -S clock_settime -k time-change' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+time-change" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/localtime" \
 || update_audit_config '-w /etc/localtime -p wa -k time-change' || return
}

test_audit_user_group() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+identity" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/group" || update_audit_config '-w /etc/group -p wa -k identity' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+identity" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/passwd" || update_audit_config '-w /etc/passwd -p wa -k identity' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+identity" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/gshadow" || update_audit_config '-w /etc/gshadow -p wa -k identity' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+identity" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/shadow" || update_audit_config '-w /etc/shadow -p wa -k identity' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+identity" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/security\/opasswd" || update_audit_config '-w /etc/security/opasswd -p wa -k identity' || return
}

test_audit_network_env() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-S[[:space:]]+sethostname" \
  | egrep "\-S[[:space:]]+setdomainname" | egrep "\-F[[:space:]]+arch=b64" | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-S[[:space:]]+sethostname" \
  | egrep "\-S[[:space:]]+setdomainname" | egrep "\-F[[:space:]]+arch=b32" | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/issue" || update_audit_config '-w /etc/issue -p wa -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/issue.net" || update_audit_config '-w /etc/issue.net -p wa -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/hosts" || update_audit_config '-w /etc/hosts -p wa -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/sysconfig\/network" || update_audit_config '-w /etc/sysconfig/network -p wa -k system-locale' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+system-locale" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\w[[:space:]]+\/etc\/sysconfig\/network-scripts\/" || update_audit_config '-w /etc/sysconfig/network-scripts/ -p wa -k system-locale' || return
}

test_audit_sys_mac() {
cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+MAC-policy" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/selinux\/" || update_audit_config '-w /etc/selinux/ -p wa -k MAC-policy' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+MAC-policy" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/usr\/share\/selinux\/" || update_audit_config '-w /usr/share/selinux/ -p wa -k MAC-policy' || return
}

test_audit_logins_logouts() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+logins" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/log\/lastlog" || update_audit_config '-w /var/log/lastlog -p wa -k logins' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+logins" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/run\/faillock\/" || update_audit_config '-w /var/run/faillock/ -p wa -k logins' || return
}

test_audit_session_init() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+session" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/run\/utmp" || update_audit_config '-w /var/run/utmp -p wa -k session' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+logins" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/log\/wtmp" || update_audit_config '-w /var/log/wtmp -p wa -k logins' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+logins" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/log\/btmp" || update_audit_config '-w /var/log/btmp -p wa -k logins' || return
}

test_audit_dac_perm_mod_events() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+chmod" \
  | egrep "\-S[[:space:]]+fchmod" | egrep "\-S[[:space:]]+fchmodat" | egrep "\-F[[:space:]]+arch=b64" \
  | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+chmod" \
  | egrep "\-S[[:space:]]+fchmod" | egrep "\-S[[:space:]]+fchmodat" | egrep "\-F[[:space:]]+arch=b32" \
  | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+chown" \
  | egrep "\-S[[:space:]]+fchown" | egrep "\-S[[:space:]]+fchownat" | egrep "\-S[[:space:]]+fchown" \
  | egrep "\-F[[:space:]]+arch=b64" | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+chown" \
  | egrep "\-S[[:space:]]+fchown" | egrep "\-S[[:space:]]+fchownat" | egrep "\-S[[:space:]]+fchown" \
  | egrep "\-F[[:space:]]+arch=b32" | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return
  
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+setxattr" \
  | egrep "\-S[[:space:]]+lsetxattr" | egrep "\-S[[:space:]]+fsetxattr" | egrep "\-S[[:space:]]+removexattr" \
  | egrep "\-S[[:space:]]+lremovexattr" | egrep "\-S[[:space:]]+fremovexattr" | egrep "\-F[[:space:]]+arch=b64" \
  | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+perm_mod" | egrep "\-S[[:space:]]+setxattr" \
  | egrep "\-S[[:space:]]+lsetxattr" | egrep "\-S[[:space:]]+fsetxattr" | egrep "\-S[[:space:]]+removexattr" \
  | egrep "\-S[[:space:]]+lremovexattr" | egrep "\-S[[:space:]]+fremovexattr" | egrep "\-F[[:space:]]+arch=b32" \
  | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod' || return
}

test_unsuc_unauth_acc_attempts() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+access" | egrep "\-S[[:space:]]+creat" \
  | egrep "\-S[[:space:]]+open" | egrep "\-S[[:space:]]+openat" | egrep "\-S[[:space:]]+truncate" \
  | egrep "\-S[[:space:]]+ftruncate" | egrep "\-F[[:space:]]+arch=b64" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" | egrep "\-F[[:space:]]exit=\-EACCES" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+access" | egrep "\-S[[:space:]]+creat" \
  | egrep "\-S[[:space:]]+open" | egrep "\-S[[:space:]]+openat" | egrep "\-S[[:space:]]+truncate" \
  | egrep "\-S[[:space:]]+ftruncate" | egrep "\-F[[:space:]]+arch=b32" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" | egrep "\-F[[:space:]]exit=\-EACCES" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+access" | egrep "\-S[[:space:]]+creat" \
  | egrep "\-S[[:space:]]+open" | egrep "\-S[[:space:]]+openat" | egrep "\-S[[:space:]]+truncate" \
  | egrep "\-S[[:space:]]+ftruncate" | egrep "\-F[[:space:]]+arch=b64" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" | egrep "\-F[[:space:]]exit=\-EPERM" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+access" | egrep "\-S[[:space:]]+creat" \
  | egrep "\-S[[:space:]]+open" | egrep "\-S[[:space:]]+openat" | egrep "\-S[[:space:]]+truncate" \
  | egrep "\-S[[:space:]]+ftruncate" | egrep "\-F[[:space:]]+arch=b32" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" | egrep "\-F[[:space:]]exit=\-EPERM" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access' || return

}

test_coll_priv_cmds() {
  local priv_cmds
  priv_cmds="$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f)"
  for cmd in ${priv_cmds} ; do
    cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+privileged" | egrep "\-F[[:space:]]+path=${cmd}" \
    | egrep "\-F[[:space:]]+perm=x" | egrep "\-F[[:space:]]+auid>=1000" | egrep "\-F[[:space:]]+auid\!=4294967295" \
    | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" || return
  done
}

test_coll_suc_fs_mnts() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+mounts" | egrep "\-S[[:space:]]+mount" \
  | egrep "\-F[[:space:]]+arch=b64" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+mounts" | egrep "\-S[[:space:]]+mount" \
  | egrep "\-F[[:space:]]+arch=b32" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts' || return
}

test_coll_file_del_events() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+delete" | egrep "\-S[[:space:]]+unlink" \
  | egrep "\-F[[:space:]]+arch=b64" | egrep "\-S[[:space:]]+unlinkat" | egrep "\-S[[:space:]]+rename" \
  | egrep "\-S[[:space:]]+renameat" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+delete" | egrep "\-S[[:space:]]+unlink" \
  | egrep "\-F[[:space:]]+arch=b32" | egrep "\-S[[:space:]]+unlinkat" | egrep "\-S[[:space:]]+rename" \
  | egrep "\-S[[:space:]]+renameat" | egrep "\-F[[:space:]]+auid>=1000" \
  | egrep "\-F[[:space:]]+auid\!=4294967295" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete' || return

}

test_coll_chg2_sysadm_scope() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+scope" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/sudoers" || update_audit_config '-w /etc/sudoers -p wa -k scope' || return
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+scope" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/etc\/sudoers.d\/" || update_audit_config '-w /etc/sudoers.d/ -p wa -k scope' || return

}

test_coll_sysadm_actions() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+actions" | egrep "\-p[[:space:]]+wa" \
  | egrep -q "\-w[[:space:]]+\/var\/log\/sudo.log" || update_audit_config '-w /var/log/sudo.log -p wa -k actions' || return
}

test_kmod_lod_unlod() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+modules" | egrep "\-p[[:space:]]+x" \
  | egrep -q "\-w[[:space:]]+\/sbin\/insmod" || update_audit_config '-w /sbin/insmod -p x -k modules' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+modules" | egrep "\-p[[:space:]]+x" \
  | egrep -q "\-w[[:space:]]+\/sbin\/rmmod" || update_audit_config '-w /sbin/rmmod -p x -k modules' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+modules" | egrep "\-p[[:space:]]+x" \
  | egrep -q "\-w[[:space:]]+\/sbin\/modprobe" || update_audit_config '-w /sbin/modprobe -p x -k modules' || return

  cut -d\# -f1 ${AUDIT_RULES} | egrep "\-k[[:space:]]+modules" | egrep "\-S[[:space:]]+delete_module" \
  | egrep "\-F[[:space:]]+arch=b64" | egrep "\-S[[:space:]]+init_module" \
  | egrep -q "\-a[[:space:]]+always,exit|\-a[[:space:]]+exit,always" \
 || update_audit_config '-a always,exit -F arch=b64 -S init_module -S delete_module -k modules' || return
}

test_audit_cfg_immut() {
  cut -d\# -f1 ${AUDIT_RULES} | egrep -q "^-e[[:space:]]+2" || update_audit_config '-e 2' || return
}

test_rsyslog_content() {
  grep -q "^*.*[^I][^I]*@" ${RSYSLOG_CNF} 2>/dev/null || return
}

test_syslogng_content() {
  egrep -q "destination[[:space:]]+logserver[[:space:]]+\{[[:space:]]*tcp\(\".+\"[[:space:]]+port\([[:digit:]]+\)\)\;[[:space:]]*\}\;" ${SYSLOGNG_CONF} 2>/dev/null || return
  egrep -q "log[[:space:]]+\{[[:space:]]*source\(src\)\;[[:space:]]*destination\(logserver\)\;[[:space:]]*\}\;" ${SYSLOGNG_CONF} 2>/dev/null || return
}

test_rsyslog_syslogng_installed() {
  test_rpm_installed rsyslog && return
  test_rpm_installed syslog-ng && return
  return 1
}

test_var_log_files_permissions() {
  [[ $(find /var/log -type f -ls | grep -v "\-r\-\-\-\-\-\-\-\-" | grep -v "\-rw\-\-\-\-\-\-\-" | grep -v "\-rw\-r\-\-\-\-\-" | wc -l) -eq 0 ]] \
 || find /var/log -type f -exec chmod g-wx,o-rwx {} + || return
}

test_at_cron_auth_users() {
  [[ -f ${AT_DENY} ]] || touch ${AT_DENY} || return 
  [[ -f ${CRON_DENY} ]] || touch ${CRON_DENY} || return 
  [[ -f ${AT_ALLOW} ]] || touch ${AT_ALLOW} || return
  [[ -f ${CRON_ALLOW} ]] || touch ${CRON_ALLOW} || return
  test_permissions_0600_root_root "${CRON_ALLOW}" || return
  test_permissions_0600_root_root "${AT_ALLOW}" || return
}

test_pam_pwquality() {
  egrep pam_pwquality.so ${PASS_AUTH} | egrep try_first_pass | egrep -q retry=3 || return
  egrep pam_pwquality.so ${SYSTEM_AUTH} | egrep try_first_pass | egrep -q retry=3 || return
  [[ $(egrep "^minlen[[:space:]]+=[[:space:]]" ${PWQUAL_CNF} | awk '{print $NF}') -ge 14 ]] || return
  egrep -q "^dcredit[[:space:]]+=[[:space:]]+-1" ${PWQUAL_CNF} || return
  egrep -q "^ucredit[[:space:]]+=[[:space:]]+-1" ${PWQUAL_CNF} || return
  egrep -q "^ocredit[[:space:]]+=[[:space:]]+-1" ${PWQUAL_CNF} || return
  egrep -q "^lcredit[[:space:]]+=[[:space:]]+-1" ${PWQUAL_CNF} || return
}

test_password_history() {
  egrep '^password\s+sufficient\s+pam_unix.so' ${PASS_AUTH} | egrep -q 'remember=' || return
  [[ $(egrep  -o "remember=[[:digit:]]+" ${PASS_AUTH} | awk -F'=' '{print $2}') -ge 5 ]] || return
  egrep '^password\s+sufficient\s+pam_unix.so' ${SYSTEM_AUTH} | egrep -q 'remember=' || return
  [[ $(egrep  -o "remember=[[:digit:]]+" ${SYSTEM_AUTH} | awk -F'=' '{print $2}') -ge 5 ]] || return
}

test_password_algorithm() {
  egrep '^password\s+sufficient\s+pam_unix.so' ${PASS_AUTH} | egrep -q sha512 || return
  egrep '^password\s+sufficient\s+pam_unix.so' ${SYSTEM_AUTH} | egrep -q sha512 || return
}

test_password_expiration() {
  egrep -q "^PASS_MAX_DAYS" ${LOGIN_DEFS} || return
  local actual_value
  actual_value=$(egrep "^PASS_MAX_DAYS" ${LOGIN_DEFS} | awk '{print $2}')
  [[ ${actual_value} -le 365 ]] || sed -i "/^PASS_MAX_DAYS/s/${actual_value}/365/" ${LOGIN_DEFS} || return
}

test_password_minium_change() {
  egrep -q "^PASS_MIN_DAYS" ${LOGIN_DEFS} || return
  local actual_value
  actual_value=$(egrep "^PASS_MIN_DAYS" ${LOGIN_DEFS} | awk '{print $2}')
  [[ ${actual_value} -ge 7 ]] || sed -i "/^PASS_MIN_DAYS/s/${actual_value}/7/" ${LOGIN_DEFS} || return
}

test_password_expiration_warn() {
  egrep -q "^PASS_WARN_AGE" ${LOGIN_DEFS} || return
  local actual_value
  actual_value=$(egrep "^PASS_WARN_AGE" ${LOGIN_DEFS} | awk '{print $2}')
  [[ ${actual_value} -ge 7 ]] || sed -i "/^PASS_WARN_AGE/s/${actual_value}/7/" ${LOGIN_DEFS} || return
}

test_password_lock() {
  [[ $(useradd -D | grep INACTIVE | awk -F'=' '{print $2}') -le 30 ]] && [[ $(useradd -D | grep INACTIVE | awk -F'=' '{print $2}') -ne -1 ]] || return
}

test_password_empty() {
  [[ $(awk -F':' '($2 == "") {print $1}' /etc/passwd)X == 'X' ]] || return
}

test_root_group_id() {
  [[ $(grep "^root:" /etc/passwd | cut -f4 -d:) -eq 0 ]] || return
}

test_system_account() {
  [[ $(egrep -v "^\+" /etc/passwd | awk -F: '($1!="root" && $1!="sync" && $1!="shutdown" && $1!="halt" && $3<1000 && $7!="/sbin/nologin" && $7!="/bin/false") {print}') == '' ]] || return
}

test_legacy_entries() {
  local file="${1}"
  [[ $(egrep -o '^\+:' $file)X == 'X' ]] || return
}

test_param() {
  local file="${1}" 
  local parameter="${2}" 
  local value="${3}" 
  cut -d\# -f1 ${file} | egrep -q "^${parameter}[[:space:]]+${value}" || (egrep -q "^#${parameter}" ${file} && sed -i "s@^#${parameter}.*@${parameter} ${value}@"     ${file}) || (egrep -q "^${parameter}" ${file} && sed -i "s@^${parameter}.*@${parameter} ${value}@" ${file}) || echo "${parameter} ${value}" >> ${file} || return
}

test_ssh_param_le() {
  local parameter="${1}" 
  local allowed_max="${2}"
  local actual_value
  actual_value=$(cut -d\# -f1 ${SSHD_CFG} | grep "${parameter}" | cut -d" " -f2)
  [[ ${actual_value} -le ${allowed_max} ]] || return 
}

test_ssh_idle_timeout() {
  test_ssh_param_le ClientAliveInterval 300 || return
  test_ssh_param_le ClientAliveCountMax 3 || return
}

test_ssh_access() {
  local allow_users
  local allow_groups
  local deny_users
  local deny_users
  allow_users="$(cut -d\# -f1 ${SSHD_CFG} | grep "AllowUsers" | cut -d" " -f2)"
  allow_groups="$(cut -d\# -f1 ${SSHD_CFG} | grep "AllowGroups" | cut -d" " -f2)"
  deny_users="$(cut -d\# -f1 ${SSHD_CFG} | grep "DenyUsers" | cut -d" " -f2)"
  deny_groups="$(cut -d\# -f1 ${SSHD_CFG} | grep "DenyGroups" | cut -d" " -f2)"
  [[ -n "${allow_users}" ]] || return
  [[ -n "${allow_groups}" ]] || return
  [[ -n "${deny_users}" ]] || return
  [[ -n "${deny_groups}" ]] || return
}

test_wrapper() {
  local do_skip=$1
  shift
  local msg=$1
  shift
  local func=$1
  shift
  local args=$@
  if [[ "$do_skip" -eq 0 ]]; then
    ${func} ${args} 
    if [[ "$?" -eq 0 ]]; then
      pass "${msg}"
    else
      warn "${msg}"
    fi
  else
    skip "${msg}"
  fi
}
