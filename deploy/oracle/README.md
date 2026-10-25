# Publicar MESE gratis en Oracle Cloud

Oracle Cloud da para siempre, sin costo, una máquina virtual pequeña ("Always Free"). Ahí corren juntos
el servidor de MESE y MySQL. Para 2 o 3 usuarias sobra. Elegimos la región **México Central (Querétaro)**
para que los datos de las familias se queden en México.

| Qué | Cómo queda |
|---|---|
| Costo | $0 al mes, dentro de los límites de Always Free |
| Dirección | `https://<ip>.sslip.io` gratis, o un dominio propio |
| HTTPS | Automático con Caddy (certificado de Let's Encrypt que se renueva solo) |
| Base de datos | MySQL 8 en la misma máquina, solo accesible desde ella |
| Respaldos | Uno diario en `/var/backups/mese` (se guardan 30) y, opcional, copia a Google Drive |
| Mantenimiento | Ubuntu instala solo las actualizaciones de seguridad; para versiones nuevas de MESE, un comando |

## 1. Crear la cuenta

1. Entre a <https://signup.cloud.oracle.com> y cree la cuenta con el correo de MESE (o el suyo).
2. En **Home Region** elija **Mexico Central (Queretaro)**. No se puede cambiar después, y los recursos
   gratis solo existen en esa región.
3. Oracle pide una tarjeta solo para verificar que es una persona. Hace un cargo temporal pequeño que
   devuelve, y no cobra mientras se use lo gratuito.

**Recomendado:** cuando la cuenta esté lista, pásela a **Pay As You Go** (menú *Billing → Upgrade and
Manage Payment*). Sigue costando $0 si no se sale de Always Free, pero Oracle ya no puede apagar la
máquina por "poco uso". Con 2 usuarias la máquina casi no trabaja, y en las cuentas solo gratuitas Oracle
recupera las máquinas que pasan 7 días con muy poco uso. Para no salirse de lo gratis, active también un
**presupuesto con alerta de $1** (*Billing → Budgets*).

## 2. Crear la máquina

En el menú: **Compute → Instances → Create instance**.

- **Name:** `mese`
- **Image:** *Canonical Ubuntu 24.04*
- **Shape:** *Ampere VM.Standard.A1.Flex* con **1 OCPU y 6 GB** de memoria (marcado "Always Free eligible").
  Si dice *Out of capacity*, pruebe otro *Availability domain* o use *VM.Standard.E2.1.Micro* (1 GB; el
  script agrega memoria de intercambio y alcanza para MESE).
- **Networking:** deje que cree la red (VCN) y marque **Assign a public IPv4 address**.
- **SSH keys:** *Generate a key pair* y descargue **la llave privada**. Guárdela bien: es la única forma de
  entrar a la máquina.
- **Boot volume:** el tamaño que propone (47 GB) está dentro de lo gratis.

Al terminar, copie la **Public IP address** de la máquina.

## 3. Abrir los puertos 80 y 443

En la página de la máquina: **Subnet → Security Lists → Default Security List → Add Ingress Rules**.
Agregue dos reglas:

| Source CIDR | IP Protocol | Destination Port Range |
|---|---|---|
| `0.0.0.0/0` | TCP | `80` |
| `0.0.0.0/0` | TCP | `443` |

(El firewall de dentro de la máquina lo abre el script.)

## 4. Instalar MESE

Desde una terminal en su computadora (en Windows sirve PowerShell):

```bash
ssh -i ruta/a/la-llave.key ubuntu@IP_PUBLICA
git clone https://github.com/softweeird-creator/Mese_WebApp.git
cd Mese_WebApp
sudo bash deploy/oracle/instalar.sh
```

Si el repositorio es privado, `git clone` pide usuario y contraseña: use su usuario de GitHub y, como
contraseña, un *token* de solo lectura (GitHub → Settings → Developer settings → Fine-grained tokens, con
permiso *Contents: Read-only* sobre este repositorio).

El script tarda unos 5 minutos. Al final muestra la dirección, por ejemplo `https://140.84.10.20.sslip.io`.
Ábrala, entre con `admin` / `mese2026` y la página le pedirá una contraseña nueva.

### Con dominio propio (opcional)

1. En el DNS del dominio (por ejemplo en Cloudflare, gratis) cree un registro **A** `sistema` → la IP
   pública. En Cloudflare déjelo primero en **DNS only** (nube gris).
2. Corra `sudo bash deploy/oracle/instalar.sh sistema.mese.org`. Caddy saca el certificado solo.
3. Si después quiere el proxy de Cloudflare (nube naranja), ponga **SSL/TLS → Full (strict)**.

## 5. Cargar los Excel

1. En Excel guarde cada hoja como **CSV UTF-8 (delimitado por comas)**: la hoja BASE como `base.csv`,
   B-DATOS del BDI como `bdi.csv` y DATOS de la base histórica como `historica.csv`.
2. Súbalos: `scp -i la-llave.key base.csv bdi.csv historica.csv ubuntu@IP_PUBLICA:~/`
3. En la máquina:
   ```bash
   cd ~/Mese_WebApp
   sudo bash deploy/oracle/cargar_excel.sh ~/base.csv ~/bdi.csv ~/historica.csv 2026-10-31
   ```
   La fecha es el corte del Excel. Muestra cuántos participantes, familias e históricos entraron y los
   valores que conviene revisar.
4. Borre los CSV de la máquina y de su computadora: `rm ~/*.csv`. Tienen datos de menores.
5. En la página, en **Usuarios**, asigne los participantes a cada trabajadora social (en el Excel la
   columna T.S. viene vacía).

La carga es para el inicio. Si se repite, borra lo que vino del Excel anterior y lo vuelve a cargar: lo
que se agregó en la página se conserva, pero se pierden los cambios hechos en la página a personas que
venían del Excel.

## 6. Respaldos

- Cada día a las 3:30 se guarda la base en `/var/backups/mese/mese-AAAA-MM-DD.sql.gz` (se conservan 30).
- Para bajar una copia a su computadora:
  `scp -i la-llave.key ubuntu@IP_PUBLICA:/var/backups/mese/mese-*.sql.gz .` (hay que copiarlos con
  `sudo cp` a la carpeta de `ubuntu` primero, porque solo root puede leerlos).
- **Copia automática fuera de la máquina (recomendado):** `sudo apt install rclone`, luego
  `sudo rclone config` y cree un destino llamado **`mese`** (por ejemplo Google Drive de MESE). Desde
  ese día cada respaldo también se sube a la carpeta `respaldos-mese`.
- Restaurar un respaldo: `gunzip -c /var/backups/mese/mese-AAAA-MM-DD.sql.gz | sudo mysql`

## 7. Actualizar a una versión nueva

```bash
cd ~/Mese_WebApp && git pull && sudo bash deploy/oracle/actualizar.sh
```

Hace un respaldo, actualiza funciones, vistas y procedimientos de la base sin tocar los datos, y reinicia
el servidor.

## Si algo falla

| Problema | Qué revisar |
|---|---|
| La página no abre | Las reglas de los puertos 80 y 443 del paso 3 |
| Error de certificado | Que el dominio apunte a la IP y el puerto 80 esté abierto; `sudo journalctl -u caddy -n 50` |
| "Ocurrió un error en el servidor" | `sudo journalctl -u mese -n 50` |
| Olvidé la contraseña del admin | `cd /opt/mese/server && sudo -u mese npm run clave -- admin NuevaClave` |
| Reiniciar todo | `sudo systemctl restart mysql mese caddy` |
