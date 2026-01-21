-- ================================================
-- Entertainment Hub - Sample Data
-- Realistic test data for development/testing
-- ================================================

BEGIN;

-- ================================================
-- 1. RANKING TIERS
-- ================================================

INSERT INTO ranking_tiers (tier_name, min_likes, max_likes, tier_icon, tier_color, points_reward, tier_description)
VALUES 
    ('Bronze', 0, 24, '🥉', '#CD7F32', 500, 'Welcome to the community! Keep engaging to level up.'),
    ('Silver', 25, 74, '🥈', '#C0C0C0', 750, 'You''re making great contributions!'),
    ('Gold', 75, 149, '🏆', '#FFD700', 1000, 'An esteemed member of the community.'),
    ('Emerald', 150, 299, '💎', '#50C878', 1250, 'Your insights are valued by many.'),
    ('Diamond', 300, NULL, '💎', '#B9F2FF', 1500, 'Elite status - a true entertainment expert!')
ON CONFLICT (tier_name) DO NOTHING;

-- ================================================
-- 2. GENRES
-- ================================================

INSERT INTO genres (name, description) VALUES
    ('Action', 'High-energy films with physical stunts, chases, and battles'),
    ('Adventure', 'Epic journeys and quests in exotic locations'),
    ('Comedy', 'Humorous and lighthearted entertainment'),
    ('Drama', 'Serious, plot-driven narratives exploring human emotions'),
    ('Horror', 'Frightening and suspenseful content designed to scare'),
    ('Sci-Fi', 'Science fiction exploring futuristic concepts and technology'),
    ('Fantasy', 'Magical and supernatural elements in imaginative worlds'),
    ('Thriller', 'Suspenseful and tense narratives with plot twists'),
    ('Romance', 'Love stories and romantic relationships'),
    ('Documentary', 'Non-fiction informational content about real events'),
    ('Animation', 'Animated films and shows for all ages'),
    ('Crime', 'Stories about criminal activities and investigations'),
    ('Mystery', 'Puzzles and whodunits that keep you guessing'),
    ('Western', 'Stories set in the American Old West'),
    ('Musical', 'Films and shows featuring song and dance numbers')
ON CONFLICT (name) DO NOTHING;

-- ================================================
-- 3. STREAMING PLATFORMS
-- ================================================

INSERT INTO streaming_platforms (platform_name, platform_code, logo_url, website_url, subscription_required, description)
VALUES 
    ('Netflix', 'NETFLIX', '/logos/netflix.png', 'https://www.netflix.com', TRUE, 'Stream thousands of movies and TV shows'),
    ('Hulu', 'HULU', '/logos/hulu.png', 'https://www.hulu.com', TRUE, 'Watch current season TV and classic shows'),
    ('Disney+', 'DISNEY_PLUS', '/logos/disney-plus.png', 'https://www.disneyplus.com', TRUE, 'Disney, Pixar, Marvel, Star Wars, and National Geographic'),
    ('Max', 'MAX', '/logos/max.png', 'https://www.max.com', TRUE, 'HBO, Warner Bros, and more premium content'),
    ('Prime Video', 'PRIME_VIDEO', '/logos/prime-video.png', 'https://www.amazon.com/primevideo', TRUE, 'Amazon''s streaming service with originals and classics'),
    ('Apple TV+', 'APPLE_TV_PLUS', '/logos/apple-tv.png', 'https://tv.apple.com', TRUE, 'Apple Originals and exclusive content')
ON CONFLICT (platform_code) DO NOTHING;

-- ================================================
-- 4. COMMUNITY CATEGORIES
-- ================================================

INSERT INTO community_categories (category_name, category_code, icon, description)
VALUES 
    ('Survival & Suspense', 'SURVIVAL_SUSPENSE', '🔦', 'Edge-of-your-seat thrillers and survival stories'),
    ('Heroes & Villains', 'HEROES_VILLAINS', '🦸', 'Superhero adventures and villain showdowns'),
    ('Mind Bending Stories', 'MIND_BENDING', '🧠', 'Complex narratives and plot twists that challenge perception'),
    ('Chills & Thrills', 'CHILLS_THRILLS', '😱', 'Horror and supernatural content that sends shivers'),
    ('Mind & Mystery', 'MIND_MYSTERY', '🔍', 'Detective stories and mysteries to solve'),
    ('Love & Laughs', 'LOVE_LAUGHS', '❤️', 'Romantic comedies and feel-good content'),
    ('Animation', 'ANIMATION', '🎨', 'Animated films and shows for all ages'),
    ('Reality & Competition', 'REALITY_COMPETITION', '🏆', 'Reality TV and competition shows'),
    ('Family', 'FAMILY', '👨‍👩‍👧‍👦', 'Family-friendly content for all ages')
ON CONFLICT (category_code) DO NOTHING;

-- ================================================
-- 5. NOTIFICATION TYPES
-- ================================================

INSERT INTO notification_types (type_name, description, icon) VALUES
    ('like', 'Someone liked your content', '👍'),
    ('comment', 'New comment on your content', '💬'),
    ('follow', 'New follower', '👤'),
    ('mention', 'You were mentioned', '@'),
    ('community_invite', 'Invited to community', '📧'),
    ('tier_up', 'Tier progression achieved', '⬆️'),
    ('spoiler_report', 'Spoiler report (moderators)', '⚠️'),
    ('post_reply', 'Reply to your post', '↩️'),
    ('review_helpful', 'Your review was marked helpful', '✅'),
    ('new_content', 'New content in your favorite genre', '🎬')
ON CONFLICT (type_name) DO NOTHING;

-- ================================================
-- 6. INTERACTION TYPES
-- ================================================

INSERT INTO interaction_types (type_name, description, icon) VALUES
    ('like', 'Like content', '👍'),
    ('dislike', 'Dislike content', '👎'),
    ('share', 'Share content', '🔗'),
    ('bookmark', 'Bookmark for later', '🔖'),
    ('view', 'View content', '👁️')
ON CONFLICT (type_name) DO NOTHING;

-- ================================================
-- 7. REPORT TYPES
-- ================================================

INSERT INTO report_types (type_name, description, severity_level) VALUES
    ('spam', 'Spam or misleading content', 'low'),
    ('harassment', 'Harassment or bullying', 'high'),
    ('hate_speech', 'Hate speech or discrimination', 'critical'),
    ('spoilers', 'Unmarked spoilers', 'medium'),
    ('inappropriate', 'Inappropriate or offensive content', 'medium'),
    ('copyright', 'Copyright violation', 'high'),
    ('impersonation', 'Impersonation of another user', 'high'),
    ('self_harm', 'Self-harm or suicide content', 'critical'),
    ('misinformation', 'False or misleading information', 'medium')
ON CONFLICT (type_name) DO NOTHING;

-- ================================================
-- 8. SENTIMENT CATEGORIES
-- ================================================

INSERT INTO sentiment_categories (category_name, color_hex, icon) VALUES
    ('Excited', '#FF6B6B', '🎉'),
    ('Loved', '#FF1744', '❤️'),
    ('Happy', '#FFD700', '😊'),
    ('Satisfied', '#4CAF50', '😌'),
    ('Neutral', '#9E9E9E', '😐'),
    ('Confused', '#FFA726', '😕'),
    ('Disappointed', '#FF9800', '😞'),
    ('Angry', '#F44336', '😠'),
    ('Scared', '#9C27B0', '😨'),
    ('Sad', '#2196F3', '😢'),
    ('Bored', '#607D8B', '😴'),
    ('Disgusted', '#795548', '🤢')
ON CONFLICT (category_name) DO NOTHING;

-- ================================================
-- 9. SENTIMENT TAGS
-- ================================================

INSERT INTO sentiment_tags (tag_name, category_id) VALUES
    -- Excited
    ('Mind-Blown', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Excited')),
    ('Epic', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Excited')),
    ('Thrilling', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Excited')),
    ('Unexpected', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Excited')),
    -- Loved
    ('Heartwarming', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Loved')),
    ('Beautiful', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Loved')),
    ('Touching', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Loved')),
    ('Romantic', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Loved')),
    -- Happy
    ('Feel-Good', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Happy')),
    ('Uplifting', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Happy')),
    ('Cheerful', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Happy')),
    ('Funny', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Happy')),
    -- Satisfied
    ('Well-Made', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Satisfied')),
    ('Satisfying', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Satisfied')),
    ('Solid', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Satisfied')),
    ('Balanced', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Satisfied')),
    -- Disappointed
    ('Letdown', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Disappointed')),
    ('Underwhelming', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Disappointed')),
    ('Missed-Potential', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Disappointed')),
    -- Scared
    ('Terrifying', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Scared')),
    ('Creepy', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Scared')),
    ('Suspenseful', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Scared')),
    -- Sad
    ('Heartbreaking', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Sad')),
    ('Emotional', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Sad')),
    ('Tearjerker', (SELECT category_id FROM sentiment_categories WHERE category_name = 'Sad'))
ON CONFLICT (tag_name) DO NOTHING;

-- ================================================
-- 10. CONTENT REQUEST TYPES
-- ================================================

INSERT INTO content_request_types (type_name, description) VALUES
    ('missing_content', 'Request for missing movie or show'),
    ('incorrect_info', 'Report incorrect information'),
    ('duplicate_removal', 'Request duplicate content removal'),
    ('metadata_update', 'Request metadata corrections')
ON CONFLICT (type_name) DO NOTHING;

-- ================================================
-- 11. SAMPLE USERS
-- ================================================

INSERT INTO users (username, email, password_hash, first_name, last_name, date_of_birth, bio) VALUES
    ('movie_buff_2024', 'moviebuff@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Alex', 'Johnson', '1995-03-15', 'Film enthusiast and aspiring critic. Love sci-fi and thrillers!'),
    ('cinema_lover', 'cinemalover@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Sam', 'Chen', '1988-07-22', 'Watching movies since I could walk. Classics are my jam.'),
    ('binge_watcher', 'bingewatcher@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Jordan', 'Smith', '1992-11-30', 'TV show addict. Currently rewatching Breaking Bad for the 5th time.'),
    ('horror_fan_87', 'horrorfan@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Taylor', 'Martinez', '1987-10-31', 'If it doesn''t scare me, I''m not interested. 👻'),
    ('comedy_central', 'comedycentral@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Morgan', 'Lee', '1990-05-18', 'Life''s too short for bad comedies. Rom-coms are life!'),
    ('animation_artist', 'animationartist@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Casey', 'Williams', '1985-02-14', 'Pixar movies make me cry every time. Studio Ghibli fanatic.'),
    ('documentary_deep', 'docdiver@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Riley', 'Brown', '1993-09-09', 'Real stories > Fiction. Nature docs are my meditation.'),
    ('marvel_maniac', 'marvelmaniac@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Avery', 'Davis', '1996-06-01', 'MCU superfan. Watched Endgame 10 times in theaters.'),
    ('classic_cinema', 'classiccinema@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Quinn', 'Anderson', '1980-12-25', 'Hitchcock, Kubrick, Spielberg. The masters.'),
    ('streaming_scout', 'streamingscout@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8', 'Drew', 'Wilson', '1998-04-07', 'Always finding hidden gems on streaming platforms.')
RETURNING user_id;

-- ================================================
-- 12. INITIALIZE USER POINTS FOR SAMPLE USERS
-- ================================================

INSERT INTO user_points (user_id, current_tier_id, total_points, total_likes_received)
SELECT 
    user_id,
    (SELECT tier_id FROM ranking_tiers WHERE tier_name = 'Bronze'),
    0,
    0
FROM users
WHERE username IN ('movie_buff_2024', 'cinema_lover', 'binge_watcher', 'horror_fan_87', 'comedy_central', 
                   'animation_artist', 'documentary_deep', 'marvel_maniac', 'classic_cinema', 'streaming_scout');

-- ================================================
-- 13. CREATE USER PREFERENCES
-- ================================================

INSERT INTO preferences (user_id, theme, language, spoiler_protection_level, privacy_level)
SELECT 
    user_id,
    CASE (random() * 2)::INTEGER WHEN 0 THEN 'light' WHEN 1 THEN 'dark' ELSE 'auto' END,
    'en',
    CASE (random() * 2)::INTEGER WHEN 0 THEN 'off' WHEN 1 THEN 'moderate' ELSE 'strict' END,
    'public'
FROM users
WHERE username IN ('movie_buff_2024', 'cinema_lover', 'binge_watcher', 'horror_fan_87', 'comedy_central', 
                   'animation_artist', 'documentary_deep', 'marvel_maniac', 'classic_cinema', 'streaming_scout');

-- ================================================
-- 14. SAMPLE MOVIES
-- ================================================

INSERT INTO movies (title, description, release_date, duration, language, rating, director, country_of_origin, poster_url, backdrop_url) VALUES
    ('Inception', 'A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea into the mind of a C.E.O.', '2010-07-16', 148, 'English', 8.8, 'Christopher Nolan', 'USA', '/posters/inception.jpg', '/backdrops/inception.jpg'),
    ('The Dark Knight', 'When the menace known as the Joker wreaks havoc and chaos on the people of Gotham, Batman must accept one of the greatest psychological and physical tests of his ability to fight injustice.', '2008-07-18', 152, 'English', 9.0, 'Christopher Nolan', 'USA', '/posters/dark-knight.jpg', '/backdrops/dark-knight.jpg'),
    ('Interstellar', 'A team of explorers travel through a wormhole in space in an attempt to ensure humanity''s survival.', '2014-11-07', 169, 'English', 8.6, 'Christopher Nolan', 'USA', '/posters/interstellar.jpg', '/backdrops/interstellar.jpg'),
    ('The Shawshank Redemption', 'Two imprisoned men bond over a number of years, finding solace and eventual redemption through acts of common decency.', '1994-09-23', 142, 'English', 9.3, 'Frank Darabont', 'USA', '/posters/shawshank.jpg', '/backdrops/shawshank.jpg'),
    ('Pulp Fiction', 'The lives of two mob hitmen, a boxer, a gangster and his wife intertwine in four tales of violence and redemption.', '1994-10-14', 154, 'English', 8.9, 'Quentin Tarantino', 'USA', '/posters/pulp-fiction.jpg', '/backdrops/pulp-fiction.jpg'),
    ('The Matrix', 'A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.', '1999-03-31', 136, 'English', 8.7, 'Lana Wachowski, Lilly Wachowski', 'USA', '/posters/matrix.jpg', '/backdrops/matrix.jpg'),
    ('Forrest Gump', 'The presidencies of Kennedy and Johnson, the Vietnam War, and other historical events unfold from the perspective of an Alabama man with an IQ of 75.', '1994-07-06', 142, 'English', 8.8, 'Robert Zemeckis', 'USA', '/posters/forrest-gump.jpg', '/backdrops/forrest-gump.jpg'),
    ('Parasite', 'Greed and class discrimination threaten the newly formed symbiotic relationship between the wealthy Park family and the destitute Kim clan.', '2019-05-30', 132, 'Korean', 8.6, 'Bong Joon Ho', 'South Korea', '/posters/parasite.jpg', '/backdrops/parasite.jpg'),
    ('Spirited Away', 'During her family''s move to the suburbs, a sullen 10-year-old girl wanders into a world ruled by gods, witches, and spirits, where humans are changed into beasts.', '2001-07-20', 125, 'Japanese', 8.6, 'Hayao Miyazaki', 'Japan', '/posters/spirited-away.jpg', '/backdrops/spirited-away.jpg'),
    ('Get Out', 'A young African-American visits his white girlfriend''s parents for the weekend, where his simmering uneasiness about their reception of him eventually reaches a boiling point.', '2017-02-24', 104, 'English', 7.7, 'Jordan Peele', 'USA', '/posters/get-out.jpg', '/backdrops/get-out.jpg'),
    ('Everything Everywhere All at Once', 'An aging Chinese immigrant is swept up in an insane adventure, where she alone can save the world by exploring other universes.', '2022-03-25', 139, 'English', 7.8, 'Daniel Kwan, Daniel Scheinert', 'USA', '/posters/eeaao.jpg', '/backdrops/eeaao.jpg'),
    ('Oppenheimer', 'The story of American scientist J. Robert Oppenheimer and his role in the development of the atomic bomb.', '2023-07-21', 180, 'English', 8.3, 'Christopher Nolan', 'USA', '/posters/oppenheimer.jpg', '/backdrops/oppenheimer.jpg')
RETURNING movie_id, title;

-- ================================================
-- 15. SAMPLE TV SHOWS
-- ================================================

INSERT INTO shows (title, description, start_date, end_date, seasons, episodes_per_season, episode_duration, language, rating, creator, country_of_origin, poster_url, backdrop_url) VALUES
    ('Breaking Bad', 'A high school chemistry teacher turned methamphetamine producer partners with a former student to secure his family''s future.', '2008-01-20', '2013-09-29', 5, 13, 47, 'English', 9.5, 'Vince Gilligan', 'USA', '/posters/breaking-bad.jpg', '/backdrops/breaking-bad.jpg'),
    ('Game of Thrones', 'Nine noble families fight for control over the lands of Westeros, while an ancient enemy returns after being dormant for millennia.', '2011-04-17', '2019-05-19', 8, 10, 60, 'English', 9.2, 'David Benioff, D.B. Weiss', 'USA', '/posters/got.jpg', '/backdrops/got.jpg'),
    ('Stranger Things', 'When a young boy disappears, his mother, a police chief and his friends must confront terrifying supernatural forces to get him back.', '2016-07-15', NULL, 4, 8, 50, 'English', 8.7, 'The Duffer Brothers', 'USA', '/posters/stranger-things.jpg', '/backdrops/stranger-things.jpg'),
    ('The Last of Us', 'After a global pandemic destroys civilization, a hardened survivor takes charge of a 14-year-old girl who may be humanity''s last hope.', '2023-01-15', NULL, 1, 9, 60, 'English', 8.8, 'Craig Mazin, Neil Druckmann', 'USA', '/posters/tlou.jpg', '/backdrops/tlou.jpg'),
    ('The Office', 'A mockumentary on a group of typical office workers, where the workday consists of ego clashes, inappropriate behavior, and tedium.', '2005-03-24', '2013-05-16', 9, 22, 22, 'English', 9.0, 'Greg Daniels', 'USA', '/posters/office.jpg', '/backdrops/office.jpg'),
    ('Succession', 'The Roy family is known for controlling the biggest media and entertainment company in the world. However, their world changes when their father steps down from the company.', '2018-06-03', '2023-05-28', 4, 10, 60, 'English', 8.9, 'Jesse Armstrong', 'USA', '/posters/succession.jpg', '/backdrops/succession.jpg'),
    ('The Bear', 'A young chef from the fine dining world returns to Chicago to run his family''s sandwich shop.', '2022-06-23', NULL, 2, 10, 35, 'English', 8.6, 'Christopher Storer', 'USA', '/posters/bear.jpg', '/backdrops/bear.jpg'),
    ('Wednesday', 'Follows Wednesday Addams'' years as a student at Nevermore Academy, where she tries to master her psychic ability and solve a murder mystery.', '2022-11-23', NULL, 1, 8, 50, 'English', 8.1, 'Alfred Gough, Miles Millar', 'USA', '/posters/wednesday.jpg', '/backdrops/wednesday.jpg')
RETURNING show_id, title;

-- ================================================
-- 16. ASSOCIATE MOVIES WITH GENRES
-- ================================================

-- Inception: Action, Sci-Fi, Thriller
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Inception'),
    genre_id
FROM genres WHERE name IN ('Action', 'Sci-Fi', 'Thriller');

-- The Dark Knight: Action, Crime, Drama
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'The Dark Knight'),
    genre_id
FROM genres WHERE name IN ('Action', 'Crime', 'Drama');

-- Interstellar: Adventure, Drama, Sci-Fi
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Interstellar'),
    genre_id
FROM genres WHERE name IN ('Adventure', 'Drama', 'Sci-Fi');

-- The Shawshank Redemption: Drama
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'The Shawshank Redemption'),
    genre_id
FROM genres WHERE name IN ('Drama');

-- Pulp Fiction: Crime, Drama
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Pulp Fiction'),
    genre_id
FROM genres WHERE name IN ('Crime', 'Drama');

-- The Matrix: Action, Sci-Fi
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'The Matrix'),
    genre_id
FROM genres WHERE name IN ('Action', 'Sci-Fi');

-- Forrest Gump: Drama, Romance
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Forrest Gump'),
    genre_id
FROM genres WHERE name IN ('Drama', 'Romance');

-- Parasite: Drama, Thriller
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Parasite'),
    genre_id
FROM genres WHERE name IN ('Drama', 'Thriller');

-- Spirited Away: Animation, Adventure, Fantasy
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Spirited Away'),
    genre_id
FROM genres WHERE name IN ('Animation', 'Adventure', 'Fantasy');

-- Get Out: Horror, Mystery, Thriller
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Get Out'),
    genre_id
FROM genres WHERE name IN ('Horror', 'Mystery', 'Thriller');

-- Everything Everywhere All at Once: Action, Adventure, Comedy
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Everything Everywhere All at Once'),
    genre_id
FROM genres WHERE name IN ('Action', 'Adventure', 'Comedy');

-- Oppenheimer: Drama
INSERT INTO moviegenres (movie_id, genre_id)
SELECT 
    (SELECT movie_id FROM movies WHERE title = 'Oppenheimer'),
    genre_id
FROM genres WHERE name IN ('Drama');

-- ================================================
-- 17. ASSOCIATE SHOWS WITH GENRES
-- ================================================

-- Breaking Bad: Crime, Drama, Thriller
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'Breaking Bad'),
    genre_id
FROM genres WHERE name IN ('Crime', 'Drama', 'Thriller');

-- Game of Thrones: Action, Adventure, Drama, Fantasy
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'Game of Thrones'),
    genre_id
FROM genres WHERE name IN ('Action', 'Adventure', 'Drama', 'Fantasy');

-- Stranger Things: Drama, Fantasy, Horror, Mystery, Sci-Fi
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'Stranger Things'),
    genre_id
FROM genres WHERE name IN ('Drama', 'Fantasy', 'Horror', 'Mystery', 'Sci-Fi');

-- The Last of Us: Action, Adventure, Drama, Horror, Sci-Fi
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'The Last of Us'),
    genre_id
FROM genres WHERE name IN ('Action', 'Adventure', 'Drama', 'Horror', 'Sci-Fi');

-- The Office: Comedy
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'The Office'),
    genre_id
FROM genres WHERE name IN ('Comedy');

-- Succession: Drama
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'Succession'),
    genre_id
FROM genres WHERE name IN ('Drama');

-- The Bear: Comedy, Drama
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'The Bear'),
    genre_id
FROM genres WHERE name IN ('Comedy', 'Drama');

-- Wednesday: Comedy, Crime, Fantasy, Mystery
INSERT INTO showgenres (show_id, genre_id)
SELECT 
    (SELECT show_id FROM shows WHERE title = 'Wednesday'),
    genre_id
FROM genres WHERE name IN ('Comedy', 'Crime', 'Fantasy', 'Mystery');

-- ================================================
-- 18. ADD STREAMING PLATFORM AVAILABILITY
-- ================================================

-- Inception on Netflix and Max
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available, subscription_tier)
SELECT 
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Inception'),
    platform_id,
    TRUE,
    'Standard'
FROM streaming_platforms WHERE platform_code IN ('NETFLIX', 'MAX');

-- The Dark Knight on Max
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'The Dark Knight'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'MAX';

-- Interstellar on Prime Video
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Interstellar'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'PRIME_VIDEO';

-- Spirited Away on Max
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Spirited Away'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'MAX';

-- Breaking Bad on Netflix
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'show',
    (SELECT show_id FROM shows WHERE title = 'Breaking Bad'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'NETFLIX';

-- Stranger Things on Netflix
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'show',
    (SELECT show_id FROM shows WHERE title = 'Stranger Things'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'NETFLIX';

-- The Last of Us on Max
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'show',
    (SELECT show_id FROM shows WHERE title = 'The Last of Us'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'MAX';

-- The Office on Netflix
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'show',
    (SELECT show_id FROM shows WHERE title = 'The Office'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'NETFLIX';

-- Wednesday on Netflix
INSERT INTO content_platform_availability (content_type, content_id, platform_id, is_available)
SELECT 
    'show',
    (SELECT show_id FROM shows WHERE title = 'Wednesday'),
    platform_id,
    TRUE
FROM streaming_platforms WHERE platform_code = 'NETFLIX';

-- ================================================
-- 19. SAMPLE COMMUNITIES
-- ================================================

INSERT INTO communities (category_id, name, description, created_by, community_image, is_public)
SELECT 
    (SELECT category_id FROM community_categories WHERE category_code = 'HEROES_VILLAINS'),
    'Marvel Cinematic Universe',
    'Discuss all things MCU - from Iron Man to the latest releases. Spoiler tags required!',
    (SELECT user_id FROM users WHERE username = 'marvel_maniac'),
    '/communities/mcu.jpg',
    TRUE;

INSERT INTO communities (category_id, name, description, created_by, community_image, is_public)
SELECT 
    (SELECT category_id FROM community_categories WHERE category_code = 'MIND_BENDING'),
    'Christopher Nolan Fans',
    'Exploring the intricate narratives and stunning visuals of Nolan films. Time is relative here.',
    (SELECT user_id FROM users WHERE username = 'movie_buff_2024'),
    '/communities/nolan.jpg',
    TRUE;

INSERT INTO communities (category_id, name, description, created_by, community_image, is_public)
SELECT 
    (SELECT category_id FROM community_categories WHERE category_code = 'CHILLS_THRILLS'),
    'Horror Headquarters',
    'For those who love a good scare. Share your favorite horror films and discuss what keeps you up at night.',
    (SELECT user_id FROM users WHERE username = 'horror_fan_87'),
    '/communities/horror.jpg',
    TRUE;

INSERT INTO communities (category_id, name, description, created_by, community_image, is_public)
SELECT 
    (SELECT category_id FROM community_categories WHERE category_code = 'ANIMATION'),
    'Studio Ghibli Appreciation',
    'Celebrating the magical worlds of Hayao Miyazaki and Studio Ghibli. All ages welcome!',
    (SELECT user_id FROM users WHERE username = 'animation_artist'),
    '/communities/ghibli.jpg',
    TRUE;

-- ================================================
-- 20. SAMPLE REVIEWS
-- ================================================

-- Review 1: Inception by movie_buff_2024
INSERT INTO reviews (user_id, content_type, content_id, rating, review_text, contains_spoilers)
SELECT 
    (SELECT user_id FROM users WHERE username = 'movie_buff_2024'),
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Inception'),
    9.5,
    'Mind-bending masterpiece! Nolan delivers a stunning visual experience combined with a complex narrative that keeps you guessing. The dream-within-a-dream concept is executed perfectly. Hans Zimmer''s score is phenomenal. This is cinema at its finest.',
    FALSE;

-- Review 2: Breaking Bad by binge_watcher
INSERT INTO reviews (user_id, content_type, content_id, rating, review_text, contains_spoilers)
SELECT 
    (SELECT user_id FROM users WHERE username = 'binge_watcher'),
    'show',
    (SELECT show_id FROM shows WHERE title = 'Breaking Bad'),
    10.0,
    'The greatest TV show ever made. Walter White''s transformation is mesmerizing to watch. Every season builds on the last, creating tension that never lets up. Bryan Cranston and Aaron Paul deliver career-defining performances. Five seasons of pure perfection.',
    FALSE;

-- Review 3: Get Out by horror_fan_87
INSERT INTO reviews (user_id, content_type, content_id, rating, review_text, contains_spoilers)
SELECT 
    (SELECT user_id FROM users WHERE username = 'horror_fan_87'),
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Get Out'),
    9.0,
    'Jordan Peele''s directorial debut is a brilliant social thriller that uses horror to explore racism in America. The Sunken Place is one of the most terrifying concepts in recent horror. Daniel Kaluuya is phenomenal. This movie will stay with you long after the credits roll.',
    FALSE;

-- Review 4: Spirited Away by animation_artist
INSERT INTO reviews (user_id, content_type, content_id, rating, review_text, contains_spoilers)
SELECT 
    (SELECT user_id FROM users WHERE username = 'animation_artist'),
    'movie',
    (SELECT movie_id FROM movies WHERE title = 'Spirited Away'),
    10.0,
    'Miyazaki''s masterpiece. The animation is breathtaking, the story is enchanting, and the world-building is unparalleled. Every frame is a work of art. Chihiro''s journey is both magical and deeply emotional. This is why I fell in love with animation.',
    FALSE;

-- Review 5: The Office by comedy_central
INSERT INTO reviews (user_id, content_type, content_id, rating, review_text, contains_spoilers)
SELECT 
    (SELECT user_id FROM users WHERE username = 'comedy_central'),
    'show',
    (SELECT show_id FROM shows WHERE title = 'The Office'),
    9.5,
    'The mockumentary format works perfectly for this hilarious workplace comedy. Michael Scott is one of the greatest TV characters ever created. The Jim and Pam romance is adorable. Seasons 2-5 are comedy gold. Infinitely rewatchable comfort food.',
    FALSE;

COMMIT;

-- ================================================
-- VERIFY SAMPLE DATA
-- ================================================

\echo 'Sample data loaded successfully!'
\echo ''
\echo 'Summary:'
SELECT 
    'Users' as item,
    COUNT(*)::TEXT as count
FROM users
UNION ALL
SELECT 'Movies', COUNT(*)::TEXT FROM movies
UNION ALL
SELECT 'TV Shows', COUNT(*)::TEXT FROM shows
UNION ALL
SELECT 'Genres', COUNT(*)::TEXT FROM genres
UNION ALL
SELECT 'Streaming Platforms', COUNT(*)::TEXT FROM streaming_platforms
UNION ALL
SELECT 'Communities', COUNT(*)::TEXT FROM communities
UNION ALL
SELECT 'Reviews', COUNT(*)::TEXT FROM reviews
UNION ALL
SELECT 'Ranking Tiers', COUNT(*)::TEXT FROM ranking_tiers;