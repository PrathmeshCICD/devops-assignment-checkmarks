job('Timestamp Job') {
    triggers {
        cron('H/5 * * * *')
    }
    label('kubernetes')
    steps {
        shell('''
#!/bin/bash
# Create table if not exists
psql "postgres://postgres:drow@postgresql.devops.svc.cluster.local:5432/devops?sslmode=disable" -c "CREATE TABLE IF NOT EXISTS timestamps (id SERIAL PRIMARY KEY, timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"
# Insert current timestamp
psql "postgres://postgres:drow@postgresql.devops.svc.cluster.local:5432/devops?sslmode=disable" -c "INSERT INTO timestamps (timestamp) VALUES (NOW());"
''')
    }
}