# Entertainment Hub Database
## Test Queries - Part 1

**Database Version**: 1.3.0  
**Total Tables**: 80  
**Last Updated**: July 27, 2025

---

## Table of Contents

1. [Use Case 1: User Registration & Onboarding](#use-case-1)
2. [Use Case 2: Adding Content with Streaming](#use-case-2)
3. [Use Case 3: User Reviews Content](#use-case-3)
4. [Use Case 4: Tier Progression](#use-case-4)

---

## Use Case 1: User Registration & Onboarding {#use-case-1}

### Scenario
New user signs up and gets complete initial setup including user account, points tracking, and default preferences.

### Step 1: Create New User Account
```sql
-- Begin transaction for atomic operation
BEGIN;

-- Insert new user
INSERT INTO users (username, email, password_hash, first_name, last_name, date_of_birth)
VALUES (
    'john_doe',
    'john@example.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5UpGm4VT0pY8S',  -- bcrypt hash
    'John',
    'Doe',
    '1995-06-15'
)
RETURNING user_id, username, email, created_at;

-- Expected Result:
-- user_id | username | email              | created_at
-- --------|----------|--------------------|--------------------------
-- 1       | john_doe | john@example.com   | 2024-12-29 10:30:00+00
```

### Step 2: Initialize User Points (Bronze Tier)
```sql
-- Initialize user points with Bronze tier
INSERT INTO user_points (user_id, current_tier_id, total_points, total_likes_received)
VALUES (
    1,  -- user_id from previous step
    (SELECT tier_id FROM ranking_tiers WHERE tier_name = 'Bronze'),
    0,
    0
)
RETURNING user_id, total_points, current_tier_id;

-- Expected Result:
-- user_id | total_points | current_tier_id
-- --------|--------------|----------------
-- 1       | 0            | 1
```

### Step 3: Create Default Preferences
```sql
-- Create user preferences with sensible defaults
INSERT INTO preferences (
    user_id,
    theme,
    language,
    email_notifications,
    push_notifications,
    spoiler_protection_level,
    privacy_level
)
VALUES (
    1,
    'dark',
    'en',
    TRUE,
    FALSE,
    'strict',
    'public'
)
RETURNING user_id, theme, spoiler_protection_level;

-- Expected Result:
-- user_id | theme | spoiler_protection_level
-- --------|-------|-------------------------
-- 1       | dark  | strict
```

### Step 4: Commit Transaction
```sql
COMMIT;
```

### Step 5: Verify Complete User Setup
```sql
-- Query to verify all user data was created correctly
SELECT 
    u.user_id,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.created_at,
    -- Points and tier information
    up.total_points,
    up.total_likes_received,
    rt.tier_name,
    rt.tier_icon,
    rt.tier_color,
    -- Preferences
    p.theme,
    p.spoiler_protection_level,
    p.email_notifications,
    p.privacy_level
FROM users u
JOIN user_points up ON u.user_id = up.user_id
JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
JOIN preferences p ON u.user_id = p.user_id
WHERE u.user_id = 1;

-- Expected Result:
-- user_id | username | email            | first_name | last_name | created_at          | total_points | total_likes | tier_name | tier_icon | tier_color | theme | spoiler_level | email_notif | privacy
-- --------|----------|------------------|------------|-----------|---------------------|--------------|-------------|-----------|-----------|------------|-------|---------------|-------------|--------
-- 1       | john_doe | john@example.com | John       | Doe       | 2024-12-29 10:30:00 | 0            | 0           | Bronze    | 🥉        | #CD7F32    | dark  | strict        | true        | public
```

### Test Query: User Login
```sql
-- Authenticate user by username or email
SELECT 
    u.user_id,
    u.username,
    u.email,
    u.password_hash,
    u.first_name,
    u.last_name,
    u.profile_picture,
    u.is_active,
    u.user_role,
    -- User stats
    up.total_points,
    up.total_likes_received,
    rt.tier_name,
    rt.tier_icon,
    rt.tier_color
FROM users u
LEFT JOIN user_points up ON u.user_id = up.user_id
LEFT JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
WHERE (u.username = 'john_doe' OR u.email = 'john_doe')
AND u.is_active = TRUE;

-- Application should verify password_hash matches
-- Then update last_login:

UPDATE users 
SET last_login = CURRENT_TIMESTAMP 
WHERE user_id = 1;

-- Log successful login
INSERT INTO login_attempts (user_id, ip_address, user_agent, success)
VALUES (1, '192.168.1.100', 'Mozilla/5.0...', TRUE);
```

---

## Use Case 2: Adding Content with Streaming Availability {#use-case-2}

### Scenario
Add a new movie to the database with genre associations and streaming platform availability.

### Step 1: Insert Movie
```sql
BEGIN;

-- Insert movie metadata
INSERT INTO movies (
    title,
    description,
    release_date,
    duration,
    language,
    rating,
    director,
    country_of_origin,
    poster_url,
    backdrop_url,
    trailer_url
)
VALUES (
    'Inception',
    'A thief who steals corporate secrets through the use of dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.',
    '2010-07-16',
    148,
    'English',
    8.8,
    'Christopher Nolan',
    'USA',
    '/posters/inception.jpg',
    '/backdrops/inception.jpg',
    'https://youtube.com/watch?v=YoHD9XEInc0'
)
RETURNING movie_id, title, rating;

-- Expected Result:
-- movie_id | title     | rating
-- ---------|-----------|-------
-- 1        | Inception | 8.8
```

### Step 2: Add Genre Associations
```sql
-- Associate movie with multiple genres
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 1, genre_id 
FROM genres 
WHERE name IN ('Action', 'Sci-Fi', 'Thriller')
RETURNING movie_id, genre_id;

-- Expected Result (3 rows):
-- movie_id | genre_id
-- ---------|----------
-- 1        | 1        (Action)
-- 1        | 6        (Sci-Fi)
-- 1        | 8        (Thriller)
```

### Step 3: Add Streaming Platform Availability
```sql
-- Add to Netflix and Prime Video
INSERT INTO content_platform_availability (
    content_type,
    content_id,
    platform_id,
    is_available,
    available_from,
    subscription_tier
)
SELECT 
    'movie',
    1,
    platform_id,
    TRUE,
    CURRENT_DATE,
    'Standard'
FROM streaming_platforms
WHERE platform_code IN ('NETFLIX', 'PRIME_VIDEO')
RETURNING content_id, platform_id;

-- Expected Result (2 rows):
-- content_id | platform_id
-- -----------|-------------
-- 1          | 1           (Netflix)
-- 1          | 5           (Prime Video)
```

### Step 4: Add Trailer
```sql
-- Add official trailer
INSERT INTO trailers (
    content_type,
    content_id,
    trailer_url,
    title,
    duration,
    language
)
VALUES (
    'movie',
    1,
    'https://youtube.com/watch?v=YoHD9XEInc0',
    'Inception - Official Trailer',
    150,
    'en'
)
RETURNING trailer_id;
```

### Step 5: Commit Transaction
```sql
COMMIT;
```

### Step 6: Verify Complete Content Setup
```sql
-- Query to get complete movie information
SELECT 
    m.movie_id,
    m.title,
    m.description,
    m.release_date,
    m.duration,
    m.rating,
    m.director,
    m.poster_url,
    -- Genres as JSON array
    (SELECT json_agg(json_build_object('id', g.genre_id, 'name', g.name))
     FROM moviegenres mg 
     JOIN genres g ON mg.genre_id = g.genre_id 
     WHERE mg.movie_id = m.movie_id) as genres,
    -- Streaming platforms as JSON array
    (SELECT json_agg(json_build_object(
        'platform_id', sp.platform_id,
        'platform_name', sp.platform_name,
        'platform_code', sp.platform_code,
        'logo_url', sp.logo_url,
        'subscription_tier', cpa.subscription_tier
    ))
    FROM content_platform_availability cpa
    JOIN streaming_platforms sp ON cpa.platform_id = sp.platform_id
    WHERE cpa.content_type = 'movie' 
    AND cpa.content_id = m.movie_id
    AND cpa.is_available = TRUE) as streaming_platforms,
    -- Trailer information
    (SELECT json_build_object(
        'trailer_url', t.trailer_url,
        'title', t.title,
        'duration', t.duration
    ) FROM trailers t 
    WHERE t.content_type = 'movie' 
    AND t.content_id = m.movie_id 
    LIMIT 1) as trailer
FROM movies m
WHERE m.movie_id = 1;

-- Expected Result: One row with complete movie details including nested JSON for genres, platforms, and trailer
```

### Test Query: Search Movies by Title
```sql
-- Search for movies (case-insensitive partial match)
SELECT 
    m.movie_id,
    m.title,
    m.poster_url,
    m.rating,
    m.release_date,
    -- Genre names as array
    ARRAY(
        SELECT g.name 
        FROM moviegenres mg 
        JOIN genres g ON mg.genre_id = g.genre_id 
        WHERE mg.movie_id = m.movie_id
    ) as genres,
    -- Review count
    (SELECT COUNT(*) FROM reviews WHERE content_type = 'movie' AND content_id = m.movie_id) as review_count
FROM movies m
WHERE LOWER(m.title) LIKE LOWER('%inception%')
ORDER BY m.rating DESC NULLS LAST
LIMIT 20;
```

### Test Query: Get Movies by Genre
```sql
-- Get all Action movies
SELECT 
    m.movie_id,
    m.title,
    m.poster_url,
    m.rating,
    m.release_date,
    m.director
FROM movies m
JOIN moviegenres mg ON m.movie_id = mg.movie_id
WHERE mg.genre_id = (SELECT genre_id FROM genres WHERE name = 'Action')
ORDER BY m.rating DESC NULLS LAST, m.release_date DESC
LIMIT 20;
```

### Test Query: Get Movies Available on Specific Platform
```sql
-- Get all movies on Netflix
SELECT 
    m.movie_id,
    m.title,
    m.poster_url,
    m.rating,
    cpa.available_from,
    cpa.subscription_tier
FROM content_platform_availability cpa
JOIN movies m ON cpa.content_type = 'movie' AND cpa.content_id = m.movie_id
WHERE cpa.platform_id = (SELECT platform_id FROM streaming_platforms WHERE platform_code = 'NETFLIX')
AND cpa.is_available = TRUE
AND (cpa.available_until IS NULL OR cpa.available_until > CURRENT_DATE)
ORDER BY m.rating DESC
LIMIT 50;
```

---

## Use Case 3: User Reviews Content {#use-case-3}

### Scenario
User writes a review for a movie and earns points for creating content.

### Step 1: User Submits Review
```sql
BEGIN;

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
    1,  -- john_doe
    'movie',
    1,  -- Inception
    9.0,
    'Mind-bending masterpiece! The dream sequences are brilliantly crafted and the ending will have you thinking for days. Christopher Nolan at his finest.',
    FALSE
)
RETURNING review_id, user_id, rating, created_at;

-- Expected Result:
-- review_id | user_id | rating | created_at
-- ----------|---------|--------|-------------------------
-- 1         | 1       | 9.0    | 2024-12-29 11:00:00+00
```

### Step 2: Award Points for Creating Review
```sql
-- Log point transaction
INSERT INTO point_transactions (
    user_id,
    points_change,
    transaction_type,
    description
)
VALUES (
    1,
    10,
    'review_created',
    'Created review for Inception'
)
RETURNING transaction_id, points_change;

-- Update user's total points
UPDATE user_points 
SET total_points = total_points + 10,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1
RETURNING total_points;

-- Expected Result:
-- total_points
-- -------------
-- 10
```

### Step 3: Track User Activity
```sql
-- Log activity for "recently viewed"
INSERT INTO user_activity (
    user_id,
    activity_type,
    content_type,
    content_id,
    activity_timestamp
)
VALUES (
    1,
    'review_created',
    'movie',
    1,
    CURRENT_TIMESTAMP
);
```

### Step 4: Commit Transaction
```sql
COMMIT;
```

### Step 5: Verify Review and Points
```sql
-- Get complete review information with user stats
SELECT 
    r.review_id,
    r.rating,
    r.review_text,
    r.contains_spoilers,
    r.created_at,
    -- User information
    u.user_id,
    u.username,
    u.profile_picture,
    -- User stats
    up.total_points,
    up.total_likes_received,
    rt.tier_name,
    rt.tier_icon,
    -- Content information
    m.title as movie_title,
    m.poster_url,
    -- Interaction counts
    (SELECT COUNT(*) 
     FROM user_interactions ui
     JOIN interaction_types it ON ui.interaction_type_id = it.interaction_type_id
     WHERE ui.content_type = 'review' 
     AND ui.content_id = r.review_id
     AND it.type_name = 'like') as like_count,
    (SELECT COUNT(*) 
     FROM comments 
     WHERE review_id = r.review_id) as comment_count
FROM reviews r
JOIN users u ON r.user_id = u.user_id
JOIN user_points up ON u.user_id = up.user_id
JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
JOIN movies m ON r.content_type = 'movie' AND r.content_id = m.movie_id
WHERE r.review_id = 1;

-- Expected Result:
-- review_id | rating | review_text       | username | total_points | tier_name | movie_title | like_count | comment_count
-- ----------|--------|-------------------|----------|--------------|-----------|-------------|------------|---------------
-- 1         | 9.0    | Mind-bending...   | john_doe | 10           | Bronze    | Inception   | 0          | 0
```

### Test Query: Get Reviews for Content (with Pagination)
```sql
-- Get reviews for Inception (page 1, 10 per page)
SELECT 
    r.review_id,
    r.rating,
    r.review_text,
    r.contains_spoilers,
    r.created_at,
    u.username,
    u.profile_picture,
    rt.tier_name,
    rt.tier_icon,
    -- Like count
    (SELECT COUNT(*) 
     FROM user_interactions ui
     JOIN interaction_types it ON ui.interaction_type_id = it.interaction_type_id
     WHERE ui.content_type = 'review' 
     AND ui.content_id = r.review_id
     AND it.type_name = 'like') as like_count
FROM reviews r
JOIN users u ON r.user_id = u.user_id
LEFT JOIN user_points up ON u.user_id = up.user_id
LEFT JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
WHERE r.content_type = 'movie' 
AND r.content_id = 1
ORDER BY r.created_at DESC
LIMIT 10 OFFSET 0;
```

### Test Query: Get User's Reviews
```sql
-- Get all reviews by john_doe
SELECT 
    r.review_id,
    r.rating,
    r.review_text,
    r.created_at,
    -- Content info
    CASE 
        WHEN r.content_type = 'movie' THEN m.title
        WHEN r.content_type = 'show' THEN s.title
    END as content_title,
    CASE 
        WHEN r.content_type = 'movie' THEN m.poster_url
        WHEN r.content_type = 'show' THEN s.poster_url
    END as poster_url,
    r.content_type,
    -- Stats
    (SELECT COUNT(*) 
     FROM user_interactions ui
     JOIN interaction_types it ON ui.interaction_type_id = it.interaction_type_id
     WHERE ui.content_type = 'review' 
     AND ui.content_id = r.review_id
     AND it.type_name = 'like') as likes
FROM reviews r
LEFT JOIN movies m ON r.content_type = 'movie' AND r.content_id = m.movie_id
LEFT JOIN shows s ON r.content_type = 'show' AND r.content_id = s.show_id
WHERE r.user_id = 1
ORDER BY r.created_at DESC;
```

---

## Use Case 4: Tier Progression (Bronze → Silver) {#use-case-4}

### Scenario
User receives 25 likes on their review, triggering tier progression from Bronze to Silver.

### Simulate Multiple Users Liking the Review
```sql
BEGIN;

-- Create 25 test users and have them like the review
DO $$
DECLARE
    i INTEGER;
    new_user_id INTEGER;
    like_interaction_id INTEGER;
BEGIN
    -- Get the 'like' interaction type ID
    SELECT interaction_type_id INTO like_interaction_id
    FROM interaction_types WHERE type_name = 'like';
    
    FOR i IN 1..25 LOOP
        -- Create test user
        INSERT INTO users (username, email, password_hash)
        VALUES (
            'user_' || i,
            'user' || i || '@example.com',
            '$2b$12$testhash'
        )
        RETURNING user_id INTO new_user_id;
        
        -- Initialize their points
        INSERT INTO user_points (user_id, current_tier_id)
        VALUES (new_user_id, 1);
        
        -- User likes john_doe's review
        INSERT INTO user_interactions (
            user_id,
            content_type,
            content_id,
            interaction_type_id
        )
        VALUES (
            new_user_id,
            'review',
            1,
            like_interaction_id
        );
        
        -- Award 1 point to review owner (john_doe)
        INSERT INTO point_transactions (
            user_id,
            points_change,
            transaction_type,
            description
        )
        VALUES (
            1,  -- john_doe
            1,
            'like_received',
            'Received like on review from user_' || i
        );
        
        -- Update john_doe's points
        UPDATE user_points 
        SET total_points = total_points + 1,
            total_likes_received = total_likes_received + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id = 1;
        
    END LOOP;
    
    RAISE NOTICE 'Created 25 users and likes';
END $$;

COMMIT;
```

### Check and Apply Tier Progression
```sql
BEGIN;

-- Check if user is eligible for tier upgrade
WITH current_status AS (
    SELECT 
        up.user_id,
        up.total_likes_received,
        up.current_tier_id,
        rt.tier_name as current_tier_name
    FROM user_points up
    JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
    WHERE up.user_id = 1
),
eligible_tier AS (
    SELECT 
        rt.tier_id,
        rt.tier_name,
        rt.points_reward,
        rt.min_likes,
        rt.max_likes
    FROM ranking_tiers rt, current_status cs
    WHERE cs.total_likes_received >= rt.min_likes
    AND (rt.max_likes IS NULL OR cs.total_likes_received <= rt.max_likes)
    AND rt.tier_id > cs.current_tier_id  -- Only upgrade, not downgrade
    ORDER BY rt.min_likes DESC
    LIMIT 1
)
-- Update user's tier if eligible
UPDATE user_points up
SET current_tier_id = et.tier_id,
    total_points = up.total_points + et.points_reward,
    last_tier_check = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
FROM eligible_tier et
WHERE up.user_id = 1
RETURNING 
    up.user_id,
    et.tier_name as new_tier,
    et.points_reward as bonus_points,
    up.total_points as new_total_points;

-- Expected Result:
-- user_id | new_tier | bonus_points | new_total_points
-- --------|----------|--------------|------------------
-- 1       | Silver   | 750          | 785

-- Log the tier progression
INSERT INTO point_transactions (
    user_id,
    points_change,
    transaction_type,
    description
)
SELECT 
    1,
    points_reward,
    'tier_progression',
    'Advanced to ' || tier_name || ' tier'
FROM eligible_tier;

COMMIT;
```

### Verify Tier Progression
```sql
-- Get complete user profile with new tier
SELECT 
    u.user_id,
    u.username,
    u.email,
    u.profile_picture,
    -- Points and tier
    up.total_points,
    up.total_likes_received,
    rt.tier_name,
    rt.tier_icon,
    rt.tier_color,
    rt.min_likes,
    rt.max_likes,
    -- Progress to next tier
    CASE 
        WHEN rt.max_likes IS NULL THEN 100.00
        ELSE ROUND(
            ((up.total_likes_received - rt.min_likes)::numeric / 
             (rt.max_likes - rt.min_likes)::numeric) * 100, 
            2
        )
    END as tier_progress_percentage,
    -- Transaction history
    (SELECT COUNT(*) FROM point_transactions WHERE user_id = u.user_id) as total_transactions,
    (SELECT SUM(points_change) 
     FROM point_transactions 
     WHERE user_id = u.user_id 
     AND transaction_type = 'like_received') as total_likes_points
FROM users u
JOIN user_points up ON u.user_id = up.user_id
JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
WHERE u.user_id = 1;

-- Expected Result:
-- user_id | username | total_points | total_likes | tier_name | tier_icon | min_likes | max_likes | tier_progress | total_transactions
-- --------|----------|--------------|-------------|-----------|-----------|-----------|-----------|---------------|-------------------
-- 1       | john_doe | 785          | 25          | Silver    | 🥈        | 25        | 74        | 0.00          | 27
```

### Test Query: Get Leaderboard (Top Users by Points)
```sql
-- Get top 10 users by total points
SELECT 
    ROW_NUMBER() OVER (ORDER BY up.total_points DESC) as rank,
    u.user_id,
    u.username,
    u.profile_picture,
    up.total_points,
    up.total_likes_received,
    rt.tier_name,
    rt.tier_icon,
    rt.tier_color,
    -- Additional stats
    (SELECT COUNT(*) FROM reviews WHERE user_id = u.user_id) as review_count,
    (SELECT COUNT(*) FROM user_posts WHERE user_id = u.user_id) as post_count
FROM users u
JOIN user_points up ON u.user_id = up.user_id
JOIN ranking_tiers rt ON up.current_tier_id = rt.tier_id
WHERE u.is_active = TRUE
ORDER BY up.total_points DESC
LIMIT 10;
```

### Test Query: Get User's Point History
```sql
-- Get point transaction history for john_doe
SELECT 
    pt.transaction_id,
    pt.points_change,
    pt.transaction_type,
    pt.description,
    pt.created_at,
    -- Running total
    SUM(pt.points_change) OVER (
        ORDER BY pt.created_at 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) as running_total
FROM point_transactions pt
WHERE pt.user_id = 1
ORDER BY pt.created_at DESC
LIMIT 50;
```

---

**Entertainment Hub Database v1.3.0**  
**Test Queries - Part 1**