# LEMP container `lemp_progetti`

Questo repository rappresenta l'intera infrastruttura dello stack LEMP come **Infrastructure as Code (IaC)**: tutto ciò che serve per distribuire, riprodurre e gestire l'ambiente è versionato qui. Nessun passaggio manuale fuori da questo repository è necessario per ricostruire lo stack da zero.

## Indice

- [Panoramica](#panoramica)
- [Prerequisiti](#prerequisiti)
- [Repository](#repository)
- [Siti attualmente serviti](#siti-attualmente-serviti)
- [Come funziona il flusso](#come-funziona-il-flusso)
- [Ricostruzione da zero](#ricostruzione-da-zero)
- [Aggiunta di nuovi siti](#aggiunta-di-nuovi-siti)
- [Struttura dei servizi](#struttura-dei-servizi)
- [File principali](#file-principali)
- [Avvio e gestione](#avvio-e-gestione)
- [Backup](#backup)
- [Accesso ai container](#accesso-ai-container)
- [Note operative](#note-operative)

---

## Panoramica

Questo repository contiene uno stack Docker Compose con tre servizi:

| Servizio | Immagine | Container |
| --- | --- | --- |
| `nginx` | `nginx:1.27-alpine` | `lemp_progetti` |
| `php` | build locale da `dockerfile_php-fpm` (`php:8.2-fpm-alpine`) | `lemp_progetti_php` |
| `mariadb` | `mariadb:10.11` | `lemp_mariadb` |

Le richieste arrivano da un **Nginx Proxy esterno**, che inoltra i domini pubblici verso il container **`lemp_progetti`** sulla rete Docker esterna `nginx-proxy-network`.

---

## Prerequisiti

Prima di procedere, assicurarsi che siano installati e disponibili:

| Requisito | Versione minima | Verifica |
| --- | --- | --- |
| Docker Engine | 24.x | `docker --version` |
| Docker Compose | v2.x (plugin) | `docker compose version` |
| Git | 2.x | `git --version` |
| Accesso SSH a GitHub | — | `ssh -T git@github.com` |

> ⚠️ Lo stack **non pubblica porte verso l'host**: il traffico arriva esclusivamente dal reverse proxy esterno tramite la rete Docker `nginx-proxy-network`.

---

## Repository

Il repository ufficiale del progetto è:

```
git@github.com:filippo-bilardo/lemp_progetti.git
```

### Prima configurazione (pubblicazione iniziale)

Se stai inizializzando il repository per la prima volta da una directory locale:

```bash
git add .
git commit -m "first commit"
git branch -M main
git remote add origin git@github.com:filippo-bilardo/lemp_progetti.git
git push -u origin main
```

### Clone su una nuova macchina

Per clonare il repository su un nuovo host:

```bash
git clone git@github.com:filippo-bilardo/lemp_progetti.git
cd lemp_progetti
```

### Aggiornamento del repository

Per inviare le modifiche locali al repository remoto:

```bash
git add .
git commit -m "descrizione delle modifiche"
git push
```

> 💡 **Principio IaC**: il repository è la **fonte di verità** dell'intera infrastruttura. Qualsiasi modifica alla configurazione (Nginx, PHP, Docker Compose, script) deve essere committata prima di essere applicata in produzione.

---

## Siti attualmente serviti

Il container espone internamente questi virtual host Nginx:

| Dominio | Root nel container | Sorgente locale |
| --- | --- | --- |
| `ideeincucina.filippobilardo.it` | `/var/www/html/ideeincucina` | `./volumes/ideeincucina/www` |
| `blog.filippobilardo.it` | `/var/www/html/blog-fblabs` | `./volumes/blog-fblabs/www` |
| `viaggio-firenze-2026.filippobilardo.it` | `/var/www/html/viaggio-firenze-2026` | `./volumes/viaggio-firenze-2026/www` |

---

## Come funziona il flusso

```
Utente (HTTPS)
     │
     ▼
Nginx Proxy Manager  ←──  termina SSL, legge header Host
     │
     ▼  HTTP interno (Docker network: nginx-proxy-network)
lemp_progetti  (nginx:1.27-alpine)
     │
     ├── file statico? ──► serve direttamente
     │
     └── file PHP? ──► FastCGI → lemp_progetti_php (php:8.2-fpm-alpine)
                                        │
                                        └── DB? ──► lemp_mariadb (hostname: mariadb)
```

1. L'utente apre `https://ideeincucina.filippobilardo.it/` oppure `https://blog.filippobilardo.it/`.
2. Il [reverse proxy esterno](http://100.78.215.69:81/login) termina HTTPS e inoltra la richiesta HTTP al container `lemp_progetti`.
3. Nginx nel container seleziona il blocco `server` in base all'header `Host`.
4. Se la richiesta punta a un file statico, Nginx lo serve direttamente.
5. Se la richiesta punta a un file PHP, Nginx la inoltra a `php:9000`.
6. PHP-FPM esegue lo script usando i file montati dai bind mount locali.
7. Se necessario, l'applicazione si collega a `mariadb` tramite hostname interno Docker `mariadb`.

---

## Ricostruzione da zero

Questa sezione descrive come ricostruire l'intera infrastruttura partendo da zero su un host pulito, seguendo il principio IaC: **tutto ciò che serve è nel repository**.

### Step 1 — Clona il repository

```bash
git clone git@github.com:filippo-bilardo/lemp_progetti.git
cd lemp_progetti
```

### Step 2 — Crea la rete Docker esterna

La rete `nginx-proxy-network` deve esistere sull'host prima dell'avvio dello stack (è condivisa col reverse proxy esterno):

```bash
docker network create nginx-proxy-network
```

> ℹ️ Se la rete esiste già, il comando restituisce un errore non bloccante.

### Step 3 — Configura le variabili d'ambiente

Il file `.env` **non è versionato** (contiene segreti). Il file `.env.example` nel repository contiene tutte le variabili necessarie con valori segnaposto:

```bash
cp .env.example .env
```

Modifica `.env` valorizzando almeno:

```dotenv
MYSQL_ROOT_PASSWORD=...
MYSQL_USER=lemp
MYSQL_PASSWORD=...
MYSQL_DATABASE=ideeincucina
WEBSERVER_ADMIN_USERNAME=admin
WEBSERVER_ADMIN_PASSWORD=...
```

> ⚠️ Non committare mai il file `.env` nel repository. È già incluso in `.gitignore`.

### Step 4 — (Opzionale) Ricostruzione pulita del database

Se vuoi una ricostruzione davvero pulita del database, rimuovi il datadir persistente:

```bash
docker compose down
rm -rf ./volumes/mysql_data
```

> ℹ️ Gli script in `/docker-entrypoint-initdb.d/` vengono eseguiti **solo al primo avvio** di MariaDB su un datadir vuoto. Se `./volumes/mysql_data` esiste già, il bootstrap SQL non viene rieseguito automaticamente.

### Step 5 — Avvia lo stack

```bash
docker compose up -d --build
```

Con queste impostazioni, al primo avvio su datadir vuoto:
- MariaDB crea automaticamente il database `ideeincucina`
- L'utente applicativo riceve i grant sul database dichiarato in `.env`
- Lo schema iniziale viene caricato da `./volumes/ideeincucina/www/inst/database.sql`
- PHP usa `mariadb` come hostname interno Docker e le credenziali esposte via environment

### Riepilogo rapido (tutto in un blocco)

```bash
git clone git@github.com:filippo-bilardo/lemp_progetti.git
cd lemp_progetti
docker network create nginx-proxy-network
cp .env.example .env
# → modifica .env con i valori reali
docker compose up -d --build
```

---

## Aggiunta di nuovi siti

Per aggiungere un nuovo sito seguendo il principio IaC:

1. Crea la directory per i file del sito nel repository:
   ```bash
   mkdir -p ./volumes/nuovo-sito/www
   ```
2. Aggiungi un nuovo bind mount in `docker-compose.yml` per il nuovo sito.
3. Aggiungi un nuovo blocco `server` in `./volumes/nginx/conf.d/default.conf` con la configurazione del virtual host.
4. Committa le modifiche nel repository:
   ```bash
   git add .
   git commit -m "aggiunge virtual host nuovo-sito"
   git push
   ```
5. Riavvia lo stack per applicare le modifiche:
   ```bash
   docker compose restart
   ```
6. Nel pannello [Aruba Hosting](https://managehosting.aruba.it/), crea il nuovo dominio (es. `nuovo-sito.filippobilardo.it`) e punta i DNS verso l'IP del reverse proxy esterno (`163.192.115.36`).
7. Disabilita il sito su eventuali proxy precedenti prima di richiedere un nuovo certificato SSL.
8. Su [Nginx Proxy Manager](http://100.78.215.69:81/), aggiungi un nuovo proxy host che inoltri `nuovo-sito.filippobilardo.it` → `lemp_progetti:80`.

---

## Struttura dei servizi

### `nginx`

- Immagine: `nginx:1.27-alpine`
- Nome container: `lemp_progetti`
- Legge la configurazione da `./volumes/nginx/conf.d`
- Monta i siti in sola lettura, incluso `viaggio-firenze-2026`
- Non contiene il runtime PHP: inoltra le richieste FastCGI a `php`

### `php`

- Build locale da `dockerfile_php-fpm`
- Immagine base: `php:8.2-fpm-alpine`
- Nome container: `lemp_progetti_php`
- Monta i siti PHP in lettura/scrittura per eseguire PHP

### `mariadb`

- Immagine: `mariadb:10.11`
- Nome container: `lemp_mariadb`
- Dati persistenti in `./volumes/mysql_data`

---

## File principali

| File / Directory | Descrizione |
| --- | --- |
| `docker-compose.yml` | Definizione dichiarativa dell'intero stack |
| `dockerfile_php-fpm` | Immagine PHP-FPM custom (IaC: build riproducibile) |
| `.env.example` | Template variabili d'ambiente (versionato, senza segreti) |
| `.gitignore` | Esclude `.env`, `mysql_data` e altri artefatti locali |
| `volumes/nginx/conf.d/default.conf` | Virtual host Nginx (versionato) |
| `.dockerignore` | Build context minima per l'immagine PHP |
| `restart-with-backup.sh` | Dump DB + archivio config + restart stack |
| `volumes/ideeincucina/setup/reset-ideeincucina-admin-password.sh` | Reset password admin sito ideeincucina |

---

## Avvio e gestione

Avvio (con rebuild immagini):

```bash
docker compose up -d --build
```

Stop (preserva i volumi):

```bash
docker compose down
```

Stop con rimozione volumi (⚠️ distrugge il DB):

```bash
docker compose down -v
```

Riavvio con backup automatico:

```bash
./restart-with-backup.sh
```

Reset password admin `ideeincucina`:

```bash
./volumes/ideeincucina/setup/reset-ideeincucina-admin-password.sh 'NuovaPassword123!'
```

---

## Backup

Lo script `restart-with-backup.sh` esegue in sequenza:

1. Dump completo MariaDB in `./backup/`
2. Archivio dei file di configurazione principali
3. `docker compose restart`

> 💡 Per una strategia IaC completa, i backup del database dovrebbero essere schedulati tramite `cron` o un orchestratore esterno e archiviati in storage persistente esterno all'host.

---

## Accesso ai container

Accesso al container Nginx:

```bash
docker exec -it lemp_progetti sh
```

Accesso al container PHP-FPM:

```bash
docker exec -it lemp_progetti_php sh
```

Accesso al database MariaDB:

```bash
docker exec -it lemp_mariadb mariadb -u lemp -p
```

---

## Note operative

- Il container pubblico da usare come destinazione del proxy è **`lemp_progetti`**.
- Lo stack **non pubblica porte verso l'host**: il traffico passa esclusivamente dal reverse proxy esterno.
- La rete `nginx-proxy-network` deve esistere prima dell'avvio dello stack.
- Il file `.env` contiene segreti e **non deve mai essere committato** nel repository.
- Il file `.env.example` è il documento IaC delle variabili richieste: va tenuto aggiornato ad ogni nuova variabile introdotta.
