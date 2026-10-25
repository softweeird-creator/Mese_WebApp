#!/usr/bin/env bash
# Respaldo de la base de MESE: un archivo comprimido por día en /var/backups/mese,
# se conservan los últimos 30. Lo corre cron todos los días a las 3:30.
# Restaurar:  gunzip -c /var/backups/mese/mese-AAAA-MM-DD.sql.gz | sudo mysql
set -euo pipefail
DIR=/var/backups/mese
mkdir -p "$DIR" && chmod 700 "$DIR"
archivo="$DIR/mese-$(date +%F).sql.gz"
mysqldump --single-transaction --routines --triggers --events --databases mese | gzip > "$archivo.tmp"
mv "$archivo.tmp" "$archivo" && chmod 600 "$archivo"
find "$DIR" -name 'mese-*.sql.gz' -mtime +30 -delete

# Copia fuera de la máquina (opcional): si se configuró rclone con un destino llamado "mese"
# (Google Drive, OneDrive...), se sube ahí también. Ver deploy/oracle/README.md.
if command -v rclone >/dev/null && rclone listremotes 2>/dev/null | grep -q '^mese:'; then
  rclone copy "$archivo" mese:respaldos-mese --quiet
fi
echo "Respaldo: $archivo ($(du -h "$archivo" | cut -f1))"
