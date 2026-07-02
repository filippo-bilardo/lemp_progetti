#!/bin/bash
# =============================================================================
# newapp.sh — Aggiunge una nuova applicazione web allo stack LEMP
# =============================================================================
#
# Uso:  ./newapp.sh
#       ./newapp.sh --help
#
# Cosa fa:
#   1. Crea la struttura  volumes/<slug>/www/
#   2. Genera il virtual host Nginx  volumes/nginx/conf.d/<dominio>.conf
#   3. Aggiunge i bind mount in docker-compose.yml  (nginx + php)
#   4. (opzionale) Crea il database MariaDB:
#        - aggiunge DB_<SLUG> in .env.example e .env
#        - aggiunge il blocco CREATE DATABASE in
#          volumes/<slug>/setup/mysql_<slug>/init.sql
#        - aggiunge le variabili env a mariadb e php in docker-compose.yml
#   5. Crea un file index placeholder (php o html)
#   6. Mostra riepilogo e prossimi passi
#
# Dipendenze: bash, python3  (già disponibili su Ubuntu)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Colori ----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "   ${BLUE}ℹ  $*${NC}"; }
success() { echo -e "   ${GREEN}✅ $*${NC}"; }
warn()    { echo -e "   ${YELLOW}⚠  $*${NC}"; }
err()     { echo -e "\n   ${RED}❌ ERRORE: $*${NC}\n"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}▸ $*${NC}"; }
hr()      { echo -e "${CYAN}────────────────────────────────────────────────${NC}"; }

# --- Help ------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo ""
    echo "  newapp.sh — Aggiunge una nuova app allo stack LEMP"
    echo ""
    echo "  Uso: ./newapp.sh"
    echo ""
    echo "  Modifica automaticamente:"
    echo "    volumes/<slug>/www/                         cartella sito"
    echo "    volumes/nginx/conf.d/<dominio>.conf         virtual host Nginx"
    echo "    docker-compose.yml                          bind mount nginx + php"
    echo "    volumes/<slug>/setup/mysql_<slug>/init.sql       CREATE DATABASE per-app (opz.)"
    echo "    .env.example / .env                         DB_<SLUG>=... (opz.)"
    echo "    .env_<slug>                                 file env dedicato app"
    echo "    APPS.md                                     registro applicazioni"
    echo "    volumes/<slug>/setup/mysql_<slug>/          init SQL per-app (opz.)"
    echo ""
    exit 0
fi

# =============================================================================
# 1. RACCOLTA PARAMETRI
# =============================================================================
echo ""
hr
echo -e "${BOLD}   newapp.sh — Nuova applicazione su stack LEMP${NC}"
hr
echo ""

# --- Slug ---
while true; do
    read -p "  Slug app  (nome cartella, es: miosito): " APP_SLUG
    APP_SLUG="${APP_SLUG,,}"            # lowercase
    APP_SLUG="${APP_SLUG// /-}"         # spazi → trattini
    APP_SLUG="${APP_SLUG//[^a-z0-9-]/}" # solo alfanumerici e trattini
    [[ -z "$APP_SLUG" ]]              && { warn "Lo slug non può essere vuoto."; continue; }
    [[ -d "volumes/${APP_SLUG}" ]]    && { warn "volumes/${APP_SLUG} esiste già. Scegli un altro slug."; continue; }
    break
done

# --- Dominio ---
while true; do
    read -p "  Dominio   (es: miosito.filippobilardo.it): " DOMAIN
    [[ -z "$DOMAIN" ]]                                     && { warn "Il dominio non può essere vuoto."; continue; }
    [[ -f "volumes/nginx/conf.d/${DOMAIN}.conf" ]]         && { warn "${DOMAIN}.conf esiste già."; continue; }
    break
done

# --- Tipo app ---
echo ""
echo "  Tipo applicazione:"
echo "    1) PHP + Statico  — serve PHP e file statici  (default)"
echo "    2) Solo Statico   — solo HTML/CSS/JS, nessun PHP"
read -p "  Scelta [1/2, invio=1]: " APP_TYPE_CHOICE
case "${APP_TYPE_CHOICE:-1}" in
    2) APP_TYPE="static" ;;
    *) APP_TYPE="php"    ;;
esac

# --- Routing URL ---
echo ""
if [ "$APP_TYPE" = "php" ]; then
    echo "  Routing URL:"
    echo "    1) Standard  — try_files → /index.php   (CMS, framework Laravel/WP)  (default)"
    echo "    2) SPA       — try_files → /index.html  (React / Vue / Angular)"
    echo "    3) Strict    — 404 se il file non esiste"
    read -p "  Scelta [1/2/3, invio=1]: " ROUTING_CHOICE
    case "${ROUTING_CHOICE:-1}" in
        2) ROUTING="spa"      ;;
        3) ROUTING="strict"   ;;
        *) ROUTING="standard" ;;
    esac
else
    echo "  Routing URL:"
    echo "    1) SPA     — try_files → /index.html  (default)"
    echo "    2) Strict  — 404 se il file non esiste"
    read -p "  Scelta [1/2, invio=1]: " ROUTING_CHOICE
    case "${ROUTING_CHOICE:-1}" in
        2) ROUTING="strict" ;;
        *) ROUTING="spa"    ;;
    esac
fi

# --- Database ---
HAS_DB="n"; DB_NAME=""; DB_VAR=""
if [ "$APP_TYPE" = "php" ]; then
    echo ""
    read -p "  Database MariaDB necessario? (y/N): " HAS_DB_ANSWER
    if [[ "${HAS_DB_ANSWER,,}" =~ ^y ]]; then
        HAS_DB="y"
        DB_DEFAULT="${APP_SLUG//-/_}"
        read -p "  Nome database (invio=${DB_DEFAULT}): " DB_NAME_INPUT
        DB_NAME="${DB_NAME_INPUT:-$DB_DEFAULT}"
        DB_VAR="DB_$(echo "${APP_SLUG}" | tr '[:lower:]-' '[:upper:]_')"
    fi
fi

# --- Index placeholder ---
echo ""
read -p "  Creare file index placeholder? (Y/n): " CREATE_INDEX_ANSWER
CREATE_INDEX="y"
[[ "${CREATE_INDEX_ANSWER,,}" =~ ^n ]] && CREATE_INDEX="n"

# --- Riepilogo ---
echo ""
hr
echo -e "${BOLD}   Riepilogo${NC}"
hr
echo "   Slug:         ${APP_SLUG}"
echo "   Dominio:      ${DOMAIN}"
echo "   Tipo:         ${APP_TYPE}"
echo "   Routing:      ${ROUTING}"
if [ "$HAS_DB" = "y" ]; then
    echo "   Database:     ${DB_NAME}  →  var: \${${DB_VAR}}"
else
    echo "   Database:     no"
fi
echo "   Index:        $([ "$CREATE_INDEX" = "y" ] && echo 'sì' || echo 'no')"
echo ""
read -p "  Procedere? (Y/n): " CONFIRM
[[ "${CONFIRM,,}" =~ ^n ]] && { echo "  Annullato."; exit 0; }

# =============================================================================
# 2. ESECUZIONE
# =============================================================================
echo ""
hr
echo -e "${BOLD}   Creazione...${NC}"
hr

# ---------------------------------------------------------------------------
# 2a. Struttura cartelle
# ---------------------------------------------------------------------------
step "Struttura cartelle"
mkdir -p "volumes/${APP_SLUG}/www"
success "volumes/${APP_SLUG}/www/"
if [ "$HAS_DB" = "y" ]; then
    mkdir -p "volumes/${APP_SLUG}/setup/mysql_${APP_SLUG}"
    success "volumes/${APP_SLUG}/setup/mysql_${APP_SLUG}/"
fi

# ---------------------------------------------------------------------------
# 2b. Virtual host Nginx
# ---------------------------------------------------------------------------
step "Virtual host Nginx"

NGINX_CONF="volumes/nginx/conf.d/${DOMAIN}.conf"

# Genera il blocco location in base a tipo + routing
build_location_block() {
    if [ "$APP_TYPE" = "php" ]; then
        case "$ROUTING" in
            standard)
                cat << 'BLOCK'
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index  index.php;
        fastcgi_pass   php:9000;
    }
BLOCK
                ;;
            spa)
                cat << 'BLOCK'
    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~ \.php$ {
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index  index.php;
        fastcgi_pass   php:9000;
    }
BLOCK
                ;;
            strict)
                cat << 'BLOCK'
    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        try_files      $uri =404;
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index  index.php;
        fastcgi_pass   php:9000;
    }
BLOCK
                ;;
        esac
    else
        # static
        case "$ROUTING" in
            spa)
                cat << 'BLOCK'
    location / {
        try_files $uri $uri/ /index.html;
    }
BLOCK
                ;;
            strict)
                cat << 'BLOCK'
    location / {
        try_files $uri $uri/ =404;
    }
BLOCK
                ;;
        esac
    fi
}

{
    echo "server {"
    echo "    listen 80;"
    echo "    server_name ${DOMAIN};"
    echo ""
    echo "    root /var/www/html/${APP_SLUG};"
    echo "    index index.php index.html index.htm;"
    echo ""
    build_location_block
    echo ""
    echo "    location ~ /\.(?!well-known) {"
    echo "        deny all;"
    echo "    }"
    echo "}"
} > "$NGINX_CONF"

success "${NGINX_CONF}"

# ---------------------------------------------------------------------------
# 2c. Index placeholder
# ---------------------------------------------------------------------------
if [ "$CREATE_INDEX" = "y" ]; then
    step "File index placeholder"
    if [ "$APP_TYPE" = "php" ]; then
        {
            echo '<?php'
            echo "// Placeholder — ${APP_SLUG}"
            echo "// Dominio: ${DOMAIN}"
            echo "// Generato da newapp.sh il $(date '+%d/%m/%Y')"
            echo '?>'
            echo '<!DOCTYPE html>'
            echo '<html lang="it">'
            echo '<head>'
            echo "    <meta charset=\"UTF-8\">"
            echo "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
            echo "    <title>${APP_SLUG}</title>"
            echo '</head>'
            echo '<body>'
            echo "    <h1>${APP_SLUG}</h1>"
            echo "    <p>Dominio: <strong>${DOMAIN}</strong></p>"
            echo '    <p>PHP: <?php echo phpversion(); ?></p>'
            echo "    <p><em>Placeholder generato da newapp.sh</em></p>"
            echo '</body>'
            echo '</html>'
        } > "volumes/${APP_SLUG}/www/index.php"
        success "volumes/${APP_SLUG}/www/index.php"
    else
        {
            echo '<!DOCTYPE html>'
            echo '<html lang="it">'
            echo '<head>'
            echo "    <meta charset=\"UTF-8\">"
            echo "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
            echo "    <title>${APP_SLUG}</title>"
            echo '</head>'
            echo '<body>'
            echo "    <h1>${APP_SLUG}</h1>"
            echo "    <p>Dominio: <strong>${DOMAIN}</strong></p>"
            echo "    <p><em>Placeholder generato da newapp.sh il $(date '+%d/%m/%Y')</em></p>"
            echo '</body>'
            echo '</html>'
        } > "volumes/${APP_SLUG}/www/index.html"
        success "volumes/${APP_SLUG}/www/index.html"
    fi
fi

# ---------------------------------------------------------------------------
# 2d. Patch docker-compose.yml  (Python3 — manipolazione YAML affidabile)
# ---------------------------------------------------------------------------
step "Aggiornamento docker-compose.yml"

export APP_SLUG APP_TYPE HAS_DB DB_NAME DB_VAR

python3 << 'PYEOF'
import os, sys

app_slug = os.environ['APP_SLUG']
app_type = os.environ['APP_TYPE']
has_db   = os.environ['HAS_DB']
db_name  = os.environ.get('DB_NAME', '')
db_var   = os.environ.get('DB_VAR', '')

DC = 'docker-compose.yml'

with open(DC, 'r') as f:
    content = f.read()

errors = []

def insert_before(text, marker, new_line):
    if marker not in text:
        errors.append(f"Marker non trovato in {DC}: '{marker}'")
        return text
    return text.replace(marker, new_line + '\n' + marker)

# 1. Nginx: aggiunge volume :ro
nginx_marker = '      # <<< newapp: nginx volumes >>>'
nginx_vol    = f'      - ./volumes/{app_slug}/www:/var/www/html/{app_slug}:ro'
content = insert_before(content, nginx_marker, nginx_vol)

# 2. PHP: aggiunge volume (solo per app PHP)
if app_type == 'php':
    php_vol_marker = '      # <<< newapp: php volumes >>>'
    php_vol        = f'      - ./volumes/{app_slug}/www:/var/www/html/{app_slug}'
    content = insert_before(content, php_vol_marker, php_vol)

# 3. MariaDB env + PHP env (solo se ha DB)
if has_db == 'y':
    # Variabile bash: ${DB_MIOSITO:-miosito}
    bash_var = '${' + db_var + ':-' + db_name + '}'

    # MariaDB environment
    mariadb_marker = '      # <<< newapp: mariadb env >>>'
    mariadb_env    = f'      {db_var}:{" " * (13 - len(db_var))}${{{db_var}:-{db_name}}}'
    content = insert_before(content, mariadb_marker, mariadb_env)

    # MariaDB volume: per-app init SQL
    mariadb_vol_marker = '      # <<< newapp: mariadb volumes >>>'
    init_sql_path = f'./volumes/{app_slug}/setup/mysql_{app_slug}/init.sql'
    mariadb_vol   = f'      - {init_sql_path}:/docker-entrypoint-initdb.d/20-{app_slug}.sql:ro'
    content = insert_before(content, mariadb_vol_marker, mariadb_vol)

    # PHP environment
    php_env_marker = '      # <<< newapp: php env >>>'
    var_suffix     = db_var.replace('DB_', '')
    php_env        = f'      DB_NAME_{var_suffix}: ${{{db_var}:-{db_name}}}  # {app_slug}'
    content = insert_before(content, php_env_marker, php_env)

if errors:
    for e in errors:
        print(f'   ⚠  {e}')
    sys.exit(1)

with open(DC, 'w') as f:
    f.write(content)

print('   ✅ docker-compose.yml aggiornato')
PYEOF

# ---------------------------------------------------------------------------
# 2e. Database: .env.example, .env, init.sql
# ---------------------------------------------------------------------------
if [ "$HAS_DB" = "y" ]; then
    step "Configurazione database"

    # .env.example — aggiunge la nuova variabile nella sezione DB
    {
        echo ""
        echo "# Database: ${APP_SLUG}"
        echo "${DB_VAR}=${DB_NAME}"
    } >> .env.example
    success ".env.example  →  aggiunta ${DB_VAR}=${DB_NAME}"

    # .env — aggiunge la variabile se il file esiste
    if [ -f .env ]; then
        {
            echo ""
            echo "# Database: ${APP_SLUG}"
            echo "${DB_VAR}=${DB_NAME}"
        } >> .env
        success ".env  →  aggiunta ${DB_VAR}=${DB_NAME}"
    else
        warn ".env non trovato — ricordati di aggiungerlo dopo: cp .env.example .env"
    fi

    # init.sql per-app — crea setup/mysql_<slug>/init.sql con CREATE DATABASE + GRANT
    MYSQL_DIR="volumes/${APP_SLUG}/setup/mysql_${APP_SLUG}"
    INIT_SQL="${MYSQL_DIR}/init.sql"
    {
        echo "-- ============================================================================="
        echo "-- init.sql — Bootstrap database per ${APP_SLUG}"
        echo "-- Generato da newapp.sh il $(date '+%d/%m/%Y')"
        echo "-- ============================================================================="
        echo ""
        echo "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
        echo "    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        echo "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${MYSQL_USER}'@'%';"
        echo ""
    } > "${INIT_SQL}"
    success "${INIT_SQL}"

fi

# ---------------------------------------------------------------------------
# 2f. App tracking — .env_<slug> + APPS.md
# ---------------------------------------------------------------------------
step "Registrazione app"

# Crea .env_<slug>
ENV_FILE=".env_${APP_SLUG}"
{
    echo "# App metadata — locale (escluso da git, vedi .gitignore)"
    echo "APP_SLUG=${APP_SLUG}"
    echo "APP_DOMAIN=${DOMAIN}"
    echo "APP_TYPE=${APP_TYPE}"
    echo "DB_NAME=${DB_NAME}"
    echo "DB_VAR=${DB_VAR}"
    echo "DB_USER=\${MYSQL_USER}"
    echo "DB_PASSWORD=\${MYSQL_PASSWORD}"
} > "${ENV_FILE}"
success "${ENV_FILE}"

# Appende a APPS.md
DB_INIT_SQL="volumes/${APP_SLUG}/setup/mysql_${APP_SLUG}/init.sql"
if [ "$HAS_DB" = "y" ] && [ -f "${DB_INIT_SQL}" ]; then
    INIT_SQL_REF="${DB_INIT_SQL}"
else
    INIT_SQL_REF="-"
fi
DB_NAME_DISPLAY="${DB_NAME:--}"
DB_VAR_DISPLAY="${DB_VAR:--}"

echo "| ${APP_SLUG} | ${DOMAIN} | ${APP_TYPE} | ${DB_NAME_DISPLAY} | ${INIT_SQL_REF} | ${ENV_FILE} |" >> APPS.md
success "APPS.md  →  aggiunta riga per ${APP_SLUG}"

# =============================================================================
# 3. RIEPILOGO FINALE E PROSSIMI PASSI
# =============================================================================
echo ""
hr
echo -e "${BOLD}   Completato! 🎉${NC}"
hr
echo ""
echo -e "   ${BOLD}File creati / modificati:${NC}"
echo "    ✅ volumes/${APP_SLUG}/www/"
echo "    ✅ volumes/nginx/conf.d/${DOMAIN}.conf"
[ "$APP_TYPE" = "php" ] && echo "    ✅ docker-compose.yml  (mount nginx :ro + php)"  \
                        || echo "    ✅ docker-compose.yml  (mount nginx :ro)"
echo "    ✅ .env_${APP_SLUG}"
echo "    ✅ APPS.md"
if [ "$HAS_DB" = "y" ]; then
    echo "    ✅ .env.example  (${DB_VAR}=${DB_NAME})"
    [ -f .env ] && echo "    ✅ .env  (${DB_VAR}=${DB_NAME})"
    echo "    ✅ volumes/${APP_SLUG}/setup/mysql_${APP_SLUG}/init.sql"
fi

echo ""
echo -e "   ${BOLD}Prossimi passi:${NC}"
STEP=1

echo "   ${STEP}. Ricarica Nginx per attivare il nuovo virtual host:"
echo "      docker exec lemp_progetti nginx -s reload"
STEP=$((STEP+1))

if [ "$APP_TYPE" = "php" ]; then
    echo ""
    echo "   ${STEP}. Riavvia lo stack per montare il nuovo volume PHP:"
    echo "      ./manage.sh restart"
    STEP=$((STEP+1))
fi

if [ "$HAS_DB" = "y" ]; then
    echo ""
    echo "   ${STEP}. Database '${DB_NAME}':"
    echo "      • Al prossimo avvio su datadir VUOTO viene creato automaticamente."
    echo "      • Se MariaDB è già in esecuzione, crealo adesso:"
    echo "        ./manage.sh mariadb-root"
    DB_USER=$(grep '^MYSQL_USER=' .env 2>/dev/null | cut -d= -f2 || echo 'lemp')
    echo "        > CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    echo "        > GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';"
    echo "        > FLUSH PRIVILEGES;"
    STEP=$((STEP+1))
fi

echo ""
echo "   ${STEP}. DNS: punta ${DOMAIN} → 163.192.115.36  (IP reverse proxy)"
STEP=$((STEP+1))
echo ""
echo "   ${STEP}. Nginx Proxy Manager: aggiungi proxy host"
echo "      ${DOMAIN}  →  lemp_progetti:80"
STEP=$((STEP+1))

echo ""
echo "   ${STEP}. Committa le modifiche IaC:"
echo "      git add ."
echo "      git commit -m \"feat: aggiunge app ${APP_SLUG} (${DOMAIN})\""
echo "      git push"
echo ""
hr
