#!/bin/bash
# =============================================================================
# 10-create-databases.sh — Bootstrap multi-database MariaDB
#
# IaC: ogni sito dichiara il proprio database tramite variabili d'ambiente.
# Questo script viene eseguito automaticamente dal container MariaDB
# SOLO al primo avvio su un datadir vuoto (directory /var/lib/mysql vuota).
#
# Per aggiungere un nuovo database:
#   1. Aggiungi la variabile DB_<SITO>=nome_db in .env e .env.example
#   2. Aggiungi un blocco CREATE DATABASE / GRANT qui sotto
#   3. Committa nel repository (è un file IaC)
#   4. Rimuovi ./volumes/mysql_data/ e riavvia per rieseguire il bootstrap
# =============================================================================

set -e

echo "🗄️  Bootstrap: creazione database applicativi..."

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL

    -- -------------------------------------------------------------------------
    -- Database: ideeincucina
    -- -------------------------------------------------------------------------
    CREATE DATABASE IF NOT EXISTS \`${DB_IDEEINCUCINA:-ideeincucina}\`
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \`${DB_IDEEINCUCINA:-ideeincucina}\`.* TO '${MYSQL_USER}'@'%';

    -- -------------------------------------------------------------------------
    -- Database: blog-fblabs
    -- -------------------------------------------------------------------------
    CREATE DATABASE IF NOT EXISTS \`${DB_BLOG:-blog_fblabs}\`
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \`${DB_BLOG:-blog_fblabs}\`.* TO '${MYSQL_USER}'@'%';

    -- -------------------------------------------------------------------------
    -- Aggiungi qui i database dei nuovi siti seguendo lo stesso pattern
    -- -------------------------------------------------------------------------

    FLUSH PRIVILEGES;
EOSQL

echo "✅  Database creati: ${DB_IDEEINCUCINA:-ideeincucina}, ${DB_BLOG:-blog_fblabs}"
