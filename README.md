# Kenshimota Backup Mysql

## Repository

<a href = "https://github.com/kenshimota/backup-mysql-8.git">
    https://github.com/kenshimota/backup-mysql-8.git
</a>

## Enviroment

### For Database

- <b>DB_NAME</b> is the database name
- <b>DB_USERNAME</b> is the database username
- <b>DB_PASSWORD</b> is the database password
- <b>DB_HOSTNAME</b> is the database hostname
- <b>DB_PORT</b> is the database port, which usually is 3306

### For time

- <b>BACKUP_SCHEDULE</b> is the list of times (24h format) when backups run each day, for example: <code>"10:00 20:00"</code>
- <b>BACKUP_TIMEZONE</b> is optional and defines the timezone used by the schedule, for example: <code>UTC</code>

### Amazon Web Service

- <b>AWS_ACCESS_KEY_ID</b> is the amazon access key
- <b>AWS_SECRET_ACCESS_KEY</b> is the
- <b>AWS_DEFAULT_REGION</b> is the region where is your machine, for example us-east-2
- <b>AWS_BUCKET</b> is the bucket name in S3, for example mybucket
- <b>AWS_PREFIX</b> is the bucket prefix in S3, for example myprefix

### Cleanup Backup

- <b>EXPIRATE*IN_MONTHS* is a number that indicates how many months the backups will be kept. For example, if the value is 3, the backups older than 3 months will be deleted from the S3 bucket.
