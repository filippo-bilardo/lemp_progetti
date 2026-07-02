#!/bin/bash
# =============================================================================
# manage.sh — Script di gestione stack LEMP Progetti
# Versione: 2.0 - 02/07/26 - Filippo Bilardo
#
# Utilizzo: ./manage.sh <comando> [opzioni]
# =============================================================================

# Carica .env se presente (non obbligatorio: setup funziona anche senza)
[ -f .env ] && source .env

NOME_APP="LEMP Progetti"

# Legge gli URL delle app dai file .env_* (dinamico)
APPS_URLS=()
for f in .env_*; do
    [ -f "$f" ] || continue
    source "$f"
    [ -n "$APP_DOMAIN" ] && APPS_URLS+=("http://${APP_DOMAIN}")
done

# =============================================================================
show_usage() {
# =============================================================================
    echo ""
    echo "Script di gestione — ${NOME_APP}"
    echo ""
    echo "Utilizzo: $0 <comando> [opzioni]"
    echo ""
    echo "Comandi di deploy:"
    echo "  setup             - Ricostruzione da zero (IaC): rete → .env → stack"
    echo "  start             - Avvia lo stack: docker compose up -d"
    echo "  stop              - Ferma e rimuove i container: docker compose down"
    echo "  restart           - Riavvia i container: docker compose restart"
    echo "  build             - Ricostruisce le immagini: docker compose build --no-cache"
    echo "  status            - Stato dei container: docker compose ps"
    echo "  logs              - Log in tempo reale (mariadb, php, nginx)"
    echo ""
    echo "Comandi di accesso:"
    echo "  nginx-shell       - Shell nel container nginx (sh)"
    echo "  php-shell         - Shell nel container php (sh)"
    echo "  mariadb-shell     - Shell nel container mariadb (sh)"
    echo "  mariadb-root      - Accesso MariaDB come root"
    echo ""
    echo "Comandi database:"
    echo "  mariadb-list-db               - Lista tutti i database"
    echo "  mariadb-dump-db <database>    - Dump di un database in ./backup/"
    echo "  mariadb-restore-db <file.sql> - Ripristino da dump"
    echo ""
    echo "Comandi di pulizia:"
    echo "  apps              - Elenca tutte le applicazioni registrate"
    echo ""
    echo "Comandi di pulizia:"
    echo "  clean             - Rimuove container, immagini e volumi (doppia conferma)"
    echo ""
    echo "Esempi:"
    echo "  $0 setup"
    echo "  $0 start"
    echo "  $0 mariadb-dump-db ideeincucina"
    echo "  $0 mariadb-restore-db backup/backup_ideeincucina_250702_120000.sql"
    echo ""
}

case "$1" in

# =============================================================================
# DEPLOY
# =============================================================================

    setup)
        # -----------------------------------------------------------------
        # Ricostruzione da zero — IaC compliant
        # Idempotente: può essere rieseguito senza effetti collaterali.
        # -----------------------------------------------------------------
        echo ""
        echo "🏗️  Setup — Ricostruzione da zero (${NOME_APP})"
        echo "══════════════════════════════════════════════"
        echo ""

        # 1. Rete Docker esterna
        echo "1️⃣  Verifica rete Docker 'nginx-proxy-network'..."
        docker network create nginx-proxy-network 2>/dev/null \
            && echo "   ✅ Rete 'nginx-proxy-network' creata." \
            || echo "   ℹ️  Rete 'nginx-proxy-network' già esistente."
        echo ""

        # 2. File .env
        echo "2️⃣  Verifica file .env..."
        if [ ! -f .env ]; then
            cp .env.example .env
            echo "   ✅ File .env creato da .env.example."
            echo ""
            echo "   ⚠️  Apri .env e imposta le password reali, poi riesegui:"
            echo "      nano .env"
            echo "      ./manage.sh setup"
            echo ""
            exit 0
        else
            echo "   ℹ️  File .env presente."
            source .env
        fi
        echo ""

        # 3. Pulizia opzionale datadir MariaDB
        echo "3️⃣  Pulizia datadir MariaDB (opzionale)..."
        if [ -d "./volumes/mysql_data" ] && [ "$(ls -A ./volumes/mysql_data 2>/dev/null | grep -v '.gitkeep')" ]; then
            echo "   Il datadir './volumes/mysql_data/' contiene dati esistenti."
            echo "   Rimuoverli forza il rieseguimento del bootstrap SQL al prossimo avvio."
            read -p "   Rimuovere i dati MariaDB per un avvio pulito? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker compose down 2>/dev/null || true
                rm -rf ./volumes/mysql_data/*
                echo "   🗑️  Dati MariaDB rimossi. Il bootstrap SQL verrà rieseguito."
            else
                echo "   ℹ️  Dati MariaDB conservati (bootstrap SQL non verrà rieseguito)."
            fi
        else
            echo "   ℹ️  Datadir vuoto o assente: il bootstrap SQL verrà eseguito al primo avvio."
        fi
        echo ""

        # 4. Build e avvio stack
        echo "4️⃣  Build e avvio stack..."
        echo "   docker compose up -d --build"
        docker compose up -d --build
        echo ""
        echo "✅ Setup completato!"
        echo ""
        for url in "${APPS_URLS[@]}"; do echo "🌐 ${url}"; done
        echo ""
        ;;

    start)
        echo "🚀 Avvio stack ${NOME_APP}..."
        echo "   docker compose up -d"
        docker compose up -d
        echo "✅ Stack avviato!"
        for url in "${APPS_URLS[@]}"; do echo "🌐 ${url}"; done
        ;;

    stop)
        echo "⏹️  Arresto stack ${NOME_APP}..."
        echo "   Ferma e rimuove tutti i container. I dati in ./volumes/ sono conservati."
        read -p "⚠️  Sei sicuro? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Operazione annullata."
            exit 1
        fi
        docker compose down
        echo ""
        read -p "🗑️  Vuoi eliminare anche i dati MariaDB? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf volumes/mysql_data/*
            echo "🗑️  Dati MariaDB eliminati."
        fi
        echo "✅ Stack arrestato."
        ;;

    restart)
        echo "🔄 Riavvio stack ${NOME_APP}..."
        docker compose restart
        echo "✅ Stack riavviato."
        ;;

    build)
        echo "🔨 Rebuild immagini ${NOME_APP}..."
        docker compose build --no-cache
        echo "✅ Immagini ricostruite."
        ;;

    status)
        echo "📊 Stato dei container:"
        echo ""
        docker compose ps
        ;;

    logs)
        echo "📋 Log stack ${NOME_APP} (Ctrl+C per uscire):"
        docker compose logs -f --tail=100 --timestamps mariadb php nginx
        ;;

# =============================================================================
# ACCESSO AI CONTAINER
# =============================================================================

    nginx-shell)
        echo "🐚 Shell container nginx..."
        docker compose exec nginx sh
        ;;

    php-shell)
        echo "🐚 Shell container php..."
        docker compose exec php sh
        ;;

    mariadb-shell)
        echo "🐚 Shell container mariadb..."
        docker compose exec mariadb sh
        ;;

    mariadb-root)
        echo "🗄️  Accesso MariaDB come root..."
        docker compose exec mariadb mysql -u root -p"${MYSQL_ROOT_PASSWORD}"
        ;;

# =============================================================================
# DATABASE
# =============================================================================

    mariadb-list-db)
        echo "🗄️  Database presenti in MariaDB:"
        docker compose exec mariadb mysql -u root -p"${MYSQL_ROOT_PASSWORD}" \
            -e "SHOW DATABASES;" 2>/dev/null
        ;;

    mariadb-dump-db)
        if [ -z "$2" ]; then
            echo "❌ Specifica il nome del database:"
            echo "   $0 mariadb-dump-db <database>"
            exit 1
        fi
        mkdir -p backup
        DUMP_FILE="backup/backup_${2}_$(date +%y%m%d_%H%M%S).sql"
        echo "🔹 Dump database '$2' → ${DUMP_FILE} ..."
        docker exec lemp_mariadb mysqldump \
            -u root -p"${MYSQL_ROOT_PASSWORD}" "$2" > "${DUMP_FILE}"
        if [ $? -eq 0 ]; then
            echo "✅ Dump completato: ${DUMP_FILE}"
        else
            echo "❌ Errore durante il dump."
            exit 1
        fi
        ;;

    mariadb-restore-db)
        if [ -z "$2" ]; then
            echo "❌ Specifica il file di dump:"
            echo "   $0 mariadb-restore-db <file.sql>"
            exit 1
        fi
        if [ ! -f "$2" ]; then
            echo "❌ File non trovato: $2"
            exit 1
        fi
        echo "🔹 Ripristino database '${MYSQL_DATABASE:-ideeincucina}' da '$2'..."
        docker exec -i lemp_mariadb mysql \
            -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_IDEEINCUCINA:-ideeincucina}" < "$2"
        if [ $? -eq 0 ]; then
            echo "✅ Ripristino completato."
        else
            echo "❌ Errore durante il ripristino."
            exit 1
        fi
        ;;

# =============================================================================
# APP
# =============================================================================

    apps)
        echo ""
        echo "📋 Applicazioni registrate:"
        echo ""
        if [ -f APPS.md ]; then
            # Estrae la tabella da APPS.md (salta header e separatore)
            sed -n '4,$p' APPS.md | while IFS='|' read -r slug dominio tipo db init_sql env_file; do
                slug="${slug// /}"; dominio="${dominio// /}"
                [ -z "$slug" ] && continue
                printf "   %-25s %s\n" "${slug}" "${dominio}"
            done
        else
            echo "   (nessuna app registrata in APPS.md)"
        fi
        echo ""
        ;;

# =============================================================================
# PULIZIA
# =============================================================================

    clean)
        echo "🧹 Pulizia completa — container, immagini e volumi"
        read -p "⚠️  Sei sicuro? Questo rimuoverà tutti i container e le immagini. (y/N): " -n 1 -r
        echo
        read -p "⚠️  Confermi di voler procedere? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker compose down --rmi all --volumes --remove-orphans
            echo "✅ Pulizia completata."
        else
            echo "❌ Operazione annullata."
        fi
        ;;

    *)
        show_usage
        exit 1
        ;;
esac
