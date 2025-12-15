# MGMTCLT - Client Management

> **OS** : Debian 13 GUI  
> **IP** : 10.4.99.1 (VLAN 99 - Management)  
> **Rôle** : Administration réseau, Ansible

---

## 🎯 Contexte (Sujet)

Ce poste est dédié à l'administration des équipements réseau :

| Fonction           | Description                                                               |
| ------------------ | ------------------------------------------------------------------------- |
| **Ansible**        | Playbooks pour gérer ACCSW1, ACCSW2, CORESW1, CORESW2.                    |
| **Backup/Restore** | Sauvegarde et restauration des configs switches via TFTP local.           |
| **Monitoring**     | Collecte version OS, état interfaces, paramètres environnementaux (3750). |
| **NTP**            | Synchronisation des switches avec HQINFRASRV.                             |
| **Stockage**       | Playbooks stockés sur FTP (INETSRV - ftp.worldskills.org).                |

---

## 📋 Prérequis

- [ ] Debian 13 avec interface graphique
- [ ] Connecté au VLAN 99 (Management)
- [ ] Accès SSH aux switches

---

## 1️⃣ Configuration de base

### Hostname

```bash
hostnamectl set-hostname mgmtclt
```

### Configuration réseau (IP statique ou DHCP)

```bash
cat > /etc/network/interfaces << 'EOF'
auto eth0
iface eth0 inet static
    address 10.4.99.1
    netmask 255.255.255.0
    gateway 10.4.99.254
    dns-nameservers 10.4.10.1
    dns-search wsl2025.org hq.wsl2025.org
EOF
```

---

## 2️⃣ Installation des outils

```bash
apt update
apt install -y ansible python3-pip git curl wget openssh-client tftp-hpa tftpd-hpa

# Ansible Collections pour Cisco IOS
ansible-galaxy collection install cisco.ios
pip3 install paramiko netmiko
```

---

## 3️⃣ Configuration TFTP Server

```bash
cat > /etc/default/tftpd-hpa << 'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

mkdir -p /srv/tftp
chmod 777 /srv/tftp
systemctl restart tftpd-hpa
systemctl enable tftpd-hpa
```

---

## 4️⃣ Configuration Ansible

### Inventaire avec les vraies IP

```bash
mkdir -p ~/ansible
cat > ~/ansible/inventory.yml << 'EOF'
all:
  children:
    switches:
      hosts:
        accsw1:
          ansible_host: 10.4.99.11
        accsw2:
          ansible_host: 10.4.99.12
        coresw1:
          ansible_host: 10.4.99.253
        coresw2:
          ansible_host: 10.4.99.252
      vars:
        ansible_network_os: cisco.ios.ios
        ansible_connection: network_cli
        ansible_user: admin
        ansible_password: P@ssw0rd
        ansible_become: yes
        ansible_become_method: enable
        ansible_become_password: P@ssw0rd
EOF
```

### Configuration Ansible

```bash
cat > ~/ansible/ansible.cfg << 'EOF'
[defaults]
inventory = inventory.yml
host_key_checking = False
timeout = 30
deprecation_warnings = False

[persistent_connection]
command_timeout = 30
connect_timeout = 30
EOF
```

---

## 5️⃣ Playbooks Ansible

### Playbook 1 : Backup des configurations

```bash
cat > ~/ansible/backup_config.yml << 'EOF'
---
- name: Backup switch configurations
  hosts: switches
  gather_facts: no
  
  tasks:
    - name: Get current date
      set_fact:
        backup_date: "{{ lookup('pipe', 'date +%Y%m%d') }}"
      delegate_to: localhost
      run_once: true
      
    - name: Get running configuration
      cisco.ios.ios_command:
        commands:
          - show running-config
      register: config
      
    - name: Save configuration to local file
      copy:
        content: "{{ config.stdout[0] }}"
        dest: "/srv/tftp/{{ inventory_hostname }}_{{ backup_date }}.cfg"
      delegate_to: localhost
EOF
```

### Playbook 2 : Restore des configurations

```bash
cat > ~/ansible/restore_config.yml << 'EOF'
---
- name: Restore switch configurations from TFTP
  hosts: switches
  gather_facts: no
  vars:
    tftp_server: 10.4.99.1
  
  tasks:
    - name: Restore from TFTP
      cisco.ios.ios_command:
        commands:
          - "copy tftp://{{ tftp_server }}/{{ inventory_hostname }}.cfg running-config"
      
    - name: Save to startup
      cisco.ios.ios_config:
        save_when: always
EOF
```

### Playbook 3 : Collecter version OS

```bash
cat > ~/ansible/get_version.yml << 'EOF'
---
- name: Collect OS version from all switches
  hosts: switches
  gather_facts: no
  
  tasks:
    - name: Get version
      cisco.ios.ios_command:
        commands:
          - show version | include Version
      register: version
      
    - name: Display version
      debug:
        msg: "{{ inventory_hostname }}: {{ version.stdout_lines[0] }}"
EOF
```

### Playbook 4 : État des interfaces

```bash
cat > ~/ansible/interface_status.yml << 'EOF'
---
- name: Display interface status
  hosts: switches
  gather_facts: no
  
  tasks:
    - name: Get interface brief
      cisco.ios.ios_command:
        commands:
          - show ip interface brief
      register: interfaces
      
    - name: Display interfaces
      debug:
        var: interfaces.stdout_lines[0]
EOF
```

### Playbook 5 : Synchronisation NTP

```bash
cat > ~/ansible/sync_ntp.yml << 'EOF'
---
- name: Synchronize NTP on all switches
  hosts: switches
  gather_facts: no
  
  tasks:
    - name: Configure NTP server
      cisco.ios.ios_config:
        lines:
          - ntp server 10.4.10.2 prefer
          - clock timezone CET 1
          - clock summer-time CEST recurring last Sun Mar 2:00 last Sun Oct 3:00
          
    - name: Verify NTP status
      cisco.ios.ios_command:
        commands:
          - show ntp status
      register: ntp
      
    - name: Display NTP status
      debug:
        msg: "{{ inventory_hostname }}: {{ ntp.stdout_lines[0][0] | default('NTP not synced') }}"
EOF
```

### Playbook 6 : Paramètres environnementaux

```bash
cat > ~/ansible/environment_status.yml << 'EOF'
---
- name: Display environment status (3750 switches)
  hosts: switches
  gather_facts: no
  
  tasks:
    - name: Get environment status
      cisco.ios.ios_command:
        commands:
          - show environment all
      register: env
      ignore_errors: yes
      
    - name: Display environment
      debug:
        var: env.stdout_lines[0]
      when: env.stdout_lines is defined
EOF
```

---

## 6️⃣ Exécution des playbooks

```bash
cd ~/ansible

# Tester la connexion
ansible switches -m ping

# Backup
ansible-playbook backup_config.yml

# Version OS
ansible-playbook get_version.yml

# Interfaces
ansible-playbook interface_status.yml

# NTP
ansible-playbook sync_ntp.yml

# Environnement
ansible-playbook environment_status.yml
```

---

## 7️⃣ Upload vers FTP (INETSRV)

```bash
apt install -y lftp

# Upload des playbooks vers INETSRV
lftp -u devops,P@ssw0rd ftp.worldskills.org << 'EOF'
cd /playbooks
mput ~/ansible/*.yml
bye
EOF
```

---

## 8️⃣ Test SSH manuel

```bash
# Connexion aux switches
ssh admin@10.4.99.11   # ACCSW1
ssh admin@10.4.99.12   # ACCSW2
ssh admin@10.4.99.253  # CORESW1
ssh admin@10.4.99.252  # CORESW2
```

---

## ✅ Vérification Finale

### 🔌 Comment se connecter à MGMTCLT

1. Ouvrir la console VMware du poste MGMTCLT
2. Se connecter avec l'utilisateur local (ex: `admin` / mot de passe configuré)
3. Ouvrir un terminal : clic droit sur le bureau → **Terminal** ou `Ctrl+Alt+T`
4. Tu dois voir le prompt : `admin@mgmtclt:~$`

---

### Test 1 : Ping vers les switches

**Étape 1** : Tape cette commande (teste les 4 switches d'un coup) :
```bash
for ip in 10.4.99.11 10.4.99.12 10.4.99.253 10.4.99.252; do ping -c 1 -W 1 $ip > /dev/null && echo "$ip OK" || echo "$ip ECHEC"; done
```

**Étape 2** : Regarde le résultat :
```
10.4.99.11 OK
10.4.99.12 OK
10.4.99.253 OK
10.4.99.252 OK
```

✅ **C'est bon si** : Tu vois "OK" pour les 4 IPs
❌ **Problème si** : "ECHEC" → Le switch ne répond pas (vérifie VLAN 99)

---

### Test 2 : SSH vers un switch

**Étape 1** : Tape cette commande :
```bash
ssh admin@10.4.99.11
```

**Étape 2** : Tu dois voir :
1. D'abord la bannière : `/!\ Restricted access. Only for authorized people /!\`
2. Ensuite le prompt de mot de passe
3. Tape le mot de passe : `P@ssw0rd`
4. Tu arrives sur le prompt Cisco : `ACCSW1>`

**Étape 3** : Tape `exit` pour sortir

✅ **C'est bon si** : Tu as vu la bannière et pu te connecter
❌ **Problème si** : "Connection refused" → SSH pas configuré sur le switch

---

### Test 3 : Ansible ping

**Étape 1** : Va dans le dossier Ansible :
```bash
cd ~/ansible
```

**Étape 2** : Tape cette commande :
```bash
ansible switches -m ping
```

**Étape 3** : Regarde le résultat :
```
accsw1 | SUCCESS => { "changed": false, "ping": "pong" }
accsw2 | SUCCESS => { "changed": false, "ping": "pong" }
coresw1 | SUCCESS => { "changed": false, "ping": "pong" }
coresw2 | SUCCESS => { "changed": false, "ping": "pong" }
```

✅ **C'est bon si** : Tu vois `SUCCESS` pour les 4 switches
❌ **Problème si** : `UNREACHABLE` → Problème SSH ou inventaire Ansible

---

### Test 4 : Vérifier TFTP

**Étape 1** : Tape cette commande :
```bash
systemctl is-active tftpd-hpa
```

**Étape 2** : Regarde le résultat :
```
active
```

✅ **C'est bon si** : `active`
❌ **Problème si** : `inactive` → TFTP pas démarré

---

### Test 5 : Accès FTP vers INETSRV

**Étape 1** : Tape cette commande :
```bash
curl -s -u devops:P@ssw0rd ftp://ftp.worldskills.org/ | head -3
```

**Étape 2** : Regarde le résultat (liste de fichiers) :
```
drwxr-xr-x    2 1000     1000         4096 Jan 01 12:00 playbooks
-rw-r--r--    1 1000     1000          123 Jan 01 12:00 README.txt
```

✅ **C'est bon si** : Tu vois une liste de fichiers/dossiers
❌ **Problème si** : Erreur 530 → Mauvais login/mot de passe

---

### 📋 Résumé rapide (copie-colle tout d'un coup)

```bash
echo "=== PING SWITCHES ===" 
for ip in 10.4.99.11 10.4.99.12 10.4.99.253 10.4.99.252; do ping -c 1 -W 1 $ip > /dev/null && echo "$ip OK" || echo "$ip ECHEC"; done

echo "=== TFTP ===" 
systemctl is-active tftpd-hpa

echo "=== ANSIBLE ===" 
cd ~/ansible && ansible switches -m ping 2>/dev/null | grep -E "SUCCESS|UNREACHABLE"

echo "=== FTP INETSRV ===" 
curl -s -u devops:P@ssw0rd ftp://ftp.worldskills.org/ 2>/dev/null | head -2 || echo "FTP ECHEC"
```

---

## 📝 Tableau des équipements

| Équipement | IP          | Rôle              |
| ---------- | ----------- | ----------------- |
| MGMTCLT    | 10.4.99.1   | Client Management |
| ACCSW1     | 10.4.99.11  | Access Switch 1   |
| ACCSW2     | 10.4.99.12  | Access Switch 2   |
| CORESW1    | 10.4.99.253 | Core Switch 1     |
| CORESW2    | 10.4.99.252 | Core Switch 2     |
| Gateway    | 10.4.99.254 | VIP HSRP          |

---

## 📝 Notes

- Seul le VLAN 99 (Management) peut accéder aux switches en SSH
- Les playbooks doivent être stockés sur INETSRV (8.8.4.2)
- Le serveur NTP est HQINFRASRV (10.4.10.2)
- La bannière SSH affiche : `/!\ Restricted access. Only for authorized people /!\`
