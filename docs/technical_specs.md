# Entertainment Hub Database
## Technical Specifications

**Project**: Spoiler-Free Entertainment Discussion Platform  
**Database Version**: 1.3.0  
**Total Tables**: 80  
**Last Updated**: July 27, 2025

---

## Table of Contents

1. [Database Architecture](#database-architecture)
2. [System Requirements](#system-requirements)
3. [Performance Metrics](#performance-metrics)
4. [Storage Estimates](#storage-estimates)
5. [Technology Stack](#technology-stack)
6. [Feature Support Matrix](#feature-support-matrix)

---

## Database Architecture

### Overview

**Database Engine**: PostgreSQL 13.x or higher  
**Hosting Platform**: Amazon AWS RDS  
**Architecture Type**: Relational Database (RDBMS)

### Schema Statistics

| Metric | Count |
|--------|-------|
| **Total Tables** | 80 |
| **Materialized Views** | 8 |
| **Performance Indexes** | 200+ |
| **Stored Procedures** | 15+ |
| **Triggers** | 10+ |
| **Sequences** | 80 |
| **Foreign Key Constraints** | 150+ |
| **Check Constraints** | 50+ |

### Table Organization by Category

| Category | Tables | Purpose |
|----------|--------|---------|
| User Management | 3 | User accounts, preferences, social connections |
| Content Management | 6 | Movies, TV shows, genres, trailers |
| User-Generated Content | 5 | Reviews, comments, watchlists, favorites |
| Ranking & Points System | 7 | Gamification, tier progression, activity tracking |
| Communities System | 5 | Discussion groups, posts, memberships |
| Streaming & Discovery | 8 | Platform availability, trending algorithms, roulette |
| Spoiler Protection System | 7 | Progress tracking, AI detection, reporting |
| Sentiment Analysis System | 6 | Emotion tracking, AI-powered analysis |
| AI Enhancement | 4 | GPT summaries, recommendations, API usage |
| Security & Authentication | 7 | Auth0 integration, sessions, notifications |
| Moderation & Reporting | 5 | Content/user reports, moderation actions |
| User Preferences & UI | 6 | View settings, filters, UI customization |
| Analytics & Performance | 8 | Sessions, interactions, discovery metrics |
| Missing Content Requests | 5 | User requests, voting, admin workflow |
| **TOTAL** | **80** | |

### Key Relationships

**User → Content**: One-to-many (users create reviews, comments, posts)  
**Content → Genres**: Many-to-many (movies/shows have multiple genres)  
**Content → Platforms**: Many-to-many (available on multiple streaming services)  
**Users → Communities**: Many-to-many (users join multiple communities)  
**Users → Points/Tiers**: One-to-one (each user has one point record)  
**Content → Progress**: One-to-many (users track progress per content)

---

## System Requirements

### Minimum Requirements (Development Environment)

**Database Server**:
- PostgreSQL 13.0 or higher
- CPU: 2 cores
- RAM: 4 GB
- Storage: 50 GB SSD
- Network: 100 Mbps

**Application Server**:
- Node.js 16+ or Python 3.8+
- CPU: 2 cores
- RAM: 4 GB
- Storage: 20 GB SSD

**Supported Operating Systems**:
- Ubuntu 20.04 LTS or higher
- macOS 11 (Big Sur) or higher
- Windows 10/11 (with WSL2)
- Amazon Linux 2

### Recommended Requirements (Staging Environment)

**Database Server**:
- PostgreSQL 14.0 or higher
- CPU: 4 cores
- RAM: 8 GB
- Storage: 200 GB SSD
- Network: 1 Gbps

**Application Server**:
- Node.js 18+ or Python 3.10+
- CPU: 4 cores
- RAM: 8 GB
- Storage: 50 GB SSD

### Production Requirements (AWS RDS)

**Database Instance**:
- Instance Class: `db.r5.xlarge` or higher
- PostgreSQL Version: 14.x or 15.x
- vCPUs: 4+
- Memory: 32 GB RAM minimum
- Storage: 500 GB GP3 SSD
- IOPS: 3000 baseline
- Multi-AZ: Enabled
- Backup Retention: 7-30 days
- Enhanced Monitoring: Enabled

**Application Servers** (AWS EC2):
- Instance Type: `t3.large` or higher
- vCPUs: 2+
- Memory: 8 GB RAM
- Storage: 100 GB
- Auto-scaling: 2-10 instances
- Load Balancer: Application Load Balancer

### Network Requirements

**Security**:
- SSL/TLS encryption required
- VPC with private subnets for database
- Security groups properly configured
- Port 5432 open for PostgreSQL (internal only)
- Bastion host for database access

**Bandwidth**:
- Development: 10 Mbps minimum
- Staging: 100 Mbps minimum
- Production: 1 Gbps minimum

### Software Dependencies

**Required PostgreSQL Extensions**:
```sql
-- Performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Full-text search capabilities
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Advanced indexing
CREATE EXTENSION IF NOT EXISTS btree_gin;
```

**Optional Extensions**:
```sql
-- UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

---

## Performance Metrics

### Expected Query Performance

| Query Type | Target Time | Description |
|-----------|-------------|-------------|
| Simple Lookups (by ID) | < 5ms | Direct primary key queries |
| User Authentication | < 10ms | Username/email lookup with join |
| Content Search | < 50ms | Full-text search with filters |
| User Feed Generation | < 100ms | Complex joins with 20-50 results |
| Trending Calculation | < 200ms | Aggregation with window functions |
| Complex Analytics | < 500ms | Multi-table joins with aggregations |
| Batch Operations | < 2s | Bulk inserts/updates (100+ rows) |

### Concurrent User Capacity

| Environment | Users | Notes |
|-------------|-------|-------|
| Development | 10-50 | Single instance, no load balancing |
| Staging | 100-500 | Simulates production load |
| Production (Initial) | 1,000-5,000 | Single database instance |
| Production (Scaled) | 10,000-50,000 | Read replicas + connection pooling |
| Production (High Scale) | 50,000+ | Sharding + caching layer required |

### Connection Pool Settings

**Recommended Pool Sizes**:
```javascript
// Development
{
  max: 5,
  min: 1,
  idleTimeoutMillis: 30000
}

// Staging
{
  max: 20,
  min: 5,
  idleTimeoutMillis: 30000
}

// Production
{
  max: 100,  // Per application instance
  min: 10,
  idleTimeoutMillis: 10000,
  connectionTimeoutMillis: 5000
}
```

### Throughput Benchmarks

**Transactions Per Second (TPS)**:
- **Read Operations**: 5,000-10,000 TPS
- **Write Operations**: 1,000-2,000 TPS
- **Mixed Workload**: 3,000-5,000 TPS

---

## Storage Estimates

### Empty Database Size

**Initial Schema**: ~50 MB
- Tables: ~10 MB
- Indexes: ~15 MB
- System catalogs: ~25 MB

### Growth Projections

**Per 1,000 Active Users**:
- User data: ~10 MB
- User preferences: ~5 MB
- User activity logs: ~15 MB
- Social connections: ~8 MB
- **Subtotal**: ~40 MB per 1K users

**Per 10,000 Movies/Shows**:
- Content metadata: ~50 MB
- Genre associations: ~20 MB
- Streaming availability: ~30 MB
- Trailers/media links: ~20 MB
- **Subtotal**: ~120 MB per 10K items

**Per 100,000 Reviews**:
- Review text: ~150 MB
- Comments: ~100 MB
- Interactions (likes): ~30 MB
- Sentiment data: ~20 MB
- **Subtotal**: ~300 MB per 100K reviews

### Production Scale Examples

**Small Scale** (10K users, 5K content, 50K reviews):
- Database: ~5 GB
- Indexes: ~2 GB
- **Total**: ~7 GB

**Medium Scale** (100K users, 50K content, 500K reviews):
- Database: ~15 GB
- Indexes: ~5 GB
- **Total**: ~20 GB

**Large Scale** (500K users, 200K content, 5M reviews):
- Database: ~80 GB
- Indexes: ~30 GB
- **Total**: ~110 GB

**Enterprise Scale** (1M+ users, 500K+ content, 20M+ reviews):
- Database: ~250 GB
- Indexes: ~100 GB
- **Total**: ~350 GB

---

## Technology Stack

### Core Database

**PostgreSQL 13.x - 15.x**
- ACID compliant
- Advanced indexing (B-tree, GiST, GIN, BRIN)
- Full-text search
- JSON/JSONB support
- Window functions
- Common Table Expressions (CTEs)
- Materialized views

### Hosting & Infrastructure

**Primary**: Amazon AWS RDS for PostgreSQL
- Multi-AZ deployments
- Automated backups
- Point-in-time recovery
- Read replicas
- Performance Insights
- Enhanced monitoring

**Alternative Options**:
- Google Cloud SQL for PostgreSQL
- Azure Database for PostgreSQL
- Self-hosted on AWS EC2
- DigitalOcean Managed Databases

### External Services Integration

**Authentication**:
- Auth0 (primary)
- AWS Cognito
- Firebase Auth

**Streaming Platforms**:
- Netflix (via partner API)
- Hulu API
- Disney+ Content API
- Max (HBO Max) API
- Prime Video API
- Apple TV+ API

**AI Services**:
- OpenAI GPT-4 API
- Anthropic Claude API
- Hugging Face Models
- AWS Comprehend (sentiment)
- Custom ML models

---

## Feature Support Matrix

### Core Features

| Feature | Status | Tables Used |
|---------|--------|-------------|
| User Registration & Authentication | ✅ Complete | users, auth0_users, auth0_sessions |
| Content Management (Movies/Shows) | ✅ Complete | movies, shows, genres, trailers |
| User Reviews & Ratings | ✅ Complete | reviews, comments |
| Watchlists & Favorites | ✅ Complete | watchlists, watchlist_items, favorites |
| 5-Tier Ranking System | ✅ Complete | ranking_tiers, user_points, point_transactions |
| Communities & Discussions | ✅ Complete | communities, community_posts, community_memberships |
| Streaming Platform Integration | ✅ Complete | streaming_platforms, content_platform_availability |
| Trending Algorithms | ✅ Complete | trending_content, user_interactions |
| Spoiler Protection | ✅ Complete | content_progress, spoiler_reports, ai_spoiler_analysis |
| Sentiment Analysis | ✅ Complete | sentiment_tags, ai_sentiment_analysis |
| AI Content Summaries | ✅ Complete | gpt_summaries, gpt_api_usage |
| Content Recommendations | ✅ Complete | augmented_recommendations |
| Moderation Tools | ✅ Complete | user_reports, content_reports, moderation_actions |
| Missing Content Requests | ✅ Complete | missing_content_requests, content_request_votes |

### Security Features

- ✅ Auth0 integration for enterprise SSO
- ✅ Multi-factor authentication support
- ✅ Role-based access control (User, Moderator, Admin, Super Admin)
- ✅ Session management with expiration
- ✅ Brute force protection
- ✅ Password hashing (bcrypt with salt)
- ✅ SSL/TLS encryption in transit
- ✅ Encryption at rest (AWS RDS)
- ✅ GDPR compliance
- ✅ Audit trails for all moderation actions

---

**Entertainment Hub Database v1.3.0**  
**Technical Specifications**  
**80 Tables | Production Ready**