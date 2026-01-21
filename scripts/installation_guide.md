# Entertainment Hub Database
## Installation Guide

**Database Version**: 1.3.0  
**Total Tables**: 80  
**Last Updated**: July 27, 2025

---

## Table of Contents

1. [Local Development Setup](#local-development-setup)
2. [AWS RDS Setup](#aws-rds-setup)
3. [Database Configuration](#database-configuration)
4. [Initial Setup Steps](#initial-setup-steps)
5. [Connection Testing](#connection-testing)

---

## Local Development Setup

### Step 1: Install PostgreSQL

#### macOS (using Homebrew)
```bash
# Install PostgreSQL
brew install postgresql@14

# Start PostgreSQL service
brew services start postgresql@14

# Verify installation
psql --version
```

#### Ubuntu/Debian
```bash
# Update package list
sudo apt update

# Install PostgreSQL
sudo apt install postgresql-14 postgresql-contrib-14

# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Verify installation
psql --version
```

#### Windows

1. Download PostgreSQL installer from: https://www.postgresql.org/download/windows/
2. Run the installer
3. Follow installation wizard
4. Remember the password you set for the `postgres` user
5. Add PostgreSQL to PATH (usually done automatically)

### Step 2: Create Database and User
```bash
# Connect to PostgreSQL as superuser
sudo -u postgres psql

# Or on Windows/macOS:
psql -U postgres
```

Once connected, run these SQL commands:
```sql
-- Create the database
CREATE DATABASE entertainment_hub;

-- Create a dedicated user
CREATE USER entertainment_user WITH PASSWORD 'your_secure_password_here';

-- Grant all privileges on the database
GRANT ALL PRIVILEGES ON DATABASE entertainment_hub TO entertainment_user;

-- Connect to the new database
\c entertainment_hub

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO entertainment_user;

-- Grant default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON TABLES TO entertainment_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON SEQUENCES TO entertainment_user;

-- Exit psql
\q
```

### Step 3: Enable Required Extensions

Connect to your database:
```bash
psql -U entertainment_user -d entertainment_hub
```

Enable extensions:
```sql
-- Performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Full-text search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Advanced indexing
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Optional: UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Optional: Cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Verify extensions
\dx
```

Expected output:
```
                                      List of installed extensions
       Name       | Version |   Schema   |                        Description                        
------------------+---------+------------+-----------------------------------------------------------
 btree_gin        | 1.3     | public     | support for indexing common datatypes in GIN
 pg_stat_statements | 1.9   | public     | track planning and execution statistics of all SQL statements
 pg_trgm          | 1.6     | public     | text similarity measurement and index searching based on trigrams
 plpgsql          | 1.0     | pg_catalog | PL/pgSQL procedural language
```

### Step 4: Configure PostgreSQL (Optional Performance Tuning)

Edit PostgreSQL configuration file:

**Location**:
- macOS: `/opt/homebrew/var/postgresql@14/postgresql.conf`
- Ubuntu: `/etc/postgresql/14/main/postgresql.conf`
- Windows: `C:\Program Files\PostgreSQL\14\data\postgresql.conf`

**Recommended settings for development**:
```conf
# Memory Settings
shared_buffers = 256MB              # 25% of RAM
effective_cache_size = 1GB          # 75% of RAM
work_mem = 4MB
maintenance_work_mem = 64MB

# Connection Settings
max_connections = 100

# Performance
random_page_cost = 1.1              # For SSD
effective_io_concurrency = 200      # For SSD

# Logging
log_min_duration_statement = 1000   # Log queries slower than 1 second
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'none'

# Query Planning
default_statistics_target = 100
```

After editing, restart PostgreSQL:
```bash
# macOS
brew services restart postgresql@14

# Ubuntu
sudo systemctl restart postgresql

# Windows - use Services app or:
net stop postgresql-x64-14
net start postgresql-x64-14
```

---

## AWS RDS Setup

### Step 1: Create RDS Instance via AWS Console

1. **Navigate to RDS Console**:
   - Go to AWS Console → RDS → Create database

2. **Choose Database Creation Method**:
   - Select "Standard create"

3. **Engine Options**:
   - Engine type: PostgreSQL
   - Version: PostgreSQL 14.7 (or latest 14.x)

4. **Templates**:
   - Production (for production)
   - Dev/Test (for staging)

5. **Settings**:
   - DB instance identifier: `entertainment-hub-prod`
   - Master username: `entertainment_admin`
   - Master password: [Generate secure password]
   - Confirm password

6. **DB Instance Class**:
   - Burstable classes: `db.t3.medium` (for dev/test)
   - Memory optimized: `db.r5.xlarge` (for production)

7. **Storage**:
   - Storage type: General Purpose SSD (gp3)
   - Allocated storage: 500 GB
   - Storage autoscaling: Enable (max 1000 GB)
   - Provisioned IOPS: 3000

8. **Availability & Durability**:
   - Multi-AZ deployment: Yes (for production)

9. **Connectivity**:
   - Virtual private cloud (VPC): Select your VPC
   - Subnet group: Create new or select existing
   - Public access: No (recommended)
   - VPC security group: Create new
   - Availability Zone: No preference

10. **Database Authentication**:
    - Password authentication

11. **Additional Configuration**:
    - Initial database name: `entertainment_hub`
    - DB parameter group: default.postgres14
    - Backup retention period: 7-30 days
    - Backup window: 03:00-04:00 UTC
    - Enhanced monitoring: Enable
    - Enable auto minor version upgrade: Yes
    - Maintenance window: Sunday 04:00-05:00 UTC
    - Deletion protection: Enable (for production)

12. **Click "Create database"**

### Step 2: Create RDS Instance via AWS CLI
```bash
# Set variables
AWS_REGION="us-east-1"
DB_IDENTIFIER="entertainment-hub-prod"
DB_NAME="entertainment_hub"
DB_USERNAME="entertainment_admin"
DB_PASSWORD="YourSecurePassword123!"
VPC_SECURITY_GROUP_ID="sg-xxxxxxxxx"
DB_SUBNET_GROUP="your-subnet-group"

# Create RDS instance
aws rds create-db-instance \
    --db-instance-identifier $DB_IDENTIFIER \
    --db-instance-class db.r5.xlarge \
    --engine postgres \
    --engine-version 14.7 \
    --master-username $DB_USERNAME \
    --master-user-password $DB_PASSWORD \
    --allocated-storage 500 \
    --storage-type gp3 \
    --iops 3000 \
    --db-name $DB_NAME \
    --vpc-security-group-ids $VPC_SECURITY_GROUP_ID \
    --db-subnet-group-name $DB_SUBNET_GROUP \
    --multi-az \
    --backup-retention-period 30 \
    --preferred-backup-window "03:00-04:00" \
    --preferred-maintenance-window "sun:04:00-sun:05:00" \
    --enable-cloudwatch-logs-exports '["postgresql","upgrade"]' \
    --storage-encrypted \
    --monitoring-interval 60 \
    --monitoring-role-arn "arn:aws:iam::YOUR_ACCOUNT_ID:role/rds-monitoring-role" \
    --enable-performance-insights \
    --performance-insights-retention-period 7 \
    --deletion-protection \
    --tags Key=Environment,Value=Production Key=Project,Value=EntertainmentHub \
    --region $AWS_REGION

# Wait for instance to be available (takes 10-15 minutes)
aws rds wait db-instance-available \
    --db-instance-identifier $DB_IDENTIFIER \
    --region $AWS_REGION

echo "RDS instance created successfully!"
```

### Step 3: Configure Security Group
```bash
# Get your IP address
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Allow PostgreSQL access from your IP (for initial setup only)
aws ec2 authorize-security-group-ingress \
    --group-id $VPC_SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5432 \
    --cidr $MY_IP/32 \
    --region $AWS_REGION

# Allow access from application servers (use security group)
aws ec2 authorize-security-group-ingress \
    --group-id $VPC_SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5432 \
    --source-group sg-app-servers-xxxxx \
    --region $AWS_REGION
```

### Step 4: Create Custom Parameter Group
```bash
# Create parameter group
aws rds create-db-parameter-group \
    --db-parameter-group-name entertainment-hub-params \
    --db-parameter-group-family postgres14 \
    --description "Custom parameters for Entertainment Hub" \
    --region $AWS_REGION

# Modify parameters for optimization
aws rds modify-db-parameter-group \
    --db-parameter-group-name entertainment-hub-params \
    --parameters \
        "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
        "ParameterName=max_connections,ParameterValue=200,ApplyMethod=immediate" \
        "ParameterName=work_mem,ParameterValue=4096,ApplyMethod=immediate" \
        "ParameterName=maintenance_work_mem,ParameterValue=65536,ApplyMethod=immediate" \
        "ParameterName=effective_cache_size,ParameterValue=8388608,ApplyMethod=immediate" \
        "ParameterName=random_page_cost,ParameterValue=1.1,ApplyMethod=immediate" \
    --region $AWS_REGION

# Apply parameter group to RDS instance
aws rds modify-db-instance \
    --db-instance-identifier $DB_IDENTIFIER \
    --db-parameter-group-name entertainment-hub-params \
    --apply-immediately \
    --region $AWS_REGION

# Reboot to apply parameters requiring restart
aws rds reboot-db-instance \
    --db-instance-identifier $DB_IDENTIFIER \
    --region $AWS_REGION
```

### Step 5: Get RDS Endpoint
```bash
# Get RDS endpoint address
aws rds describe-db-instances \
    --db-instance-identifier $DB_IDENTIFIER \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text \
    --region $AWS_REGION

# Output example:
# entertainment-hub-prod.c9akl3sfsv2a.us-east-1.rds.amazonaws.com
```

### Step 6: Connect to RDS Instance
```bash
# Set your RDS endpoint
RDS_ENDPOINT="entertainment-hub-prod.c9akl3sfsv2a.us-east-1.rds.amazonaws.com"

# Connect via psql
psql -h $RDS_ENDPOINT \
     -p 5432 \
     -U entertainment_admin \
     -d entertainment_hub

# You'll be prompted for the password
```

---

## Database Configuration

### Environment Variables Setup

Create a `.env` file in your project root:
```bash
# Database Configuration
DB_HOST=localhost                    # Or your RDS endpoint
DB_PORT=5432
DB_NAME=entertainment_hub
DB_USER=entertainment_user          # Or entertainment_admin for RDS
DB_PASSWORD=your_secure_password
DB_SSL=false                        # Set to 'true' for RDS

# Connection Pool
DB_POOL_MIN=5
DB_POOL_MAX=20

# Application
NODE_ENV=development
PORT=4000

# Auth0
AUTH0_DOMAIN=your-domain.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret

# AWS (if using S3, CloudWatch, etc.)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

### Connection Configuration (Node.js)

Create `config/database.js`:
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'entertainment_hub',
  user: process.env.DB_USER || 'entertainment_user',
  password: process.env.DB_PASSWORD,
  
  // Connection pool settings
  max: parseInt(process.env.DB_POOL_MAX) || 20,
  min: parseInt(process.env.DB_POOL_MIN) || 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
  
  // SSL configuration (required for RDS)
  ssl: process.env.DB_SSL === 'true' ? {
    rejectUnauthorized: false
  } : false,
  
  // Application name for monitoring
  application_name: 'entertainment_hub_api',
  
  // Query timeout
  statement_timeout: 30000,
});

// Test connection
pool.on('connect', (client) => {
  console.log('✓ New database connection established');
});

pool.on('error', (err, client) => {
  console.error('✗ Unexpected error on idle client', err);
  process.exit(-1);
});

// Export pool
module.exports = pool;
```

### Connection Configuration (Python)

Create `config/database.py`:
```python
import os
import psycopg2
from psycopg2 import pool

class Database:
    def __init__(self):
        self.connection_pool = psycopg2.pool.SimpleConnectionPool(
            minconn=int(os.getenv('DB_POOL_MIN', 5)),
            maxconn=int(os.getenv('DB_POOL_MAX', 20)),
            host=os.getenv('DB_HOST', 'localhost'),
            port=os.getenv('DB_PORT', 5432),
            database=os.getenv('DB_NAME', 'entertainment_hub'),
            user=os.getenv('DB_USER', 'entertainment_user'),
            password=os.getenv('DB_PASSWORD'),
            sslmode='require' if os.getenv('DB_SSL') == 'true' else 'disable',
            application_name='entertainment_hub_api',
            connect_timeout=10
        )
    
    def get_connection(self):
        return self.connection_pool.getconn()
    
    def return_connection(self, connection):
        self.connection_pool.putconn(connection)
    
    def close_all_connections(self):
        self.connection_pool.closeall()

# Create singleton instance
db = Database()
```

---

## Initial Setup Steps

### Step 1: Verify Database Connection
```bash
# Test connection
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();"

# Expected output:
# PostgreSQL 14.7 on x86_64-pc-linux-gnu...
```

### Step 2: Set Database Permissions
```sql
-- Connect as superuser (postgres or RDS master user)
\c entertainment_hub

-- Grant permissions to your application user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO entertainment_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO entertainment_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO entertainment_user;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON TABLES TO entertainment_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT ALL ON SEQUENCES TO entertainment_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT EXECUTE ON FUNCTIONS TO entertainment_user;
```

### Step 3: Enable Extensions
```sql
-- Connect to your database
\c entertainment_hub

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Verify extensions
SELECT extname, extversion FROM pg_extension;
```

---

## Connection Testing

### Basic Connection Test

Create `test_connection.js`:
```javascript
const pool = require('./config/database');

async function testConnection() {
  try {
    // Test simple query
    const result = await pool.query('SELECT NOW() as current_time, version() as pg_version');
    console.log('✓ Database connection successful!');
    console.log('Current time:', result.rows[0].current_time);
    console.log('PostgreSQL version:', result.rows[0].pg_version);
    
    // Test connection pool
    const poolInfo = await pool.query(`
      SELECT 
        count(*) as total_connections,
        count(*) FILTER (WHERE state = 'active') as active_connections,
        count(*) FILTER (WHERE state = 'idle') as idle_connections
      FROM pg_stat_activity 
      WHERE datname = current_database()
    `);
    console.log('\nConnection pool status:');
    console.log(poolInfo.rows[0]);
    
    process.exit(0);
  } catch (error) {
    console.error('✗ Database connection failed:', error.message);
    process.exit(1);
  }
}

testConnection();
```

Run the test:
```bash
node test_connection.js
```

### Python Connection Test

Create `test_connection.py`:
```python
from config.database import db

def test_connection():
    try:
        # Get connection from pool
        conn = db.get_connection()
        cursor = conn.cursor()
        
        # Test simple query
        cursor.execute("SELECT NOW() as current_time, version() as pg_version")
        result = cursor.fetchone()
        
        print("✓ Database connection successful!")
        print(f"Current time: {result[0]}")
        print(f"PostgreSQL version: {result[1]}")
        
        # Clean up
        cursor.close()
        db.return_connection(conn)
        
    except Exception as error:
        print(f"✗ Database connection failed: {error}")
        exit(1)

if __name__ == "__main__":
    test_connection()
```

---

## Troubleshooting

### Common Issues

**Issue 1: Connection Refused**
```
Error: connect ECONNREFUSED 127.0.0.1:5432
```

Solution:
- Check if PostgreSQL is running: `pg_isready`
- Verify port: `lsof -i :5432` (macOS/Linux)
- Check `postgresql.conf` for `listen_addresses`

**Issue 2: Authentication Failed**
```
Error: password authentication failed for user "entertainment_user"
```

Solution:
- Verify password is correct
- Check `pg_hba.conf` for authentication method
- Reset password if needed: `ALTER USER entertainment_user PASSWORD 'newpassword';`

**Issue 3: Database Does Not Exist**
```
Error: database "entertainment_hub" does not exist
```

Solution:
- Create database: `CREATE DATABASE entertainment_hub;`
- Verify connection string has correct database name

**Issue 4: Extension Cannot Be Created**
```
Error: permission denied to create extension "pg_stat_statements"
```

Solution:
- Connect as superuser (postgres) and create extension
- Or grant CREATE privilege: `GRANT CREATE ON DATABASE entertainment_hub TO entertainment_user;`

**Issue 5: AWS RDS Connection Timeout**
```
Error: timeout expired
```

Solution:
- Check security group allows traffic on port 5432
- Verify RDS instance is publicly accessible (if connecting from outside VPC)
- Use bastion host or VPN for private RDS instances
- Check network ACLs

---

## Next Steps

After successful installation:

1. ✅ Run deployment scripts to create all 80 tables
2. ✅ Run verification script to confirm setup
3. ✅ Configure application connection
4. ✅ Set up backup automation
5. ✅ Configure monitoring

Proceed to **File 3: Deployment Scripts**

---

**Entertainment Hub Database v1.3.0**  
**Installation Guide Complete**