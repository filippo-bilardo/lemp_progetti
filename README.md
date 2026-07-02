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

Il container espone internamente i virtual host Nginx elencati in [APPS.md](APPS.md).

| Slug | Dominio | Database | Init SQL |
| --- | --- | --- | --- |
| `ideeincucina` | `ideeincucina.filippobilardo.it` | `ideeincucina` | `volumes/ideeincucina/setup/mysql_ideeincucina/init.sql` |
| `blog-fblabs` | `blog.filippobilardo.it` | `blog_fblabs` | - |
| `viaggio-firenze-2026` | `viaggio-firenze-2026.filippobilardo.it` | - | - |

> 💡 Per l'elenco completo e aggiornato, consulta [APPS.md](APPS.md). Ogni app ha un file `.env_<slug>` con i propri metadati (dominio, tipo, database).

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

Lo script `manage.sh` gestisce in modo **idempotente** tutti i passi della ricostruzione: può essere rieseguito senza effetti collaterali.

### Metodo rapido — `./manage.sh setup`

```bash
git clone git@github.com:filippo-bilardo/lemp_progetti.git
cd lemp_progetti
./manage.sh setup
```

Al primo avvio, `setup` crea `.env` da `.env.example` e si ferma chiedendo di valorizzare le variabili:

```bash
# → apri .env e imposta le password reali
nano .env

# riesegui per completare il deploy
./manage.sh setup
```

### Cosa fa `./manage.sh setup` — passo per passo

| Passo | Azione | Idempotente |
| --- | --- | --- |
| 1 | Crea la rete Docker `nginx-proxy-network` (se non esiste) | ✅ |
| 2 | Crea `.env` da `.env.example` (se assente), poi si ferma per la configurazione | ✅ |
| 3 | Chiede se rimuovere `./volumes/mysql_data/` per un bootstrap DB pulito | ✅ |
| 4 | Esegue `docker compose up -d --build` | ✅ |

Con un datadir vuoto, al primo avvio MariaDB esegue automaticamente gli script SQL in ordine alfabetico da ogni app in `setup/mysql_<slug>/init.sql`:
- `volumes/ideeincucina/setup/mysql_ideeincucina/init.sql` → crea DB + schema ideeincucina
- `volumes/blog-fblabs/setup/mysql_blog-fblabs/init.sql` → crea DB blog_fblabs

### Configurazione `.env`

Dopo il primo `./manage.sh setup`, valorizza nel file `.env` almeno:

```dotenv
MYSQL_ROOT_PASSWORD=...
MYSQL_USER=lemp
MYSQL_PASSWORD=...

# Un database per sito — aggiungi variabili al crescere dello stack
DB_IDEEINCUCINA=ideeincucina
DB_BLOG_FBLABS=blog_fblabs

WEBSERVER_ADMIN_USERNAME=admin
WEBSERVER_ADMIN_PASSWORD=...
```

> ⚠️ `MYSQL_DATABASE` è stata **rimossa**: supportava un solo database, rompendo il principio IaC per stack multi-sito. La gestione multi-database avviene tramite script SQL per-app in `volumes/<slug>/setup/mysql_<slug>/init.sql`.

> 💡 **Aggiungere un nuovo database** = aggiungere `DB_<SITO>=nome_db` in `.env.example` e `.env`, poi creare `volumes/<slug>/setup/mysql_<slug>/init.sql` con CREATE DATABASE + GRANT.

> ⚠️ Non committare mai il file `.env` nel repository. È già incluso in `.gitignore`.

> 💡 I file `.env_<slug>` (es. `.env_ideeincucina`) contengono metadati pubblici dell'app (slug, dominio, tipo, database) e **sono tracciati in git**. Fanno da registro machine-readable delle applicazioni.

---

## Aggiunta di nuovi siti

Per aggiungere un nuovo sito, usa lo script interattivo `newapp.sh`:

```bash
./newapp.sh
```

Lo script segue il principio IaC e automatizza tutti i passi:

| Passo | Azione |
| --- | --- |
| 1 | Crea `volumes/<slug>/www/` — directory del sito |
| 2 | Crea `volumes/nginx/conf.d/<dominio>.conf` — virtual host Nginx |
| 3 | Crea `volumes/<slug>/setup/mysql_<slug>/init.sql` — init SQL per-app (CREATE DATABASE + GRANT) |
| 4 | Aggiorna `docker-compose.yml` — bind mount nginx, php e init SQL |
| 5 | Aggiorna `.env.example` / `.env` — variabile `DB_<SLUG>` (se con DB) |
| 6 | Crea `.env_<slug>` — file metadati app (tracciato in git) |
| 7 | Aggiorna `APPS.md` — registro applicazioni |

Dopo aver eseguito `newapp.sh`:

1. Ricarica Nginx:
   ```bash
   docker exec lemp_progetti nginx -s reload
   ```
2. Se l'app usa PHP, riavvia lo stack:
   ```bash
   ./manage.sh restart
   ```
3. Se l'app usa database e MariaDB è già in esecuzione, crealo manualmente:
   ```bash
   ./manage.sh mariadb-root
   ```
4. Committa le modifiche IaC:
   ```bash
   git add .
   git commit -m "feat: aggiunge app <slug> (<dominio>)"
   git push
   ```
5. Nel pannello [Aruba Hosting](https://managehosting.aruba.it/), crea il nuovo dominio (es. `nuovo-sito.filippobilardo.it`) e punta i DNS verso l'IP del reverse proxy esterno (`163.192.115.36`).
6. Su [Nginx Proxy Manager](http://100.78.215.69:81/), aggiungi un nuovo proxy host che inoltri `nuovo-sito.filippobilardo.it` → `lemp_progetti:80`.

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
| `manage.sh` | Script di gestione: `setup`, `start`, `stop`, `build`, `logs`, shell, dump DB… |
| `newapp.sh` | Script interattivo per aggiungere nuove applicazioni |
| `.env.example` | Template variabili d'ambiente (versionato, senza segreti) |
| `.gitignore` | Traccia i file IaC in `volumes/`; esclude `.env`, `mysql_data`, siti |
| `.env_<slug>` | Metadati per-app (slug, dominio, tipo, db) — tracciati in git |
| `APPS.md` | Registro di tutte le applicazioni gestite |
| `volumes/nginx/conf.d/*.conf` | Configurazione virtual host Nginx (IaC, versionata) |
| `volumes/<slug>/setup/mysql_<slug>/init.sql` | Init SQL per-app (CREATE DATABASE + GRANT + schema) |
| `volumes/<slug>/mysql_<slug>/init.sql` | Init SQL per-app (schema/bootstrap database) |
| `.dockerignore` | Build context minima per l'immagine PHP |

---

## Avvio e gestione

Tutti i comandi passano attraverso `manage.sh`:

```bash
# Prima installazione / ricostruzione da zero
./manage.sh setup

# Avvio (con rebuild immagini)
./manage.sh build && ./manage.sh start
# oppure direttamente:
docker compose up -d --build

# Stop (preserva i dati in ./volumes/)
./manage.sh stop

# Riavvio rapido
./manage.sh restart

# Elenco applicazioni registrate
./manage.sh apps

# Log in tempo reale
./manage.sh logs

# Stato container
./manage.sh status
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
