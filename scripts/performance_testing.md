# Entertainment Hub Database
## Performance Testing

**Database Version**: 1.3.0  
**Total Tables**: 80  
**Last Updated**: July 27, 2025

---

## Table of Contents

1. [Load Testing Setup](#load-testing-setup)
2. [Test Data Generation](#test-data-generation)
3. [Performance Benchmarks](#performance-benchmarks)
4. [Query Performance Tests](#query-performance-tests)
5. [Connection Pool Testing](#connection-pool-testing)
6. [Stress Testing](#stress-testing)

---

## Load Testing Setup

### Prerequisites
```sql
-- Enable pg_stat_statements for query monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

### Helper Functions
```sql
-- Function to cleanup test data
CREATE OR REPLACE FUNCTION cleanup_test_data()
RETURNS void AS $$
BEGIN
    DELETE FROM users WHERE username LIKE 'test_user_%';
    DELETE FROM movies WHERE title LIKE 'Test Movie %';
    DELETE FROM shows WHERE title LIKE 'Test Show %';
    DELETE FROM reviews WHERE review_text LIKE 'Test review%';
    DELETE FROM user_interactions WHERE user_id IN (
        SELECT user_id FROM users WHERE username LIKE 'test_user_%'
    );
    
    RAISE NOTICE 'Test data cleaned up successfully';
END;
$$ LANGUAGE plpgsql;

-- Function to get database statistics
CREATE OR REPLACE FUNCTION get_db_stats()
RETURNS TABLE (
    metric TEXT,
    value TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'Database Size'::TEXT, pg_size_pretty(pg_database_size(current_database()))
    UNION ALL
    SELECT 'Table Count'::TEXT, COUNT(*)::TEXT 
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    UNION ALL
    SELECT 'Index Count'::TEXT, COUNT(*)::TEXT 
    FROM pg_indexes 
    WHERE schemaname = 'public'
    UNION ALL
    SELECT 'Active Connections'::TEXT, COUNT(*)::TEXT 
    FROM pg_stat_activity 
    WHERE state = 'active'
    UNION ALL
    SELECT 'Cache Hit Ratio'::TEXT, 
           ROUND((sum(heap_blks_hit)::numeric / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 2)::TEXT || '%'
    FROM pg_statio_user_tables;
END;
$$ LANGUAGE plpgsql;
```

---

## Test Data Generation

### Generate Test Users
```sql
CREATE OR REPLACE FUNCTION generate_test_users(count INTEGER)
RETURNS void AS $$
DECLARE
    i INTEGER;
    new_user_id INTEGER;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    FOR i IN 1..count LOOP
        -- Create user
        INSERT INTO users (username, email, password_hash, first_name, last_name)
        VALUES (
            'test_user_' || i,
            'test' || i || '@example.com',
            '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8',
            'Test',
            'User' || i
        )
        RETURNING user_id INTO new_user_id;
        
        -- Initialize points (Bronze tier)
        INSERT INTO user_points (user_id, current_tier_id, total_points)
        VALUES (new_user_id, 1, 0);
        
        -- Create preferences
        INSERT INTO preferences (user_id, theme, spoiler_protection_level)
        VALUES (
            new_user_id,
            CASE (random() * 2)::INTEGER WHEN 0 THEN 'light' WHEN 1 THEN 'dark' ELSE 'auto' END,
            CASE (random() * 2)::INTEGER WHEN 0 THEN 'off' WHEN 1 THEN 'moderate' ELSE 'strict' END
        );
        
        -- Progress indicator
        IF i % 100 = 0 THEN
            RAISE NOTICE 'Created % users...', i;
        END IF;
    END LOOP;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'Created % test users in % seconds', 
                 count, 
                 EXTRACT(EPOCH FROM (end_time - start_time));
END;
$$ LANGUAGE plpgsql;

-- Usage:
-- SELECT generate_test_users(1000);
```

### Generate Test Movies
```sql
CREATE OR REPLACE FUNCTION generate_test_movies(count INTEGER)
RETURNS void AS $$
DECLARE
    i INTEGER;
    new_movie_id INTEGER;
    random_genre INTEGER;
    genre_count INTEGER;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    FOR i IN 1..count LOOP
        -- Create movie
        INSERT INTO movies (
            title,
            description,
            release_date,
            duration,
            rating,
            director,
            poster_url
        )
        VALUES (
            'Test Movie ' || i,
            'This is a test movie description for movie number ' || i || '. It contains various plot elements and character development.',
            CURRENT_DATE - (random() * 3650)::INTEGER,  -- Random date within 10 years
            90 + (random() * 90)::INTEGER,              -- 90-180 minutes
            5.0 + (random() * 5.0),                     -- 5.0-10.0 rating
            'Director ' || (random() * 100)::INTEGER,
            '/posters/test-' || i || '.jpg'
        )
        RETURNING movie_id INTO new_movie_id;
        
        -- Add 1-3 random genres
        genre_count := 1 + (random() * 2)::INTEGER;
        FOR j IN 1..genre_count LOOP
            SELECT genre_id INTO random_genre 
            FROM genres 
            ORDER BY RANDOM() 
            LIMIT 1;
            
            INSERT INTO moviegenres (movie_id, genre_id)
            VALUES (new_movie_id, random_genre)
            ON CONFLICT DO NOTHING;
        END LOOP;
        
        -- Add to 1-2 random streaming platforms
        INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
        SELECT 'movie', new_movie_id, platform_id, TRUE
        FROM streaming_platforms
        ORDER BY RANDOM()
        LIMIT 1 + (random())::INTEGER;
        
        IF i % 100 = 0 THEN
            RAISE NOTICE 'Created % movies...', i;
        END IF;
    END LOOP;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'Created % test movies in % seconds', 
                 count, 
                 EXTRACT(EPOCH FROM (end_time - start_time));
END;
$$ LANGUAGE plpgsql;

-- Usage:
-- SELECT generate_test_movies(1000);
```

### Generate Test Reviews
```sql
CREATE OR REPLACE FUNCTION generate_test_reviews(count INTEGER)
RETURNS void AS $$
DECLARE
    i INTEGER;
    random_user INTEGER;
    random_movie INTEGER;
    random_rating NUMERIC;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    FOR i IN 1..count LOOP
        -- Get random test user
        SELECT user_id INTO random_user 
        FROM users 
        WHERE username LIKE 'test_user_%'
        ORDER BY RANDOM() 
        LIMIT 1;
        
        -- Get random test movie
        SELECT movie_id INTO random_movie 
        FROM movies 
        WHERE title LIKE 'Test Movie %'
        ORDER BY RANDOM() 
        LIMIT 1;
        
        -- Generate rating
        random_rating := 5.0 + (random() * 5.0);
        
        -- Create review
        INSERT INTO reviews (
            user_id,
            content_type,
            content_id,
            rating,
            review_text,
            contains_spoilers
        )
        VALUES (
            random_user,
            'movie',
            random_movie,
            random_rating,
            'Test review text for movie. This is a detailed review with multiple sentences. The movie was ' || 
            CASE WHEN random_rating > 7.5 THEN 'excellent' WHEN random_rating > 5.5 THEN 'good' ELSE 'average' END || 
            ' and I would recommend it.',
            random() < 0.3  -- 30% contain spoilers
        );
        
        IF i % 500 = 0 THEN
            RAISE NOTICE 'Created % reviews...', i;
        END IF;
    END LOOP;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'Created % test reviews in % seconds', 
                 count, 
                 EXTRACT(EPOCH FROM (end_time - start_time));
END;
$$ LANGUAGE plpgsql;

-- Usage:
-- SELECT generate_test_reviews(5000);
```

### Generate User Interactions
```sql
CREATE OR REPLACE FUNCTION generate_test_interactions(count INTEGER)
RETURNS void AS $$
DECLARE
    i INTEGER;
    random_user INTEGER;
    random_review INTEGER;
    like_type_id INTEGER;
    view_type_id INTEGER;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    
    -- Get interaction type IDs
    SELECT interaction_type_id INTO like_type_id 
    FROM interaction_types WHERE type_name = 'like';
    
    SELECT interaction_type_id INTO view_type_id 
    FROM interaction_types WHERE type_name = 'view';
    
    FOR i IN 1..count LOOP
        -- Get random test user
        SELECT user_id INTO random_user 
        FROM users 
        WHERE username LIKE 'test_user_%'
        ORDER BY RANDOM() 
        LIMIT 1;
        
        -- Get random review
        SELECT review_id INTO random_review 
        FROM reviews 
        ORDER BY RANDOM() 
        LIMIT 1;
        
        -- Create interaction (like or view)
        INSERT INTO user_interactions (
            user_id,
            content_type,
            content_id,
            interaction_type_id,
            created_at
        )
        VALUES (
            random_user,
            'review',
            random_review,
            CASE WHEN random() < 0.7 THEN view_type_id ELSE like_type_id END,
            CURRENT_TIMESTAMP - (random() * INTERVAL '30 days')
        )
        ON CONFLICT DO NOTHING;
        
        IF i % 1000 = 0 THEN
            RAISE NOTICE 'Created % interactions...', i;
        END IF;
    END LOOP;
    
    end_time := clock_timestamp();
    RAISE NOTICE 'Created % test interactions in % seconds', 
                 count, 
                 EXTRACT(EPOCH FROM (end_time - start_time));
END;
$$ LANGUAGE plpgsql;

-- Usage:
-- SELECT generate_test_interactions(10000);
```

---

## Performance Benchmarks

### Benchmark Framework
```sql
CREATE OR REPLACE FUNCTION run_performance_benchmarks()
RETURNS TABLE (
    test_name TEXT,
    execution_time_ms NUMERIC,
    rows_returned BIGINT,
    status TEXT
) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    exec_time NUMERIC;
    row_count BIGINT;
BEGIN
    -- Test 1: Simple user lookup by ID
    test_name := 'User lookup by ID';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM users WHERE user_id = 1;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 5 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 2: User authentication query
    test_name := 'User authentication';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM users u
    LEFT JOIN user_points up ON u.user_id = up.user_id
    LEFT JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
    WHERE u.username = 'test_user_1';
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 10 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 3: Content search
    test_name := 'Content search (LIKE query)';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM movies 
    WHERE LOWER(title) LIKE '%test%' 
    LIMIT 20;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 50 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 4: User feed generation
    test_name := 'User feed (20 posts)';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM user_posts up
    JOIN users u ON up.user_id = u.user_id
    LEFT JOIN user_points upts ON u.user_id = upts.user_id
    LEFT JOIN ranking_tiers rt ON upts.current_tier_id = rt.tier_id
    ORDER BY up.created_at DESC
    LIMIT 20;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 100 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 5: Reviews with spoiler filtering
    test_name := 'Reviews with spoiler check';
    start_time := clock_timestamp();
    
    WITH user_progress AS (
        SELECT content_type, content_id, completed
        FROM content_progress
        WHERE user_id = 1
    )
    SELECT COUNT(*) INTO row_count
    FROM reviews r
    LEFT JOIN user_progress up ON (
        up.content_type = r.content_type 
        AND up.content_id = r.content_id
    )
    WHERE r.content_type = 'movie'
    LIMIT 50;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 100 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 6: Complex join (content with genres and platforms)
    test_name := 'Complex content query';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM movies m
    LEFT JOIN LATERAL (
        SELECT json_agg(g.name) as genres
        FROM moviegenres mg 
        JOIN genres g ON mg.genre_id = g.genre_id 
        WHERE mg.movie_id = m.movie_id
    ) genres ON true
    LEFT JOIN LATERAL (
        SELECT json_agg(sp.platform_name) as platforms
        FROM content_platform_availability cpa
        JOIN streaming_platforms sp ON cpa.platform_id = sp.platform_id
        WHERE cpa.content_type = 'movie' 
        AND cpa.content_id = m.movie_id
    ) platforms ON true
    LIMIT 20;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 200 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 7: Aggregation query
    test_name := 'Content statistics aggregation';
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO row_count
    FROM (
        SELECT 
            m.movie_id,
            COUNT(DISTINCT r.review_id) as review_count,
            AVG(r.rating) as avg_rating,
            COUNT(DISTINCT ui.user_id) as interaction_count
        FROM movies m
        LEFT JOIN reviews r ON r.content_type = 'movie' AND r.content_id = m.movie_id
        LEFT JOIN user_interactions ui ON ui.content_type = 'movie' AND ui.content_id = m.movie_id
        GROUP BY m.movie_id
        LIMIT 100
    ) stats;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 500 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
    -- Test 8: Trending calculation
    test_name := 'Trending score calculation';
    start_time := clock_timestamp();
    
    WITH content_engagement AS (
        SELECT 
            ui.content_type,
            ui.content_id,
            COUNT(DISTINCT ui.user_id) as unique_users,
            SUM(CASE WHEN it.type_name = 'view' THEN 1 ELSE 0 END) as views,
            SUM(CASE WHEN it.type_name = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN it.type_name = 'share' THEN 1 ELSE 0 END) as shares
        FROM user_interactions ui
        JOIN interaction_types it ON ui.interaction_type_id = it.interaction_type_id
        WHERE ui.created_at > CURRENT_TIMESTAMP - INTERVAL '1 day'
        GROUP BY ui.content_type, ui.content_id
    )
    SELECT COUNT(*) INTO row_count
    FROM (
        SELECT 
            content_type,
            content_id,
            (unique_users * 1.0 + likes * 0.5 + shares * 2.0) as trending_score
        FROM content_engagement
        ORDER BY trending_score DESC
        LIMIT 10
    ) trending;
    
    end_time := clock_timestamp();
    execution_time_ms := EXTRACT(MILLISECOND FROM (end_time - start_time));
    rows_returned := row_count;
    status := CASE WHEN execution_time_ms < 200 THEN 'PASS' ELSE 'SLOW' END;
    RETURN NEXT;
    
END;
$$ LANGUAGE plpgsql;
```

### Run Benchmarks
```sql
-- Execute benchmark suite
SELECT * FROM run_performance_benchmarks();

-- Expected output:
-- test_name                      | execution_time_ms | rows_returned | status
-- -------------------------------|-------------------|---------------|-------
-- User lookup by ID              | 2.5               | 1             | PASS
-- User authentication            | 8.3               | 1             | PASS
-- Content search (LIKE query)    | 35.7              | 20            | PASS
-- User feed (20 posts)           | 67.4              | 20            | PASS
-- Reviews with spoiler check     | 89.2              | 50            | PASS
-- Complex content query          | 156.8             | 20            | PASS
-- Content statistics aggregation | 387.5             | 100           | PASS
-- Trending score calculation     | 178.3             | 10            | PASS
```

---

## Query Performance Tests

### Individual Query Performance
```sql
-- Test query with EXPLAIN ANALYZE
EXPLAIN ANALYZE
SELECT 
    m.movie_id,
    m.title,
    m.rating,
    (SELECT json_agg(g.name) 
     FROM moviegenres mg 
     JOIN genres g ON mg.genre_id = g.genre_id 
     WHERE mg.movie_id = m.movie_id) as genres
FROM movies m
WHERE m.rating > 8.0
ORDER BY m.rating DESC
LIMIT 10;

-- Look for:
-- - Execution Time (should be < 50ms)
-- - Index scans vs Sequential scans
-- - Nested Loop vs Hash Join
```

### Slow Query Detection
```sql
-- Find slowest queries (requires pg_stat_statements)
SELECT 
    queryid,
    LEFT(query, 100) as query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time,
    stddev_exec_time,
    rows
FROM pg_stat_statements 
WHERE mean_exec_time > 100  -- Queries averaging over 100ms
ORDER BY mean_exec_time DESC 
LIMIT 10;
```

### Index Usage Analysis
```sql
-- Check index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE schemaname = 'public'
ORDER BY idx_scan DESC
LIMIT 20;

-- Find unused indexes (candidates for removal)
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE idx_scan = 0
AND schemaname = 'public'
AND indexrelid NOT IN (
    -- Exclude primary key and unique constraints
    SELECT indexrelid FROM pg_index WHERE indisprimary OR indisunique
)
ORDER BY pg_relation_size(indexrelid) DESC;
```

---

## Connection Pool Testing

### Simulate Concurrent Connections
```sql
-- Function to simulate concurrent user activity
CREATE OR REPLACE FUNCTION simulate_concurrent_load(
    num_connections INTEGER DEFAULT 10,
    queries_per_connection INTEGER DEFAULT 100
)
RETURNS TABLE (
    connection_id INTEGER,
    total_queries INTEGER,
    avg_query_time_ms NUMERIC,
    min_query_time_ms NUMERIC,
    max_query_time_ms NUMERIC
) AS $$
DECLARE
    i INTEGER;
    j INTEGER;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    query_times NUMERIC[];
BEGIN
    FOR i IN 1..num_connections LOOP
        query_times := ARRAY[]::NUMERIC[];
        
        FOR j IN 1..queries_per_connection LOOP
            start_time := clock_timestamp();
            
            -- Simulate various query types
            CASE (random() * 4)::INTEGER
                WHEN 0 THEN
                    -- User lookup
                    PERFORM * FROM users WHERE user_id = (random() * 1000)::INTEGER;
                WHEN 1 THEN
                    -- Content search
                    PERFORM * FROM movies WHERE rating > 7.0 LIMIT 10;
                WHEN 2 THEN
                    -- Review fetch
                    PERFORM * FROM reviews WHERE content_type = 'movie' LIMIT 20;
                ELSE
                    -- Complex join
                    PERFORM m.*, 
                        (SELECT json_agg(g.name) FROM moviegenres mg JOIN genres g ON mg.genre_id = g.genre_id WHERE mg.movie_id = m.movie_id)
                    FROM movies m LIMIT 5;
            END CASE;
            
            end_time := clock_timestamp();
            query_times := array_append(query_times, EXTRACT(MILLISECOND FROM (end_time - start_time)));
        END LOOP;
        
        connection_id := i;
        total_queries := queries_per_connection;
        avg_query_time_ms := (SELECT AVG(t) FROM unnest(query_times) t);
        min_query_time_ms := (SELECT MIN(t) FROM unnest(query_times) t);
        max_query_time_ms := (SELECT MAX(t) FROM unnest(query_times) t);
        
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Run concurrent load test
SELECT * FROM simulate_concurrent_load(10, 100);
```

### Monitor Active Connections
```sql
-- View current connections
SELECT 
    datname as database,
    usename as username,
    count(*) as connection_count,
    count(*) FILTER (WHERE state = 'active') as active,
    count(*) FILTER (WHERE state = 'idle') as idle,
    count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction
FROM pg_stat_activity 
WHERE datname = current_database()
GROUP BY datname, usename;
```

---

## Stress Testing

### Full Load Test
```sql
-- Complete load test procedure
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_time NUMERIC;
BEGIN
    start_time := clock_timestamp();
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Entertainment Hub - Load Testing';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Clean up previous test data
    RAISE NOTICE 'Cleaning up previous test data...';
    PERFORM cleanup_test_data();
    RAISE NOTICE '';
    
    -- Generate test data
    RAISE NOTICE 'Generating test data...';
    RAISE NOTICE '  Creating 1,000 users...';
    PERFORM generate_test_users(1000);
    
    RAISE NOTICE '  Creating 500 movies...';
    PERFORM generate_test_movies(500);
    
    RAISE NOTICE '  Creating 5,000 reviews...';
    PERFORM generate_test_reviews(5000);
    
    RAISE NOTICE '  Creating 10,000 interactions...';
    PERFORM generate_test_interactions(10000);
    RAISE NOTICE '';
    
    -- Run performance benchmarks
    RAISE NOTICE 'Running performance benchmarks...';
    RAISE NOTICE '';
    
    -- Display results
    RAISE NOTICE 'Benchmark Results:';
    RAISE NOTICE '==================';
    
    FOR rec IN SELECT * FROM run_performance_benchmarks() LOOP
        RAISE NOTICE '% : % ms [%]', 
                     RPAD(rec.test_name, 35), 
                     LPAD(rec.execution_time_ms::TEXT, 8), 
                     rec.status;
    END LOOP;
    
    RAISE NOTICE '';
    
    -- Database statistics
    RAISE NOTICE 'Database Statistics:';
    RAISE NOTICE '====================';
    
    FOR rec IN SELECT * FROM get_db_stats() LOOP
        RAISE NOTICE '% : %', RPAD(rec.metric, 25), rec.value;
    END LOOP;
    
    end_time := clock_timestamp();
    total_time := EXTRACT(EPOCH FROM (end_time - start_time));
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Load test completed in % seconds', ROUND(total_time, 2);
    RAISE NOTICE '========================================';
END $$;
```

### Cache Performance Test
```sql
-- Test cache hit ratio under load
SELECT 
    'Cache Hit Ratio' as metric,
    ROUND(
        (sum(heap_blks_hit)::numeric / 
         NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 
        2
    ) as percentage
FROM pg_statio_user_tables;

-- Should be > 95% for good performance
```

### Table Size Analysis
```sql
-- Analyze table sizes after load test
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(
        pg_total_relation_size(schemaname||'.'||tablename) - 
        pg_relation_size(schemaname||'.'||tablename)
    ) as index_size,
    ROUND(
        100.0 * (pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) / 
        NULLIF(pg_total_relation_size(schemaname||'.'||tablename), 0),
        2
    ) as index_ratio_percent
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
```

---

## Performance Optimization Tips

### Query Optimization Checklist
```sql
-- 1. Check for missing indexes
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'public'
AND n_distinct > 100  -- High cardinality columns
AND correlation < 0.1  -- Low correlation with physical order
ORDER BY n_distinct DESC;

-- 2. Analyze table statistics
ANALYZE VERBOSE;

-- 3. Check for bloat
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    n_dead_tup,
    n_live_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_tuple_percent
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- 4. Vacuum if needed
-- VACUUM ANALYZE tablename;
```

### Monitoring Queries
```sql
-- Monitor long-running queries
SELECT 
    pid,
    now() - query_start as duration,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
AND query_start < now() - interval '5 seconds'
ORDER BY duration DESC;

-- Kill long-running query if needed:
-- SELECT pg_terminate_backend(pid);
```

---

**Entertainment Hub Database v1.3.0**  
**Performance Testing Guide**