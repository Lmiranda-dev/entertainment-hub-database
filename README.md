# Entertainment Hub Database System

A comprehensive, enterprise-grade PostgreSQL database system designed for a modern entertainment platform supporting 30,000+ titles with infrastructure scaled for 500,000 concurrent users.

## Overview

This database system powers a complete entertainment hub platform with advanced features including AI-powered spoiler detection, sentiment analysis, community engagement, streaming integration, and sophisticated content discovery mechanisms. The system manages user interactions, content metadata, social features, and personalization at scale.

**Database Statistics:**
- **80 tables** across three major system expansions
- **8 optimized views** for complex query patterns
- **Advanced trigger systems** for real-time data processing
- **AI service integration** for content analysis and protection
- **Multi-tier architecture** supporting high concurrency

## Technical Architecture

### Database Technology
- **RDBMS:** PostgreSQL
- **Design Pattern:** Normalized relational schema with strategic denormalization for performance
- **Scalability:** Designed for 500,000 concurrent users
- **Content Capacity:** 30,000+ titles with room for expansion

### Key Features

#### 🛡️ AI-Powered Spoiler Protection System (7 tables)
- Real-time spoiler detection using AI analysis
- Context-aware spoiler warnings
- User-customizable spoiler sensitivity settings
- Episode-specific spoiler tracking
- Community-driven spoiler flagging and verification
- Machine learning integration for content safety

#### 💭 Sentiment Analysis Engine (6 tables)
- Automated sentiment scoring for reviews and discussions
- Emotion classification and tracking
- Sentiment trend analysis over time
- User sentiment profiles
- Review quality assessment
- Integration with AI services for natural language processing

#### 🎯 Content Management System (6 tables)
- Multi-format content support (movies, TV shows, anime, etc.)
- Comprehensive metadata management
- Genre and tag classification
- Content relationships and recommendations
- Production information tracking
- Release and availability management

#### 👥 Social & Community Features (11 tables across multiple systems)
- User profiles with customizable preferences
- Friend connections and social graphs
- Discussion forums and comment threads
- User-generated reviews and ratings
- Community voting and engagement metrics
- Follower/following relationships

#### 🏆 Ranking & Gamification (7 tables)
- Multi-tier points and achievement system
- User reputation and ranking
- Badge and trophy awards
- Leaderboards and competitive features
- Activity-based progression tracking
- Community recognition systems

#### 📺 Streaming Integration & Discovery (8 tables)
- Multi-platform streaming service tracking
- Content availability across platforms
- Personalized watchlists and queues
- Trending content analysis
- Discovery algorithms
- Platform-specific metadata

#### 🔐 Security & Authentication (8 tables)
- Auth0 integration for modern authentication
- Session management and token handling
- Role-based access control (RBAC)
- Security audit logging
- User activity monitoring
- API key management

#### 🛠️ Moderation & Content Reporting (5 tables)
- Comprehensive reporting system
- Content moderation workflows
- Automated and manual review processes
- Report classification and prioritization
- Moderator action tracking

#### 📝 User Preferences & Personalization (6 tables)
- Granular user preference management
- UI customization options
- Notification settings
- Content filtering preferences
- Display and accessibility options
- Cross-device preference sync

#### 🎬 Missing Content Request System (5 tables)
- Community-driven content addition requests
- Vote-based prioritization
- Request commenting and discussion
- Request status tracking and history
- Content type classification

#### 🤖 AI Enhancement Layer (4 tables)
- AI processing job queue
- Model performance tracking
- AI-generated content tags
- Machine learning model versioning

## Database Schema

### Original Core System (38 tables)

**User Management (3 tables)**
- User accounts and profiles
- User authentication data
- User settings and preferences

**Content Management (6 tables)**
- Content catalog (movies, shows, anime)
- Content metadata and attributes
- Genre and category classifications

**User-Generated Content (5 tables)**
- Reviews and ratings
- User comments and discussions
- User-created lists and collections

**Social & Interactions (6 tables)**
- Friend relationships
- Social engagement metrics
- User activity feeds

**Spoiler Protection (7 tables)**
- Spoiler detection and flagging
- Spoiler sensitivity settings
- Episode-specific spoiler tracking

**Sentiment Analysis (6 tables)**
- Sentiment scoring engine
- Emotion classification
- Sentiment trend tracking

**AI Enhancement (4 tables)**
- AI processing infrastructure
- ML model management
- AI-generated metadata

**Security (1 table)**
- Audit logs and security events

### First Expansion (37 tables)

**Ranking & Points System (7 tables)**
- User reputation and points
- Achievement tracking
- Leaderboard management

**Communities System (5 tables)**
- Community creation and management
- Community membership
- Community-specific content

**Streaming & Discovery (8 tables)**
- Streaming platform integration
- Content availability tracking
- Personalized recommendations

**Security & Authentication (7 tables)**
- Auth0 integration
- OAuth token management
- Role-based permissions

**Moderation & Reporting (5 tables)**
- Content reporting system
- Moderation workflows
- Moderator actions

**User Preferences & UI (6 tables)**
- Detailed preference management
- UI customization options
- Notification settings

### Second Expansion (5 tables)

**Missing Content Requests**
- Content request submission and tracking
- Community voting on requests
- Request discussion threads
- Request history and status
- Request type classification

### Optimized Views (8 views)

Performance-optimized views for common query patterns:
- `content_with_streaming` - Content joined with streaming availability
- `trending_content_with_details` - Trending analysis with full metadata
- `user_profiles_with_stats` - Complete user profiles with engagement statistics
- `spoiler_safe_reviews` - Reviews with spoiler protection applied
- `sentiment_enhanced_reviews` - Reviews with sentiment analysis data
- `user_recently_viewed` - User viewing history with content details
- `discussion_summaries_with_content` - Discussion threads with context
- `admin_request_dashboard` - Administrative overview of content requests

## Advanced Features

### Trigger Systems
- Real-time data validation and integrity enforcement
- Automated timestamp management
- Cascade operations for related data
- Event-driven notifications
- Denormalization triggers for performance optimization

### Stored Procedures & Functions
- Complex business logic encapsulation
- Batch processing operations
- Data aggregation and reporting
- Search and recommendation algorithms

### Indexing Strategy
- Composite indexes for common query patterns
- Full-text search indexes
- Partial indexes for filtered queries
- GiST/GIN indexes for advanced data types

### Data Integrity
- Foreign key constraints across all relationships
- Check constraints for data validation
- Unique constraints for business rules
- Transaction isolation for concurrent operations

## Performance Considerations

**Scalability Features:**
- Indexed foreign keys for join performance
- Materialized views for expensive queries
- Partitioning strategies for large tables
- Query optimization for high-concurrency scenarios
- Connection pooling support

**Caching Strategy:**
- Frequently accessed data identified for application-level caching
- View-based caching for complex aggregations
- Session data optimization

## Setup Instructions

### Prerequisites
- PostgreSQL 12+ (recommended: PostgreSQL 14+)
- pgAdmin or another PostgreSQL client (optional)
- Minimum 4GB RAM for development environment
- 20GB+ disk space for full dataset

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/YOUR-USERNAME/entertainment-hub-database.git
cd entertainment-hub-database
```

2. **Create the database**
```bash
createdb entertainment_hub
```

3. **Run the schema creation scripts**
```bash
psql -d entertainment_hub -f schema/01_core_tables.sql
psql -d entertainment_hub -f schema/02_expansion_tables.sql
psql -d entertainment_hub -f schema/03_views.sql
psql -d entertainment_hub -f schema/04_triggers.sql
psql -d entertainment_hub -f schema/05_indexes.sql
```

4. **Load sample data (optional)**
```bash
psql -d entertainment_hub -f data/sample_data.sql
```

5. **Verify installation**
```bash
psql -d entertainment_hub -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
# Should return 80 tables
```

## Sample Queries

### Get trending content with streaming availability
```sql
SELECT * FROM trending_content_with_details 
WHERE trending_score > 0.7 
ORDER BY trending_score DESC 
LIMIT 10;
```

### Find spoiler-safe reviews for a specific show
```sql
SELECT * FROM spoiler_safe_reviews 
WHERE content_id = 123 
AND spoiler_level <= 'LOW'
ORDER BY sentiment_score DESC;
```

### User profile with complete statistics
```sql
SELECT * FROM user_profiles_with_stats 
WHERE user_id = 456;
```

### Most requested missing content
```sql
SELECT 
    mcr.title,
    mcr.request_type,
    COUNT(crv.vote_id) as vote_count,
    mcr.status
FROM missing_content_requests mcr
LEFT JOIN content_request_votes crv ON mcr.request_id = crv.request_id
GROUP BY mcr.request_id, mcr.title, mcr.request_type, mcr.status
ORDER BY vote_count DESC
LIMIT 20;
```

## Project Context

This database system was developed as part of a Google-affiliated senior design project at Florida International University. The system was designed to support an entertainment platform serving 30,000+ titles with infrastructure capable of handling 500,000 concurrent users.

**Key Design Decisions:**
- Chose PostgreSQL for robust ACID compliance and advanced features
- Implemented AI integration points for modern content analysis
- Designed for horizontal scalability and high availability
- Prioritized data integrity while maintaining performance
- Built with security and privacy as foundational principles

## Use Cases

This database architecture supports:
- **Content Discovery Platforms** - Comprehensive metadata and recommendation systems
- **Social Entertainment Networks** - User engagement and community features
- **Streaming Aggregators** - Multi-platform content availability tracking
- **Review Platforms** - Advanced sentiment analysis and spoiler protection
- **Community-Driven Content Sites** - User-generated content and moderation

## Technologies & Integration Points

- **PostgreSQL** - Primary database management system
- **AI/ML Services** - Spoiler detection and sentiment analysis integration
- **Auth0** - Modern authentication and authorization
- **RESTful APIs** - Application layer integration ready
- **Analytics Platforms** - Data export and business intelligence support

## Future Enhancements

Potential expansion areas:
- GraphQL API layer for flexible querying
- Time-series data for advanced analytics
- Geographic content availability tracking
- Multi-language support for international content
- Advanced recommendation algorithms using collaborative filtering
- Real-time notification system integration
- Content similarity matching using vector embeddings

## Documentation

Additional documentation can be found in the `/docs` directory:
- `ER_DIAGRAM.md` - Complete entity-relationship diagrams
- `API_INTEGRATION.md` - Guidelines for application integration
- `PERFORMANCE_TUNING.md` - Query optimization strategies
- `SECURITY.md` - Security implementation details
- `MIGRATION_GUIDE.md` - Database version migration procedures

## Contributing

This is an academic portfolio project and is not currently accepting contributions. However, feel free to fork the repository and adapt it for your own projects.

## License

This project is available under the MIT License. See LICENSE file for details.

## Contact

**Luis** - Computer Engineering Graduate, Florida International University (2025)

For questions or collaboration opportunities, please reach out via GitHub issues or connect on LinkedIn.

---

**Note:** This database contains no real user data. All sample data is anonymized and generated for demonstration purposes only.
