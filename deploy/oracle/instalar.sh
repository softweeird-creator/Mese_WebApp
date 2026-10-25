#!/usr/bin/env bash
# =====================================================================
#  deploy/oracle/instalar.sh — instala MESE en una máquina Ubuntu 22.04
#  o 24.04 (pensado para Oracle Cloud "Always Free", sirve en cualquier VPS).
#
#  Deja funcionando: MySQL 8 con la base, el servidor de MESE como servicio,
#  HTTPS automático con Caddy, el firewall abierto en 80/443 y un respaldo
#  diario de la base.
#
#  Uso, desde la carpeta del repositorio ya clonado en la máquina:
#    sudo bash deploy/oracle/instalar.sh                 # dirección gratis <ip>.sslip.io
#    sudo bash deploy/oracle/instalar.sh sistema.mese.org   # con dominio propio
#
#  Si la base "mese" ya existe no la toca (para actualizar use actualizar.sh).
# =====================================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Corra el script con sudo."; exit 1; }
REPO=$(cd "$(dirname "$0")/../.." && pwd)
APP=/opt/mese
ETC=/etc/mese
paso() { echo; echo "=== $* ==="; }

IP=$(curl -fsS --max-time 10 https://ifconfig.me || curl -fsS --max-time 10 https://api.ipify.org || true)
DOMINIO=${1:-${IP:+$IP.sslip.io}}
[ -n "$DOMINIO" ] || { echo "No pude saber la IP pública. Indique el dominio: sudo bash $0 su.dominio.org"; exit 1; }

paso "Memoria de intercambio (para máquinas de 1 GB)"
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 2000000 ] && ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Se agregaron 2 GB de intercambio."
else
  echo "No hace falta."
fi

paso "Paquetes del sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q mysql-server git curl gzip rsync build-essential python3 debian-keyring debian-archive-keyring apt-transport-https iptables-persistent >/dev/null

if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -q nodejs >/dev/null
fi
echo "Node $(node -v)"

if ! command -v caddy >/dev/null; then
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -y -q caddy >/dev/null
fi
echo "$(caddy version | cut -d' ' -f1)"

paso "MySQL con poca memoria"
cat > /etc/mysql/mysql.conf.d/mese.cnf <<'CNF'
[mysqld]
# Pocos usuarios: se reduce la memoria para que quepa en la máquina gratis
performance_schema      = OFF
innodb_buffer_pool_size = 128M
max_connections         = 40
bind-address            = 127.0.0.1
mysqlx                  = OFF
CNF
systemctl restart mysql

paso "Base de datos"
mkdir -p "$ETC" && chmod 700 "$ETC"
if [ -f "$ETC/credenciales" ]; then
  # shellcheck disable=SC1091
  . "$ETC/credenciales"
else
  CLAVE_APP=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
  CLAVE_REP=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
  printf 'CLAVE_APP=%s\nCLAVE_REP=%s\n' "$CLAVE_APP" "$CLAVE_REP" > "$ETC/credenciales"
  chmod 600 "$ETC/credenciales"
fi
if mysql -e "USE mese" 2>/dev/null; then
  echo "La base 'mese' ya existe: no se toca. Para actualizarla use deploy/oracle/actualizar.sh."
else
  cd "$REPO/db"
  for f in 01_esquema 02_catalogos 03_funciones_vistas 04_procedimientos 05_triggers 06_carga_excel; do
    mysql < "$f.sql" > /dev/null && echo "  $f.sql"
  done
  sed "s/CAMBIE_ESTA_CONTRASENA_1/$CLAVE_APP/; s/CAMBIE_ESTA_CONTRASENA_2/$CLAVE_REP/" 08_seguridad.sql | mysql && echo "  08_seguridad.sql"
  mysql < 09_pagina.sql && echo "  09_pagina.sql"
fi

paso "Servidor de MESE en $APP"
id mese >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin mese
mkdir -p "$APP"
rsync -a --delete --exclude .git --exclude node_modules --exclude server/.env --exclude server/dist "$REPO/" "$APP/"
cat > "$APP/server/.env" <<ENV
PUERTO=3000
MODO=produccion
PROXY=si
DB_HOST=127.0.0.1
DB_PUERTO=3306
DB_USUARIO=mese_app
DB_CLAVE="$CLAVE_APP"
DB_NOMBRE=mese
ENV
chmod 600 "$APP/server/.env"
chown -R mese:mese "$APP"
sudo -u mese -H bash -c "cd $APP/server && npm ci --no-audit --no-fund --loglevel=error && npm run build --silent"

cat > /etc/systemd/system/mese.service <<UNIT
[Unit]
Description=Servidor de MESE
After=network.target mysql.service
Requires=mysql.service

[Service]
User=mese
WorkingDirectory=$APP/server
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now mese >/dev/null 2>&1
systemctl restart mese

paso "HTTPS con Caddy para $DOMINIO"
cat > /etc/caddy/Caddyfile <<CADDY
$DOMINIO {
	encode gzip
	reverse_proxy 127.0.0.1:3000
}
CADDY
systemctl reload caddy || systemctl restart caddy

paso "Firewall de la máquina (puertos 80 y 443)"
# Las imágenes de Ubuntu de Oracle traen iptables que bloquea todo menos SSH
for p in 80 443; do
  iptables -C INPUT -p tcp --dport "$p" -m state --state NEW -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 5 -p tcp --dport "$p" -m state --state NEW -j ACCEPT
done
netfilter-persistent save >/dev/null 2>&1 || true

paso "Respaldo diario de la base"
install -m 755 "$REPO/deploy/oracle/respaldo.sh" /usr/local/bin/mese-respaldo
echo '30 3 * * * root /usr/local/bin/mese-respaldo' > /etc/cron.d/mese-respaldo
/usr/local/bin/mese-respaldo

paso "Listo"
sleep 2
if [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/yo)" = 401 ]; then
  echo "El servidor responde."
else
  echo "El servidor no responde todavía. Revise: journalctl -u mese -n 50"
fi
cat <<FIN

  Dirección:   https://$DOMINIO
  Entrar:      usuario admin, contraseña mese2026 (la página pide cambiarla)
  Respaldos:   /var/backups/mese (uno por día, se guardan 30)
  Contraseñas de MySQL de la aplicación: $ETC/credenciales

  Si la página no abre, revise que en Oracle Cloud la "Security List" de la
  red permita los puertos 80 y 443 (ver deploy/oracle/README.md, paso 4).
FIN
