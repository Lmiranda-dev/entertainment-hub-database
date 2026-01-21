--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2025-07-25 11:23:13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 395 (class 1255 OID 26267)
-- Name: ai_enhanced_spoiler_check(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.ai_enhanced_spoiler_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    ai_result RECORD;
BEGIN
    -- First, run basic keyword check
    NEW := check_for_spoiler_keywords(NEW);
    
    -- If no keywords found, but text is long, run AI analysis
    IF NOT NEW.contains_spoilers AND LENGTH(NEW.review_text) > 100 THEN
        -- This would call your AI service (implemented in backend)
        -- For now, just flag for AI analysis
        INSERT INTO ai_processing_queue (content_type, content_id, job_type)
        VALUES ('review', NEW.review_id, 'spoiler_analysis');
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.ai_enhanced_spoiler_check() OWNER TO postgres;

--
-- TOC entry 422 (class 1255 OID 27336)
-- Name: calculate_trending_content(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_trending_content(p_trending_type character varying DEFAULT 'daily'::character varying, p_region character varying DEFAULT 'US'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    date_cutoff TIMESTAMP;
    current_date_calc DATE := CURRENT_DATE;
BEGIN
    -- Determine date cutoff based on trending type
    CASE p_trending_type
        WHEN 'daily' THEN date_cutoff := CURRENT_TIMESTAMP - INTERVAL '1 day';
        WHEN 'weekly' THEN date_cutoff := CURRENT_TIMESTAMP - INTERVAL '7 days';
        WHEN 'monthly' THEN date_cutoff := CURRENT_TIMESTAMP - INTERVAL '30 days';
        ELSE date_cutoff := CURRENT_TIMESTAMP - INTERVAL '1 day';
    END CASE;
    
    -- Clear existing trending data for this type and date
    DELETE FROM trending_content 
    WHERE trending_type = p_trending_type 
    AND region = p_region 
    AND date_calculated = current_date_calc;
    
    -- Calculate trending movies
    INSERT INTO trending_content (content_type, content_id, trending_type, region, rank_position, trending_score, view_count, interaction_count, date_calculated)
    SELECT 
        'movie',
        movie_id,
        p_trending_type,
        p_region,
        ROW_NUMBER() OVER (ORDER BY trending_score DESC),
        trending_score,
        view_count,
        interaction_count,
        current_date_calc
    FROM (
        SELECT 
            m.movie_id,
            -- Calculate trending score (views + interactions * 2 + reviews * 3)
            COALESCE(views.view_count, 0) + 
            COALESCE(interactions.interaction_count, 0) * 2 + 
            COALESCE(reviews.review_count, 0) * 3 as trending_score,
            COALESCE(views.view_count, 0) as view_count,
            COALESCE(interactions.interaction_count, 0) as interaction_count
        FROM movies m
        LEFT JOIN (
            SELECT 
                reference_id as movie_id,
                COUNT(*) as view_count
            FROM user_activity 
            WHERE activity_type = 'view_movie' 
            AND created_at >= date_cutoff
            AND reference_type = 'movie'
            GROUP BY reference_id
        ) views ON m.movie_id = views.movie_id
        LEFT JOIN (
            SELECT 
                content_id as movie_id,
                COUNT(*) as interaction_count
            FROM user_interactions 
            WHERE content_type = 'movie'
            AND created_at >= date_cutoff
            GROUP BY content_id
        ) interactions ON m.movie_id = interactions.movie_id
        LEFT JOIN (
            SELECT 
                content_id as movie_id,
                COUNT(*) as review_count
            FROM reviews 
            WHERE content_type = 'movie'
            AND created_at >= date_cutoff
            GROUP BY content_id
        ) reviews ON m.movie_id = reviews.movie_id
        WHERE COALESCE(views.view_count, 0) + COALESCE(interactions.interaction_count, 0) + COALESCE(reviews.review_count, 0) > 0
    ) trending_movies
    LIMIT 100;
    
    -- Calculate trending shows (similar logic)
    INSERT INTO trending_content (content_type, content_id, trending_type, region, rank_position, trending_score, view_count, interaction_count, date_calculated)
    SELECT 
        'show',
        show_id,
        p_trending_type,
        p_region,
        ROW_NUMBER() OVER (ORDER BY trending_score DESC),
        trending_score,
        view_count,
        interaction_count,
        current_date_calc
    FROM (
        SELECT 
            s.show_id,
            COALESCE(views.view_count, 0) + 
            COALESCE(interactions.interaction_count, 0) * 2 + 
            COALESCE(reviews.review_count, 0) * 3 as trending_score,
            COALESCE(views.view_count, 0) as view_count,
            COALESCE(interactions.interaction_count, 0) as interaction_count
        FROM shows s
        LEFT JOIN (
            SELECT 
                reference_id as show_id,
                COUNT(*) as view_count
            FROM user_activity 
            WHERE activity_type = 'view_show' 
            AND created_at >= date_cutoff
            AND reference_type = 'show'
            GROUP BY reference_id
        ) views ON s.show_id = views.show_id
        LEFT JOIN (
            SELECT 
                content_id as show_id,
                COUNT(*) as interaction_count
            FROM user_interactions 
            WHERE content_type = 'show'
            AND created_at >= date_cutoff
            GROUP BY content_id
        ) interactions ON s.show_id = interactions.show_id
        LEFT JOIN (
            SELECT 
                content_id as show_id,
                COUNT(*) as review_count
            FROM reviews 
            WHERE content_type = 'show'
            AND created_at >= date_cutoff
            GROUP BY content_id
        ) reviews ON s.show_id = reviews.show_id
        WHERE COALESCE(views.view_count, 0) + COALESCE(interactions.interaction_count, 0) + COALESCE(reviews.review_count, 0) > 0
    ) trending_shows
    LIMIT 100;
    
END;
$$;


ALTER FUNCTION public.calculate_trending_content(p_trending_type character varying, p_region character varying) OWNER TO postgres;

--
-- TOC entry 408 (class 1255 OID 27304)
-- Name: calculate_user_total_points(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_user_total_points() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    user_total INTEGER;
BEGIN
    -- Calculate total points for the user
    SELECT COALESCE(SUM(points_change), 0) 
    INTO user_total
    FROM point_transactions 
    WHERE user_id = NEW.user_id;
    
    -- Update user_points table
    INSERT INTO user_points (user_id, total_points)
    VALUES (NEW.user_id, user_total)
    ON CONFLICT (user_id) 
    DO UPDATE SET 
        total_points = user_total,
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_user_total_points() OWNER TO postgres;

--
-- TOC entry 426 (class 1255 OID 27524)
-- Name: check_duplicate_requests(character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_duplicate_requests(p_title character varying, p_content_type character varying, p_release_year integer DEFAULT NULL::integer) RETURNS TABLE(request_id integer, title character varying, content_type character varying, release_year integer, status character varying, similarity_score integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        mcr.request_id,
        mcr.title,
        mcr.content_type,
        mcr.release_year,
        mcr.status,
        -- Simple similarity scoring (can be enhanced with fuzzy matching)
        CASE 
            WHEN LOWER(mcr.title) = LOWER(p_title) THEN 100
            WHEN LOWER(mcr.title) LIKE '%' || LOWER(p_title) || '%' THEN 75
            WHEN LOWER(p_title) LIKE '%' || LOWER(mcr.title) || '%' THEN 75
            ELSE 50
        END as similarity_score
    FROM missing_content_requests mcr
    WHERE mcr.content_type = p_content_type
    AND mcr.status NOT IN ('rejected', 'duplicate')
    AND (
        LOWER(mcr.title) LIKE '%' || LOWER(p_title) || '%' 
        OR LOWER(p_title) LIKE '%' || LOWER(mcr.title) || '%'
        OR (p_release_year IS NOT NULL AND mcr.release_year = p_release_year)
    )
    ORDER BY similarity_score DESC, mcr.created_at DESC;
END;
$$;


ALTER FUNCTION public.check_duplicate_requests(p_title character varying, p_content_type character varying, p_release_year integer) OWNER TO postgres;

--
-- TOC entry 394 (class 1255 OID 26028)
-- Name: check_for_spoiler_keywords(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_for_spoiler_keywords() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    spoiler_keywords TEXT[];
    keyword TEXT;
BEGIN
    -- This would be expanded with actual keywords specific to each content
    -- In practice, you might load these from another table specific to the content
    spoiler_keywords := ARRAY['dies', 'killed', 'ending', 'twist', 'reveals', 'secret identity'];
    
    -- Check if any spoiler keywords are in the text
    FOREACH keyword IN ARRAY spoiler_keywords LOOP
        IF NEW.review_text ILIKE '%' || keyword || '%' THEN
            NEW.contains_spoilers := TRUE;
            RETURN NEW;
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_for_spoiler_keywords() OWNER TO postgres;

--
-- TOC entry 411 (class 1255 OID 25613)
-- Name: create_connection_notification(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_connection_notification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    notification_type_id_var INTEGER;
    should_notify BOOLEAN;
BEGIN
    -- Get the appropriate notification type
    IF NEW.connection_type = 'follow' THEN
        SELECT notification_type_id INTO notification_type_id_var 
        FROM notification_types 
        WHERE type_name = 'new_follower';
        
        -- Check if user wants follow notifications
        SELECT notification_follow INTO should_notify 
        FROM preferences 
        WHERE user_id = NEW.followed_id;
    ELSIF NEW.connection_type = 'friend' AND NEW.status = 'pending' THEN
        SELECT notification_type_id INTO notification_type_id_var 
        FROM notification_types 
        WHERE type_name = 'friend_request';
        
        -- Check if user wants friend request notifications
        SELECT notification_friend_request INTO should_notify 
        FROM preferences 
        WHERE user_id = NEW.followed_id;
    ELSIF NEW.connection_type = 'friend' AND NEW.status = 'accepted' THEN
        SELECT notification_type_id INTO notification_type_id_var 
        FROM notification_types 
        WHERE type_name = 'friend_accepted';
        
        -- Check if user wants friend acceptance notifications
        SELECT notification_friend_request INTO should_notify 
        FROM preferences 
        WHERE user_id = NEW.follower_id;
    END IF;
    
    -- Create notification if appropriate
    IF notification_type_id_var IS NOT NULL AND should_notify THEN
        -- For new/pending connection, notify the followed person
        IF NEW.status = 'pending' OR NEW.connection_type = 'follow' THEN
            INSERT INTO notifications (
                user_id, 
                notification_type_id, 
                sender_id, 
                message
            )
            VALUES (
                NEW.followed_id,
                notification_type_id_var,
                NEW.follower_id,
                CASE 
                    WHEN NEW.connection_type = 'follow' THEN 'You have a new follower'
                    WHEN NEW.connection_type = 'friend' THEN 'You have a new friend request'
                    ELSE 'You have a new connection'
                END
            );
        -- For accepted connections, notify the requester
        ELSIF NEW.status = 'accepted' THEN
            INSERT INTO notifications (
                user_id, 
                notification_type_id, 
                sender_id, 
                message
            )
            VALUES (
                NEW.follower_id,
                notification_type_id_var,
                NEW.followed_id,
                'Your friend request was accepted'
            );
        END IF;
    END IF;
    
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.create_connection_notification() OWNER TO postgres;

--
-- TOC entry 410 (class 1255 OID 25611)
-- Name: create_interaction_notification(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_interaction_notification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    receiver_id INTEGER;
    notification_type_id_var INTEGER;
    should_notify BOOLEAN;
BEGIN
    -- Determine the notification receiver and type based on interaction
    IF NEW.content_type = 'review' THEN
        -- Get the review owner
        SELECT user_id INTO receiver_id 
        FROM reviews 
        WHERE review_id = NEW.content_id;
        
        -- Set notification type
        IF NEW.interaction_type_id = (SELECT interaction_type_id FROM interaction_types WHERE type_name = 'like') THEN
            SELECT notification_type_id INTO notification_type_id_var 
            FROM notification_types 
            WHERE type_name = 'like_on_review';
        END IF;
    END IF;
    
    -- Don't notify yourself
    IF receiver_id = NEW.user_id THEN
        RETURN NULL;
    END IF;
    
    -- Check if the receiver wants this notification
    IF NEW.interaction_type_id = (SELECT interaction_type_id FROM interaction_types WHERE type_name = 'like') THEN
        SELECT notification_like INTO should_notify 
        FROM preferences 
        WHERE user_id = receiver_id;
    ELSE
        should_notify := TRUE; -- Default to notify for other types
    END IF;
    
    -- Create notification if appropriate
    IF receiver_id IS NOT NULL AND notification_type_id_var IS NOT NULL AND should_notify THEN
        INSERT INTO notifications (
            user_id, 
            notification_type_id, 
            sender_id, 
            content_type, 
            content_id, 
            message
        )
        VALUES (
            receiver_id,
            notification_type_id_var,
            NEW.user_id,
            NEW.content_type,
            NEW.content_id,
            'You have a new interaction on your content'
        );
    END IF;
    
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.create_interaction_notification() OWNER TO postgres;

--
-- TOC entry 413 (class 1255 OID 25900)
-- Name: export_current_movie_data(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.export_current_movie_data()
    LANGUAGE plpgsql
    AS $$
DECLARE
    movie_rec RECORD;
    movie_json JSONB;
BEGIN
    -- Export each movie as a separate JSON document
    FOR movie_rec IN SELECT movie_id FROM movies LOOP
        movie_json := get_movie_document(movie_rec.movie_id);
        
        -- This would be replaced with actual file writing logic
        -- In PostgreSQL you'd use COPY TO or a custom function with file_fdw
        -- In practice, this would run in application code, not in the database
        RAISE NOTICE 'Exporting movie %: %', movie_rec.movie_id, movie_json;
    END LOOP;
END;
$$;


ALTER PROCEDURE public.export_current_movie_data() OWNER TO postgres;

--
-- TOC entry 397 (class 1255 OID 25898)
-- Name: generate_trending_recommendations(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.generate_trending_recommendations()
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Clear old trending recommendations
    DELETE FROM augmented_recommendations WHERE recommendation_type = 'trending';
    
    -- Insert new trending recommendations based on recent activity
    INSERT INTO augmented_recommendations (user_id, content_type, content_id, recommendation_type, score, reasoning)
    SELECT 
        u.user_id,
        ui.content_type,
        ui.content_id,
        'trending',
        COUNT(*) * 0.01, -- Simple score based on interaction count
        'This content is trending right now'
    FROM users u
    CROSS JOIN (
        SELECT content_type, content_id, COUNT(*) as interaction_count
        FROM user_interactions
        WHERE created_at > (CURRENT_TIMESTAMP - INTERVAL '7 days')
        GROUP BY content_type, content_id
        ORDER BY interaction_count DESC
        LIMIT 20
    ) ui
    GROUP BY u.user_id, ui.content_type, ui.content_id
    ON CONFLICT (user_id, content_type, content_id, recommendation_type) 
    DO UPDATE SET score = EXCLUDED.score, created_at = CURRENT_TIMESTAMP;
    
    COMMIT;
END;
$$;


ALTER PROCEDURE public.generate_trending_recommendations() OWNER TO postgres;

--
-- TOC entry 417 (class 1255 OID 26240)
-- Name: get_content_sentiment_summary(character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_content_sentiment_summary(p_content_type character varying, p_content_id integer) RETURNS TABLE(total_reviews bigint, positive_percentage numeric, top_tags json, overall_mood character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(r.review_id) as total_reviews,
        ROUND(
            (COUNT(CASE WHEN ai.overall_sentiment IN ('positive', 'very_positive') THEN 1 END) * 100.0 / 
             NULLIF(COUNT(r.review_id), 0))::DECIMAL, 1
        ) as positive_percentage,
        (
            SELECT json_agg(json_build_object('tag', st.tag_name, 'count', tag_counts.tag_count))
            FROM (
                SELECT cst.tag_id, COUNT(*) as tag_count
                FROM content_sentiment_tags cst
                JOIN reviews rev ON cst.content_type = 'review' AND cst.content_id = rev.review_id
                WHERE rev.content_type = p_content_type AND rev.content_id = p_content_id
                GROUP BY cst.tag_id
                ORDER BY COUNT(*) DESC
                LIMIT 5
            ) tag_counts
            JOIN sentiment_tags st ON tag_counts.tag_id = st.tag_id
        ) as top_tags,
        CASE 
            WHEN AVG(r.rating) >= 8 THEN 'Very Positive'
            WHEN AVG(r.rating) >= 6 THEN 'Positive'  
            WHEN AVG(r.rating) >= 4 THEN 'Mixed'
            ELSE 'Negative'
        END as overall_mood
    FROM reviews r
    LEFT JOIN ai_sentiment_analysis ai ON ai.content_type = 'review' AND ai.content_id = r.review_id
    WHERE r.content_type = p_content_type AND r.content_id = p_content_id;
END;
$$;


ALTER FUNCTION public.get_content_sentiment_summary(p_content_type character varying, p_content_id integer) OWNER TO postgres;

--
-- TOC entry 412 (class 1255 OID 25899)
-- Name: get_movie_document(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_movie_document(movie_id_param integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', m.movie_id,
        'type', 'movie',
        'title', m.title,
        'description', m.description,
        'release_date', m.release_date,
        'duration', m.duration,
        'language', m.language,
        'rating', m.rating,
        'director', m.director,
        'country', m.country_of_origin,
        'media', jsonb_build_object(
            'poster', m.poster_url,
            'backdrop', m.backdrop_url,
            'trailer', m.trailer_url
        ),
        'genres', (
            SELECT jsonb_agg(jsonb_build_object('id', g.genre_id, 'name', g.name))
            FROM genres g
            JOIN moviegenres mg ON g.genre_id = mg.genre_id
            WHERE mg.movie_id = m.movie_id
        ),
        'stats', jsonb_build_object(
            'reviews', (SELECT COUNT(*) FROM reviews WHERE content_type = 'movie' AND content_id = m.movie_id),
            'average_rating', (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE content_type = 'movie' AND content_id = m.movie_id),
            'likes', (SELECT COUNT(*) FROM user_interactions 
                      WHERE content_type = 'movie' AND content_id = m.movie_id 
                      AND interaction_type_id = (SELECT interaction_type_id FROM interaction_types WHERE type_name = 'like')),
            'watchlists', (SELECT COUNT(*) FROM watchlist_items WHERE content_type = 'movie' AND content_id = m.movie_id)
        ),
        'reviews', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', r.review_id,
                'user', jsonb_build_object('id', u.user_id, 'username', u.username, 'profile_pic', u.profile_picture),
                'rating', r.rating,
                'text', r.review_text,
                'date', r.created_at
            ))
            FROM reviews r
            JOIN users u ON r.user_id = u.user_id
            WHERE r.content_type = 'movie' AND r.content_id = m.movie_id
            ORDER BY r.created_at DESC
            LIMIT 5
        )
    ) INTO result
    FROM movies m
    WHERE m.movie_id = movie_id_param;
    
    RETURN result;
END;
$$;


ALTER FUNCTION public.get_movie_document(movie_id_param integer) OWNER TO postgres;

--
-- TOC entry 425 (class 1255 OID 27523)
-- Name: get_request_statistics(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_request_statistics() RETURNS TABLE(total_requests bigint, pending_requests bigint, approved_requests bigint, rejected_requests bigint, added_requests bigint, avg_resolution_time interval)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_requests,
        COUNT(*) FILTER (WHERE status = 'pending') as pending_requests,
        COUNT(*) FILTER (WHERE status = 'approved') as approved_requests,
        COUNT(*) FILTER (WHERE status = 'rejected') as rejected_requests,
        COUNT(*) FILTER (WHERE status = 'added') as added_requests,
        AVG(resolved_at - created_at) FILTER (WHERE resolved_at IS NOT NULL) as avg_resolution_time
    FROM missing_content_requests;
END;
$$;


ALTER FUNCTION public.get_request_statistics() OWNER TO postgres;

--
-- TOC entry 423 (class 1255 OID 27337)
-- Name: get_roulette_recommendation(integer, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_roulette_recommendation(p_user_id integer, p_where_to_look character varying DEFAULT 'all'::character varying, p_content_type character varying DEFAULT 'all'::character varying, p_platform character varying DEFAULT 'all'::character varying) RETURNS TABLE(content_type character varying, content_id integer, title character varying, poster_url character varying, rating numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH filtered_content AS (
        SELECT 
            'movie' as content_type,
            m.movie_id as content_id,
            m.title,
            m.poster_url,
            m.rating
        FROM movies m
        WHERE (p_content_type = 'all' OR p_content_type = 'movie')
        AND (
            p_where_to_look = 'all' 
            OR (p_where_to_look = 'watchlist' AND EXISTS (
                SELECT 1 FROM watchlist_items wi 
                JOIN watchlists w ON wi.watchlist_id = w.watchlist_id
                WHERE w.user_id = p_user_id AND wi.content_type = 'movie' AND wi.content_id = m.movie_id
            ))
        )
        AND (
            p_platform = 'all'
            OR EXISTS (
                SELECT 1 FROM content_platform_availability cpa
                JOIN streaming_platforms sp ON cpa.platform_id = sp.platform_id
                WHERE cpa.content_type = 'movie' AND cpa.content_id = m.movie_id 
                AND sp.platform_code = p_platform AND cpa.is_available = TRUE
            )
        )
        
        UNION ALL
        
        SELECT 
            'show' as content_type,
            s.show_id as content_id,
            s.title,
            s.poster_url,
            s.rating
        FROM shows s
        WHERE (p_content_type = 'all' OR p_content_type = 'show')
        AND (
            p_where_to_look = 'all' 
            OR (p_where_to_look = 'watchlist' AND EXISTS (
                SELECT 1 FROM watchlist_items wi 
                JOIN watchlists w ON wi.watchlist_id = w.watchlist_id
                WHERE w.user_id = p_user_id AND wi.content_type = 'show' AND wi.content_id = s.show_id
            ))
        )
        AND (
            p_platform = 'all'
            OR EXISTS (
                SELECT 1 FROM content_platform_availability cpa
                JOIN streaming_platforms sp ON cpa.platform_id = sp.platform_id
                WHERE cpa.content_type = 'show' AND cpa.content_id = s.show_id 
                AND sp.platform_code = p_platform AND cpa.is_available = TRUE
            )
        )
    )
    SELECT 
        fc.content_type,
        fc.content_id,
        fc.title,
        fc.poster_url,
        fc.rating
    FROM filtered_content fc
    ORDER BY RANDOM()
    LIMIT 1;
END;
$$;


ALTER FUNCTION public.get_roulette_recommendation(p_user_id integer, p_where_to_look character varying, p_content_type character varying, p_platform character varying) OWNER TO postgres;

--
-- TOC entry 416 (class 1255 OID 26030)
-- Name: is_content_spoiler_for_user(integer, character varying, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_content_spoiler_for_user(p_user_id integer, p_content_type character varying, p_content_id integer, p_season integer DEFAULT NULL::integer, p_episode integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    user_progress RECORD;
BEGIN
    -- Get user's progress for this content
    SELECT * INTO user_progress
    FROM content_progress
    WHERE user_id = p_user_id
    AND content_type = p_content_type
    AND content_id = p_content_id;
    
    -- If no progress record, everything is a spoiler
    IF user_progress IS NULL THEN
        RETURN TRUE;
    END IF;
    
    -- For movies, check if completed
    IF p_content_type = 'movie' THEN
        RETURN NOT user_progress.completed;
    END IF;
    
    -- For shows, check episode progress
    IF p_content_type = 'show' AND p_season IS NOT NULL THEN
        -- If discussing a season the user hasn't reached
        IF p_season > user_progress.last_season_watched THEN
            RETURN TRUE;
        END IF;
        
        -- If same season but later episode
        IF p_season = user_progress.last_season_watched AND 
           p_episode IS NOT NULL AND 
           p_episode > user_progress.last_episode_watched THEN
            RETURN TRUE;
        END IF;
    END IF;
    
    RETURN FALSE;
END;
$$;


ALTER FUNCTION public.is_content_spoiler_for_user(p_user_id integer, p_content_type character varying, p_content_id integer, p_season integer, p_episode integer) OWNER TO postgres;

--
-- TOC entry 424 (class 1255 OID 27506)
-- Name: log_request_status_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_request_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only log if status actually changed
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO content_request_history (
            request_id,
            old_status,
            new_status,
            change_reason
        ) VALUES (
            NEW.request_id,
            OLD.status,
            NEW.status,
            CASE 
                WHEN NEW.status = 'approved' THEN 'Request approved by admin'
                WHEN NEW.status = 'rejected' THEN 'Request rejected: ' || COALESCE(NEW.rejection_reason, 'No reason provided')
                WHEN NEW.status = 'duplicate' THEN 'Marked as duplicate'
                WHEN NEW.status = 'added' THEN 'Content has been added to database'
                ELSE 'Status updated'
            END
        );
        
        -- Set resolved timestamp
        IF NEW.status IN ('approved', 'rejected', 'duplicate', 'added') THEN
            NEW.resolved_at = CURRENT_TIMESTAMP;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_request_status_change() OWNER TO postgres;

--
-- TOC entry 418 (class 1255 OID 26328)
-- Name: needs_discussion_summary(character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.needs_discussion_summary(p_content_type character varying, p_content_id integer, p_timeframe character varying DEFAULT 'weekly'::character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    last_summary_time TIMESTAMP;
    new_discussions_count INTEGER;
BEGIN
    -- Get the last summary time
    SELECT last_discussion_included INTO last_summary_time
    FROM gpt_summaries 
    WHERE content_type = p_content_type 
    AND content_id = p_content_id 
    AND discussion_timeframe = p_timeframe
    ORDER BY generated_at DESC 
    LIMIT 1;
    
    -- If no summary exists, we need one
    IF last_summary_time IS NULL THEN
        RETURN TRUE;
    END IF;
    
    -- Count new discussions since last summary
    SELECT COUNT(*) INTO new_discussions_count
    FROM (
        SELECT created_at FROM reviews 
        WHERE content_type = p_content_type 
        AND content_id = p_content_id 
        AND created_at > last_summary_time
        
        UNION ALL
        
        SELECT created_at FROM comments c
        JOIN reviews r ON c.review_id = r.review_id
        WHERE r.content_type = p_content_type 
        AND r.content_id = p_content_id 
        AND c.created_at > last_summary_time
    ) new_content;
    
    -- Need new summary if there are 5+ new discussions
    RETURN new_discussions_count >= 5;
END;
$$;


ALTER FUNCTION public.needs_discussion_summary(p_content_type character varying, p_content_id integer, p_timeframe character varying) OWNER TO postgres;

--
-- TOC entry 391 (class 1255 OID 26069)
-- Name: needs_gpt_summary(character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.needs_gpt_summary(p_content_type character varying, p_content_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    summary_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM gpt_summaries 
        WHERE content_type = p_content_type 
        AND content_id = p_content_id
        AND needs_refresh = FALSE
    ) INTO summary_exists;
    
    RETURN NOT summary_exists;
END;
$$;


ALTER FUNCTION public.needs_gpt_summary(p_content_type character varying, p_content_id integer) OWNER TO postgres;

--
-- TOC entry 414 (class 1255 OID 25912)
-- Name: queue_data_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.queue_data_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        INSERT INTO data_change_queue (table_name, operation, record_id)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.movie_id);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO data_change_queue (table_name, operation, record_id)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.movie_id);
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.queue_data_change() OWNER TO postgres;

--
-- TOC entry 389 (class 1255 OID 25876)
-- Name: refresh_all_materialized_views(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.refresh_all_materialized_views() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    view_name TEXT;
BEGIN
    FOR view_name IN SELECT matviewname FROM pg_matviews
    LOOP
        EXECUTE 'REFRESH MATERIALIZED VIEW ' || view_name;
    END LOOP;
END;
$$;


ALTER FUNCTION public.refresh_all_materialized_views() OWNER TO postgres;

--
-- TOC entry 421 (class 1255 OID 27307)
-- Name: track_user_activity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.track_user_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Track various user activities
    IF TG_TABLE_NAME = 'reviews' AND TG_OP = 'INSERT' THEN
        INSERT INTO user_activity (user_id, activity_type, reference_type, reference_id)
        VALUES (NEW.user_id, 'create_review', NEW.content_type, NEW.content_id);
        
        -- Award points for writing a review
        INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
        VALUES (NEW.user_id, 5, 'review_written', 'review', NEW.review_id, 'Wrote a review');
        
    ELSIF TG_TABLE_NAME = 'user_posts' AND TG_OP = 'INSERT' THEN
        INSERT INTO user_activity (user_id, activity_type, reference_type, reference_id)
        VALUES (NEW.user_id, 'create_post', 'post', NEW.post_id);
        
        -- Award points for creating a post
        INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
        VALUES (NEW.user_id, 3, 'post_created', 'post', NEW.post_id, 'Created a post');
        
    ELSIF TG_TABLE_NAME = 'community_posts' AND TG_OP = 'INSERT' THEN
        INSERT INTO user_activity (user_id, activity_type, reference_type, reference_id)
        VALUES (NEW.user_id, 'create_community_post', 'community_post', NEW.post_id);
        
        -- Award points for community post
        INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
        VALUES (NEW.user_id, 3, 'community_post_created', 'community_post', NEW.post_id, 'Created a community post');
        
    ELSIF TG_TABLE_NAME = 'comments' AND TG_OP = 'INSERT' THEN
        INSERT INTO user_activity (user_id, activity_type, reference_type, reference_id)
        VALUES (NEW.user_id, 'create_comment', 'comment', NEW.comment_id);
        
        -- Award points for comments
        INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
        VALUES (NEW.user_id, 1, 'comment_created', 'comment', NEW.comment_id, 'Posted a comment');
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.track_user_activity() OWNER TO postgres;

--
-- TOC entry 419 (class 1255 OID 27305)
-- Name: update_community_member_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_community_member_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.is_active = TRUE THEN
        UPDATE communities 
        SET member_count = member_count + 1 
        WHERE community_id = NEW.community_id;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.is_active = FALSE AND NEW.is_active = TRUE THEN
            UPDATE communities 
            SET member_count = member_count + 1 
            WHERE community_id = NEW.community_id;
        ELSIF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
            UPDATE communities 
            SET member_count = member_count - 1 
            WHERE community_id = NEW.community_id;
        END IF;
    ELSIF TG_OP = 'DELETE' AND OLD.is_active = TRUE THEN
        UPDATE communities 
        SET member_count = member_count - 1 
        WHERE community_id = OLD.community_id;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.update_community_member_count() OWNER TO postgres;

--
-- TOC entry 420 (class 1255 OID 27306)
-- Name: update_community_post_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_community_post_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE communities 
        SET post_count = post_count + 1 
        WHERE community_id = NEW.community_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE communities 
        SET post_count = post_count - 1 
        WHERE community_id = OLD.community_id;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.update_community_post_count() OWNER TO postgres;

--
-- TOC entry 393 (class 1255 OID 25603)
-- Name: update_interaction_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_interaction_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO interaction_counts (content_type, content_id, interaction_type_id, count)
        VALUES (NEW.content_type, NEW.content_id, NEW.interaction_type_id, 1)
        ON CONFLICT (content_type, content_id, interaction_type_id)
        DO UPDATE SET count = interaction_counts.count + 1, updated_at = CURRENT_TIMESTAMP;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE interaction_counts
        SET count = count - 1, updated_at = CURRENT_TIMESTAMP
        WHERE content_type = OLD.content_type 
          AND content_id = OLD.content_id 
          AND interaction_type_id = OLD.interaction_type_id;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_interaction_count() OWNER TO postgres;

--
-- TOC entry 415 (class 1255 OID 27504)
-- Name: update_missing_request_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_missing_request_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_missing_request_timestamp() OWNER TO postgres;

--
-- TOC entry 385 (class 1255 OID 25454)
-- Name: update_modified_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_modified_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_modified_column() OWNER TO postgres;

--
-- TOC entry 390 (class 1255 OID 25879)
-- Name: update_movie_genres_array(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_movie_genres_array() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE movies
    SET genres_array = ARRAY(
        SELECT g.name
        FROM genres g
        JOIN moviegenres mg ON g.genre_id = mg.genre_id
        WHERE mg.movie_id = NEW.movie_id
    )
    WHERE movie_id = NEW.movie_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_movie_genres_array() OWNER TO postgres;

--
-- TOC entry 392 (class 1255 OID 26238)
-- Name: update_sentiment_tag_usage(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_sentiment_tag_usage() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE sentiment_tags 
        SET usage_count = usage_count + 1 
        WHERE tag_id = NEW.tag_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE sentiment_tags 
        SET usage_count = GREATEST(usage_count - 1, 0) 
        WHERE tag_id = OLD.tag_id;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.update_sentiment_tag_usage() OWNER TO postgres;

--
-- TOC entry 396 (class 1255 OID 27303)
-- Name: update_user_points(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_user_points() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Award points based on interaction type
        CASE NEW.interaction_type
            WHEN 'like' THEN
                -- Award 1 point to the content creator for receiving a like
                INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
                SELECT 
                    u.user_id, 
                    1, 
                    'like_received', 
                    NEW.content_type, 
                    NEW.content_id,
                    'Received a like on ' || NEW.content_type
                FROM users u
                WHERE u.user_id = (
                    CASE 
                        WHEN NEW.content_type = 'review' THEN (SELECT user_id FROM reviews WHERE review_id = NEW.content_id)
                        WHEN NEW.content_type = 'post' THEN (SELECT user_id FROM user_posts WHERE post_id = NEW.content_id)
                        WHEN NEW.content_type = 'community_post' THEN (SELECT user_id FROM community_posts WHERE post_id = NEW.content_id)
                    END
                );
                
            WHEN 'share' THEN
                -- Award 2 points for shares
                INSERT INTO point_transactions (user_id, points_change, transaction_type, reference_type, reference_id, description)
                SELECT 
                    u.user_id, 
                    2, 
                    'share_received', 
                    NEW.content_type, 
                    NEW.content_id,
                    'Content was shared'
                FROM users u
                WHERE u.user_id = (
                    CASE 
                        WHEN NEW.content_type = 'review' THEN (SELECT user_id FROM reviews WHERE review_id = NEW.content_id)
                        WHEN NEW.content_type = 'post' THEN (SELECT user_id FROM user_posts WHERE post_id = NEW.content_id)
                        WHEN NEW.content_type = 'community_post' THEN (SELECT user_id FROM community_posts WHERE post_id = NEW.content_id)
                    END
                );
        END CASE;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.update_user_points() OWNER TO postgres;

--
-- TOC entry 388 (class 1255 OID 25464)
-- Name: validate_favorite_content(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_favorite_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.content_type = 'movie' THEN
        IF NOT EXISTS (SELECT 1 FROM movies WHERE movie_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid movie_id: %', NEW.content_id;
        END IF;
    ELSIF NEW.content_type = 'show' THEN
        IF NOT EXISTS (SELECT 1 FROM shows WHERE show_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid show_id: %', NEW.content_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_favorite_content() OWNER TO postgres;

--
-- TOC entry 386 (class 1255 OID 25460)
-- Name: validate_review_content(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_review_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.content_type = 'movie' THEN
        IF NOT EXISTS (SELECT 1 FROM movies WHERE movie_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid movie_id: %', NEW.content_id;
        END IF;
    ELSIF NEW.content_type = 'show' THEN
        IF NOT EXISTS (SELECT 1 FROM shows WHERE show_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid show_id: %', NEW.content_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_review_content() OWNER TO postgres;

--
-- TOC entry 387 (class 1255 OID 25462)
-- Name: validate_watchlist_item_content(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_watchlist_item_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.content_type = 'movie' THEN
        IF NOT EXISTS (SELECT 1 FROM movies WHERE movie_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid movie_id: %', NEW.content_id;
        END IF;
    ELSIF NEW.content_type = 'show' THEN
        IF NOT EXISTS (SELECT 1 FROM shows WHERE show_id = NEW.content_id) THEN
            RAISE EXCEPTION 'Invalid show_id: %', NEW.content_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_watchlist_item_content() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 379 (class 1259 OID 27453)
-- Name: content_request_comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_request_comments (
    comment_id integer NOT NULL,
    request_id integer NOT NULL,
    user_id integer NOT NULL,
    comment_text text NOT NULL,
    is_admin_comment boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.content_request_comments OWNER TO postgres;

--
-- TOC entry 377 (class 1259 OID 27431)
-- Name: content_request_votes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_request_votes (
    vote_id integer NOT NULL,
    request_id integer NOT NULL,
    user_id integer NOT NULL,
    vote_type character varying(10) DEFAULT 'support'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_request_votes_vote_type_check CHECK (((vote_type)::text = ANY ((ARRAY['support'::character varying, 'oppose'::character varying])::text[])))
);


ALTER TABLE public.content_request_votes OWNER TO postgres;

--
-- TOC entry 375 (class 1259 OID 27389)
-- Name: missing_content_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.missing_content_requests (
    request_id integer NOT NULL,
    user_id integer NOT NULL,
    content_type character varying(10) NOT NULL,
    title character varying(255) NOT NULL,
    release_year integer,
    additional_details text,
    status character varying(20) DEFAULT 'pending'::character varying,
    priority character varying(10) DEFAULT 'normal'::character varying,
    assigned_to integer,
    admin_notes text,
    rejection_reason text,
    duplicate_of integer,
    added_movie_id integer,
    added_show_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamp with time zone,
    CONSTRAINT missing_content_requests_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[]))),
    CONSTRAINT missing_content_requests_priority_check CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'normal'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))),
    CONSTRAINT missing_content_requests_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying, 'approved'::character varying, 'rejected'::character varying, 'duplicate'::character varying, 'added'::character varying])::text[]))),
    CONSTRAINT valid_content_link CHECK (((((content_type)::text = 'movie'::text) AND (added_movie_id IS NOT NULL) AND (added_show_id IS NULL)) OR (((content_type)::text = 'show'::text) AND (added_show_id IS NOT NULL) AND (added_movie_id IS NULL)) OR ((added_movie_id IS NULL) AND (added_show_id IS NULL))))
);


ALTER TABLE public.missing_content_requests OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 25263)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    first_name character varying(50),
    last_name character varying(50),
    date_of_birth date,
    profile_picture character varying(255),
    bio text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    last_login timestamp with time zone,
    is_active boolean DEFAULT true
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 382 (class 1259 OID 27508)
-- Name: admin_request_dashboard; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.admin_request_dashboard AS
 SELECT mcr.request_id,
    mcr.title,
    mcr.content_type,
    mcr.release_year,
    mcr.status,
    mcr.priority,
    mcr.created_at,
    u.username AS requester_username,
    admin_user.username AS assigned_admin,
    ( SELECT count(*) AS count
           FROM public.content_request_votes
          WHERE ((content_request_votes.request_id = mcr.request_id) AND ((content_request_votes.vote_type)::text = 'support'::text))) AS support_votes,
    ( SELECT count(*) AS count
           FROM public.content_request_comments
          WHERE (content_request_comments.request_id = mcr.request_id)) AS comment_count,
        CASE
            WHEN (mcr.created_at > (now() - '1 day'::interval)) THEN 'New'::text
            WHEN (mcr.created_at > (now() - '7 days'::interval)) THEN 'Recent'::text
            ELSE 'Older'::text
        END AS age_category
   FROM ((public.missing_content_requests mcr
     JOIN public.users u ON ((mcr.user_id = u.user_id)))
     LEFT JOIN public.users admin_user ON ((mcr.assigned_to = admin_user.user_id)))
  ORDER BY
        CASE mcr.priority
            WHEN 'urgent'::text THEN 1
            WHEN 'high'::text THEN 2
            WHEN 'normal'::text THEN 3
            WHEN 'low'::text THEN 4
            ELSE NULL::integer
        END, mcr.created_at DESC;


ALTER VIEW public.admin_request_dashboard OWNER TO postgres;

--
-- TOC entry 280 (class 1259 OID 26182)
-- Name: ai_sentiment_analysis; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ai_sentiment_analysis (
    analysis_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    overall_sentiment character varying(20),
    confidence_score numeric(5,4),
    emotion_scores jsonb,
    detected_categories jsonb,
    ai_model_used character varying(100),
    analysis_timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    needs_review boolean DEFAULT false,
    CONSTRAINT ai_sentiment_analysis_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying])::text[]))),
    CONSTRAINT ai_sentiment_analysis_overall_sentiment_check CHECK (((overall_sentiment)::text = ANY ((ARRAY['very_positive'::character varying, 'positive'::character varying, 'neutral'::character varying, 'negative'::character varying, 'very_negative'::character varying])::text[])))
);


ALTER TABLE public.ai_sentiment_analysis OWNER TO postgres;

--
-- TOC entry 279 (class 1259 OID 26181)
-- Name: ai_sentiment_analysis_analysis_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ai_sentiment_analysis_analysis_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ai_sentiment_analysis_analysis_id_seq OWNER TO postgres;

--
-- TOC entry 6277 (class 0 OID 0)
-- Dependencies: 279
-- Name: ai_sentiment_analysis_analysis_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ai_sentiment_analysis_analysis_id_seq OWNED BY public.ai_sentiment_analysis.analysis_id;


--
-- TOC entry 287 (class 1259 OID 26256)
-- Name: ai_spoiler_analysis; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ai_spoiler_analysis (
    analysis_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    original_text text NOT NULL,
    spoiler_probability numeric(5,4),
    spoiler_categories jsonb,
    ai_model_used character varying(100),
    confidence_score numeric(3,2),
    analyzed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    human_verified boolean DEFAULT false,
    CONSTRAINT ai_spoiler_analysis_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying])::text[])))
);


ALTER TABLE public.ai_spoiler_analysis OWNER TO postgres;

--
-- TOC entry 286 (class 1259 OID 26255)
-- Name: ai_spoiler_analysis_analysis_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ai_spoiler_analysis_analysis_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ai_spoiler_analysis_analysis_id_seq OWNER TO postgres;

--
-- TOC entry 6278 (class 0 OID 0)
-- Dependencies: 286
-- Name: ai_spoiler_analysis_analysis_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ai_spoiler_analysis_analysis_id_seq OWNED BY public.ai_spoiler_analysis.analysis_id;


--
-- TOC entry 222 (class 1259 OID 25299)
-- Name: genres; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.genres (
    genre_id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text
);


ALTER TABLE public.genres OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 25334)
-- Name: moviegenres; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.moviegenres (
    movie_id integer NOT NULL,
    genre_id integer NOT NULL
);


ALTER TABLE public.moviegenres OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 25310)
-- Name: movies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movies (
    movie_id integer NOT NULL,
    title character varying(255) NOT NULL,
    description text NOT NULL,
    release_date date,
    duration integer,
    language character varying(50),
    poster_url character varying(255),
    backdrop_url character varying(255),
    trailer_url character varying(255),
    rating numeric(3,1),
    director character varying(100),
    country_of_origin character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    genres_array text[],
    CONSTRAINT movies_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (10)::numeric)))
);


ALTER TABLE public.movies OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 25365)
-- Name: reviews; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reviews (
    review_id integer NOT NULL,
    user_id integer NOT NULL,
    content_type character varying(10) NOT NULL,
    content_id integer NOT NULL,
    rating integer NOT NULL,
    review_text text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    contains_spoilers boolean DEFAULT false,
    CONSTRAINT reviews_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[]))),
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 10)))
);


ALTER TABLE public.reviews OWNER TO postgres;

--
-- TOC entry 271 (class 1259 OID 26077)
-- Name: augmented_movies; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE MATERIALIZED VIEW public.augmented_movies AS
 SELECT movie_id,
    title,
    description,
    release_date,
    duration,
    rating,
    poster_url,
    backdrop_url,
    director,
    ( SELECT string_agg((g.name)::text, ', '::text) AS string_agg
           FROM (public.moviegenres mg
             JOIN public.genres g ON ((mg.genre_id = g.genre_id)))
          WHERE (mg.movie_id = m.movie_id)) AS genres,
    ( SELECT count(*) AS count
           FROM public.reviews
          WHERE (((reviews.content_type)::text = 'movie'::text) AND (reviews.content_id = m.movie_id))) AS review_count,
    ( SELECT COALESCE(avg(reviews.rating), (0)::numeric) AS "coalesce"
           FROM public.reviews
          WHERE (((reviews.content_type)::text = 'movie'::text) AND (reviews.content_id = m.movie_id))) AS user_rating
   FROM public.movies m
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.augmented_movies OWNER TO postgres;

--
-- TOC entry 254 (class 1259 OID 25882)
-- Name: augmented_recommendations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.augmented_recommendations (
    recommendation_id integer NOT NULL,
    user_id integer NOT NULL,
    content_type character varying(10) NOT NULL,
    content_id integer NOT NULL,
    recommendation_type character varying(50) NOT NULL,
    score numeric(5,4),
    reasoning text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.augmented_recommendations OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 25881)
-- Name: augmented_recommendations_recommendation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.augmented_recommendations_recommendation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.augmented_recommendations_recommendation_id_seq OWNER TO postgres;

--
-- TOC entry 6279 (class 0 OID 0)
-- Dependencies: 253
-- Name: augmented_recommendations_recommendation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.augmented_recommendations_recommendation_id_seq OWNED BY public.augmented_recommendations.recommendation_id;


--
-- TOC entry 228 (class 1259 OID 25349)
-- Name: showgenres; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.showgenres (
    show_id integer NOT NULL,
    genre_id integer NOT NULL
);


ALTER TABLE public.showgenres OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 25322)
-- Name: shows; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.shows (
    show_id integer NOT NULL,
    title character varying(255) NOT NULL,
    description text NOT NULL,
    start_date date,
    end_date date,
    seasons integer DEFAULT 1,
    episodes_per_season integer,
    episode_duration integer,
    language character varying(50),
    poster_url character varying(255),
    backdrop_url character varying(255),
    trailer_url character varying(255),
    rating numeric(3,1),
    creator character varying(100),
    country_of_origin character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    genres_array text[],
    CONSTRAINT shows_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (10)::numeric)))
);


ALTER TABLE public.shows OWNER TO postgres;

--
-- TOC entry 272 (class 1259 OID 26089)
-- Name: augmented_shows; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE MATERIALIZED VIEW public.augmented_shows AS
 SELECT show_id,
    title,
    description,
    start_date,
    seasons,
    rating,
    poster_url,
    creator,
    ( SELECT string_agg((g.name)::text, ', '::text) AS string_agg
           FROM (public.showgenres sg
             JOIN public.genres g ON ((sg.genre_id = g.genre_id)))
          WHERE (sg.show_id = s.show_id)) AS genres,
    ( SELECT count(*) AS count
           FROM public.reviews
          WHERE (((reviews.content_type)::text = 'show'::text) AND (reviews.content_id = s.show_id))) AS review_count,
    ( SELECT COALESCE(avg(reviews.rating), (0)::numeric) AS "coalesce"
           FROM public.reviews
          WHERE (((reviews.content_type)::text = 'show'::text) AND (reviews.content_id = s.show_id))) AS user_rating
   FROM public.shows s
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.augmented_shows OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 25434)
-- Name: favorites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.favorites (
    user_id integer NOT NULL,
    content_type character varying(10) NOT NULL,
    content_id integer NOT NULL,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT favorites_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.favorites OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 25278)
-- Name: preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.preferences (
    preference_id integer NOT NULL,
    user_id integer NOT NULL,
    theme character varying(20) DEFAULT 'light'::character varying,
    email_notifications boolean DEFAULT true,
    push_notifications boolean DEFAULT true,
    subtitle_language character varying(10) DEFAULT 'en'::character varying,
    autoplay boolean DEFAULT true,
    mature_content boolean DEFAULT false,
    privacy_level character varying(20) DEFAULT 'public'::character varying,
    notification_follow boolean DEFAULT true,
    notification_friend_request boolean DEFAULT true,
    notification_comment boolean DEFAULT true,
    notification_like boolean DEFAULT true,
    notification_mention boolean DEFAULT true,
    notification_content_update boolean DEFAULT true,
    show_spoilers boolean DEFAULT false,
    auto_hide_future_episodes boolean DEFAULT true,
    view_mode character varying(20) DEFAULT 'card'::character varying,
    sort_preference character varying(50) DEFAULT 'most_recent'::character varying,
    items_per_page integer DEFAULT 20,
    enable_autoplay boolean DEFAULT true,
    show_spoiler_warnings boolean DEFAULT true,
    enable_roulette_animations boolean DEFAULT true,
    homepage_layout character varying(30) DEFAULT 'default'::character varying
);


ALTER TABLE public.preferences OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 25492)
-- Name: user_connections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_connections (
    connection_id integer NOT NULL,
    follower_id integer NOT NULL,
    followed_id integer NOT NULL,
    connection_type character varying(20) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT no_self_connection CHECK ((follower_id <> followed_id)),
    CONSTRAINT user_connections_connection_type_check CHECK (((connection_type)::text = ANY ((ARRAY['follow'::character varying, 'friend'::character varying])::text[]))),
    CONSTRAINT user_connections_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'rejected'::character varying, 'blocked'::character varying])::text[])))
);


ALTER TABLE public.user_connections OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 25406)
-- Name: watchlists; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.watchlists (
    watchlist_id integer NOT NULL,
    user_id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    is_public boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.watchlists OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 25830)
-- Name: augmented_user_profiles; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE MATERIALIZED VIEW public.augmented_user_profiles AS
 SELECT u.user_id,
    u.username,
    u.first_name,
    u.last_name,
    u.profile_picture,
    u.bio,
    u.last_login,
    ( SELECT count(*) AS count
           FROM public.reviews
          WHERE (reviews.user_id = u.user_id)) AS review_count,
    ( SELECT count(*) AS count
           FROM public.watchlists
          WHERE (watchlists.user_id = u.user_id)) AS watchlist_count,
    ( SELECT count(*) AS count
           FROM public.user_connections
          WHERE ((user_connections.followed_id = u.user_id) AND ((user_connections.connection_type)::text = 'follow'::text))) AS follower_count,
    ( SELECT count(*) AS count
           FROM public.user_connections
          WHERE ((user_connections.follower_id = u.user_id) AND ((user_connections.connection_type)::text = 'follow'::text))) AS following_count,
    ( SELECT count(*) AS count
           FROM public.favorites
          WHERE (favorites.user_id = u.user_id)) AS favorites_count,
    ( SELECT count(*) AS count
           FROM public.user_connections
          WHERE (((user_connections.follower_id = u.user_id) OR (user_connections.followed_id = u.user_id)) AND ((user_connections.connection_type)::text = 'friend'::text) AND ((user_connections.status)::text = 'accepted'::text))) AS friend_count,
    p.theme,
    p.subtitle_language
   FROM (public.users u
     LEFT JOIN public.preferences p ON ((u.user_id = p.user_id)))
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.augmented_user_profiles OWNER TO postgres;

--
-- TOC entry 296 (class 1259 OID 26475)
-- Name: auth0_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth0_sessions (
    session_id integer NOT NULL,
    auth0_user_id integer NOT NULL,
    session_token character varying(500),
    refresh_token character varying(500),
    access_token character varying(1000),
    id_token character varying(1000),
    device_info text,
    ip_address character varying(45),
    user_agent text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp with time zone NOT NULL,
    last_accessed timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    revoked boolean DEFAULT false,
    revoked_at timestamp with time zone
);


ALTER TABLE public.auth0_sessions OWNER TO postgres;

--
-- TOC entry 6280 (class 0 OID 0)
-- Dependencies: 296
-- Name: TABLE auth0_sessions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.auth0_sessions IS 'Auth0 session and token management';


--
-- TOC entry 295 (class 1259 OID 26474)
-- Name: auth0_sessions_session_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auth0_sessions_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auth0_sessions_session_id_seq OWNER TO postgres;

--
-- TOC entry 6281 (class 0 OID 0)
-- Dependencies: 295
-- Name: auth0_sessions_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auth0_sessions_session_id_seq OWNED BY public.auth0_sessions.session_id;


--
-- TOC entry 294 (class 1259 OID 26453)
-- Name: auth0_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auth0_users (
    auth0_user_id integer NOT NULL,
    auth0_id character varying(255) NOT NULL,
    user_id integer,
    email character varying(255) NOT NULL,
    email_verified boolean DEFAULT false,
    provider character varying(50) NOT NULL,
    connection character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    last_login timestamp with time zone,
    login_count integer DEFAULT 0,
    auth0_metadata jsonb,
    app_metadata jsonb,
    profile_synced boolean DEFAULT false,
    sync_required boolean DEFAULT false
);


ALTER TABLE public.auth0_users OWNER TO postgres;

--
-- TOC entry 6282 (class 0 OID 0)
-- Dependencies: 294
-- Name: TABLE auth0_users; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.auth0_users IS 'Auth0 integration - links Auth0 identities to local users';


--
-- TOC entry 293 (class 1259 OID 26452)
-- Name: auth0_users_auth0_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auth0_users_auth0_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auth0_users_auth0_user_id_seq OWNER TO postgres;

--
-- TOC entry 6283 (class 0 OID 0)
-- Dependencies: 293
-- Name: auth0_users_auth0_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auth0_users_auth0_user_id_seq OWNED BY public.auth0_users.auth0_user_id;


--
-- TOC entry 232 (class 1259 OID 25385)
-- Name: comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comments (
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    review_id integer NOT NULL,
    comment_text text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    contains_spoilers boolean DEFAULT false
);


ALTER TABLE public.comments OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 25384)
-- Name: comments_comment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.comments_comment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.comments_comment_id_seq OWNER TO postgres;

--
-- TOC entry 6284 (class 0 OID 0)
-- Dependencies: 231
-- Name: comments_comment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.comments_comment_id_seq OWNED BY public.comments.comment_id;


--
-- TOC entry 320 (class 1259 OID 26766)
-- Name: communities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.communities (
    community_id integer NOT NULL,
    community_name character varying(200) NOT NULL,
    description text,
    community_type character varying(50) DEFAULT 'general'::character varying,
    category_id integer,
    content_type character varying(20),
    content_id integer,
    genre_id integer,
    creator_id integer NOT NULL,
    avatar_url character varying(500),
    banner_url character varying(500),
    member_count integer DEFAULT 0,
    post_count integer DEFAULT 0,
    is_private boolean DEFAULT false,
    is_featured boolean DEFAULT false,
    rules text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.communities OWNER TO postgres;

--
-- TOC entry 319 (class 1259 OID 26765)
-- Name: communities_community_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.communities_community_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.communities_community_id_seq OWNER TO postgres;

--
-- TOC entry 6285 (class 0 OID 0)
-- Dependencies: 319
-- Name: communities_community_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.communities_community_id_seq OWNED BY public.communities.community_id;


--
-- TOC entry 318 (class 1259 OID 26750)
-- Name: community_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.community_categories (
    category_id integer NOT NULL,
    category_name character varying(100) NOT NULL,
    category_code character varying(50) NOT NULL,
    description text,
    icon character varying(100),
    color_hex character varying(7),
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.community_categories OWNER TO postgres;

--
-- TOC entry 317 (class 1259 OID 26749)
-- Name: community_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.community_categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.community_categories_category_id_seq OWNER TO postgres;

--
-- TOC entry 6286 (class 0 OID 0)
-- Dependencies: 317
-- Name: community_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.community_categories_category_id_seq OWNED BY public.community_categories.category_id;


--
-- TOC entry 322 (class 1259 OID 26797)
-- Name: community_memberships; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.community_memberships (
    membership_id integer NOT NULL,
    community_id integer NOT NULL,
    user_id integer NOT NULL,
    role character varying(50) DEFAULT 'member'::character varying,
    joined_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true
);


ALTER TABLE public.community_memberships OWNER TO postgres;

--
-- TOC entry 321 (class 1259 OID 26796)
-- Name: community_memberships_membership_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.community_memberships_membership_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.community_memberships_membership_id_seq OWNER TO postgres;

--
-- TOC entry 6287 (class 0 OID 0)
-- Dependencies: 321
-- Name: community_memberships_membership_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.community_memberships_membership_id_seq OWNED BY public.community_memberships.membership_id;


--
-- TOC entry 326 (class 1259 OID 26848)
-- Name: community_post_comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.community_post_comments (
    comment_id integer NOT NULL,
    post_id integer NOT NULL,
    user_id integer NOT NULL,
    parent_comment_id integer,
    content text NOT NULL,
    like_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.community_post_comments OWNER TO postgres;

--
-- TOC entry 325 (class 1259 OID 26847)
-- Name: community_post_comments_comment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.community_post_comments_comment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.community_post_comments_comment_id_seq OWNER TO postgres;

--
-- TOC entry 6288 (class 0 OID 0)
-- Dependencies: 325
-- Name: community_post_comments_comment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.community_post_comments_comment_id_seq OWNED BY public.community_post_comments.comment_id;


--
-- TOC entry 324 (class 1259 OID 26819)
-- Name: community_posts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.community_posts (
    post_id integer NOT NULL,
    community_id integer NOT NULL,
    user_id integer NOT NULL,
    title character varying(500),
    content text NOT NULL,
    post_type character varying(50) DEFAULT 'text'::character varying,
    media_urls jsonb,
    external_url character varying(500),
    tags jsonb,
    like_count integer DEFAULT 0,
    comment_count integer DEFAULT 0,
    share_count integer DEFAULT 0,
    view_count integer DEFAULT 0,
    is_pinned boolean DEFAULT false,
    is_nsfw boolean DEFAULT false,
    contains_spoilers boolean DEFAULT false,
    spoiler_scope character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.community_posts OWNER TO postgres;

--
-- TOC entry 323 (class 1259 OID 26818)
-- Name: community_posts_post_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.community_posts_post_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.community_posts_post_id_seq OWNER TO postgres;

--
-- TOC entry 6289 (class 0 OID 0)
-- Dependencies: 323
-- Name: community_posts_post_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.community_posts_post_id_seq OWNED BY public.community_posts.post_id;


--
-- TOC entry 343 (class 1259 OID 27065)
-- Name: content_analytics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_analytics (
    analytics_id integer NOT NULL,
    content_type character varying(50) NOT NULL,
    content_id integer NOT NULL,
    metric_type character varying(50) NOT NULL,
    metric_value integer NOT NULL,
    date_recorded date NOT NULL,
    hour_recorded integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.content_analytics OWNER TO postgres;

--
-- TOC entry 342 (class 1259 OID 27064)
-- Name: content_analytics_analytics_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_analytics_analytics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_analytics_analytics_id_seq OWNER TO postgres;

--
-- TOC entry 6290 (class 0 OID 0)
-- Dependencies: 342
-- Name: content_analytics_analytics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_analytics_analytics_id_seq OWNED BY public.content_analytics.analytics_id;


--
-- TOC entry 355 (class 1259 OID 27150)
-- Name: content_discovery_metrics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_discovery_metrics (
    metric_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    discovery_source character varying(100) NOT NULL,
    user_id integer,
    resulted_in_engagement boolean DEFAULT false,
    engagement_type character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.content_discovery_metrics OWNER TO postgres;

--
-- TOC entry 354 (class 1259 OID 27149)
-- Name: content_discovery_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_discovery_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_discovery_metrics_metric_id_seq OWNER TO postgres;

--
-- TOC entry 6291 (class 0 OID 0)
-- Dependencies: 354
-- Name: content_discovery_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_discovery_metrics_metric_id_seq OWNED BY public.content_discovery_metrics.metric_id;


--
-- TOC entry 312 (class 1259 OID 26697)
-- Name: content_platform_availability; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_platform_availability (
    availability_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    platform_id integer NOT NULL,
    is_available boolean DEFAULT true,
    availability_region character varying(10) DEFAULT 'US'::character varying,
    added_date date,
    removal_date date,
    content_url character varying(500),
    last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_platform_availability_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.content_platform_availability OWNER TO postgres;

--
-- TOC entry 311 (class 1259 OID 26696)
-- Name: content_platform_availability_availability_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_platform_availability_availability_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_platform_availability_availability_id_seq OWNER TO postgres;

--
-- TOC entry 6292 (class 0 OID 0)
-- Dependencies: 311
-- Name: content_platform_availability_availability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_platform_availability_availability_id_seq OWNED BY public.content_platform_availability.availability_id;


--
-- TOC entry 258 (class 1259 OID 25919)
-- Name: content_progress; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_progress (
    progress_id integer NOT NULL,
    user_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    last_season_watched integer,
    last_episode_watched integer,
    completed boolean DEFAULT false,
    last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_progress_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.content_progress OWNER TO postgres;

--
-- TOC entry 257 (class 1259 OID 25918)
-- Name: content_progress_progress_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_progress_progress_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_progress_progress_id_seq OWNER TO postgres;

--
-- TOC entry 6293 (class 0 OID 0)
-- Dependencies: 257
-- Name: content_progress_progress_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_progress_progress_id_seq OWNED BY public.content_progress.progress_id;


--
-- TOC entry 302 (class 1259 OID 26543)
-- Name: content_reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_reports (
    report_id integer NOT NULL,
    reporter_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    report_type_id integer NOT NULL,
    reason text,
    evidence_urls jsonb,
    specific_excerpt text,
    status character varying(20) DEFAULT 'pending'::character varying,
    priority character varying(20) DEFAULT 'normal'::character varying,
    auto_flagged boolean DEFAULT false,
    ai_confidence_score numeric(3,2),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamp with time zone,
    assigned_moderator_id integer,
    moderator_notes text,
    resolution_action character varying(100),
    content_hidden boolean DEFAULT false,
    content_deleted boolean DEFAULT false,
    content_edited boolean DEFAULT false,
    CONSTRAINT content_reports_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying, 'discussion_post'::character varying, 'discussion_topic'::character varying])::text[]))),
    CONSTRAINT content_reports_priority_check CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'normal'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))),
    CONSTRAINT content_reports_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying, 'resolved'::character varying, 'dismissed'::character varying, 'escalated'::character varying])::text[])))
);


ALTER TABLE public.content_reports OWNER TO postgres;

--
-- TOC entry 6294 (class 0 OID 0)
-- Dependencies: 302
-- Name: TABLE content_reports; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.content_reports IS 'Reports made against content (reviews, comments, posts)';


--
-- TOC entry 301 (class 1259 OID 26542)
-- Name: content_reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_reports_report_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_reports_report_id_seq OWNER TO postgres;

--
-- TOC entry 6295 (class 0 OID 0)
-- Dependencies: 301
-- Name: content_reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_reports_report_id_seq OWNED BY public.content_reports.report_id;


--
-- TOC entry 378 (class 1259 OID 27452)
-- Name: content_request_comments_comment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_request_comments_comment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_request_comments_comment_id_seq OWNER TO postgres;

--
-- TOC entry 6296 (class 0 OID 0)
-- Dependencies: 378
-- Name: content_request_comments_comment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_request_comments_comment_id_seq OWNED BY public.content_request_comments.comment_id;


--
-- TOC entry 381 (class 1259 OID 27475)
-- Name: content_request_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_request_history (
    history_id integer NOT NULL,
    request_id integer NOT NULL,
    changed_by integer,
    old_status character varying(20),
    new_status character varying(20),
    change_reason text,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.content_request_history OWNER TO postgres;

--
-- TOC entry 380 (class 1259 OID 27474)
-- Name: content_request_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_request_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_request_history_history_id_seq OWNER TO postgres;

--
-- TOC entry 6297 (class 0 OID 0)
-- Dependencies: 380
-- Name: content_request_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_request_history_history_id_seq OWNED BY public.content_request_history.history_id;


--
-- TOC entry 373 (class 1259 OID 27376)
-- Name: content_request_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_request_types (
    request_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.content_request_types OWNER TO postgres;

--
-- TOC entry 372 (class 1259 OID 27375)
-- Name: content_request_types_request_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_request_types_request_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_request_types_request_type_id_seq OWNER TO postgres;

--
-- TOC entry 6298 (class 0 OID 0)
-- Dependencies: 372
-- Name: content_request_types_request_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_request_types_request_type_id_seq OWNED BY public.content_request_types.request_type_id;


--
-- TOC entry 376 (class 1259 OID 27430)
-- Name: content_request_votes_vote_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_request_votes_vote_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_request_votes_vote_id_seq OWNER TO postgres;

--
-- TOC entry 6299 (class 0 OID 0)
-- Dependencies: 376
-- Name: content_request_votes_vote_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_request_votes_vote_id_seq OWNED BY public.content_request_votes.vote_id;


--
-- TOC entry 282 (class 1259 OID 26197)
-- Name: content_sentiment_summary; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_sentiment_summary (
    summary_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    total_reviews integer DEFAULT 0,
    very_positive_count integer DEFAULT 0,
    positive_count integer DEFAULT 0,
    neutral_count integer DEFAULT 0,
    negative_count integer DEFAULT 0,
    very_negative_count integer DEFAULT 0,
    top_sentiment_tags jsonb,
    average_sentiment_score numeric(3,2),
    sentiment_trend character varying(20),
    last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_sentiment_summary_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.content_sentiment_summary OWNER TO postgres;

--
-- TOC entry 281 (class 1259 OID 26196)
-- Name: content_sentiment_summary_summary_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_sentiment_summary_summary_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_sentiment_summary_summary_id_seq OWNER TO postgres;

--
-- TOC entry 6300 (class 0 OID 0)
-- Dependencies: 281
-- Name: content_sentiment_summary_summary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_sentiment_summary_summary_id_seq OWNED BY public.content_sentiment_summary.summary_id;


--
-- TOC entry 278 (class 1259 OID 26161)
-- Name: content_sentiment_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_sentiment_tags (
    content_sentiment_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    tag_id integer NOT NULL,
    user_id integer NOT NULL,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_sentiment_tags_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying])::text[])))
);


ALTER TABLE public.content_sentiment_tags OWNER TO postgres;

--
-- TOC entry 277 (class 1259 OID 26160)
-- Name: content_sentiment_tags_content_sentiment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_sentiment_tags_content_sentiment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_sentiment_tags_content_sentiment_id_seq OWNER TO postgres;

--
-- TOC entry 6301 (class 0 OID 0)
-- Dependencies: 277
-- Name: content_sentiment_tags_content_sentiment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_sentiment_tags_content_sentiment_id_seq OWNED BY public.content_sentiment_tags.content_sentiment_id;


--
-- TOC entry 267 (class 1259 OID 26017)
-- Name: content_spoiler_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_spoiler_tags (
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    tag_id integer NOT NULL,
    CONSTRAINT content_spoiler_tags_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying, 'discussion_post'::character varying])::text[])))
);


ALTER TABLE public.content_spoiler_tags OWNER TO postgres;

--
-- TOC entry 314 (class 1259 OID 26717)
-- Name: content_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_status (
    status_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    status_type character varying(50) NOT NULL,
    status_date date,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT content_status_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.content_status OWNER TO postgres;

--
-- TOC entry 313 (class 1259 OID 26716)
-- Name: content_status_status_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.content_status_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.content_status_status_id_seq OWNER TO postgres;

--
-- TOC entry 6302 (class 0 OID 0)
-- Dependencies: 313
-- Name: content_status_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.content_status_status_id_seq OWNED BY public.content_status.status_id;


--
-- TOC entry 310 (class 1259 OID 26682)
-- Name: streaming_platforms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.streaming_platforms (
    platform_id integer NOT NULL,
    platform_name character varying(100) NOT NULL,
    platform_code character varying(20) NOT NULL,
    logo_url character varying(255),
    base_url character varying(255),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.streaming_platforms OWNER TO postgres;

--
-- TOC entry 370 (class 1259 OID 27326)
-- Name: content_with_streaming; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.content_with_streaming AS
 SELECT 'movie'::text AS content_type,
    m.movie_id AS content_id,
    m.title,
    m.description,
    m.poster_url,
    m.rating,
    m.release_date,
    m.director,
    ( SELECT json_agg(json_build_object('platform', sp.platform_name, 'platform_code', sp.platform_code, 'logo_url', sp.logo_url, 'content_url', cpa.content_url)) AS json_agg
           FROM (public.content_platform_availability cpa
             JOIN public.streaming_platforms sp ON ((cpa.platform_id = sp.platform_id)))
          WHERE (((cpa.content_type)::text = 'movie'::text) AND (cpa.content_id = m.movie_id) AND (cpa.is_available = true))) AS available_platforms,
    ( SELECT string_agg((g.name)::text, ', '::text) AS string_agg
           FROM (public.moviegenres mg
             JOIN public.genres g ON ((mg.genre_id = g.genre_id)))
          WHERE (mg.movie_id = m.movie_id)) AS genres
   FROM public.movies m
UNION ALL
 SELECT 'show'::text AS content_type,
    s.show_id AS content_id,
    s.title,
    s.description,
    s.poster_url,
    s.rating,
    s.start_date AS release_date,
    s.creator AS director,
    ( SELECT json_agg(json_build_object('platform', sp.platform_name, 'platform_code', sp.platform_code, 'logo_url', sp.logo_url, 'content_url', cpa.content_url)) AS json_agg
           FROM (public.content_platform_availability cpa
             JOIN public.streaming_platforms sp ON ((cpa.platform_id = sp.platform_id)))
          WHERE (((cpa.content_type)::text = 'show'::text) AND (cpa.content_id = s.show_id) AND (cpa.is_available = true))) AS available_platforms,
    ( SELECT string_agg((g.name)::text, ', '::text) AS string_agg
           FROM (public.showgenres sg
             JOIN public.genres g ON ((sg.genre_id = g.genre_id)))
          WHERE (sg.show_id = s.show_id)) AS genres
   FROM public.shows s;


ALTER VIEW public.content_with_streaming OWNER TO postgres;

--
-- TOC entry 256 (class 1259 OID 25902)
-- Name: data_change_queue; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.data_change_queue (
    change_id integer NOT NULL,
    table_name text NOT NULL,
    operation character varying(10) NOT NULL,
    record_id integer NOT NULL,
    change_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    processed boolean DEFAULT false
);


ALTER TABLE public.data_change_queue OWNER TO postgres;

--
-- TOC entry 255 (class 1259 OID 25901)
-- Name: data_change_queue_change_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.data_change_queue_change_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.data_change_queue_change_id_seq OWNER TO postgres;

--
-- TOC entry 6303 (class 0 OID 0)
-- Dependencies: 255
-- Name: data_change_queue_change_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.data_change_queue_change_id_seq OWNED BY public.data_change_queue.change_id;


--
-- TOC entry 264 (class 1259 OID 25979)
-- Name: discussion_posts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discussion_posts (
    post_id integer NOT NULL,
    topic_id integer NOT NULL,
    user_id integer NOT NULL,
    content text NOT NULL,
    contains_spoilers boolean DEFAULT false,
    spoiler_info character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.discussion_posts OWNER TO postgres;

--
-- TOC entry 263 (class 1259 OID 25978)
-- Name: discussion_posts_post_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discussion_posts_post_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discussion_posts_post_id_seq OWNER TO postgres;

--
-- TOC entry 6304 (class 0 OID 0)
-- Dependencies: 263
-- Name: discussion_posts_post_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discussion_posts_post_id_seq OWNED BY public.discussion_posts.post_id;


--
-- TOC entry 289 (class 1259 OID 26285)
-- Name: gpt_summaries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gpt_summaries (
    summary_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    discussion_timeframe character varying(30) NOT NULL,
    discussion_scope character varying(50),
    summary_type character varying(30) NOT NULL,
    summary_text text NOT NULL,
    total_discussions_analyzed integer DEFAULT 0,
    total_users_involved integer DEFAULT 0,
    sentiment_overview character varying(100),
    key_themes jsonb,
    spoiler_safe boolean DEFAULT true,
    spoiler_level character varying(30) DEFAULT 'none'::character varying,
    ai_model_used character varying(100) DEFAULT 'gpt-4'::character varying,
    model_provider character varying(50) DEFAULT 'openai'::character varying,
    generated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    source_discussions_count integer DEFAULT 0,
    confidence_score numeric(3,2),
    needs_refresh boolean DEFAULT false,
    last_discussion_included timestamp with time zone,
    CONSTRAINT gpt_summaries_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[]))),
    CONSTRAINT gpt_summaries_discussion_scope_check CHECK (((discussion_scope)::text = ANY ((ARRAY['all_discussions'::character varying, 'spoiler_free_only'::character varying, 'specific_topic'::character varying, 'trending_discussions'::character varying])::text[]))),
    CONSTRAINT gpt_summaries_discussion_timeframe_check CHECK (((discussion_timeframe)::text = ANY ((ARRAY['daily'::character varying, 'weekly'::character varying, 'monthly'::character varying, 'all_time'::character varying])::text[]))),
    CONSTRAINT gpt_summaries_spoiler_level_check CHECK (((spoiler_level)::text = ANY ((ARRAY['none'::character varying, 'minimal'::character varying, 'moderate'::character varying])::text[]))),
    CONSTRAINT gpt_summaries_summary_type_check CHECK (((summary_type)::text = ANY ((ARRAY['brief'::character varying, 'detailed'::character varying, 'highlights'::character varying])::text[])))
);


ALTER TABLE public.gpt_summaries OWNER TO postgres;

--
-- TOC entry 6305 (class 0 OID 0)
-- Dependencies: 289
-- Name: TABLE gpt_summaries; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.gpt_summaries IS 'AI-generated spoiler-free summaries of user discussions about movies and shows';


--
-- TOC entry 6306 (class 0 OID 0)
-- Dependencies: 289
-- Name: COLUMN gpt_summaries.discussion_timeframe; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gpt_summaries.discussion_timeframe IS 'Time period of discussions included in summary (daily, weekly, monthly, all_time)';


--
-- TOC entry 6307 (class 0 OID 0)
-- Dependencies: 289
-- Name: COLUMN gpt_summaries.discussion_scope; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gpt_summaries.discussion_scope IS 'What type of discussions were analyzed for this summary';


--
-- TOC entry 6308 (class 0 OID 0)
-- Dependencies: 289
-- Name: COLUMN gpt_summaries.total_discussions_analyzed; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gpt_summaries.total_discussions_analyzed IS 'Number of reviews, comments, and posts analyzed';


--
-- TOC entry 6309 (class 0 OID 0)
-- Dependencies: 289
-- Name: COLUMN gpt_summaries.sentiment_overview; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gpt_summaries.sentiment_overview IS 'General sentiment of discussions (e.g., "Mostly positive reactions with high excitement")';


--
-- TOC entry 6310 (class 0 OID 0)
-- Dependencies: 289
-- Name: COLUMN gpt_summaries.key_themes; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.gpt_summaries.key_themes IS 'Main discussion themes without spoilers (e.g., ["acting quality", "cinematography", "emotional impact"])';


--
-- TOC entry 292 (class 1259 OID 26329)
-- Name: discussion_summaries_with_content; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.discussion_summaries_with_content AS
 SELECT gs.summary_id,
    gs.content_type,
    gs.content_id,
    gs.discussion_timeframe,
    gs.discussion_scope,
    gs.summary_type,
    gs.summary_text,
    gs.total_discussions_analyzed,
    gs.total_users_involved,
    gs.sentiment_overview,
    gs.key_themes,
    gs.spoiler_safe,
    gs.spoiler_level,
    gs.ai_model_used,
    gs.model_provider,
    gs.generated_at,
    gs.source_discussions_count,
    gs.confidence_score,
    gs.needs_refresh,
    gs.last_discussion_included,
        CASE
            WHEN ((gs.content_type)::text = 'movie'::text) THEN m.title
            WHEN ((gs.content_type)::text = 'show'::text) THEN s.title
            ELSE NULL::character varying
        END AS content_title,
        CASE
            WHEN ((gs.content_type)::text = 'movie'::text) THEN (m.release_date)::text
            WHEN ((gs.content_type)::text = 'show'::text) THEN (s.start_date)::text
            ELSE NULL::text
        END AS content_release_date
   FROM ((public.gpt_summaries gs
     LEFT JOIN public.movies m ON ((((gs.content_type)::text = 'movie'::text) AND (gs.content_id = m.movie_id))))
     LEFT JOIN public.shows s ON ((((gs.content_type)::text = 'show'::text) AND (gs.content_id = s.show_id))));


ALTER VIEW public.discussion_summaries_with_content OWNER TO postgres;

--
-- TOC entry 291 (class 1259 OID 26313)
-- Name: discussion_summary_sources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discussion_summary_sources (
    source_id integer NOT NULL,
    summary_id integer NOT NULL,
    source_type character varying(20) NOT NULL,
    source_id_ref integer NOT NULL,
    included_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT discussion_summary_sources_source_type_check CHECK (((source_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying, 'discussion_post'::character varying])::text[])))
);


ALTER TABLE public.discussion_summary_sources OWNER TO postgres;

--
-- TOC entry 290 (class 1259 OID 26312)
-- Name: discussion_summary_sources_source_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discussion_summary_sources_source_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discussion_summary_sources_source_id_seq OWNER TO postgres;

--
-- TOC entry 6311 (class 0 OID 0)
-- Dependencies: 290
-- Name: discussion_summary_sources_source_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discussion_summary_sources_source_id_seq OWNED BY public.discussion_summary_sources.source_id;


--
-- TOC entry 262 (class 1259 OID 25961)
-- Name: discussion_topics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discussion_topics (
    topic_id integer NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    spoiler_scope character varying(50),
    created_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    CONSTRAINT discussion_topics_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[]))),
    CONSTRAINT discussion_topics_spoiler_scope_check CHECK (((spoiler_scope)::text = ANY ((ARRAY['trailer_only'::character varying, 'first_episode'::character varying, 'full_season'::character varying, 'entire_series'::character varying, 'none'::character varying])::text[])))
);


ALTER TABLE public.discussion_topics OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 25960)
-- Name: discussion_topics_topic_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discussion_topics_topic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discussion_topics_topic_id_seq OWNER TO postgres;

--
-- TOC entry 6312 (class 0 OID 0)
-- Dependencies: 261
-- Name: discussion_topics_topic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discussion_topics_topic_id_seq OWNED BY public.discussion_topics.topic_id;


--
-- TOC entry 349 (class 1259 OID 27100)
-- Name: featured_content; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.featured_content (
    featured_id integer NOT NULL,
    content_type character varying(50) NOT NULL,
    content_id integer NOT NULL,
    feature_type character varying(50) NOT NULL,
    feature_location character varying(100) NOT NULL,
    title character varying(255),
    description text,
    image_url character varying(500),
    start_date date,
    end_date date,
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.featured_content OWNER TO postgres;

--
-- TOC entry 348 (class 1259 OID 27099)
-- Name: featured_content_featured_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.featured_content_featured_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.featured_content_featured_id_seq OWNER TO postgres;

--
-- TOC entry 6313 (class 0 OID 0)
-- Dependencies: 348
-- Name: featured_content_featured_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.featured_content_featured_id_seq OWNED BY public.featured_content.featured_id;


--
-- TOC entry 221 (class 1259 OID 25298)
-- Name: genres_genre_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.genres_genre_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.genres_genre_id_seq OWNER TO postgres;

--
-- TOC entry 6314 (class 0 OID 0)
-- Dependencies: 221
-- Name: genres_genre_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.genres_genre_id_seq OWNED BY public.genres.genre_id;


--
-- TOC entry 270 (class 1259 OID 26062)
-- Name: gpt_api_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gpt_api_usage (
    usage_id integer NOT NULL,
    content_type character varying(20),
    content_id integer,
    tokens_used integer,
    cost_estimate numeric(8,4),
    model_used character varying(50),
    request_type character varying(30),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.gpt_api_usage OWNER TO postgres;

--
-- TOC entry 269 (class 1259 OID 26061)
-- Name: gpt_api_usage_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gpt_api_usage_usage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gpt_api_usage_usage_id_seq OWNER TO postgres;

--
-- TOC entry 6315 (class 0 OID 0)
-- Dependencies: 269
-- Name: gpt_api_usage_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gpt_api_usage_usage_id_seq OWNED BY public.gpt_api_usage.usage_id;


--
-- TOC entry 288 (class 1259 OID 26284)
-- Name: gpt_summaries_summary_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gpt_summaries_summary_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gpt_summaries_summary_id_seq OWNER TO postgres;

--
-- TOC entry 6316 (class 0 OID 0)
-- Dependencies: 288
-- Name: gpt_summaries_summary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gpt_summaries_summary_id_seq OWNED BY public.gpt_summaries.summary_id;


--
-- TOC entry 247 (class 1259 OID 25591)
-- Name: interaction_counts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interaction_counts (
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    interaction_type_id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.interaction_counts OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 25556)
-- Name: interaction_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interaction_types (
    interaction_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true
);


ALTER TABLE public.interaction_types OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 25555)
-- Name: interaction_types_interaction_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.interaction_types_interaction_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.interaction_types_interaction_type_id_seq OWNER TO postgres;

--
-- TOC entry 6317 (class 0 OID 0)
-- Dependencies: 243
-- Name: interaction_types_interaction_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.interaction_types_interaction_type_id_seq OWNED BY public.interaction_types.interaction_type_id;


--
-- TOC entry 249 (class 1259 OID 25786)
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.login_attempts (
    attempt_id integer NOT NULL,
    user_id integer,
    email character varying(100),
    ip_address character varying(45) NOT NULL,
    success boolean NOT NULL,
    attempted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.login_attempts OWNER TO postgres;

--
-- TOC entry 248 (class 1259 OID 25785)
-- Name: login_attempts_attempt_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.login_attempts_attempt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.login_attempts_attempt_id_seq OWNER TO postgres;

--
-- TOC entry 6318 (class 0 OID 0)
-- Dependencies: 248
-- Name: login_attempts_attempt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.login_attempts_attempt_id_seq OWNED BY public.login_attempts.attempt_id;


--
-- TOC entry 374 (class 1259 OID 27388)
-- Name: missing_content_requests_request_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.missing_content_requests_request_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.missing_content_requests_request_id_seq OWNER TO postgres;

--
-- TOC entry 6319 (class 0 OID 0)
-- Dependencies: 374
-- Name: missing_content_requests_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.missing_content_requests_request_id_seq OWNED BY public.missing_content_requests.request_id;


--
-- TOC entry 304 (class 1259 OID 26578)
-- Name: moderation_actions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.moderation_actions (
    action_id integer NOT NULL,
    moderator_id integer NOT NULL,
    action_type character varying(50) NOT NULL,
    target_type character varying(20),
    target_user_id integer,
    target_content_type character varying(20),
    target_content_id integer,
    related_report_id integer,
    related_report_type character varying(20),
    action_reason text NOT NULL,
    action_duration interval,
    action_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    reversed_at timestamp with time zone,
    reversed_by integer,
    reversal_reason text,
    CONSTRAINT moderation_actions_related_report_type_check CHECK (((related_report_type)::text = ANY ((ARRAY['user_report'::character varying, 'content_report'::character varying])::text[]))),
    CONSTRAINT moderation_actions_target_type_check CHECK (((target_type)::text = ANY ((ARRAY['user'::character varying, 'content'::character varying])::text[])))
);


ALTER TABLE public.moderation_actions OWNER TO postgres;

--
-- TOC entry 6320 (class 0 OID 0)
-- Dependencies: 304
-- Name: TABLE moderation_actions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.moderation_actions IS 'Log of all moderation actions taken';


--
-- TOC entry 303 (class 1259 OID 26577)
-- Name: moderation_actions_action_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.moderation_actions_action_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.moderation_actions_action_id_seq OWNER TO postgres;

--
-- TOC entry 6321 (class 0 OID 0)
-- Dependencies: 303
-- Name: moderation_actions_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.moderation_actions_action_id_seq OWNED BY public.moderation_actions.action_id;


--
-- TOC entry 300 (class 1259 OID 26508)
-- Name: user_reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_reports (
    report_id integer NOT NULL,
    reporter_id integer NOT NULL,
    reported_user_id integer NOT NULL,
    report_type_id integer NOT NULL,
    reason text,
    evidence_urls jsonb,
    status character varying(20) DEFAULT 'pending'::character varying,
    priority character varying(20) DEFAULT 'normal'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamp with time zone,
    assigned_moderator_id integer,
    moderator_notes text,
    resolution_action character varying(100),
    CONSTRAINT user_reports_priority_check CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'normal'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))),
    CONSTRAINT user_reports_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying, 'resolved'::character varying, 'dismissed'::character varying, 'escalated'::character varying])::text[])))
);


ALTER TABLE public.user_reports OWNER TO postgres;

--
-- TOC entry 6322 (class 0 OID 0)
-- Dependencies: 300
-- Name: TABLE user_reports; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.user_reports IS 'Reports made against users for behavior violations';


--
-- TOC entry 308 (class 1259 OID 26648)
-- Name: moderator_workload; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.moderator_workload AS
 SELECT u.username AS moderator,
    count(
        CASE
            WHEN ((ur.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END) AS active_user_reports,
    count(
        CASE
            WHEN ((cr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END) AS active_content_reports,
    (count(
        CASE
            WHEN ((ur.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END) + count(
        CASE
            WHEN ((cr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END)) AS total_active_reports
   FROM ((public.users u
     LEFT JOIN public.user_reports ur ON ((u.user_id = ur.assigned_moderator_id)))
     LEFT JOIN public.content_reports cr ON ((u.user_id = cr.assigned_moderator_id)))
  GROUP BY u.user_id, u.username
 HAVING ((count(
        CASE
            WHEN ((ur.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END) + count(
        CASE
            WHEN ((cr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END)) > 0)
  ORDER BY (count(
        CASE
            WHEN ((ur.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END) + count(
        CASE
            WHEN ((cr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[])) THEN 1
            ELSE NULL::integer
        END)) DESC;


ALTER VIEW public.moderator_workload OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 25309)
-- Name: movies_movie_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.movies_movie_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.movies_movie_id_seq OWNER TO postgres;

--
-- TOC entry 6323 (class 0 OID 0)
-- Dependencies: 223
-- Name: movies_movie_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.movies_movie_id_seq OWNED BY public.movies.movie_id;


--
-- TOC entry 240 (class 1259 OID 25517)
-- Name: notification_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notification_types (
    notification_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true
);


ALTER TABLE public.notification_types OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 25516)
-- Name: notification_types_notification_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.notification_types_notification_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_types_notification_type_id_seq OWNER TO postgres;

--
-- TOC entry 6324 (class 0 OID 0)
-- Dependencies: 239
-- Name: notification_types_notification_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.notification_types_notification_type_id_seq OWNED BY public.notification_types.notification_type_id;


--
-- TOC entry 242 (class 1259 OID 25529)
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    notification_id integer NOT NULL,
    user_id integer NOT NULL,
    notification_type_id integer NOT NULL,
    sender_id integer,
    content_type character varying(30),
    content_id integer,
    message text,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.notifications OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 25528)
-- Name: notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.notifications_notification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notifications_notification_id_seq OWNER TO postgres;

--
-- TOC entry 6325 (class 0 OID 0)
-- Dependencies: 241
-- Name: notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.notifications_notification_id_seq OWNED BY public.notifications.notification_id;


--
-- TOC entry 298 (class 1259 OID 26493)
-- Name: report_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_types (
    report_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    severity_level character varying(20),
    requires_immediate_action boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT report_types_severity_level_check CHECK (((severity_level)::text = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'critical'::character varying])::text[])))
);


ALTER TABLE public.report_types OWNER TO postgres;

--
-- TOC entry 6326 (class 0 OID 0)
-- Dependencies: 298
-- Name: TABLE report_types; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.report_types IS 'Types of reports that can be made (spam, harassment, etc.)';


--
-- TOC entry 307 (class 1259 OID 26643)
-- Name: pending_reports_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.pending_reports_summary AS
 SELECT 'user_report'::text AS report_source,
    ur.report_id,
    ur.created_at,
    ur.priority,
    rt.type_name AS report_type,
    rt.severity_level,
    u1.username AS reporter,
    u2.username AS reported_user,
    ur.status,
    ur.assigned_moderator_id
   FROM (((public.user_reports ur
     JOIN public.report_types rt ON ((ur.report_type_id = rt.report_type_id)))
     JOIN public.users u1 ON ((ur.reporter_id = u1.user_id)))
     JOIN public.users u2 ON ((ur.reported_user_id = u2.user_id)))
  WHERE ((ur.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[]))
UNION ALL
 SELECT 'content_report'::text AS report_source,
    cr.report_id,
    cr.created_at,
    cr.priority,
    rt.type_name AS report_type,
    rt.severity_level,
    u.username AS reporter,
    concat(cr.content_type, ' #', cr.content_id) AS reported_user,
    cr.status,
    cr.assigned_moderator_id
   FROM ((public.content_reports cr
     JOIN public.report_types rt ON ((cr.report_type_id = rt.report_type_id)))
     JOIN public.users u ON ((cr.reporter_id = u.user_id)))
  WHERE ((cr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[]))
  ORDER BY 4 DESC, 3 DESC;


ALTER VIEW public.pending_reports_summary OWNER TO postgres;

--
-- TOC entry 331 (class 1259 OID 26929)
-- Name: point_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.point_transactions (
    transaction_id integer NOT NULL,
    user_id integer NOT NULL,
    points_change integer NOT NULL,
    transaction_type character varying(50) NOT NULL,
    reference_type character varying(50),
    reference_id integer,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.point_transactions OWNER TO postgres;

--
-- TOC entry 330 (class 1259 OID 26928)
-- Name: point_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.point_transactions_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.point_transactions_transaction_id_seq OWNER TO postgres;

--
-- TOC entry 6327 (class 0 OID 0)
-- Dependencies: 330
-- Name: point_transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.point_transactions_transaction_id_seq OWNED BY public.point_transactions.transaction_id;


--
-- TOC entry 383 (class 1259 OID 27513)
-- Name: popular_content_requests; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.popular_content_requests AS
 SELECT mcr.request_id,
    mcr.title,
    mcr.content_type,
    mcr.release_year,
    mcr.status,
    mcr.created_at,
    u.username AS requester_username,
    count(crv.vote_id) AS vote_count,
    ( SELECT count(*) AS count
           FROM public.content_request_comments
          WHERE (content_request_comments.request_id = mcr.request_id)) AS comment_count
   FROM ((public.missing_content_requests mcr
     JOIN public.users u ON ((mcr.user_id = u.user_id)))
     LEFT JOIN public.content_request_votes crv ON (((mcr.request_id = crv.request_id) AND ((crv.vote_type)::text = 'support'::text))))
  WHERE ((mcr.status)::text = ANY ((ARRAY['pending'::character varying, 'under_review'::character varying])::text[]))
  GROUP BY mcr.request_id, mcr.title, mcr.content_type, mcr.release_year, mcr.status, mcr.created_at, u.username
 HAVING (count(crv.vote_id) > 0)
  ORDER BY (count(crv.vote_id)) DESC, mcr.created_at DESC;


ALTER VIEW public.popular_content_requests OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 25277)
-- Name: preferences_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.preferences_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.preferences_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6328 (class 0 OID 0)
-- Dependencies: 219
-- Name: preferences_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.preferences_preference_id_seq OWNED BY public.preferences.preference_id;


--
-- TOC entry 328 (class 1259 OID 26886)
-- Name: ranking_tiers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ranking_tiers (
    tier_id integer NOT NULL,
    tier_name character varying(50) NOT NULL,
    tier_code character varying(30) NOT NULL,
    min_likes integer NOT NULL,
    max_likes integer,
    points_reward integer DEFAULT 0,
    tier_color character varying(7),
    tier_icon character varying(100),
    benefits jsonb,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.ranking_tiers OWNER TO postgres;

--
-- TOC entry 327 (class 1259 OID 26885)
-- Name: ranking_tiers_tier_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ranking_tiers_tier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ranking_tiers_tier_id_seq OWNER TO postgres;

--
-- TOC entry 6329 (class 0 OID 0)
-- Dependencies: 327
-- Name: ranking_tiers_tier_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ranking_tiers_tier_id_seq OWNED BY public.ranking_tiers.tier_id;


--
-- TOC entry 306 (class 1259 OID 26606)
-- Name: report_escalations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_escalations (
    escalation_id integer NOT NULL,
    report_type character varying(20) NOT NULL,
    report_id integer NOT NULL,
    escalated_by integer NOT NULL,
    escalated_to integer,
    escalation_reason text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamp with time zone,
    resolution_notes text,
    CONSTRAINT report_escalations_report_type_check CHECK (((report_type)::text = ANY ((ARRAY['user_report'::character varying, 'content_report'::character varying])::text[]))),
    CONSTRAINT report_escalations_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'resolved'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public.report_escalations OWNER TO postgres;

--
-- TOC entry 6330 (class 0 OID 0)
-- Dependencies: 306
-- Name: TABLE report_escalations; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.report_escalations IS 'Escalation system for complex reports';


--
-- TOC entry 305 (class 1259 OID 26605)
-- Name: report_escalations_escalation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_escalations_escalation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_escalations_escalation_id_seq OWNER TO postgres;

--
-- TOC entry 6331 (class 0 OID 0)
-- Dependencies: 305
-- Name: report_escalations_escalation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_escalations_escalation_id_seq OWNED BY public.report_escalations.escalation_id;


--
-- TOC entry 297 (class 1259 OID 26492)
-- Name: report_types_report_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_types_report_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_types_report_type_id_seq OWNER TO postgres;

--
-- TOC entry 6332 (class 0 OID 0)
-- Dependencies: 297
-- Name: report_types_report_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_types_report_type_id_seq OWNED BY public.report_types.report_type_id;


--
-- TOC entry 229 (class 1259 OID 25364)
-- Name: reviews_review_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reviews_review_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reviews_review_id_seq OWNER TO postgres;

--
-- TOC entry 6333 (class 0 OID 0)
-- Dependencies: 229
-- Name: reviews_review_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reviews_review_id_seq OWNED BY public.reviews.review_id;


--
-- TOC entry 345 (class 1259 OID 27075)
-- Name: roulette_filters; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roulette_filters (
    filter_id integer NOT NULL,
    filter_name character varying(100) NOT NULL,
    filter_type character varying(50) NOT NULL,
    filter_value character varying(100) NOT NULL,
    display_name character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0
);


ALTER TABLE public.roulette_filters OWNER TO postgres;

--
-- TOC entry 344 (class 1259 OID 27074)
-- Name: roulette_filters_filter_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roulette_filters_filter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roulette_filters_filter_id_seq OWNER TO postgres;

--
-- TOC entry 6334 (class 0 OID 0)
-- Dependencies: 344
-- Name: roulette_filters_filter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roulette_filters_filter_id_seq OWNED BY public.roulette_filters.filter_id;


--
-- TOC entry 347 (class 1259 OID 27084)
-- Name: roulette_results; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roulette_results (
    result_id integer NOT NULL,
    user_id integer,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    filters_applied jsonb,
    was_instant boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.roulette_results OWNER TO postgres;

--
-- TOC entry 346 (class 1259 OID 27083)
-- Name: roulette_results_result_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roulette_results_result_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roulette_results_result_id_seq OWNER TO postgres;

--
-- TOC entry 6335 (class 0 OID 0)
-- Dependencies: 346
-- Name: roulette_results_result_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roulette_results_result_id_seq OWNED BY public.roulette_results.result_id;


--
-- TOC entry 351 (class 1259 OID 27117)
-- Name: search_analytics; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.search_analytics (
    search_id integer NOT NULL,
    user_id integer,
    search_term character varying(500),
    search_type character varying(50),
    filters_applied jsonb,
    results_count integer,
    clicked_result_type character varying(50),
    clicked_result_id integer,
    session_id character varying(100),
    ip_address character varying(45),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.search_analytics OWNER TO postgres;

--
-- TOC entry 350 (class 1259 OID 27116)
-- Name: search_analytics_search_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.search_analytics_search_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.search_analytics_search_id_seq OWNER TO postgres;

--
-- TOC entry 6336 (class 0 OID 0)
-- Dependencies: 350
-- Name: search_analytics_search_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.search_analytics_search_id_seq OWNED BY public.search_analytics.search_id;


--
-- TOC entry 274 (class 1259 OID 26129)
-- Name: sentiment_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sentiment_categories (
    category_id integer NOT NULL,
    category_name character varying(50) NOT NULL,
    description text,
    color_hex character varying(7),
    icon character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sentiment_categories OWNER TO postgres;

--
-- TOC entry 273 (class 1259 OID 26128)
-- Name: sentiment_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sentiment_categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sentiment_categories_category_id_seq OWNER TO postgres;

--
-- TOC entry 6337 (class 0 OID 0)
-- Dependencies: 273
-- Name: sentiment_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sentiment_categories_category_id_seq OWNED BY public.sentiment_categories.category_id;


--
-- TOC entry 276 (class 1259 OID 26142)
-- Name: sentiment_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sentiment_tags (
    tag_id integer NOT NULL,
    tag_name character varying(30) NOT NULL,
    category_id integer,
    description text,
    usage_count integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sentiment_tags OWNER TO postgres;

--
-- TOC entry 285 (class 1259 OID 26241)
-- Name: sentiment_enhanced_reviews; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.sentiment_enhanced_reviews AS
 SELECT r.review_id,
    r.user_id,
    u.username,
    r.content_type,
    r.content_id,
    r.rating,
    r.review_text,
    r.created_at,
    ai.overall_sentiment AS ai_sentiment,
    ai.confidence_score,
    ( SELECT json_agg(json_build_object('tag', st.tag_name, 'category', sc.category_name, 'color', sc.color_hex, 'icon', sc.icon)) AS json_agg
           FROM ((public.content_sentiment_tags cst
             JOIN public.sentiment_tags st ON ((cst.tag_id = st.tag_id)))
             JOIN public.sentiment_categories sc ON ((st.category_id = sc.category_id)))
          WHERE (((cst.content_type)::text = 'review'::text) AND (cst.content_id = r.review_id))) AS sentiment_tags
   FROM ((public.reviews r
     JOIN public.users u ON ((r.user_id = u.user_id)))
     LEFT JOIN public.ai_sentiment_analysis ai ON ((((ai.content_type)::text = 'review'::text) AND (ai.content_id = r.review_id))));


ALTER VIEW public.sentiment_enhanced_reviews OWNER TO postgres;

--
-- TOC entry 275 (class 1259 OID 26141)
-- Name: sentiment_tags_tag_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sentiment_tags_tag_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sentiment_tags_tag_id_seq OWNER TO postgres;

--
-- TOC entry 6338 (class 0 OID 0)
-- Dependencies: 275
-- Name: sentiment_tags_tag_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sentiment_tags_tag_id_seq OWNED BY public.sentiment_tags.tag_id;


--
-- TOC entry 225 (class 1259 OID 25321)
-- Name: shows_show_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.shows_show_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.shows_show_id_seq OWNER TO postgres;

--
-- TOC entry 6339 (class 0 OID 0)
-- Dependencies: 225
-- Name: shows_show_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.shows_show_id_seq OWNED BY public.shows.show_id;


--
-- TOC entry 260 (class 1259 OID 25936)
-- Name: spoiler_reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.spoiler_reports (
    report_id integer NOT NULL,
    reporter_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    reason text,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    resolved_at timestamp with time zone,
    resolved_by integer,
    CONSTRAINT spoiler_reports_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['review'::character varying, 'comment'::character varying])::text[]))),
    CONSTRAINT spoiler_reports_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public.spoiler_reports OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 25935)
-- Name: spoiler_reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.spoiler_reports_report_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.spoiler_reports_report_id_seq OWNER TO postgres;

--
-- TOC entry 6340 (class 0 OID 0)
-- Dependencies: 259
-- Name: spoiler_reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.spoiler_reports_report_id_seq OWNED BY public.spoiler_reports.report_id;


--
-- TOC entry 268 (class 1259 OID 26031)
-- Name: spoiler_safe_reviews; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.spoiler_safe_reviews AS
 SELECT r.review_id,
    r.user_id,
    u.username,
    r.content_type,
    r.content_id,
    r.rating,
        CASE
            WHEN r.contains_spoilers THEN 'This review contains spoilers. Click to reveal.'::text
            ELSE r.review_text
        END AS review_text,
    r.contains_spoilers,
    r.created_at
   FROM (public.reviews r
     JOIN public.users u ON ((r.user_id = u.user_id)));


ALTER VIEW public.spoiler_safe_reviews OWNER TO postgres;

--
-- TOC entry 266 (class 1259 OID 26001)
-- Name: spoiler_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.spoiler_tags (
    tag_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    tag_name character varying(100) NOT NULL,
    description text,
    is_major boolean DEFAULT false,
    created_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT spoiler_tags_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.spoiler_tags OWNER TO postgres;

--
-- TOC entry 265 (class 1259 OID 26000)
-- Name: spoiler_tags_tag_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.spoiler_tags_tag_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.spoiler_tags_tag_id_seq OWNER TO postgres;

--
-- TOC entry 6341 (class 0 OID 0)
-- Dependencies: 265
-- Name: spoiler_tags_tag_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.spoiler_tags_tag_id_seq OWNED BY public.spoiler_tags.tag_id;


--
-- TOC entry 309 (class 1259 OID 26681)
-- Name: streaming_platforms_platform_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.streaming_platforms_platform_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.streaming_platforms_platform_id_seq OWNER TO postgres;

--
-- TOC entry 6342 (class 0 OID 0)
-- Dependencies: 309
-- Name: streaming_platforms_platform_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.streaming_platforms_platform_id_seq OWNED BY public.streaming_platforms.platform_id;


--
-- TOC entry 316 (class 1259 OID 26729)
-- Name: trailers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trailers (
    trailer_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    trailer_title character varying(255) NOT NULL,
    trailer_url character varying(500) NOT NULL,
    trailer_type character varying(50) DEFAULT 'official'::character varying,
    duration_seconds integer,
    thumbnail_url character varying(500),
    release_date date,
    view_count integer DEFAULT 0,
    is_featured boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT trailers_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.trailers OWNER TO postgres;

--
-- TOC entry 315 (class 1259 OID 26728)
-- Name: trailers_trailer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trailers_trailer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trailers_trailer_id_seq OWNER TO postgres;

--
-- TOC entry 6343 (class 0 OID 0)
-- Dependencies: 315
-- Name: trailers_trailer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trailers_trailer_id_seq OWNED BY public.trailers.trailer_id;


--
-- TOC entry 341 (class 1259 OID 27052)
-- Name: trending_content; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trending_content (
    trending_id integer NOT NULL,
    content_type character varying(50) NOT NULL,
    content_id integer NOT NULL,
    trending_type character varying(50) NOT NULL,
    region character varying(10) DEFAULT 'US'::character varying,
    rank_position integer NOT NULL,
    trending_score numeric(10,4),
    view_count integer DEFAULT 0,
    interaction_count integer DEFAULT 0,
    growth_rate numeric(5,2),
    date_calculated date NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.trending_content OWNER TO postgres;

--
-- TOC entry 340 (class 1259 OID 27051)
-- Name: trending_content_trending_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trending_content_trending_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trending_content_trending_id_seq OWNER TO postgres;

--
-- TOC entry 6344 (class 0 OID 0)
-- Dependencies: 340
-- Name: trending_content_trending_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trending_content_trending_id_seq OWNED BY public.trending_content.trending_id;


--
-- TOC entry 369 (class 1259 OID 27321)
-- Name: trending_content_with_details; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.trending_content_with_details AS
 SELECT tc.trending_id,
    tc.content_type,
    tc.content_id,
    tc.trending_type,
    tc.rank_position,
    tc.trending_score,
    tc.view_count,
    tc.interaction_count,
    tc.growth_rate,
    tc.date_calculated,
        CASE
            WHEN ((tc.content_type)::text = 'movie'::text) THEN m.title
            WHEN ((tc.content_type)::text = 'show'::text) THEN s.title
            WHEN ((tc.content_type)::text = 'discussion'::text) THEN dt.title
            ELSE NULL::character varying
        END AS content_title,
        CASE
            WHEN ((tc.content_type)::text = 'movie'::text) THEN m.poster_url
            WHEN ((tc.content_type)::text = 'show'::text) THEN s.poster_url
            ELSE NULL::character varying
        END AS poster_url,
        CASE
            WHEN ((tc.content_type)::text = 'movie'::text) THEN m.rating
            WHEN ((tc.content_type)::text = 'show'::text) THEN s.rating
            ELSE NULL::numeric
        END AS content_rating
   FROM (((public.trending_content tc
     LEFT JOIN public.movies m ON ((((tc.content_type)::text = 'movie'::text) AND (tc.content_id = m.movie_id))))
     LEFT JOIN public.shows s ON ((((tc.content_type)::text = 'show'::text) AND (tc.content_id = s.show_id))))
     LEFT JOIN public.discussion_topics dt ON ((((tc.content_type)::text = 'discussion'::text) AND (tc.content_id = dt.topic_id))));


ALTER VIEW public.trending_content_with_details OWNER TO postgres;

--
-- TOC entry 333 (class 1259 OID 26944)
-- Name: user_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_activity (
    activity_id integer NOT NULL,
    user_id integer NOT NULL,
    activity_type character varying(50) NOT NULL,
    reference_type character varying(50),
    reference_id integer,
    metadata jsonb,
    ip_address character varying(45),
    user_agent text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_activity OWNER TO postgres;

--
-- TOC entry 332 (class 1259 OID 26943)
-- Name: user_activity_activity_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_activity_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_activity_activity_id_seq OWNER TO postgres;

--
-- TOC entry 6345 (class 0 OID 0)
-- Dependencies: 332
-- Name: user_activity_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_activity_activity_id_seq OWNED BY public.user_activity.activity_id;


--
-- TOC entry 237 (class 1259 OID 25491)
-- Name: user_connections_connection_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_connections_connection_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_connections_connection_id_seq OWNER TO postgres;

--
-- TOC entry 6346 (class 0 OID 0)
-- Dependencies: 237
-- Name: user_connections_connection_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_connections_connection_id_seq OWNED BY public.user_connections.connection_id;


--
-- TOC entry 367 (class 1259 OID 27276)
-- Name: user_device_preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_device_preferences (
    device_preference_id integer NOT NULL,
    user_id integer NOT NULL,
    device_type character varying(50) NOT NULL,
    preferred_layout character varying(50),
    enable_gestures boolean DEFAULT true,
    enable_animations boolean DEFAULT true,
    font_size character varying(20) DEFAULT 'medium'::character varying,
    last_used timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_device_preferences OWNER TO postgres;

--
-- TOC entry 366 (class 1259 OID 27275)
-- Name: user_device_preferences_device_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_device_preferences_device_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_device_preferences_device_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6347 (class 0 OID 0)
-- Dependencies: 366
-- Name: user_device_preferences_device_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_device_preferences_device_preference_id_seq OWNED BY public.user_device_preferences.device_preference_id;


--
-- TOC entry 359 (class 1259 OID 27206)
-- Name: user_filter_preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_filter_preferences (
    filter_preference_id integer NOT NULL,
    user_id integer NOT NULL,
    context character varying(100) NOT NULL,
    filter_data jsonb NOT NULL,
    last_used timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_filter_preferences OWNER TO postgres;

--
-- TOC entry 358 (class 1259 OID 27205)
-- Name: user_filter_preferences_filter_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_filter_preferences_filter_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_filter_preferences_filter_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6348 (class 0 OID 0)
-- Dependencies: 358
-- Name: user_filter_preferences_filter_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_filter_preferences_filter_preference_id_seq OWNED BY public.user_filter_preferences.filter_preference_id;


--
-- TOC entry 363 (class 1259 OID 27238)
-- Name: user_homepage_sections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_homepage_sections (
    section_id integer NOT NULL,
    user_id integer NOT NULL,
    section_type character varying(100) NOT NULL,
    is_visible boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    section_settings jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_homepage_sections OWNER TO postgres;

--
-- TOC entry 362 (class 1259 OID 27237)
-- Name: user_homepage_sections_section_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_homepage_sections_section_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_homepage_sections_section_id_seq OWNER TO postgres;

--
-- TOC entry 6349 (class 0 OID 0)
-- Dependencies: 362
-- Name: user_homepage_sections_section_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_homepage_sections_section_id_seq OWNED BY public.user_homepage_sections.section_id;


--
-- TOC entry 246 (class 1259 OID 25568)
-- Name: user_interactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_interactions (
    interaction_id integer NOT NULL,
    user_id integer NOT NULL,
    interaction_type_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    value jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_interactions OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 25567)
-- Name: user_interactions_interaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_interactions_interaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_interactions_interaction_id_seq OWNER TO postgres;

--
-- TOC entry 6350 (class 0 OID 0)
-- Dependencies: 245
-- Name: user_interactions_interaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_interactions_interaction_id_seq OWNED BY public.user_interactions.interaction_id;


--
-- TOC entry 365 (class 1259 OID 27258)
-- Name: user_notification_preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_notification_preferences (
    notification_preference_id integer NOT NULL,
    user_id integer NOT NULL,
    notification_category character varying(100) NOT NULL,
    delivery_method character varying(50) NOT NULL,
    is_enabled boolean DEFAULT true,
    frequency character varying(30) DEFAULT 'immediate'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_notification_preferences OWNER TO postgres;

--
-- TOC entry 364 (class 1259 OID 27257)
-- Name: user_notification_preferences_notification_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_notification_preferences_notification_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_notification_preferences_notification_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6351 (class 0 OID 0)
-- Dependencies: 364
-- Name: user_notification_preferences_notification_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_notification_preferences_notification_preference_id_seq OWNED BY public.user_notification_preferences.notification_preference_id;


--
-- TOC entry 329 (class 1259 OID 26900)
-- Name: user_points; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_points (
    user_id integer NOT NULL,
    total_points integer DEFAULT 0,
    total_likes_received integer DEFAULT 0,
    total_dislikes_received integer DEFAULT 0,
    current_tier_id integer,
    like_points integer DEFAULT 0,
    post_points integer DEFAULT 0,
    review_points integer DEFAULT 0,
    share_points integer DEFAULT 0,
    comment_points integer DEFAULT 0,
    daily_streak integer DEFAULT 0,
    longest_streak integer DEFAULT 0,
    last_activity_date date,
    tier_updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_points OWNER TO postgres;

--
-- TOC entry 337 (class 1259 OID 26988)
-- Name: user_post_interactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_post_interactions (
    interaction_id integer NOT NULL,
    post_id integer NOT NULL,
    user_id integer NOT NULL,
    interaction_type character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_post_interactions OWNER TO postgres;

--
-- TOC entry 336 (class 1259 OID 26987)
-- Name: user_post_interactions_interaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_post_interactions_interaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_post_interactions_interaction_id_seq OWNER TO postgres;

--
-- TOC entry 6352 (class 0 OID 0)
-- Dependencies: 336
-- Name: user_post_interactions_interaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_post_interactions_interaction_id_seq OWNED BY public.user_post_interactions.interaction_id;


--
-- TOC entry 339 (class 1259 OID 27008)
-- Name: user_post_replies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_post_replies (
    reply_id integer NOT NULL,
    post_id integer NOT NULL,
    user_id integer NOT NULL,
    parent_reply_id integer,
    content text NOT NULL,
    like_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_post_replies OWNER TO postgres;

--
-- TOC entry 338 (class 1259 OID 27007)
-- Name: user_post_replies_reply_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_post_replies_reply_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_post_replies_reply_id_seq OWNER TO postgres;

--
-- TOC entry 6353 (class 0 OID 0)
-- Dependencies: 338
-- Name: user_post_replies_reply_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_post_replies_reply_id_seq OWNED BY public.user_post_replies.reply_id;


--
-- TOC entry 335 (class 1259 OID 26959)
-- Name: user_posts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_posts (
    post_id integer NOT NULL,
    user_id integer NOT NULL,
    content text NOT NULL,
    post_type character varying(50) DEFAULT 'text'::character varying,
    media_urls jsonb,
    tags jsonb,
    mentioned_users jsonb,
    original_post_id integer,
    like_count integer DEFAULT 0,
    repost_count integer DEFAULT 0,
    comment_count integer DEFAULT 0,
    view_count integer DEFAULT 0,
    is_trending boolean DEFAULT false,
    visibility character varying(20) DEFAULT 'public'::character varying,
    contains_spoilers boolean DEFAULT false,
    content_reference_type character varying(50),
    content_reference_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_posts OWNER TO postgres;

--
-- TOC entry 334 (class 1259 OID 26958)
-- Name: user_posts_post_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_posts_post_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_posts_post_id_seq OWNER TO postgres;

--
-- TOC entry 6354 (class 0 OID 0)
-- Dependencies: 334
-- Name: user_posts_post_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_posts_post_id_seq OWNED BY public.user_posts.post_id;


--
-- TOC entry 368 (class 1259 OID 27316)
-- Name: user_profiles_with_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.user_profiles_with_stats AS
 SELECT u.user_id,
    u.username,
    u.first_name,
    u.last_name,
    u.profile_picture,
    u.bio,
    u.created_at AS join_date,
    u.last_login,
    up.total_points,
    up.total_likes_received,
    up.total_dislikes_received,
    rt.tier_name,
    rt.tier_color,
    rt.tier_icon,
    rt.tier_code,
    rt.description AS tier_description,
        CASE
            WHEN (rt.max_likes IS NOT NULL) THEN round(((((up.total_likes_received - rt.min_likes))::numeric / ((rt.max_likes - rt.min_likes))::numeric) * (100)::numeric), 1)
            ELSE 100.0
        END AS tier_progress_percentage,
    ( SELECT ranking_tiers.tier_name
           FROM public.ranking_tiers
          WHERE (ranking_tiers.min_likes > COALESCE(up.total_likes_received, 0))
          ORDER BY ranking_tiers.min_likes
         LIMIT 1) AS next_tier_name,
    ( SELECT ranking_tiers.min_likes
           FROM public.ranking_tiers
          WHERE (ranking_tiers.min_likes > COALESCE(up.total_likes_received, 0))
          ORDER BY ranking_tiers.min_likes
         LIMIT 1) AS next_tier_likes_needed,
    ( SELECT count(*) AS count
           FROM public.user_connections
          WHERE ((user_connections.followed_id = u.user_id) AND ((user_connections.status)::text = 'accepted'::text))) AS follower_count,
    ( SELECT count(*) AS count
           FROM public.user_connections
          WHERE ((user_connections.follower_id = u.user_id) AND ((user_connections.status)::text = 'accepted'::text))) AS following_count,
    ( SELECT count(*) AS count
           FROM public.reviews
          WHERE (reviews.user_id = u.user_id)) AS review_count,
    ( SELECT count(*) AS count
           FROM public.user_posts
          WHERE (user_posts.user_id = u.user_id)) AS post_count,
    ( SELECT count(*) AS count
           FROM public.community_posts
          WHERE (community_posts.user_id = u.user_id)) AS community_post_count,
    ( SELECT count(*) AS count
           FROM public.comments
          WHERE (comments.user_id = u.user_id)) AS comment_count,
    ( SELECT user_activity.activity_type
           FROM public.user_activity
          WHERE (user_activity.user_id = u.user_id)
          ORDER BY user_activity.created_at DESC
         LIMIT 1) AS last_activity
   FROM ((public.users u
     LEFT JOIN public.user_points up ON ((u.user_id = up.user_id)))
     LEFT JOIN public.ranking_tiers rt ON ((up.current_tier_id = rt.tier_id)));


ALTER VIEW public.user_profiles_with_stats OWNER TO postgres;

--
-- TOC entry 371 (class 1259 OID 27331)
-- Name: user_recently_viewed; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.user_recently_viewed AS
 SELECT ua.user_id,
    ua.activity_type,
    ua.reference_type,
    ua.reference_id,
    ua.created_at,
        CASE
            WHEN ((ua.reference_type)::text = 'movie'::text) THEN m.title
            WHEN ((ua.reference_type)::text = 'show'::text) THEN s.title
            WHEN ((ua.reference_type)::text = 'discussion_topic'::text) THEN dt.title
            WHEN ((ua.reference_type)::text = 'community'::text) THEN c.community_name
            ELSE NULL::character varying
        END AS content_title,
        CASE
            WHEN ((ua.reference_type)::text = 'movie'::text) THEN m.poster_url
            WHEN ((ua.reference_type)::text = 'show'::text) THEN s.poster_url
            WHEN ((ua.reference_type)::text = 'community'::text) THEN c.avatar_url
            ELSE NULL::character varying
        END AS content_image,
        CASE
            WHEN ((ua.reference_type)::text = 'movie'::text) THEN m.release_date
            WHEN ((ua.reference_type)::text = 'show'::text) THEN s.start_date
            WHEN ((ua.reference_type)::text = 'discussion_topic'::text) THEN (dt.created_at)::date
            WHEN ((ua.reference_type)::text = 'community'::text) THEN (c.created_at)::date
            ELSE NULL::date
        END AS content_date
   FROM ((((public.user_activity ua
     LEFT JOIN public.movies m ON ((((ua.reference_type)::text = 'movie'::text) AND (ua.reference_id = m.movie_id))))
     LEFT JOIN public.shows s ON ((((ua.reference_type)::text = 'show'::text) AND (ua.reference_id = s.show_id))))
     LEFT JOIN public.discussion_topics dt ON ((((ua.reference_type)::text = 'discussion_topic'::text) AND (ua.reference_id = dt.topic_id))))
     LEFT JOIN public.communities c ON ((((ua.reference_type)::text = 'community'::text) AND (ua.reference_id = c.community_id))))
  WHERE ((ua.activity_type)::text = ANY ((ARRAY['view_movie'::character varying, 'view_show'::character varying, 'view_discussion'::character varying, 'view_community'::character varying])::text[]));


ALTER VIEW public.user_recently_viewed OWNER TO postgres;

--
-- TOC entry 299 (class 1259 OID 26507)
-- Name: user_reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_reports_report_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_reports_report_id_seq OWNER TO postgres;

--
-- TOC entry 6355 (class 0 OID 0)
-- Dependencies: 299
-- Name: user_reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_reports_report_id_seq OWNED BY public.user_reports.report_id;


--
-- TOC entry 384 (class 1259 OID 27518)
-- Name: user_request_history; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.user_request_history AS
 SELECT mcr.request_id,
    mcr.title,
    mcr.content_type,
    mcr.release_year,
    mcr.status,
    mcr.created_at,
    mcr.resolved_at,
    count(crv.vote_id) AS support_votes,
        CASE
            WHEN (((mcr.status)::text = 'added'::text) AND ((mcr.content_type)::text = 'movie'::text)) THEN m.title
            WHEN (((mcr.status)::text = 'added'::text) AND ((mcr.content_type)::text = 'show'::text)) THEN s.title
            ELSE NULL::character varying
        END AS added_content_title
   FROM (((public.missing_content_requests mcr
     LEFT JOIN public.content_request_votes crv ON (((mcr.request_id = crv.request_id) AND ((crv.vote_type)::text = 'support'::text))))
     LEFT JOIN public.movies m ON ((mcr.added_movie_id = m.movie_id)))
     LEFT JOIN public.shows s ON ((mcr.added_show_id = s.show_id)))
  GROUP BY mcr.request_id, mcr.title, mcr.content_type, mcr.release_year, mcr.status, mcr.created_at, mcr.resolved_at, m.title, s.title;


ALTER VIEW public.user_request_history OWNER TO postgres;

--
-- TOC entry 284 (class 1259 OID 26216)
-- Name: user_sentiment_patterns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sentiment_patterns (
    pattern_id integer NOT NULL,
    user_id integer NOT NULL,
    favorite_sentiment_tags jsonb,
    sentiment_tendencies jsonb,
    genre_sentiment_patterns jsonb,
    last_analyzed timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_sentiment_patterns OWNER TO postgres;

--
-- TOC entry 283 (class 1259 OID 26215)
-- Name: user_sentiment_patterns_pattern_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_sentiment_patterns_pattern_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_sentiment_patterns_pattern_id_seq OWNER TO postgres;

--
-- TOC entry 6356 (class 0 OID 0)
-- Dependencies: 283
-- Name: user_sentiment_patterns_pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_sentiment_patterns_pattern_id_seq OWNED BY public.user_sentiment_patterns.pattern_id;


--
-- TOC entry 353 (class 1259 OID 27132)
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sessions (
    session_id integer NOT NULL,
    user_id integer,
    session_uuid character varying(100) NOT NULL,
    start_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    end_time timestamp with time zone,
    page_views integer DEFAULT 0,
    interactions integer DEFAULT 0,
    device_type character varying(50),
    browser character varying(100),
    ip_address character varying(45),
    is_active boolean DEFAULT true
);


ALTER TABLE public.user_sessions OWNER TO postgres;

--
-- TOC entry 352 (class 1259 OID 27131)
-- Name: user_sessions_session_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_sessions_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_sessions_session_id_seq OWNER TO postgres;

--
-- TOC entry 6357 (class 0 OID 0)
-- Dependencies: 352
-- Name: user_sessions_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_sessions_session_id_seq OWNED BY public.user_sessions.session_id;


--
-- TOC entry 361 (class 1259 OID 27223)
-- Name: user_tab_preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_tab_preferences (
    tab_preference_id integer NOT NULL,
    user_id integer NOT NULL,
    page_context character varying(100) NOT NULL,
    active_tab character varying(50) NOT NULL,
    last_accessed timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_tab_preferences OWNER TO postgres;

--
-- TOC entry 360 (class 1259 OID 27222)
-- Name: user_tab_preferences_tab_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_tab_preferences_tab_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_tab_preferences_tab_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6358 (class 0 OID 0)
-- Dependencies: 360
-- Name: user_tab_preferences_tab_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_tab_preferences_tab_preference_id_seq OWNED BY public.user_tab_preferences.tab_preference_id;


--
-- TOC entry 357 (class 1259 OID 27186)
-- Name: user_view_preferences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_view_preferences (
    preference_id integer NOT NULL,
    user_id integer NOT NULL,
    page_section character varying(100) NOT NULL,
    view_mode character varying(20) DEFAULT 'card'::character varying,
    sort_order character varying(50) DEFAULT 'most_recent'::character varying,
    items_per_page integer DEFAULT 20,
    show_filters boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_view_preferences OWNER TO postgres;

--
-- TOC entry 356 (class 1259 OID 27185)
-- Name: user_view_preferences_preference_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_view_preferences_preference_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_view_preferences_preference_id_seq OWNER TO postgres;

--
-- TOC entry 6359 (class 0 OID 0)
-- Dependencies: 356
-- Name: user_view_preferences_preference_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_view_preferences_preference_id_seq OWNED BY public.user_view_preferences.preference_id;


--
-- TOC entry 217 (class 1259 OID 25262)
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_user_id_seq OWNER TO postgres;

--
-- TOC entry 6360 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- TOC entry 251 (class 1259 OID 25814)
-- Name: watch_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.watch_history (
    history_id integer NOT NULL,
    user_id integer NOT NULL,
    content_type character varying(20) NOT NULL,
    content_id integer NOT NULL,
    progress integer,
    completed boolean DEFAULT false,
    last_watched timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT watch_history_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'episode'::character varying])::text[])))
);


ALTER TABLE public.watch_history OWNER TO postgres;

--
-- TOC entry 250 (class 1259 OID 25813)
-- Name: watch_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.watch_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.watch_history_history_id_seq OWNER TO postgres;

--
-- TOC entry 6361 (class 0 OID 0)
-- Dependencies: 250
-- Name: watch_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.watch_history_history_id_seq OWNED BY public.watch_history.history_id;


--
-- TOC entry 235 (class 1259 OID 25422)
-- Name: watchlist_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.watchlist_items (
    watchlist_id integer NOT NULL,
    content_type character varying(10) NOT NULL,
    content_id integer NOT NULL,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT watchlist_items_content_type_check CHECK (((content_type)::text = ANY ((ARRAY['movie'::character varying, 'show'::character varying])::text[])))
);


ALTER TABLE public.watchlist_items OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 25405)
-- Name: watchlists_watchlist_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.watchlists_watchlist_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.watchlists_watchlist_id_seq OWNER TO postgres;

--
-- TOC entry 6362 (class 0 OID 0)
-- Dependencies: 233
-- Name: watchlists_watchlist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.watchlists_watchlist_id_seq OWNED BY public.watchlists.watchlist_id;


--
-- TOC entry 5221 (class 2604 OID 26185)
-- Name: ai_sentiment_analysis analysis_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_sentiment_analysis ALTER COLUMN analysis_id SET DEFAULT nextval('public.ai_sentiment_analysis_analysis_id_seq'::regclass);


--
-- TOC entry 5234 (class 2604 OID 26259)
-- Name: ai_spoiler_analysis analysis_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_spoiler_analysis ALTER COLUMN analysis_id SET DEFAULT nextval('public.ai_spoiler_analysis_analysis_id_seq'::regclass);


--
-- TOC entry 5189 (class 2604 OID 25885)
-- Name: augmented_recommendations recommendation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.augmented_recommendations ALTER COLUMN recommendation_id SET DEFAULT nextval('public.augmented_recommendations_recommendation_id_seq'::regclass);


--
-- TOC entry 5256 (class 2604 OID 26478)
-- Name: auth0_sessions session_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_sessions ALTER COLUMN session_id SET DEFAULT nextval('public.auth0_sessions_session_id_seq'::regclass);


--
-- TOC entry 5249 (class 2604 OID 26456)
-- Name: auth0_users auth0_user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_users ALTER COLUMN auth0_user_id SET DEFAULT nextval('public.auth0_users_auth0_user_id_seq'::regclass);


--
-- TOC entry 5158 (class 2604 OID 25388)
-- Name: comments comment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments ALTER COLUMN comment_id SET DEFAULT nextval('public.comments_comment_id_seq'::regclass);


--
-- TOC entry 5304 (class 2604 OID 26769)
-- Name: communities community_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.communities ALTER COLUMN community_id SET DEFAULT nextval('public.communities_community_id_seq'::regclass);


--
-- TOC entry 5300 (class 2604 OID 26753)
-- Name: community_categories category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_categories ALTER COLUMN category_id SET DEFAULT nextval('public.community_categories_category_id_seq'::regclass);


--
-- TOC entry 5312 (class 2604 OID 26800)
-- Name: community_memberships membership_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_memberships ALTER COLUMN membership_id SET DEFAULT nextval('public.community_memberships_membership_id_seq'::regclass);


--
-- TOC entry 5327 (class 2604 OID 26851)
-- Name: community_post_comments comment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_post_comments ALTER COLUMN comment_id SET DEFAULT nextval('public.community_post_comments_comment_id_seq'::regclass);


--
-- TOC entry 5316 (class 2604 OID 26822)
-- Name: community_posts post_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_posts ALTER COLUMN post_id SET DEFAULT nextval('public.community_posts_post_id_seq'::regclass);


--
-- TOC entry 5373 (class 2604 OID 27068)
-- Name: content_analytics analytics_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_analytics ALTER COLUMN analytics_id SET DEFAULT nextval('public.content_analytics_analytics_id_seq'::regclass);


--
-- TOC entry 5392 (class 2604 OID 27153)
-- Name: content_discovery_metrics metric_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_discovery_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.content_discovery_metrics_metric_id_seq'::regclass);


--
-- TOC entry 5288 (class 2604 OID 26700)
-- Name: content_platform_availability availability_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_platform_availability ALTER COLUMN availability_id SET DEFAULT nextval('public.content_platform_availability_availability_id_seq'::regclass);


--
-- TOC entry 5194 (class 2604 OID 25922)
-- Name: content_progress progress_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_progress ALTER COLUMN progress_id SET DEFAULT nextval('public.content_progress_progress_id_seq'::regclass);


--
-- TOC entry 5270 (class 2604 OID 26546)
-- Name: content_reports report_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_reports ALTER COLUMN report_id SET DEFAULT nextval('public.content_reports_report_id_seq'::regclass);


--
-- TOC entry 5432 (class 2604 OID 27456)
-- Name: content_request_comments comment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_comments ALTER COLUMN comment_id SET DEFAULT nextval('public.content_request_comments_comment_id_seq'::regclass);


--
-- TOC entry 5436 (class 2604 OID 27478)
-- Name: content_request_history history_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_history ALTER COLUMN history_id SET DEFAULT nextval('public.content_request_history_history_id_seq'::regclass);


--
-- TOC entry 5421 (class 2604 OID 27379)
-- Name: content_request_types request_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_types ALTER COLUMN request_type_id SET DEFAULT nextval('public.content_request_types_request_type_id_seq'::regclass);


--
-- TOC entry 5429 (class 2604 OID 27434)
-- Name: content_request_votes vote_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_votes ALTER COLUMN vote_id SET DEFAULT nextval('public.content_request_votes_vote_id_seq'::regclass);


--
-- TOC entry 5224 (class 2604 OID 26200)
-- Name: content_sentiment_summary summary_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_summary ALTER COLUMN summary_id SET DEFAULT nextval('public.content_sentiment_summary_summary_id_seq'::regclass);


--
-- TOC entry 5219 (class 2604 OID 26164)
-- Name: content_sentiment_tags content_sentiment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_tags ALTER COLUMN content_sentiment_id SET DEFAULT nextval('public.content_sentiment_tags_content_sentiment_id_seq'::regclass);


--
-- TOC entry 5292 (class 2604 OID 26720)
-- Name: content_status status_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_status ALTER COLUMN status_id SET DEFAULT nextval('public.content_status_status_id_seq'::regclass);


--
-- TOC entry 5191 (class 2604 OID 25905)
-- Name: data_change_queue change_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.data_change_queue ALTER COLUMN change_id SET DEFAULT nextval('public.data_change_queue_change_id_seq'::regclass);


--
-- TOC entry 5203 (class 2604 OID 25982)
-- Name: discussion_posts post_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_posts ALTER COLUMN post_id SET DEFAULT nextval('public.discussion_posts_post_id_seq'::regclass);


--
-- TOC entry 5247 (class 2604 OID 26316)
-- Name: discussion_summary_sources source_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_summary_sources ALTER COLUMN source_id SET DEFAULT nextval('public.discussion_summary_sources_source_id_seq'::regclass);


--
-- TOC entry 5200 (class 2604 OID 25964)
-- Name: discussion_topics topic_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_topics ALTER COLUMN topic_id SET DEFAULT nextval('public.discussion_topics_topic_id_seq'::regclass);


--
-- TOC entry 5381 (class 2604 OID 27103)
-- Name: featured_content featured_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.featured_content ALTER COLUMN featured_id SET DEFAULT nextval('public.featured_content_featured_id_seq'::regclass);


--
-- TOC entry 5146 (class 2604 OID 25302)
-- Name: genres genre_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genres ALTER COLUMN genre_id SET DEFAULT nextval('public.genres_genre_id_seq'::regclass);


--
-- TOC entry 5210 (class 2604 OID 26065)
-- Name: gpt_api_usage usage_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gpt_api_usage ALTER COLUMN usage_id SET DEFAULT nextval('public.gpt_api_usage_usage_id_seq'::regclass);


--
-- TOC entry 5237 (class 2604 OID 26288)
-- Name: gpt_summaries summary_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gpt_summaries ALTER COLUMN summary_id SET DEFAULT nextval('public.gpt_summaries_summary_id_seq'::regclass);


--
-- TOC entry 5177 (class 2604 OID 25559)
-- Name: interaction_types interaction_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interaction_types ALTER COLUMN interaction_type_id SET DEFAULT nextval('public.interaction_types_interaction_type_id_seq'::regclass);


--
-- TOC entry 5184 (class 2604 OID 25789)
-- Name: login_attempts attempt_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_attempts ALTER COLUMN attempt_id SET DEFAULT nextval('public.login_attempts_attempt_id_seq'::regclass);


--
-- TOC entry 5424 (class 2604 OID 27392)
-- Name: missing_content_requests request_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests ALTER COLUMN request_id SET DEFAULT nextval('public.missing_content_requests_request_id_seq'::regclass);


--
-- TOC entry 5279 (class 2604 OID 26581)
-- Name: moderation_actions action_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moderation_actions ALTER COLUMN action_id SET DEFAULT nextval('public.moderation_actions_action_id_seq'::regclass);


--
-- TOC entry 5147 (class 2604 OID 25313)
-- Name: movies movie_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movies ALTER COLUMN movie_id SET DEFAULT nextval('public.movies_movie_id_seq'::regclass);


--
-- TOC entry 5172 (class 2604 OID 25520)
-- Name: notification_types notification_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notification_types ALTER COLUMN notification_type_id SET DEFAULT nextval('public.notification_types_notification_type_id_seq'::regclass);


--
-- TOC entry 5174 (class 2604 OID 25532)
-- Name: notifications notification_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.notifications_notification_id_seq'::regclass);


--
-- TOC entry 5347 (class 2604 OID 26932)
-- Name: point_transactions transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_transactions ALTER COLUMN transaction_id SET DEFAULT nextval('public.point_transactions_transaction_id_seq'::regclass);


--
-- TOC entry 5123 (class 2604 OID 25281)
-- Name: preferences preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preferences ALTER COLUMN preference_id SET DEFAULT nextval('public.preferences_preference_id_seq'::regclass);


--
-- TOC entry 5331 (class 2604 OID 26889)
-- Name: ranking_tiers tier_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ranking_tiers ALTER COLUMN tier_id SET DEFAULT nextval('public.ranking_tiers_tier_id_seq'::regclass);


--
-- TOC entry 5282 (class 2604 OID 26609)
-- Name: report_escalations escalation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_escalations ALTER COLUMN escalation_id SET DEFAULT nextval('public.report_escalations_escalation_id_seq'::regclass);


--
-- TOC entry 5261 (class 2604 OID 26496)
-- Name: report_types report_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_types ALTER COLUMN report_type_id SET DEFAULT nextval('public.report_types_report_type_id_seq'::regclass);


--
-- TOC entry 5154 (class 2604 OID 25368)
-- Name: reviews review_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reviews ALTER COLUMN review_id SET DEFAULT nextval('public.reviews_review_id_seq'::regclass);


--
-- TOC entry 5375 (class 2604 OID 27078)
-- Name: roulette_filters filter_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roulette_filters ALTER COLUMN filter_id SET DEFAULT nextval('public.roulette_filters_filter_id_seq'::regclass);


--
-- TOC entry 5378 (class 2604 OID 27087)
-- Name: roulette_results result_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roulette_results ALTER COLUMN result_id SET DEFAULT nextval('public.roulette_results_result_id_seq'::regclass);


--
-- TOC entry 5385 (class 2604 OID 27120)
-- Name: search_analytics search_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.search_analytics ALTER COLUMN search_id SET DEFAULT nextval('public.search_analytics_search_id_seq'::regclass);


--
-- TOC entry 5212 (class 2604 OID 26132)
-- Name: sentiment_categories category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_categories ALTER COLUMN category_id SET DEFAULT nextval('public.sentiment_categories_category_id_seq'::regclass);


--
-- TOC entry 5215 (class 2604 OID 26145)
-- Name: sentiment_tags tag_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_tags ALTER COLUMN tag_id SET DEFAULT nextval('public.sentiment_tags_tag_id_seq'::regclass);


--
-- TOC entry 5150 (class 2604 OID 25325)
-- Name: shows show_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shows ALTER COLUMN show_id SET DEFAULT nextval('public.shows_show_id_seq'::regclass);


--
-- TOC entry 5197 (class 2604 OID 25939)
-- Name: spoiler_reports report_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_reports ALTER COLUMN report_id SET DEFAULT nextval('public.spoiler_reports_report_id_seq'::regclass);


--
-- TOC entry 5207 (class 2604 OID 26004)
-- Name: spoiler_tags tag_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_tags ALTER COLUMN tag_id SET DEFAULT nextval('public.spoiler_tags_tag_id_seq'::regclass);


--
-- TOC entry 5285 (class 2604 OID 26685)
-- Name: streaming_platforms platform_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.streaming_platforms ALTER COLUMN platform_id SET DEFAULT nextval('public.streaming_platforms_platform_id_seq'::regclass);


--
-- TOC entry 5295 (class 2604 OID 26732)
-- Name: trailers trailer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trailers ALTER COLUMN trailer_id SET DEFAULT nextval('public.trailers_trailer_id_seq'::regclass);


--
-- TOC entry 5368 (class 2604 OID 27055)
-- Name: trending_content trending_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trending_content ALTER COLUMN trending_id SET DEFAULT nextval('public.trending_content_trending_id_seq'::regclass);


--
-- TOC entry 5349 (class 2604 OID 26947)
-- Name: user_activity activity_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_activity ALTER COLUMN activity_id SET DEFAULT nextval('public.user_activity_activity_id_seq'::regclass);


--
-- TOC entry 5168 (class 2604 OID 25495)
-- Name: user_connections connection_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_connections ALTER COLUMN connection_id SET DEFAULT nextval('public.user_connections_connection_id_seq'::regclass);


--
-- TOC entry 5416 (class 2604 OID 27279)
-- Name: user_device_preferences device_preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_device_preferences ALTER COLUMN device_preference_id SET DEFAULT nextval('public.user_device_preferences_device_preference_id_seq'::regclass);


--
-- TOC entry 5402 (class 2604 OID 27209)
-- Name: user_filter_preferences filter_preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_filter_preferences ALTER COLUMN filter_preference_id SET DEFAULT nextval('public.user_filter_preferences_filter_preference_id_seq'::regclass);


--
-- TOC entry 5406 (class 2604 OID 27241)
-- Name: user_homepage_sections section_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_homepage_sections ALTER COLUMN section_id SET DEFAULT nextval('public.user_homepage_sections_section_id_seq'::regclass);


--
-- TOC entry 5179 (class 2604 OID 25571)
-- Name: user_interactions interaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_interactions ALTER COLUMN interaction_id SET DEFAULT nextval('public.user_interactions_interaction_id_seq'::regclass);


--
-- TOC entry 5411 (class 2604 OID 27261)
-- Name: user_notification_preferences notification_preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_notification_preferences ALTER COLUMN notification_preference_id SET DEFAULT nextval('public.user_notification_preferences_notification_preference_id_seq'::regclass);


--
-- TOC entry 5362 (class 2604 OID 26991)
-- Name: user_post_interactions interaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_interactions ALTER COLUMN interaction_id SET DEFAULT nextval('public.user_post_interactions_interaction_id_seq'::regclass);


--
-- TOC entry 5364 (class 2604 OID 27011)
-- Name: user_post_replies reply_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_replies ALTER COLUMN reply_id SET DEFAULT nextval('public.user_post_replies_reply_id_seq'::regclass);


--
-- TOC entry 5351 (class 2604 OID 26962)
-- Name: user_posts post_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_posts ALTER COLUMN post_id SET DEFAULT nextval('public.user_posts_post_id_seq'::regclass);


--
-- TOC entry 5265 (class 2604 OID 26511)
-- Name: user_reports report_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports ALTER COLUMN report_id SET DEFAULT nextval('public.user_reports_report_id_seq'::regclass);


--
-- TOC entry 5232 (class 2604 OID 26219)
-- Name: user_sentiment_patterns pattern_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sentiment_patterns ALTER COLUMN pattern_id SET DEFAULT nextval('public.user_sentiment_patterns_pattern_id_seq'::regclass);


--
-- TOC entry 5387 (class 2604 OID 27135)
-- Name: user_sessions session_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions ALTER COLUMN session_id SET DEFAULT nextval('public.user_sessions_session_id_seq'::regclass);


--
-- TOC entry 5404 (class 2604 OID 27226)
-- Name: user_tab_preferences tab_preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tab_preferences ALTER COLUMN tab_preference_id SET DEFAULT nextval('public.user_tab_preferences_tab_preference_id_seq'::regclass);


--
-- TOC entry 5395 (class 2604 OID 27189)
-- Name: user_view_preferences preference_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_view_preferences ALTER COLUMN preference_id SET DEFAULT nextval('public.user_view_preferences_preference_id_seq'::regclass);


--
-- TOC entry 5120 (class 2604 OID 25266)
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- TOC entry 5186 (class 2604 OID 25817)
-- Name: watch_history history_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watch_history ALTER COLUMN history_id SET DEFAULT nextval('public.watch_history_history_id_seq'::regclass);


--
-- TOC entry 5162 (class 2604 OID 25409)
-- Name: watchlists watchlist_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watchlists ALTER COLUMN watchlist_id SET DEFAULT nextval('public.watchlists_watchlist_id_seq'::regclass);


--
-- TOC entry 6178 (class 0 OID 26182)
-- Dependencies: 280
-- Data for Name: ai_sentiment_analysis; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ai_sentiment_analysis (analysis_id, content_type, content_id, overall_sentiment, confidence_score, emotion_scores, detected_categories, ai_model_used, analysis_timestamp, needs_review) FROM stdin;
\.


--
-- TOC entry 6184 (class 0 OID 26256)
-- Dependencies: 287
-- Data for Name: ai_spoiler_analysis; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ai_spoiler_analysis (analysis_id, content_type, content_id, original_text, spoiler_probability, spoiler_categories, ai_model_used, confidence_score, analyzed_at, human_verified) FROM stdin;
\.


--
-- TOC entry 6153 (class 0 OID 25882)
-- Dependencies: 254
-- Data for Name: augmented_recommendations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.augmented_recommendations (recommendation_id, user_id, content_type, content_id, recommendation_type, score, reasoning, metadata, created_at) FROM stdin;
\.


--
-- TOC entry 6192 (class 0 OID 26475)
-- Dependencies: 296
-- Data for Name: auth0_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth0_sessions (session_id, auth0_user_id, session_token, refresh_token, access_token, id_token, device_info, ip_address, user_agent, created_at, expires_at, last_accessed, is_active, revoked, revoked_at) FROM stdin;
\.


--
-- TOC entry 6190 (class 0 OID 26453)
-- Dependencies: 294
-- Data for Name: auth0_users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auth0_users (auth0_user_id, auth0_id, user_id, email, email_verified, provider, connection, created_at, updated_at, last_login, login_count, auth0_metadata, app_metadata, profile_synced, sync_required) FROM stdin;
\.


--
-- TOC entry 6131 (class 0 OID 25385)
-- Dependencies: 232
-- Data for Name: comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.comments (comment_id, user_id, review_id, comment_text, created_at, updated_at, contains_spoilers) FROM stdin;
6	14	7	I agree! The special effects were groundbreaking for its time.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
7	15	7	The philosophical themes really made me think.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
8	13	8	The ending still confuses me though.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
9	14	10	Walter White is one of TV's greatest characters.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
10	13	11	Michael Scott is hilarious but also cringe-worthy.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
\.


--
-- TOC entry 6214 (class 0 OID 26766)
-- Dependencies: 320
-- Data for Name: communities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.communities (community_id, community_name, description, community_type, category_id, content_type, content_id, genre_id, creator_id, avatar_url, banner_url, member_count, post_count, is_private, is_featured, rules, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6212 (class 0 OID 26750)
-- Dependencies: 318
-- Data for Name: community_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.community_categories (category_id, category_name, category_code, description, icon, color_hex, is_active, sort_order, created_at) FROM stdin;
1	Survival & Suspense	survival_suspense	Edge-of-your-seat content	🔥	\N	t	0	2025-07-11 12:28:22.346889-04
2	Heroes & Villains	heroes_villains	Good vs evil storylines	⚔️	\N	t	0	2025-07-11 12:28:22.346889-04
3	Mind Bending Stories	mind_bending	Complex plots that make you think	🧠	\N	t	0	2025-07-11 12:28:22.346889-04
4	Chills & Thrills	chills_thrills	Horror and thriller content	👻	\N	t	0	2025-07-11 12:28:22.346889-04
5	Mind & Mystery	mind_mystery	Detective stories and puzzles	🔍	\N	t	0	2025-07-11 12:28:22.346889-04
6	Love & Laughs	love_laughs	Romance and comedy content	💕	\N	t	0	2025-07-11 12:28:22.346889-04
7	Animation	animation	Animated movies and shows	🎨	\N	t	0	2025-07-11 12:28:22.346889-04
8	Reality & Competition	reality_competition	Reality TV and competition shows	🏆	\N	t	0	2025-07-11 12:28:22.346889-04
9	Family	family	Family-friendly content	👨‍👩‍👧‍👦	\N	t	0	2025-07-11 12:28:22.346889-04
\.


--
-- TOC entry 6216 (class 0 OID 26797)
-- Dependencies: 322
-- Data for Name: community_memberships; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.community_memberships (membership_id, community_id, user_id, role, joined_at, is_active) FROM stdin;
\.


--
-- TOC entry 6220 (class 0 OID 26848)
-- Dependencies: 326
-- Data for Name: community_post_comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.community_post_comments (comment_id, post_id, user_id, parent_comment_id, content, like_count, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6218 (class 0 OID 26819)
-- Dependencies: 324
-- Data for Name: community_posts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.community_posts (post_id, community_id, user_id, title, content, post_type, media_urls, external_url, tags, like_count, comment_count, share_count, view_count, is_pinned, is_nsfw, contains_spoilers, spoiler_scope, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6237 (class 0 OID 27065)
-- Dependencies: 343
-- Data for Name: content_analytics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_analytics (analytics_id, content_type, content_id, metric_type, metric_value, date_recorded, hour_recorded, created_at) FROM stdin;
\.


--
-- TOC entry 6249 (class 0 OID 27150)
-- Dependencies: 355
-- Data for Name: content_discovery_metrics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_discovery_metrics (metric_id, content_type, content_id, discovery_source, user_id, resulted_in_engagement, engagement_type, created_at) FROM stdin;
\.


--
-- TOC entry 6206 (class 0 OID 26697)
-- Dependencies: 312
-- Data for Name: content_platform_availability; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_platform_availability (availability_id, content_type, content_id, platform_id, is_available, availability_region, added_date, removal_date, content_url, last_updated) FROM stdin;
\.


--
-- TOC entry 6157 (class 0 OID 25919)
-- Dependencies: 258
-- Data for Name: content_progress; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_progress (progress_id, user_id, content_type, content_id, last_season_watched, last_episode_watched, completed, last_updated) FROM stdin;
\.


--
-- TOC entry 6198 (class 0 OID 26543)
-- Dependencies: 302
-- Data for Name: content_reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_reports (report_id, reporter_id, content_type, content_id, report_type_id, reason, evidence_urls, specific_excerpt, status, priority, auto_flagged, ai_confidence_score, created_at, updated_at, resolved_at, assigned_moderator_id, moderator_notes, resolution_action, content_hidden, content_deleted, content_edited) FROM stdin;
\.


--
-- TOC entry 6269 (class 0 OID 27453)
-- Dependencies: 379
-- Data for Name: content_request_comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_request_comments (comment_id, request_id, user_id, comment_text, is_admin_comment, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6271 (class 0 OID 27475)
-- Dependencies: 381
-- Data for Name: content_request_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_request_history (history_id, request_id, changed_by, old_status, new_status, change_reason, changed_at) FROM stdin;
\.


--
-- TOC entry 6263 (class 0 OID 27376)
-- Dependencies: 373
-- Data for Name: content_request_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_request_types (request_type_id, type_name, description, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 6267 (class 0 OID 27431)
-- Dependencies: 377
-- Data for Name: content_request_votes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_request_votes (vote_id, request_id, user_id, vote_type, created_at) FROM stdin;
\.


--
-- TOC entry 6180 (class 0 OID 26197)
-- Dependencies: 282
-- Data for Name: content_sentiment_summary; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_sentiment_summary (summary_id, content_type, content_id, total_reviews, very_positive_count, positive_count, neutral_count, negative_count, very_negative_count, top_sentiment_tags, average_sentiment_score, sentiment_trend, last_updated) FROM stdin;
1	movie	35	1	0	1	0	0	0	\N	\N	\N	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6176 (class 0 OID 26161)
-- Dependencies: 278
-- Data for Name: content_sentiment_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_sentiment_tags (content_sentiment_id, content_type, content_id, tag_id, user_id, added_at) FROM stdin;
\.


--
-- TOC entry 6166 (class 0 OID 26017)
-- Dependencies: 267
-- Data for Name: content_spoiler_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_spoiler_tags (content_type, content_id, tag_id) FROM stdin;
review	16	1
\.


--
-- TOC entry 6208 (class 0 OID 26717)
-- Dependencies: 314
-- Data for Name: content_status; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_status (status_id, content_type, content_id, status_type, status_date, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 6155 (class 0 OID 25902)
-- Dependencies: 256
-- Data for Name: data_change_queue; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.data_change_queue (change_id, table_name, operation, record_id, change_time, processed) FROM stdin;
27	movies	INSERT	35	2025-05-26 12:25:13.970952-04	f
28	movies	UPDATE	35	2025-05-26 12:25:13.970952-04	f
29	users	INSERT	1	2025-05-26 12:25:13.970952-04	f
30	movies	DELETE	35	2025-05-26 12:28:58.84149-04	f
\.


--
-- TOC entry 6163 (class 0 OID 25979)
-- Dependencies: 264
-- Data for Name: discussion_posts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discussion_posts (post_id, topic_id, user_id, content, contains_spoilers, spoiler_info, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6188 (class 0 OID 26313)
-- Dependencies: 291
-- Data for Name: discussion_summary_sources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discussion_summary_sources (source_id, summary_id, source_type, source_id_ref, included_at) FROM stdin;
\.


--
-- TOC entry 6161 (class 0 OID 25961)
-- Dependencies: 262
-- Data for Name: discussion_topics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discussion_topics (topic_id, title, description, content_type, content_id, spoiler_scope, created_by, created_at, is_active) FROM stdin;
1	Test Discussion Topic	\N	movie	35	\N	\N	2025-05-26 12:25:13.970952-04	t
\.


--
-- TOC entry 6135 (class 0 OID 25434)
-- Dependencies: 236
-- Data for Name: favorites; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.favorites (user_id, content_type, content_id, added_at) FROM stdin;
13	movie	5	2025-03-20 11:33:35.059603-04
13	show	5	2025-03-20 11:33:35.059603-04
14	show	7	2025-03-20 11:33:35.059603-04
14	movie	6	2025-03-20 11:33:35.059603-04
15	movie	7	2025-03-20 11:33:35.059603-04
15	show	8	2025-03-20 11:33:35.059603-04
\.


--
-- TOC entry 6243 (class 0 OID 27100)
-- Dependencies: 349
-- Data for Name: featured_content; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.featured_content (featured_id, content_type, content_id, feature_type, feature_location, title, description, image_url, start_date, end_date, is_active, sort_order, created_by, created_at) FROM stdin;
\.


--
-- TOC entry 6121 (class 0 OID 25299)
-- Dependencies: 222
-- Data for Name: genres; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.genres (genre_id, name, description) FROM stdin;
6	Action	Fast-paced and exciting content with physical activity
7	Comedy	Content designed to make audiences laugh
8	Drama	Serious content dealing with emotions and conflicts
9	Sci-Fi	Content exploring futuristic concepts and technology
10	Horror	Content intended to frighten or scare the audience
\.


--
-- TOC entry 6168 (class 0 OID 26062)
-- Dependencies: 270
-- Data for Name: gpt_api_usage; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gpt_api_usage (usage_id, content_type, content_id, tokens_used, cost_estimate, model_used, request_type, created_at) FROM stdin;
1	movie	35	150	\N	test-model	\N	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6186 (class 0 OID 26285)
-- Dependencies: 289
-- Data for Name: gpt_summaries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gpt_summaries (summary_id, content_type, content_id, discussion_timeframe, discussion_scope, summary_type, summary_text, total_discussions_analyzed, total_users_involved, sentiment_overview, key_themes, spoiler_safe, spoiler_level, ai_model_used, model_provider, generated_at, source_discussions_count, confidence_score, needs_refresh, last_discussion_included) FROM stdin;
\.


--
-- TOC entry 6146 (class 0 OID 25591)
-- Dependencies: 247
-- Data for Name: interaction_counts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interaction_counts (content_type, content_id, interaction_type_id, count, updated_at) FROM stdin;
\.


--
-- TOC entry 6143 (class 0 OID 25556)
-- Dependencies: 244
-- Data for Name: interaction_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interaction_types (interaction_type_id, type_name, description, is_active) FROM stdin;
1	like	Like a review or comment	t
2	share	Share content or a review	t
3	bookmark	Bookmark content for later	t
4	watch_later	Add to watch later list	t
5	rate	Rate without full review	t
7	test_interaction	Test interaction type for database verification	t
\.


--
-- TOC entry 6148 (class 0 OID 25786)
-- Dependencies: 249
-- Data for Name: login_attempts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.login_attempts (attempt_id, user_id, email, ip_address, success, attempted_at) FROM stdin;
1	\N	test1@example.com	192.168.1.1	t	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6265 (class 0 OID 27389)
-- Dependencies: 375
-- Data for Name: missing_content_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.missing_content_requests (request_id, user_id, content_type, title, release_year, additional_details, status, priority, assigned_to, admin_notes, rejection_reason, duplicate_of, added_movie_id, added_show_id, created_at, updated_at, resolved_at) FROM stdin;
\.


--
-- TOC entry 6200 (class 0 OID 26578)
-- Dependencies: 304
-- Data for Name: moderation_actions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.moderation_actions (action_id, moderator_id, action_type, target_type, target_user_id, target_content_type, target_content_id, related_report_id, related_report_type, action_reason, action_duration, action_expires_at, created_at, is_active, reversed_at, reversed_by, reversal_reason) FROM stdin;
\.


--
-- TOC entry 6126 (class 0 OID 25334)
-- Dependencies: 227
-- Data for Name: moviegenres; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.moviegenres (movie_id, genre_id) FROM stdin;
5	6
5	9
6	6
6	9
7	7
7	8
8	8
\.


--
-- TOC entry 6123 (class 0 OID 25310)
-- Dependencies: 224
-- Data for Name: movies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.movies (movie_id, title, description, release_date, duration, language, poster_url, backdrop_url, trailer_url, rating, director, country_of_origin, created_at, updated_at, genres_array) FROM stdin;
5	The Matrix	A computer hacker learns about the true nature of reality	1999-03-31	136	English	\N	\N	\N	8.7	Wachowskis	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
6	Inception	A thief who enters people's dreams to steal their secrets	2010-07-16	148	English	\N	\N	\N	8.8	Christopher Nolan	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
7	Parasite	A poor family schemes to become employed by a wealthy family	2019-05-30	132	Korean	\N	\N	\N	8.6	Bong Joon-ho	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
8	The Godfather	The aging patriarch of an organized crime dynasty transfers control	1972-03-24	175	English	\N	\N	\N	9.2	Francis Ford Coppola	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
\.


--
-- TOC entry 6139 (class 0 OID 25517)
-- Dependencies: 240
-- Data for Name: notification_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notification_types (notification_type_id, type_name, description, is_active) FROM stdin;
1	new_follower	Someone followed you	t
2	friend_request	Someone sent you a friend request	t
3	friend_accepted	Someone accepted your friend request	t
4	comment_on_review	Someone commented on your review	t
5	like_on_review	Someone liked your review	t
6	mentioned_you	Someone mentioned you in a comment	t
7	new_content_from_favorite	New content from someone you follow	t
8	watchlist_shared	Someone shared a watchlist with you	t
10	test_notification	Test notification type for database verification	t
\.


--
-- TOC entry 6141 (class 0 OID 25529)
-- Dependencies: 242
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notifications (notification_id, user_id, notification_type_id, sender_id, content_type, content_id, message, is_read, created_at) FROM stdin;
\.


--
-- TOC entry 6225 (class 0 OID 26929)
-- Dependencies: 331
-- Data for Name: point_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.point_transactions (transaction_id, user_id, points_change, transaction_type, reference_type, reference_id, description, created_at) FROM stdin;
\.


--
-- TOC entry 6119 (class 0 OID 25278)
-- Dependencies: 220
-- Data for Name: preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.preferences (preference_id, user_id, theme, email_notifications, push_notifications, subtitle_language, autoplay, mature_content, privacy_level, notification_follow, notification_friend_request, notification_comment, notification_like, notification_mention, notification_content_update, show_spoilers, auto_hide_future_episodes, view_mode, sort_preference, items_per_page, enable_autoplay, show_spoiler_warnings, enable_roulette_animations, homepage_layout) FROM stdin;
13	13	dark	t	t	en	t	t	public	t	t	t	t	t	t	f	t	card	most_recent	20	t	t	t	default
14	14	light	f	t	es	t	f	public	t	t	t	t	t	t	f	t	card	most_recent	20	t	t	t	default
15	15	system	t	t	fr	t	t	public	t	t	t	t	t	t	f	t	card	most_recent	20	t	t	t	default
49	53	dark	t	t	en	t	f	public	t	t	t	t	t	t	f	t	card	most_recent	20	t	t	t	default
\.


--
-- TOC entry 6222 (class 0 OID 26886)
-- Dependencies: 328
-- Data for Name: ranking_tiers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ranking_tiers (tier_id, tier_name, tier_code, min_likes, max_likes, points_reward, tier_color, tier_icon, benefits, description, created_at) FROM stdin;
1	Bronze	bronze	0	24	500	#CD7F32	🥉	["rookie_status"]	Bronze Tier → Rookie - Create an account to unlock Bronze Tier and start your rank progress.	2025-07-11 12:28:41.957332-04
2	Silver	silver	25	74	750	#C0C0C0	🥈	["explorer_status", "video_upload"]	Silver Tier → Explorer - Reach 25 likes on any of your posts to unlock Silver tier.	2025-07-11 12:28:41.957332-04
3	Gold	gold	75	149	1000	#FFD700	🏆	["contributor_status"]	Gold Tier → Contributor - Reach 75 likes on any of your posts to unlock Gold tier.	2025-07-11 12:28:41.957332-04
4	Emerald	emerald	150	299	1250	#50C878	💎	["influencer_status"]	Emerald Tier → Influencer - Reach 150 likes on any of your posts to unlock Emerald tier.	2025-07-11 12:28:41.957332-04
5	Diamond	diamond	300	\N	1500	#B9F2FF	💎	["trusted_status", "content_appears_in_trusted_filter"]	Diamond Tier → Trusted - Reach 300 likes on any of your posts to unlock Diamond tier.	2025-07-11 12:28:41.957332-04
\.


--
-- TOC entry 6202 (class 0 OID 26606)
-- Dependencies: 306
-- Data for Name: report_escalations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_escalations (escalation_id, report_type, report_id, escalated_by, escalated_to, escalation_reason, status, created_at, resolved_at, resolution_notes) FROM stdin;
\.


--
-- TOC entry 6194 (class 0 OID 26493)
-- Dependencies: 298
-- Data for Name: report_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_types (report_type_id, type_name, description, severity_level, requires_immediate_action, is_active, created_at) FROM stdin;
1	spam	Spam or repetitive content	medium	f	t	2025-07-04 11:41:56.164266-04
2	harassment	Harassment or bullying behavior	high	t	t	2025-07-04 11:41:56.164266-04
3	hate_speech	Hate speech or discriminatory content	critical	t	t	2025-07-04 11:41:56.164266-04
4	inappropriate_content	Inappropriate or offensive content	medium	f	t	2025-07-04 11:41:56.164266-04
5	spoilers	Unmarked spoilers in content	low	f	t	2025-07-04 11:41:56.164266-04
6	fake_information	Misinformation or fake content	high	f	t	2025-07-04 11:41:56.164266-04
7	copyright_violation	Copyright infringement	medium	f	t	2025-07-04 11:41:56.164266-04
8	threats	Threats or violent content	critical	t	t	2025-07-04 11:41:56.164266-04
9	impersonation	Impersonating another person	high	t	t	2025-07-04 11:41:56.164266-04
10	off_topic	Content not relevant to discussion	low	f	t	2025-07-04 11:41:56.164266-04
\.


--
-- TOC entry 6129 (class 0 OID 25365)
-- Dependencies: 230
-- Data for Name: reviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reviews (review_id, user_id, content_type, content_id, rating, review_text, created_at, updated_at, contains_spoilers) FROM stdin;
7	13	movie	5	9	The Matrix revolutionized the action genre with its innovative special effects and philosophical themes.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
8	14	movie	6	8	Inception is a mind-bending journey that challenges viewers to question reality.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
9	15	movie	7	10	Parasite brilliantly blends genres while delivering sharp social commentary.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
10	13	show	5	10	Breaking Bad is simply the best television drama ever made.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
11	14	show	7	9	The Office manages to be consistently funny while also deeply human.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
12	15	show	8	8	Stranger Things captures 80s nostalgia perfectly while delivering genuine thrills.	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	f
\.


--
-- TOC entry 6239 (class 0 OID 27075)
-- Dependencies: 345
-- Data for Name: roulette_filters; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roulette_filters (filter_id, filter_name, filter_type, filter_value, display_name, is_active, sort_order) FROM stdin;
1	All Available Titles	where_to_look	all	All Available Titles	t	1
2	Watchlist Only	where_to_look	watchlist	Watchlist Only	t	2
3	All Types	content_type	all	All Types	t	1
4	Movies Only	content_type	movie	Movies Only	t	2
5	Shows Only	content_type	show	Shows Only	t	3
6	All Platforms	platform	all	All Platforms	t	1
7	Netflix	platform	netflix	Netflix	t	2
8	Hulu	platform	hulu	Hulu	t	3
9	Max	platform	max	Max	t	4
10	Prime Video	platform	prime_video	Prime Video	t	5
11	Disney+	platform	disney_plus	Disney+	t	6
\.


--
-- TOC entry 6241 (class 0 OID 27084)
-- Dependencies: 347
-- Data for Name: roulette_results; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roulette_results (result_id, user_id, content_type, content_id, filters_applied, was_instant, created_at) FROM stdin;
\.


--
-- TOC entry 6245 (class 0 OID 27117)
-- Dependencies: 351
-- Data for Name: search_analytics; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.search_analytics (search_id, user_id, search_term, search_type, filters_applied, results_count, clicked_result_type, clicked_result_id, session_id, ip_address, created_at) FROM stdin;
\.


--
-- TOC entry 6172 (class 0 OID 26129)
-- Dependencies: 274
-- Data for Name: sentiment_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sentiment_categories (category_id, category_name, description, color_hex, icon, is_active, created_at) FROM stdin;
1	Excited	Enthusiastic and thrilled about the content	#ff6b6b	🤩	t	2025-05-25 20:02:30.003125-04
2	Loved	Absolutely adored the content	#ff8cc8	😍	t	2025-05-25 20:02:30.003125-04
3	Enjoyed	Had a great time watching	#4ecdc4	😊	t	2025-05-25 20:02:30.003125-04
4	Impressed	Technically or artistically impressed	#45b7d1	👏	t	2025-05-25 20:02:30.003125-04
5	Emotional	Moved to tears or deeply affected	#96ceb4	😢	t	2025-05-25 20:02:30.003125-04
6	Nostalgic	Brought back memories or feelings	#feca57	🥺	t	2025-05-25 20:02:30.003125-04
7	Surprised	Unexpected twists or revelations	#ff9ff3	😲	t	2025-05-25 20:02:30.003125-04
8	Confused	Plot was hard to follow	#54a0ff	🤔	t	2025-05-25 20:02:30.003125-04
9	Disappointed	Expected more from the content	#ffa502	😞	t	2025-05-25 20:02:30.003125-04
10	Bored	Found it uninteresting or slow	#747d8c	😴	t	2025-05-25 20:02:30.003125-04
11	Angry	Frustrated with story/characters	#ff6348	😠	t	2025-05-25 20:02:30.003125-04
12	Scared	Genuinely frightened by horror content	#2f3542	😨	t	2025-05-25 20:02:30.003125-04
13	Test-Sentiment	Test sentiment category	#ff0000	😀	t	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6174 (class 0 OID 26142)
-- Dependencies: 276
-- Data for Name: sentiment_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sentiment_tags (tag_id, tag_name, category_id, description, usage_count, is_active, created_at) FROM stdin;
1	Mind-Blown	1	Completely amazed by the content	0	t	2025-05-25 20:02:30.003125-04
2	Epic	1	Grand scale and impressive	0	t	2025-05-25 20:02:30.003125-04
3	Addictive	1	Could not stop watching	0	t	2025-05-25 20:02:30.003125-04
4	Masterpiece	2	Perfect in every way	0	t	2025-05-25 20:02:30.003125-04
5	Rewatchable	2	Will definitely watch again	0	t	2025-05-25 20:02:30.003125-04
6	Favorite	2	New favorite content	0	t	2025-05-25 20:02:30.003125-04
7	Feel-Good	3	Made me happy	0	t	2025-05-25 20:02:30.003125-04
8	Entertaining	3	Good entertainment value	0	t	2025-05-25 20:02:30.003125-04
9	Satisfying	3	Left me satisfied	0	t	2025-05-25 20:02:30.003125-04
10	Visually-Stunning	4	Amazing cinematography/visuals	0	t	2025-05-25 20:02:30.003125-04
11	Well-Written	4	Excellent script and dialogue	0	t	2025-05-25 20:02:30.003125-04
12	Great-Acting	4	Outstanding performances	0	t	2025-05-25 20:02:30.003125-04
13	Heartbreaking	5	Made me cry	0	t	2025-05-25 20:02:30.003125-04
14	Touching	5	Emotionally moving	0	t	2025-05-25 20:02:30.003125-04
15	Inspiring	5	Motivated and uplifted me	0	t	2025-05-25 20:02:30.003125-04
16	Childhood-Vibes	6	Reminded me of being young	0	t	2025-05-25 20:02:30.003125-04
17	Retro	6	Great throwback feel	0	t	2025-05-25 20:02:30.003125-04
18	Plot-Twist	7	Unexpected story turns	0	t	2025-05-25 20:02:30.003125-04
19	Unpredictable	7	Could not guess what happens next	0	t	2025-05-25 20:02:30.003125-04
20	Complex	8	Intricate plot requiring attention	0	t	2025-05-25 20:02:30.003125-04
21	Unclear	8	Hard to follow story	0	t	2025-05-25 20:02:30.003125-04
22	Overhyped	9	Did not live up to expectations	0	t	2025-05-25 20:02:30.003125-04
23	Wasted-Potential	9	Could have been much better	0	t	2025-05-25 20:02:30.003125-04
24	Slow-Paced	10	Too slow for my taste	0	t	2025-05-25 20:02:30.003125-04
25	Predictable	10	Saw everything coming	0	t	2025-05-25 20:02:30.003125-04
26	Frustrating	11	Characters made poor decisions	0	t	2025-05-25 20:02:30.003125-04
27	Annoying	11	Irritating elements	0	t	2025-05-25 20:02:30.003125-04
28	Terrifying	12	Genuinely scary	0	t	2025-05-25 20:02:30.003125-04
29	Creepy	12	Unsettling atmosphere	0	t	2025-05-25 20:02:30.003125-04
30	Test-Tag	13	Test sentiment tag	0	t	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6127 (class 0 OID 25349)
-- Dependencies: 228
-- Data for Name: showgenres; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.showgenres (show_id, genre_id) FROM stdin;
5	8
6	6
6	8
7	7
8	9
8	10
\.


--
-- TOC entry 6125 (class 0 OID 25322)
-- Dependencies: 226
-- Data for Name: shows; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.shows (show_id, title, description, start_date, end_date, seasons, episodes_per_season, episode_duration, language, poster_url, backdrop_url, trailer_url, rating, creator, country_of_origin, created_at, updated_at, genres_array) FROM stdin;
5	Breaking Bad	A high school chemistry teacher turned methamphetamine manufacturer	2008-01-20	2013-09-29	5	13	45	\N	\N	\N	\N	9.5	Vince Gilligan	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
6	Game of Thrones	Noble families fight for control over the lands of Westeros	2011-04-17	2019-05-19	8	10	60	\N	\N	\N	\N	9.3	David Benioff & D.B. Weiss	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
7	The Office	A mockumentary on a group of typical office workers	2005-03-24	2013-05-16	9	24	22	\N	\N	\N	\N	8.9	Greg Daniels	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
8	Stranger Things	A group of kids encounter supernatural forces and secret government exploits	2016-07-15	\N	4	8	50	\N	\N	\N	\N	8.7	Duffer Brothers	\N	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	\N
\.


--
-- TOC entry 6159 (class 0 OID 25936)
-- Dependencies: 260
-- Data for Name: spoiler_reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spoiler_reports (report_id, reporter_id, content_type, content_id, reason, status, created_at, resolved_at, resolved_by) FROM stdin;
\.


--
-- TOC entry 6165 (class 0 OID 26001)
-- Dependencies: 266
-- Data for Name: spoiler_tags; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spoiler_tags (tag_id, content_type, content_id, tag_name, description, is_major, created_by, created_at) FROM stdin;
1	movie	35	test-spoiler-tag	Test spoiler tag for database verification	f	\N	2025-05-26 12:25:13.970952-04
\.


--
-- TOC entry 6204 (class 0 OID 26682)
-- Dependencies: 310
-- Data for Name: streaming_platforms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.streaming_platforms (platform_id, platform_name, platform_code, logo_url, base_url, is_active, created_at) FROM stdin;
1	Netflix	netflix	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/netflix.png	\N	t	2025-07-11 12:28:03.052982-04
2	Hulu	hulu	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/hulu.png	\N	t	2025-07-11 12:28:03.052982-04
3	Max	max	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/hbo-max.png	\N	t	2025-07-11 12:28:03.052982-04
4	Prime Video	prime_video	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/prime-video.png	\N	t	2025-07-11 12:28:03.052982-04
5	Disney+	disney_plus	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/disney-plus.png	\N	t	2025-07-11 12:28:03.052982-04
6	Apple TV+	apple_tv	https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/apple-tv.png	\N	t	2025-07-11 12:28:03.052982-04
\.


--
-- TOC entry 6210 (class 0 OID 26729)
-- Dependencies: 316
-- Data for Name: trailers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trailers (trailer_id, content_type, content_id, trailer_title, trailer_url, trailer_type, duration_seconds, thumbnail_url, release_date, view_count, is_featured, created_at) FROM stdin;
\.


--
-- TOC entry 6235 (class 0 OID 27052)
-- Dependencies: 341
-- Data for Name: trending_content; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trending_content (trending_id, content_type, content_id, trending_type, region, rank_position, trending_score, view_count, interaction_count, growth_rate, date_calculated, created_at) FROM stdin;
\.


--
-- TOC entry 6227 (class 0 OID 26944)
-- Dependencies: 333
-- Data for Name: user_activity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_activity (activity_id, user_id, activity_type, reference_type, reference_id, metadata, ip_address, user_agent, created_at) FROM stdin;
\.


--
-- TOC entry 6137 (class 0 OID 25492)
-- Dependencies: 238
-- Data for Name: user_connections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_connections (connection_id, follower_id, followed_id, connection_type, status, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6261 (class 0 OID 27276)
-- Dependencies: 367
-- Data for Name: user_device_preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_device_preferences (device_preference_id, user_id, device_type, preferred_layout, enable_gestures, enable_animations, font_size, last_used) FROM stdin;
\.


--
-- TOC entry 6253 (class 0 OID 27206)
-- Dependencies: 359
-- Data for Name: user_filter_preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_filter_preferences (filter_preference_id, user_id, context, filter_data, last_used) FROM stdin;
\.


--
-- TOC entry 6257 (class 0 OID 27238)
-- Dependencies: 363
-- Data for Name: user_homepage_sections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_homepage_sections (section_id, user_id, section_type, is_visible, sort_order, section_settings, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6145 (class 0 OID 25568)
-- Dependencies: 246
-- Data for Name: user_interactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_interactions (interaction_id, user_id, interaction_type_id, content_type, content_id, value, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6259 (class 0 OID 27258)
-- Dependencies: 365
-- Data for Name: user_notification_preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_notification_preferences (notification_preference_id, user_id, notification_category, delivery_method, is_enabled, frequency, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6223 (class 0 OID 26900)
-- Dependencies: 329
-- Data for Name: user_points; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_points (user_id, total_points, total_likes_received, total_dislikes_received, current_tier_id, like_points, post_points, review_points, share_points, comment_points, daily_streak, longest_streak, last_activity_date, tier_updated_at, created_at, updated_at) FROM stdin;
13	0	0	0	1	0	0	0	0	0	0	0	\N	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04
14	0	0	0	1	0	0	0	0	0	0	0	\N	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04
15	0	0	0	1	0	0	0	0	0	0	0	\N	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04
53	0	0	0	1	0	0	0	0	0	0	0	\N	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04	2025-07-11 12:49:15.709724-04
\.


--
-- TOC entry 6231 (class 0 OID 26988)
-- Dependencies: 337
-- Data for Name: user_post_interactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_post_interactions (interaction_id, post_id, user_id, interaction_type, created_at) FROM stdin;
\.


--
-- TOC entry 6233 (class 0 OID 27008)
-- Dependencies: 339
-- Data for Name: user_post_replies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_post_replies (reply_id, post_id, user_id, parent_reply_id, content, like_count, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6229 (class 0 OID 26959)
-- Dependencies: 335
-- Data for Name: user_posts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_posts (post_id, user_id, content, post_type, media_urls, tags, mentioned_users, original_post_id, like_count, repost_count, comment_count, view_count, is_trending, visibility, contains_spoilers, content_reference_type, content_reference_id, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6196 (class 0 OID 26508)
-- Dependencies: 300
-- Data for Name: user_reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_reports (report_id, reporter_id, reported_user_id, report_type_id, reason, evidence_urls, status, priority, created_at, updated_at, resolved_at, assigned_moderator_id, moderator_notes, resolution_action) FROM stdin;
\.


--
-- TOC entry 6182 (class 0 OID 26216)
-- Dependencies: 284
-- Data for Name: user_sentiment_patterns; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sentiment_patterns (pattern_id, user_id, favorite_sentiment_tags, sentiment_tendencies, genre_sentiment_patterns, last_analyzed) FROM stdin;
\.


--
-- TOC entry 6247 (class 0 OID 27132)
-- Dependencies: 353
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sessions (session_id, user_id, session_uuid, start_time, end_time, page_views, interactions, device_type, browser, ip_address, is_active) FROM stdin;
\.


--
-- TOC entry 6255 (class 0 OID 27223)
-- Dependencies: 361
-- Data for Name: user_tab_preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_tab_preferences (tab_preference_id, user_id, page_context, active_tab, last_accessed) FROM stdin;
\.


--
-- TOC entry 6251 (class 0 OID 27186)
-- Dependencies: 357
-- Data for Name: user_view_preferences; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_view_preferences (preference_id, user_id, page_section, view_mode, sort_order, items_per_page, show_filters, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 6117 (class 0 OID 25263)
-- Dependencies: 218
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (user_id, username, email, password_hash, first_name, last_name, date_of_birth, profile_picture, bio, created_at, last_login, is_active) FROM stdin;
13	johndoe	john@example.com	hashed_password_1	John	Doe	1990-05-15	\N	Movie enthusiast	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	t
14	janedoe	jane@example.com	hashed_password_2	Jane	Doe	1992-08-20	\N	TV show critic	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	t
15	bobsmith	bob@example.com	hashed_password_3	Bob	Smith	1985-11-30	\N	Film student	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04	t
53	spoilersdemo	spoilersdemo@gmail.com	$2b$12$demo_hash_spoilers123	Demo	User	\N	\N	Spoiler-free demo account	2025-05-29 17:37:51.899346-04	\N	t
\.


--
-- TOC entry 6150 (class 0 OID 25814)
-- Dependencies: 251
-- Data for Name: watch_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.watch_history (history_id, user_id, content_type, content_id, progress, completed, last_watched) FROM stdin;
\.


--
-- TOC entry 6134 (class 0 OID 25422)
-- Dependencies: 235
-- Data for Name: watchlist_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.watchlist_items (watchlist_id, content_type, content_id, added_at) FROM stdin;
4	movie	5	2025-03-20 11:33:35.059603-04
4	movie	6	2025-03-20 11:33:35.059603-04
4	show	8	2025-03-20 11:33:35.059603-04
5	show	7	2025-03-20 11:33:35.059603-04
5	movie	7	2025-03-20 11:33:35.059603-04
6	movie	7	2025-03-20 11:33:35.059603-04
6	movie	8	2025-03-20 11:33:35.059603-04
6	show	5	2025-03-20 11:33:35.059603-04
\.


--
-- TOC entry 6133 (class 0 OID 25406)
-- Dependencies: 234
-- Data for Name: watchlists; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.watchlists (watchlist_id, user_id, name, description, is_public, created_at, updated_at) FROM stdin;
4	13	Must-Watch Sci-Fi	My collection of essential science fiction	t	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04
5	14	Comedies for Bad Days	Shows and movies that cheer me up	f	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04
6	15	Award Winners	Movies and shows that won major awards	t	2025-03-20 11:33:35.059603-04	2025-03-20 11:33:35.059603-04
\.


--
-- TOC entry 6363 (class 0 OID 0)
-- Dependencies: 279
-- Name: ai_sentiment_analysis_analysis_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ai_sentiment_analysis_analysis_id_seq', 1, true);


--
-- TOC entry 6364 (class 0 OID 0)
-- Dependencies: 286
-- Name: ai_spoiler_analysis_analysis_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ai_spoiler_analysis_analysis_id_seq', 1, false);


--
-- TOC entry 6365 (class 0 OID 0)
-- Dependencies: 253
-- Name: augmented_recommendations_recommendation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.augmented_recommendations_recommendation_id_seq', 1, true);


--
-- TOC entry 6366 (class 0 OID 0)
-- Dependencies: 295
-- Name: auth0_sessions_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth0_sessions_session_id_seq', 1, false);


--
-- TOC entry 6367 (class 0 OID 0)
-- Dependencies: 293
-- Name: auth0_users_auth0_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auth0_users_auth0_user_id_seq', 1, false);


--
-- TOC entry 6368 (class 0 OID 0)
-- Dependencies: 231
-- Name: comments_comment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.comments_comment_id_seq', 12, true);


--
-- TOC entry 6369 (class 0 OID 0)
-- Dependencies: 319
-- Name: communities_community_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.communities_community_id_seq', 1, true);


--
-- TOC entry 6370 (class 0 OID 0)
-- Dependencies: 317
-- Name: community_categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.community_categories_category_id_seq', 9, true);


--
-- TOC entry 6371 (class 0 OID 0)
-- Dependencies: 321
-- Name: community_memberships_membership_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.community_memberships_membership_id_seq', 1, false);


--
-- TOC entry 6372 (class 0 OID 0)
-- Dependencies: 325
-- Name: community_post_comments_comment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.community_post_comments_comment_id_seq', 1, false);


--
-- TOC entry 6373 (class 0 OID 0)
-- Dependencies: 323
-- Name: community_posts_post_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.community_posts_post_id_seq', 1, false);


--
-- TOC entry 6374 (class 0 OID 0)
-- Dependencies: 342
-- Name: content_analytics_analytics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_analytics_analytics_id_seq', 3, true);


--
-- TOC entry 6375 (class 0 OID 0)
-- Dependencies: 354
-- Name: content_discovery_metrics_metric_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_discovery_metrics_metric_id_seq', 1, false);


--
-- TOC entry 6376 (class 0 OID 0)
-- Dependencies: 311
-- Name: content_platform_availability_availability_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_platform_availability_availability_id_seq', 4, true);


--
-- TOC entry 6377 (class 0 OID 0)
-- Dependencies: 257
-- Name: content_progress_progress_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_progress_progress_id_seq', 1, true);


--
-- TOC entry 6378 (class 0 OID 0)
-- Dependencies: 301
-- Name: content_reports_report_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_reports_report_id_seq', 1, false);


--
-- TOC entry 6379 (class 0 OID 0)
-- Dependencies: 378
-- Name: content_request_comments_comment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_request_comments_comment_id_seq', 1, false);


--
-- TOC entry 6380 (class 0 OID 0)
-- Dependencies: 380
-- Name: content_request_history_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_request_history_history_id_seq', 1, false);


--
-- TOC entry 6381 (class 0 OID 0)
-- Dependencies: 372
-- Name: content_request_types_request_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_request_types_request_type_id_seq', 1, false);


--
-- TOC entry 6382 (class 0 OID 0)
-- Dependencies: 376
-- Name: content_request_votes_vote_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_request_votes_vote_id_seq', 1, false);


--
-- TOC entry 6383 (class 0 OID 0)
-- Dependencies: 281
-- Name: content_sentiment_summary_summary_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_sentiment_summary_summary_id_seq', 1, true);


--
-- TOC entry 6384 (class 0 OID 0)
-- Dependencies: 277
-- Name: content_sentiment_tags_content_sentiment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_sentiment_tags_content_sentiment_id_seq', 1, true);


--
-- TOC entry 6385 (class 0 OID 0)
-- Dependencies: 313
-- Name: content_status_status_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_status_status_id_seq', 1, false);


--
-- TOC entry 6386 (class 0 OID 0)
-- Dependencies: 255
-- Name: data_change_queue_change_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.data_change_queue_change_id_seq', 30, true);


--
-- TOC entry 6387 (class 0 OID 0)
-- Dependencies: 263
-- Name: discussion_posts_post_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discussion_posts_post_id_seq', 1, true);


--
-- TOC entry 6388 (class 0 OID 0)
-- Dependencies: 290
-- Name: discussion_summary_sources_source_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discussion_summary_sources_source_id_seq', 1, false);


--
-- TOC entry 6389 (class 0 OID 0)
-- Dependencies: 261
-- Name: discussion_topics_topic_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discussion_topics_topic_id_seq', 1, true);


--
-- TOC entry 6390 (class 0 OID 0)
-- Dependencies: 348
-- Name: featured_content_featured_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.featured_content_featured_id_seq', 2, true);


--
-- TOC entry 6391 (class 0 OID 0)
-- Dependencies: 221
-- Name: genres_genre_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.genres_genre_id_seq', 12, true);


--
-- TOC entry 6392 (class 0 OID 0)
-- Dependencies: 269
-- Name: gpt_api_usage_usage_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gpt_api_usage_usage_id_seq', 1, true);


--
-- TOC entry 6393 (class 0 OID 0)
-- Dependencies: 288
-- Name: gpt_summaries_summary_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gpt_summaries_summary_id_seq', 1, false);


--
-- TOC entry 6394 (class 0 OID 0)
-- Dependencies: 243
-- Name: interaction_types_interaction_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.interaction_types_interaction_type_id_seq', 7, true);


--
-- TOC entry 6395 (class 0 OID 0)
-- Dependencies: 248
-- Name: login_attempts_attempt_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.login_attempts_attempt_id_seq', 1, true);


--
-- TOC entry 6396 (class 0 OID 0)
-- Dependencies: 374
-- Name: missing_content_requests_request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.missing_content_requests_request_id_seq', 1, false);


--
-- TOC entry 6397 (class 0 OID 0)
-- Dependencies: 303
-- Name: moderation_actions_action_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.moderation_actions_action_id_seq', 1, false);


--
-- TOC entry 6398 (class 0 OID 0)
-- Dependencies: 223
-- Name: movies_movie_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.movies_movie_id_seq', 35, true);


--
-- TOC entry 6399 (class 0 OID 0)
-- Dependencies: 239
-- Name: notification_types_notification_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.notification_types_notification_type_id_seq', 10, true);


--
-- TOC entry 6400 (class 0 OID 0)
-- Dependencies: 241
-- Name: notifications_notification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.notifications_notification_id_seq', 2, true);


--
-- TOC entry 6401 (class 0 OID 0)
-- Dependencies: 330
-- Name: point_transactions_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.point_transactions_transaction_id_seq', 1, false);


--
-- TOC entry 6402 (class 0 OID 0)
-- Dependencies: 219
-- Name: preferences_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.preferences_preference_id_seq', 49, true);


--
-- TOC entry 6403 (class 0 OID 0)
-- Dependencies: 327
-- Name: ranking_tiers_tier_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ranking_tiers_tier_id_seq', 5, true);


--
-- TOC entry 6404 (class 0 OID 0)
-- Dependencies: 305
-- Name: report_escalations_escalation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_escalations_escalation_id_seq', 1, false);


--
-- TOC entry 6405 (class 0 OID 0)
-- Dependencies: 297
-- Name: report_types_report_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_types_report_type_id_seq', 10, true);


--
-- TOC entry 6406 (class 0 OID 0)
-- Dependencies: 229
-- Name: reviews_review_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reviews_review_id_seq', 16, true);


--
-- TOC entry 6407 (class 0 OID 0)
-- Dependencies: 344
-- Name: roulette_filters_filter_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roulette_filters_filter_id_seq', 11, true);


--
-- TOC entry 6408 (class 0 OID 0)
-- Dependencies: 346
-- Name: roulette_results_result_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roulette_results_result_id_seq', 1, false);


--
-- TOC entry 6409 (class 0 OID 0)
-- Dependencies: 350
-- Name: search_analytics_search_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.search_analytics_search_id_seq', 1, false);


--
-- TOC entry 6410 (class 0 OID 0)
-- Dependencies: 273
-- Name: sentiment_categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sentiment_categories_category_id_seq', 13, true);


--
-- TOC entry 6411 (class 0 OID 0)
-- Dependencies: 275
-- Name: sentiment_tags_tag_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sentiment_tags_tag_id_seq', 30, true);


--
-- TOC entry 6412 (class 0 OID 0)
-- Dependencies: 225
-- Name: shows_show_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.shows_show_id_seq', 30, true);


--
-- TOC entry 6413 (class 0 OID 0)
-- Dependencies: 259
-- Name: spoiler_reports_report_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.spoiler_reports_report_id_seq', 1, true);


--
-- TOC entry 6414 (class 0 OID 0)
-- Dependencies: 265
-- Name: spoiler_tags_tag_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.spoiler_tags_tag_id_seq', 1, true);


--
-- TOC entry 6415 (class 0 OID 0)
-- Dependencies: 309
-- Name: streaming_platforms_platform_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.streaming_platforms_platform_id_seq', 6, true);


--
-- TOC entry 6416 (class 0 OID 0)
-- Dependencies: 315
-- Name: trailers_trailer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trailers_trailer_id_seq', 3, true);


--
-- TOC entry 6417 (class 0 OID 0)
-- Dependencies: 340
-- Name: trending_content_trending_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trending_content_trending_id_seq', 1, false);


--
-- TOC entry 6418 (class 0 OID 0)
-- Dependencies: 332
-- Name: user_activity_activity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_activity_activity_id_seq', 1, false);


--
-- TOC entry 6419 (class 0 OID 0)
-- Dependencies: 237
-- Name: user_connections_connection_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_connections_connection_id_seq', 2, true);


--
-- TOC entry 6420 (class 0 OID 0)
-- Dependencies: 366
-- Name: user_device_preferences_device_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_device_preferences_device_preference_id_seq', 1, false);


--
-- TOC entry 6421 (class 0 OID 0)
-- Dependencies: 358
-- Name: user_filter_preferences_filter_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_filter_preferences_filter_preference_id_seq', 1, false);


--
-- TOC entry 6422 (class 0 OID 0)
-- Dependencies: 362
-- Name: user_homepage_sections_section_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_homepage_sections_section_id_seq', 1, false);


--
-- TOC entry 6423 (class 0 OID 0)
-- Dependencies: 245
-- Name: user_interactions_interaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_interactions_interaction_id_seq', 2, true);


--
-- TOC entry 6424 (class 0 OID 0)
-- Dependencies: 364
-- Name: user_notification_preferences_notification_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_notification_preferences_notification_preference_id_seq', 1, false);


--
-- TOC entry 6425 (class 0 OID 0)
-- Dependencies: 336
-- Name: user_post_interactions_interaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_post_interactions_interaction_id_seq', 1, false);


--
-- TOC entry 6426 (class 0 OID 0)
-- Dependencies: 338
-- Name: user_post_replies_reply_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_post_replies_reply_id_seq', 1, false);


--
-- TOC entry 6427 (class 0 OID 0)
-- Dependencies: 334
-- Name: user_posts_post_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_posts_post_id_seq', 1, false);


--
-- TOC entry 6428 (class 0 OID 0)
-- Dependencies: 299
-- Name: user_reports_report_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_reports_report_id_seq', 1, false);


--
-- TOC entry 6429 (class 0 OID 0)
-- Dependencies: 283
-- Name: user_sentiment_patterns_pattern_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_sentiment_patterns_pattern_id_seq', 1, true);


--
-- TOC entry 6430 (class 0 OID 0)
-- Dependencies: 352
-- Name: user_sessions_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_sessions_session_id_seq', 1, false);


--
-- TOC entry 6431 (class 0 OID 0)
-- Dependencies: 360
-- Name: user_tab_preferences_tab_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_tab_preferences_tab_preference_id_seq', 1, false);


--
-- TOC entry 6432 (class 0 OID 0)
-- Dependencies: 356
-- Name: user_view_preferences_preference_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_view_preferences_preference_id_seq', 4, true);


--
-- TOC entry 6433 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_user_id_seq', 53, true);


--
-- TOC entry 6434 (class 0 OID 0)
-- Dependencies: 250
-- Name: watch_history_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.watch_history_history_id_seq', 1, true);


--
-- TOC entry 6435 (class 0 OID 0)
-- Dependencies: 233
-- Name: watchlists_watchlist_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.watchlists_watchlist_id_seq', 8, true);


--
-- TOC entry 5597 (class 2606 OID 26195)
-- Name: ai_sentiment_analysis ai_sentiment_analysis_content_type_content_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_sentiment_analysis
    ADD CONSTRAINT ai_sentiment_analysis_content_type_content_id_key UNIQUE (content_type, content_id);


--
-- TOC entry 5599 (class 2606 OID 26193)
-- Name: ai_sentiment_analysis ai_sentiment_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_sentiment_analysis
    ADD CONSTRAINT ai_sentiment_analysis_pkey PRIMARY KEY (analysis_id);


--
-- TOC entry 5611 (class 2606 OID 26266)
-- Name: ai_spoiler_analysis ai_spoiler_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ai_spoiler_analysis
    ADD CONSTRAINT ai_spoiler_analysis_pkey PRIMARY KEY (analysis_id);


--
-- TOC entry 5557 (class 2606 OID 25890)
-- Name: augmented_recommendations augmented_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.augmented_recommendations
    ADD CONSTRAINT augmented_recommendations_pkey PRIMARY KEY (recommendation_id);


--
-- TOC entry 5559 (class 2606 OID 25892)
-- Name: augmented_recommendations augmented_recommendations_user_id_content_type_content_id_r_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.augmented_recommendations
    ADD CONSTRAINT augmented_recommendations_user_id_content_type_content_id_r_key UNIQUE (user_id, content_type, content_id, recommendation_type);


--
-- TOC entry 5631 (class 2606 OID 26486)
-- Name: auth0_sessions auth0_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_sessions
    ADD CONSTRAINT auth0_sessions_pkey PRIMARY KEY (session_id);


--
-- TOC entry 5624 (class 2606 OID 26468)
-- Name: auth0_users auth0_users_auth0_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_users
    ADD CONSTRAINT auth0_users_auth0_id_key UNIQUE (auth0_id);


--
-- TOC entry 5626 (class 2606 OID 26466)
-- Name: auth0_users auth0_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_users
    ADD CONSTRAINT auth0_users_pkey PRIMARY KEY (auth0_user_id);


--
-- TOC entry 5516 (class 2606 OID 25394)
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (comment_id);


--
-- TOC entry 5686 (class 2606 OID 26780)
-- Name: communities communities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_pkey PRIMARY KEY (community_id);


--
-- TOC entry 5680 (class 2606 OID 26764)
-- Name: community_categories community_categories_category_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_categories
    ADD CONSTRAINT community_categories_category_code_key UNIQUE (category_code);


--
-- TOC entry 5682 (class 2606 OID 26762)
-- Name: community_categories community_categories_category_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_categories
    ADD CONSTRAINT community_categories_category_name_key UNIQUE (category_name);


--
-- TOC entry 5684 (class 2606 OID 26760)
-- Name: community_categories community_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_categories
    ADD CONSTRAINT community_categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 5692 (class 2606 OID 26807)
-- Name: community_memberships community_memberships_community_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_memberships
    ADD CONSTRAINT community_memberships_community_id_user_id_key UNIQUE (community_id, user_id);


--
-- TOC entry 5694 (class 2606 OID 26805)
-- Name: community_memberships community_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_memberships
    ADD CONSTRAINT community_memberships_pkey PRIMARY KEY (membership_id);


--
-- TOC entry 5703 (class 2606 OID 26858)
-- Name: community_post_comments community_post_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_pkey PRIMARY KEY (comment_id);


--
-- TOC entry 5698 (class 2606 OID 26836)
-- Name: community_posts community_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_posts
    ADD CONSTRAINT community_posts_pkey PRIMARY KEY (post_id);


--
-- TOC entry 5749 (class 2606 OID 27073)
-- Name: content_analytics content_analytics_content_type_content_id_metric_type_date__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_analytics
    ADD CONSTRAINT content_analytics_content_type_content_id_metric_type_date__key UNIQUE (content_type, content_id, metric_type, date_recorded, hour_recorded);


--
-- TOC entry 5751 (class 2606 OID 27071)
-- Name: content_analytics content_analytics_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_analytics
    ADD CONSTRAINT content_analytics_pkey PRIMARY KEY (analytics_id);


--
-- TOC entry 5777 (class 2606 OID 27157)
-- Name: content_discovery_metrics content_discovery_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_discovery_metrics
    ADD CONSTRAINT content_discovery_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 5663 (class 2606 OID 26710)
-- Name: content_platform_availability content_platform_availability_content_type_content_id_platf_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_platform_availability
    ADD CONSTRAINT content_platform_availability_content_type_content_id_platf_key UNIQUE (content_type, content_id, platform_id, availability_region);


--
-- TOC entry 5665 (class 2606 OID 26708)
-- Name: content_platform_availability content_platform_availability_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_platform_availability
    ADD CONSTRAINT content_platform_availability_pkey PRIMARY KEY (availability_id);


--
-- TOC entry 5563 (class 2606 OID 25927)
-- Name: content_progress content_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_progress
    ADD CONSTRAINT content_progress_pkey PRIMARY KEY (progress_id);


--
-- TOC entry 5565 (class 2606 OID 25929)
-- Name: content_progress content_progress_user_id_content_type_content_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_progress
    ADD CONSTRAINT content_progress_user_id_content_type_content_id_key UNIQUE (user_id, content_type, content_id);


--
-- TOC entry 5645 (class 2606 OID 26561)
-- Name: content_reports content_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_reports
    ADD CONSTRAINT content_reports_pkey PRIMARY KEY (report_id);


--
-- TOC entry 5832 (class 2606 OID 27463)
-- Name: content_request_comments content_request_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_comments
    ADD CONSTRAINT content_request_comments_pkey PRIMARY KEY (comment_id);


--
-- TOC entry 5836 (class 2606 OID 27483)
-- Name: content_request_history content_request_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_history
    ADD CONSTRAINT content_request_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 5815 (class 2606 OID 27385)
-- Name: content_request_types content_request_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_types
    ADD CONSTRAINT content_request_types_pkey PRIMARY KEY (request_type_id);


--
-- TOC entry 5817 (class 2606 OID 27387)
-- Name: content_request_types content_request_types_type_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_types
    ADD CONSTRAINT content_request_types_type_name_key UNIQUE (type_name);


--
-- TOC entry 5826 (class 2606 OID 27439)
-- Name: content_request_votes content_request_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_votes
    ADD CONSTRAINT content_request_votes_pkey PRIMARY KEY (vote_id);


--
-- TOC entry 5828 (class 2606 OID 27441)
-- Name: content_request_votes content_request_votes_request_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_votes
    ADD CONSTRAINT content_request_votes_request_id_user_id_key UNIQUE (request_id, user_id);


--
-- TOC entry 5602 (class 2606 OID 26214)
-- Name: content_sentiment_summary content_sentiment_summary_content_type_content_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_summary
    ADD CONSTRAINT content_sentiment_summary_content_type_content_id_key UNIQUE (content_type, content_id);


--
-- TOC entry 5604 (class 2606 OID 26212)
-- Name: content_sentiment_summary content_sentiment_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_summary
    ADD CONSTRAINT content_sentiment_summary_pkey PRIMARY KEY (summary_id);


--
-- TOC entry 5591 (class 2606 OID 26170)
-- Name: content_sentiment_tags content_sentiment_tags_content_type_content_id_tag_id_user__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_tags
    ADD CONSTRAINT content_sentiment_tags_content_type_content_id_tag_id_user__key UNIQUE (content_type, content_id, tag_id, user_id);


--
-- TOC entry 5593 (class 2606 OID 26168)
-- Name: content_sentiment_tags content_sentiment_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_tags
    ADD CONSTRAINT content_sentiment_tags_pkey PRIMARY KEY (content_sentiment_id);


--
-- TOC entry 5575 (class 2606 OID 26022)
-- Name: content_spoiler_tags content_spoiler_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_spoiler_tags
    ADD CONSTRAINT content_spoiler_tags_pkey PRIMARY KEY (content_type, content_id, tag_id);


--
-- TOC entry 5669 (class 2606 OID 26727)
-- Name: content_status content_status_content_type_content_id_status_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_status
    ADD CONSTRAINT content_status_content_type_content_id_status_type_key UNIQUE (content_type, content_id, status_type);


--
-- TOC entry 5671 (class 2606 OID 26725)
-- Name: content_status content_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_status
    ADD CONSTRAINT content_status_pkey PRIMARY KEY (status_id);


--
-- TOC entry 5561 (class 2606 OID 25911)
-- Name: data_change_queue data_change_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.data_change_queue
    ADD CONSTRAINT data_change_queue_pkey PRIMARY KEY (change_id);


--
-- TOC entry 5571 (class 2606 OID 25989)
-- Name: discussion_posts discussion_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_posts
    ADD CONSTRAINT discussion_posts_pkey PRIMARY KEY (post_id);


--
-- TOC entry 5620 (class 2606 OID 26320)
-- Name: discussion_summary_sources discussion_summary_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_summary_sources
    ADD CONSTRAINT discussion_summary_sources_pkey PRIMARY KEY (source_id);


--
-- TOC entry 5622 (class 2606 OID 26322)
-- Name: discussion_summary_sources discussion_summary_sources_summary_id_source_type_source_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_summary_sources
    ADD CONSTRAINT discussion_summary_sources_summary_id_source_type_source_id_key UNIQUE (summary_id, source_type, source_id_ref);


--
-- TOC entry 5569 (class 2606 OID 25972)
-- Name: discussion_topics discussion_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_topics
    ADD CONSTRAINT discussion_topics_pkey PRIMARY KEY (topic_id);


--
-- TOC entry 5526 (class 2606 OID 25440)
-- Name: favorites favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (user_id, content_type, content_id);


--
-- TOC entry 5762 (class 2606 OID 27110)
-- Name: featured_content featured_content_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.featured_content
    ADD CONSTRAINT featured_content_pkey PRIMARY KEY (featured_id);


--
-- TOC entry 5495 (class 2606 OID 25308)
-- Name: genres genres_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genres
    ADD CONSTRAINT genres_name_key UNIQUE (name);


--
-- TOC entry 5497 (class 2606 OID 25306)
-- Name: genres genres_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genres
    ADD CONSTRAINT genres_pkey PRIMARY KEY (genre_id);


--
-- TOC entry 5577 (class 2606 OID 26068)
-- Name: gpt_api_usage gpt_api_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gpt_api_usage
    ADD CONSTRAINT gpt_api_usage_pkey PRIMARY KEY (usage_id);


--
-- TOC entry 5613 (class 2606 OID 26308)
-- Name: gpt_summaries gpt_summaries_content_type_content_id_discussion_timeframe__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gpt_summaries
    ADD CONSTRAINT gpt_summaries_content_type_content_id_discussion_timeframe__key UNIQUE (content_type, content_id, discussion_timeframe, summary_type, discussion_scope);


--
-- TOC entry 5615 (class 2606 OID 26306)
-- Name: gpt_summaries gpt_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gpt_summaries
    ADD CONSTRAINT gpt_summaries_pkey PRIMARY KEY (summary_id);


--
-- TOC entry 5549 (class 2606 OID 25597)
-- Name: interaction_counts interaction_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interaction_counts
    ADD CONSTRAINT interaction_counts_pkey PRIMARY KEY (content_type, content_id, interaction_type_id);


--
-- TOC entry 5540 (class 2606 OID 25564)
-- Name: interaction_types interaction_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interaction_types
    ADD CONSTRAINT interaction_types_pkey PRIMARY KEY (interaction_type_id);


--
-- TOC entry 5542 (class 2606 OID 25566)
-- Name: interaction_types interaction_types_type_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interaction_types
    ADD CONSTRAINT interaction_types_type_name_key UNIQUE (type_name);


--
-- TOC entry 5551 (class 2606 OID 25792)
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (attempt_id);


--
-- TOC entry 5824 (class 2606 OID 27404)
-- Name: missing_content_requests missing_content_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_pkey PRIMARY KEY (request_id);


--
-- TOC entry 5653 (class 2606 OID 26589)
-- Name: moderation_actions moderation_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moderation_actions
    ADD CONSTRAINT moderation_actions_pkey PRIMARY KEY (action_id);


--
-- TOC entry 5505 (class 2606 OID 25338)
-- Name: moviegenres moviegenres_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moviegenres
    ADD CONSTRAINT moviegenres_pkey PRIMARY KEY (movie_id, genre_id);


--
-- TOC entry 5500 (class 2606 OID 25320)
-- Name: movies movies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movies
    ADD CONSTRAINT movies_pkey PRIMARY KEY (movie_id);


--
-- TOC entry 5533 (class 2606 OID 25525)
-- Name: notification_types notification_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notification_types
    ADD CONSTRAINT notification_types_pkey PRIMARY KEY (notification_type_id);


--
-- TOC entry 5535 (class 2606 OID 25527)
-- Name: notification_types notification_types_type_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notification_types
    ADD CONSTRAINT notification_types_type_name_key UNIQUE (type_name);


--
-- TOC entry 5538 (class 2606 OID 25538)
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (notification_id);


--
-- TOC entry 5722 (class 2606 OID 26937)
-- Name: point_transactions point_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_transactions
    ADD CONSTRAINT point_transactions_pkey PRIMARY KEY (transaction_id);


--
-- TOC entry 5491 (class 2606 OID 25290)
-- Name: preferences preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preferences
    ADD CONSTRAINT preferences_pkey PRIMARY KEY (preference_id);


--
-- TOC entry 5493 (class 2606 OID 25292)
-- Name: preferences preferences_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preferences
    ADD CONSTRAINT preferences_user_id_key UNIQUE (user_id);


--
-- TOC entry 5707 (class 2606 OID 26895)
-- Name: ranking_tiers ranking_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ranking_tiers
    ADD CONSTRAINT ranking_tiers_pkey PRIMARY KEY (tier_id);


--
-- TOC entry 5709 (class 2606 OID 26899)
-- Name: ranking_tiers ranking_tiers_tier_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ranking_tiers
    ADD CONSTRAINT ranking_tiers_tier_code_key UNIQUE (tier_code);


--
-- TOC entry 5711 (class 2606 OID 26897)
-- Name: ranking_tiers ranking_tiers_tier_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ranking_tiers
    ADD CONSTRAINT ranking_tiers_tier_name_key UNIQUE (tier_name);


--
-- TOC entry 5655 (class 2606 OID 26617)
-- Name: report_escalations report_escalations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_escalations
    ADD CONSTRAINT report_escalations_pkey PRIMARY KEY (escalation_id);


--
-- TOC entry 5635 (class 2606 OID 26504)
-- Name: report_types report_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_types
    ADD CONSTRAINT report_types_pkey PRIMARY KEY (report_type_id);


--
-- TOC entry 5637 (class 2606 OID 26506)
-- Name: report_types report_types_type_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_types
    ADD CONSTRAINT report_types_type_name_key UNIQUE (type_name);


--
-- TOC entry 5512 (class 2606 OID 25376)
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (review_id);


--
-- TOC entry 5514 (class 2606 OID 25378)
-- Name: reviews reviews_user_id_content_type_content_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_content_type_content_id_key UNIQUE (user_id, content_type, content_id);


--
-- TOC entry 5756 (class 2606 OID 27082)
-- Name: roulette_filters roulette_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roulette_filters
    ADD CONSTRAINT roulette_filters_pkey PRIMARY KEY (filter_id);


--
-- TOC entry 5760 (class 2606 OID 27093)
-- Name: roulette_results roulette_results_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roulette_results
    ADD CONSTRAINT roulette_results_pkey PRIMARY KEY (result_id);


--
-- TOC entry 5769 (class 2606 OID 27125)
-- Name: search_analytics search_analytics_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.search_analytics
    ADD CONSTRAINT search_analytics_pkey PRIMARY KEY (search_id);


--
-- TOC entry 5581 (class 2606 OID 26140)
-- Name: sentiment_categories sentiment_categories_category_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_categories
    ADD CONSTRAINT sentiment_categories_category_name_key UNIQUE (category_name);


--
-- TOC entry 5583 (class 2606 OID 26138)
-- Name: sentiment_categories sentiment_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_categories
    ADD CONSTRAINT sentiment_categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 5587 (class 2606 OID 26152)
-- Name: sentiment_tags sentiment_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_tags
    ADD CONSTRAINT sentiment_tags_pkey PRIMARY KEY (tag_id);


--
-- TOC entry 5589 (class 2606 OID 26154)
-- Name: sentiment_tags sentiment_tags_tag_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_tags
    ADD CONSTRAINT sentiment_tags_tag_name_key UNIQUE (tag_name);


--
-- TOC entry 5507 (class 2606 OID 25353)
-- Name: showgenres showgenres_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.showgenres
    ADD CONSTRAINT showgenres_pkey PRIMARY KEY (show_id, genre_id);


--
-- TOC entry 5503 (class 2606 OID 25333)
-- Name: shows shows_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shows
    ADD CONSTRAINT shows_pkey PRIMARY KEY (show_id);


--
-- TOC entry 5567 (class 2606 OID 25947)
-- Name: spoiler_reports spoiler_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_reports
    ADD CONSTRAINT spoiler_reports_pkey PRIMARY KEY (report_id);


--
-- TOC entry 5573 (class 2606 OID 26011)
-- Name: spoiler_tags spoiler_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_tags
    ADD CONSTRAINT spoiler_tags_pkey PRIMARY KEY (tag_id);


--
-- TOC entry 5657 (class 2606 OID 26691)
-- Name: streaming_platforms streaming_platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.streaming_platforms
    ADD CONSTRAINT streaming_platforms_pkey PRIMARY KEY (platform_id);


--
-- TOC entry 5659 (class 2606 OID 26695)
-- Name: streaming_platforms streaming_platforms_platform_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.streaming_platforms
    ADD CONSTRAINT streaming_platforms_platform_code_key UNIQUE (platform_code);


--
-- TOC entry 5661 (class 2606 OID 26693)
-- Name: streaming_platforms streaming_platforms_platform_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.streaming_platforms
    ADD CONSTRAINT streaming_platforms_platform_name_key UNIQUE (platform_name);


--
-- TOC entry 5678 (class 2606 OID 26741)
-- Name: trailers trailers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trailers
    ADD CONSTRAINT trailers_pkey PRIMARY KEY (trailer_id);


--
-- TOC entry 5745 (class 2606 OID 27063)
-- Name: trending_content trending_content_content_type_content_id_trending_type_regi_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trending_content
    ADD CONSTRAINT trending_content_content_type_content_id_trending_type_regi_key UNIQUE (content_type, content_id, trending_type, region, date_calculated);


--
-- TOC entry 5747 (class 2606 OID 27061)
-- Name: trending_content trending_content_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trending_content
    ADD CONSTRAINT trending_content_pkey PRIMARY KEY (trending_id);


--
-- TOC entry 5727 (class 2606 OID 26952)
-- Name: user_activity user_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_activity
    ADD CONSTRAINT user_activity_pkey PRIMARY KEY (activity_id);


--
-- TOC entry 5529 (class 2606 OID 25505)
-- Name: user_connections user_connections_follower_id_followed_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_connections
    ADD CONSTRAINT user_connections_follower_id_followed_id_key UNIQUE (follower_id, followed_id);


--
-- TOC entry 5531 (class 2606 OID 25503)
-- Name: user_connections user_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_connections
    ADD CONSTRAINT user_connections_pkey PRIMARY KEY (connection_id);


--
-- TOC entry 5811 (class 2606 OID 27285)
-- Name: user_device_preferences user_device_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_device_preferences
    ADD CONSTRAINT user_device_preferences_pkey PRIMARY KEY (device_preference_id);


--
-- TOC entry 5813 (class 2606 OID 27287)
-- Name: user_device_preferences user_device_preferences_user_id_device_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_device_preferences
    ADD CONSTRAINT user_device_preferences_user_id_device_type_key UNIQUE (user_id, device_type);


--
-- TOC entry 5789 (class 2606 OID 27214)
-- Name: user_filter_preferences user_filter_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_filter_preferences
    ADD CONSTRAINT user_filter_preferences_pkey PRIMARY KEY (filter_preference_id);


--
-- TOC entry 5791 (class 2606 OID 27216)
-- Name: user_filter_preferences user_filter_preferences_user_id_context_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_filter_preferences
    ADD CONSTRAINT user_filter_preferences_user_id_context_key UNIQUE (user_id, context);


--
-- TOC entry 5801 (class 2606 OID 27249)
-- Name: user_homepage_sections user_homepage_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_homepage_sections
    ADD CONSTRAINT user_homepage_sections_pkey PRIMARY KEY (section_id);


--
-- TOC entry 5803 (class 2606 OID 27251)
-- Name: user_homepage_sections user_homepage_sections_user_id_section_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_homepage_sections
    ADD CONSTRAINT user_homepage_sections_user_id_section_type_key UNIQUE (user_id, section_type);


--
-- TOC entry 5545 (class 2606 OID 25577)
-- Name: user_interactions user_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_interactions
    ADD CONSTRAINT user_interactions_pkey PRIMARY KEY (interaction_id);


--
-- TOC entry 5547 (class 2606 OID 25579)
-- Name: user_interactions user_interactions_user_id_interaction_type_id_content_type__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_interactions
    ADD CONSTRAINT user_interactions_user_id_interaction_type_id_content_type__key UNIQUE (user_id, interaction_type_id, content_type, content_id);


--
-- TOC entry 5806 (class 2606 OID 27267)
-- Name: user_notification_preferences user_notification_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_notification_preferences
    ADD CONSTRAINT user_notification_preferences_pkey PRIMARY KEY (notification_preference_id);


--
-- TOC entry 5808 (class 2606 OID 27269)
-- Name: user_notification_preferences user_notification_preferences_user_id_notification_category_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_notification_preferences
    ADD CONSTRAINT user_notification_preferences_user_id_notification_category_key UNIQUE (user_id, notification_category, delivery_method);


--
-- TOC entry 5717 (class 2606 OID 26917)
-- Name: user_points user_points_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_points
    ADD CONSTRAINT user_points_pkey PRIMARY KEY (user_id);


--
-- TOC entry 5736 (class 2606 OID 26994)
-- Name: user_post_interactions user_post_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_interactions
    ADD CONSTRAINT user_post_interactions_pkey PRIMARY KEY (interaction_id);


--
-- TOC entry 5738 (class 2606 OID 26996)
-- Name: user_post_interactions user_post_interactions_post_id_user_id_interaction_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_interactions
    ADD CONSTRAINT user_post_interactions_post_id_user_id_interaction_type_key UNIQUE (post_id, user_id, interaction_type);


--
-- TOC entry 5741 (class 2606 OID 27018)
-- Name: user_post_replies user_post_replies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_replies
    ADD CONSTRAINT user_post_replies_pkey PRIMARY KEY (reply_id);


--
-- TOC entry 5732 (class 2606 OID 26976)
-- Name: user_posts user_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_posts
    ADD CONSTRAINT user_posts_pkey PRIMARY KEY (post_id);


--
-- TOC entry 5643 (class 2606 OID 26521)
-- Name: user_reports user_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_pkey PRIMARY KEY (report_id);


--
-- TOC entry 5607 (class 2606 OID 26224)
-- Name: user_sentiment_patterns user_sentiment_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sentiment_patterns
    ADD CONSTRAINT user_sentiment_patterns_pkey PRIMARY KEY (pattern_id);


--
-- TOC entry 5609 (class 2606 OID 26226)
-- Name: user_sentiment_patterns user_sentiment_patterns_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sentiment_patterns
    ADD CONSTRAINT user_sentiment_patterns_user_id_key UNIQUE (user_id);


--
-- TOC entry 5773 (class 2606 OID 27141)
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (session_id);


--
-- TOC entry 5775 (class 2606 OID 27143)
-- Name: user_sessions user_sessions_session_uuid_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_session_uuid_key UNIQUE (session_uuid);


--
-- TOC entry 5795 (class 2606 OID 27229)
-- Name: user_tab_preferences user_tab_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tab_preferences
    ADD CONSTRAINT user_tab_preferences_pkey PRIMARY KEY (tab_preference_id);


--
-- TOC entry 5797 (class 2606 OID 27231)
-- Name: user_tab_preferences user_tab_preferences_user_id_page_context_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tab_preferences
    ADD CONSTRAINT user_tab_preferences_user_id_page_context_key UNIQUE (user_id, page_context);


--
-- TOC entry 5783 (class 2606 OID 27197)
-- Name: user_view_preferences user_view_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_view_preferences
    ADD CONSTRAINT user_view_preferences_pkey PRIMARY KEY (preference_id);


--
-- TOC entry 5785 (class 2606 OID 27199)
-- Name: user_view_preferences user_view_preferences_user_id_page_section_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_view_preferences
    ADD CONSTRAINT user_view_preferences_user_id_page_section_key UNIQUE (user_id, page_section);


--
-- TOC entry 5485 (class 2606 OID 25276)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 5487 (class 2606 OID 25272)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 5489 (class 2606 OID 25274)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 5553 (class 2606 OID 25822)
-- Name: watch_history watch_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watch_history
    ADD CONSTRAINT watch_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 5555 (class 2606 OID 25824)
-- Name: watch_history watch_history_user_id_content_type_content_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watch_history
    ADD CONSTRAINT watch_history_user_id_content_type_content_id_key UNIQUE (user_id, content_type, content_id);


--
-- TOC entry 5524 (class 2606 OID 25428)
-- Name: watchlist_items watchlist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watchlist_items
    ADD CONSTRAINT watchlist_items_pkey PRIMARY KEY (watchlist_id, content_type, content_id);


--
-- TOC entry 5522 (class 2606 OID 25416)
-- Name: watchlists watchlists_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watchlists
    ADD CONSTRAINT watchlists_pkey PRIMARY KEY (watchlist_id);


--
-- TOC entry 5600 (class 1259 OID 26235)
-- Name: idx_ai_sentiment_analysis_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ai_sentiment_analysis_content ON public.ai_sentiment_analysis USING btree (content_type, content_id);


--
-- TOC entry 5578 (class 1259 OID 26101)
-- Name: idx_augmented_movies_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_augmented_movies_title ON public.augmented_movies USING btree (title);


--
-- TOC entry 5579 (class 1259 OID 26102)
-- Name: idx_augmented_shows_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_augmented_shows_title ON public.augmented_shows USING btree (title);


--
-- TOC entry 5632 (class 1259 OID 26632)
-- Name: idx_auth0_sessions_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth0_sessions_active ON public.auth0_sessions USING btree (is_active, expires_at) WHERE (is_active = true);


--
-- TOC entry 5633 (class 1259 OID 26631)
-- Name: idx_auth0_sessions_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth0_sessions_user_id ON public.auth0_sessions USING btree (auth0_user_id);


--
-- TOC entry 5627 (class 1259 OID 26628)
-- Name: idx_auth0_users_auth0_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth0_users_auth0_id ON public.auth0_users USING btree (auth0_id);


--
-- TOC entry 5628 (class 1259 OID 26629)
-- Name: idx_auth0_users_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth0_users_email ON public.auth0_users USING btree (email);


--
-- TOC entry 5629 (class 1259 OID 26630)
-- Name: idx_auth0_users_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auth0_users_user_id ON public.auth0_users USING btree (user_id);


--
-- TOC entry 5517 (class 1259 OID 25452)
-- Name: idx_comments_review_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comments_review_id ON public.comments USING btree (review_id);


--
-- TOC entry 5518 (class 1259 OID 25959)
-- Name: idx_comments_spoilers; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comments_spoilers ON public.comments USING btree (contains_spoilers);


--
-- TOC entry 5519 (class 1259 OID 25453)
-- Name: idx_comments_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_comments_user_id ON public.comments USING btree (user_id);


--
-- TOC entry 5687 (class 1259 OID 26874)
-- Name: idx_communities_category; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_communities_category ON public.communities USING btree (category_id);


--
-- TOC entry 5688 (class 1259 OID 26875)
-- Name: idx_communities_creator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_communities_creator ON public.communities USING btree (creator_id);


--
-- TOC entry 5689 (class 1259 OID 26877)
-- Name: idx_communities_featured; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_communities_featured ON public.communities USING btree (is_featured);


--
-- TOC entry 5690 (class 1259 OID 26876)
-- Name: idx_communities_type_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_communities_type_content ON public.communities USING btree (community_type, content_type, content_id);


--
-- TOC entry 5695 (class 1259 OID 26879)
-- Name: idx_community_memberships_community; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_memberships_community ON public.community_memberships USING btree (community_id);


--
-- TOC entry 5696 (class 1259 OID 26878)
-- Name: idx_community_memberships_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_memberships_user ON public.community_memberships USING btree (user_id);


--
-- TOC entry 5704 (class 1259 OID 26883)
-- Name: idx_community_post_comments_post; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_post_comments_post ON public.community_post_comments USING btree (post_id);


--
-- TOC entry 5705 (class 1259 OID 26884)
-- Name: idx_community_post_comments_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_post_comments_user ON public.community_post_comments USING btree (user_id);


--
-- TOC entry 5699 (class 1259 OID 26880)
-- Name: idx_community_posts_community; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_posts_community ON public.community_posts USING btree (community_id);


--
-- TOC entry 5700 (class 1259 OID 26882)
-- Name: idx_community_posts_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_posts_created ON public.community_posts USING btree (created_at);


--
-- TOC entry 5701 (class 1259 OID 26881)
-- Name: idx_community_posts_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_community_posts_user ON public.community_posts USING btree (user_id);


--
-- TOC entry 5752 (class 1259 OID 27165)
-- Name: idx_content_analytics_content_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_analytics_content_date ON public.content_analytics USING btree (content_type, content_id, date_recorded);


--
-- TOC entry 5753 (class 1259 OID 27340)
-- Name: idx_content_analytics_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_analytics_date ON public.content_analytics USING btree (date_recorded);


--
-- TOC entry 5754 (class 1259 OID 27166)
-- Name: idx_content_analytics_metric; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_analytics_metric ON public.content_analytics USING btree (metric_type, date_recorded);


--
-- TOC entry 5778 (class 1259 OID 27176)
-- Name: idx_content_discovery_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_discovery_content ON public.content_discovery_metrics USING btree (content_type, content_id);


--
-- TOC entry 5779 (class 1259 OID 27177)
-- Name: idx_content_discovery_source; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_discovery_source ON public.content_discovery_metrics USING btree (discovery_source);


--
-- TOC entry 5666 (class 1259 OID 26742)
-- Name: idx_content_platform_availability_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_platform_availability_content ON public.content_platform_availability USING btree (content_type, content_id);


--
-- TOC entry 5667 (class 1259 OID 26743)
-- Name: idx_content_platform_availability_platform; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_platform_availability_platform ON public.content_platform_availability USING btree (platform_id);


--
-- TOC entry 5646 (class 1259 OID 26638)
-- Name: idx_content_reports_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_reports_content ON public.content_reports USING btree (content_type, content_id);


--
-- TOC entry 5647 (class 1259 OID 26640)
-- Name: idx_content_reports_moderator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_reports_moderator ON public.content_reports USING btree (assigned_moderator_id);


--
-- TOC entry 5648 (class 1259 OID 26639)
-- Name: idx_content_reports_reporter; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_reports_reporter ON public.content_reports USING btree (reporter_id);


--
-- TOC entry 5649 (class 1259 OID 26637)
-- Name: idx_content_reports_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_reports_status ON public.content_reports USING btree (status, created_at);


--
-- TOC entry 5605 (class 1259 OID 26236)
-- Name: idx_content_sentiment_summary_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_sentiment_summary_content ON public.content_sentiment_summary USING btree (content_type, content_id);


--
-- TOC entry 5594 (class 1259 OID 26233)
-- Name: idx_content_sentiment_tags_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_sentiment_tags_content ON public.content_sentiment_tags USING btree (content_type, content_id);


--
-- TOC entry 5595 (class 1259 OID 26234)
-- Name: idx_content_sentiment_tags_tag; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_sentiment_tags_tag ON public.content_sentiment_tags USING btree (tag_id);


--
-- TOC entry 5672 (class 1259 OID 26744)
-- Name: idx_content_status_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_status_content ON public.content_status USING btree (content_type, content_id);


--
-- TOC entry 5673 (class 1259 OID 26745)
-- Name: idx_content_status_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_content_status_type ON public.content_status USING btree (status_type);


--
-- TOC entry 5527 (class 1259 OID 25451)
-- Name: idx_favorites_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_favorites_user_id ON public.favorites USING btree (user_id);


--
-- TOC entry 5763 (class 1259 OID 27170)
-- Name: idx_featured_content_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_featured_content_active ON public.featured_content USING btree (is_active, start_date, end_date);


--
-- TOC entry 5764 (class 1259 OID 27169)
-- Name: idx_featured_content_type_location; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_featured_content_type_location ON public.featured_content USING btree (feature_type, feature_location);


--
-- TOC entry 5616 (class 1259 OID 26309)
-- Name: idx_gpt_summaries_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gpt_summaries_content ON public.gpt_summaries USING btree (content_type, content_id);


--
-- TOC entry 5617 (class 1259 OID 26311)
-- Name: idx_gpt_summaries_needs_refresh; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gpt_summaries_needs_refresh ON public.gpt_summaries USING btree (needs_refresh) WHERE (needs_refresh = true);


--
-- TOC entry 5618 (class 1259 OID 26310)
-- Name: idx_gpt_summaries_timeframe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gpt_summaries_timeframe ON public.gpt_summaries USING btree (discussion_timeframe, generated_at);


--
-- TOC entry 5818 (class 1259 OID 27498)
-- Name: idx_missing_requests_assigned_to; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_missing_requests_assigned_to ON public.missing_content_requests USING btree (assigned_to);


--
-- TOC entry 5819 (class 1259 OID 27496)
-- Name: idx_missing_requests_content_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_missing_requests_content_type ON public.missing_content_requests USING btree (content_type);


--
-- TOC entry 5820 (class 1259 OID 27497)
-- Name: idx_missing_requests_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_missing_requests_created_at ON public.missing_content_requests USING btree (created_at);


--
-- TOC entry 5821 (class 1259 OID 27495)
-- Name: idx_missing_requests_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_missing_requests_status ON public.missing_content_requests USING btree (status);


--
-- TOC entry 5822 (class 1259 OID 27494)
-- Name: idx_missing_requests_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_missing_requests_user_id ON public.missing_content_requests USING btree (user_id);


--
-- TOC entry 5650 (class 1259 OID 26641)
-- Name: idx_moderation_actions_moderator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_moderation_actions_moderator ON public.moderation_actions USING btree (moderator_id, created_at);


--
-- TOC entry 5651 (class 1259 OID 26642)
-- Name: idx_moderation_actions_target_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_moderation_actions_target_user ON public.moderation_actions USING btree (target_user_id) WHERE ((target_type)::text = 'user'::text);


--
-- TOC entry 5498 (class 1259 OID 25446)
-- Name: idx_movies_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movies_title ON public.movies USING btree (title);


--
-- TOC entry 5536 (class 1259 OID 25554)
-- Name: idx_notifications_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notifications_user ON public.notifications USING btree (user_id, is_read, created_at);


--
-- TOC entry 5718 (class 1259 OID 27039)
-- Name: idx_point_transactions_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_point_transactions_created ON public.point_transactions USING btree (created_at);


--
-- TOC entry 5719 (class 1259 OID 27038)
-- Name: idx_point_transactions_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_point_transactions_type ON public.point_transactions USING btree (transaction_type);


--
-- TOC entry 5720 (class 1259 OID 27037)
-- Name: idx_point_transactions_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_point_transactions_user ON public.point_transactions USING btree (user_id);


--
-- TOC entry 5833 (class 1259 OID 27501)
-- Name: idx_request_comments_request_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_request_comments_request_id ON public.content_request_comments USING btree (request_id);


--
-- TOC entry 5834 (class 1259 OID 27502)
-- Name: idx_request_comments_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_request_comments_user_id ON public.content_request_comments USING btree (user_id);


--
-- TOC entry 5837 (class 1259 OID 27503)
-- Name: idx_request_history_request_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_request_history_request_id ON public.content_request_history USING btree (request_id);


--
-- TOC entry 5829 (class 1259 OID 27499)
-- Name: idx_request_votes_request_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_request_votes_request_id ON public.content_request_votes USING btree (request_id);


--
-- TOC entry 5830 (class 1259 OID 27500)
-- Name: idx_request_votes_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_request_votes_user_id ON public.content_request_votes USING btree (user_id);


--
-- TOC entry 5508 (class 1259 OID 25449)
-- Name: idx_reviews_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reviews_content ON public.reviews USING btree (content_type, content_id);


--
-- TOC entry 5509 (class 1259 OID 25958)
-- Name: idx_reviews_spoilers; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reviews_spoilers ON public.reviews USING btree (contains_spoilers);


--
-- TOC entry 5510 (class 1259 OID 25448)
-- Name: idx_reviews_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reviews_user_id ON public.reviews USING btree (user_id);


--
-- TOC entry 5757 (class 1259 OID 27168)
-- Name: idx_roulette_results_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_roulette_results_created ON public.roulette_results USING btree (created_at);


--
-- TOC entry 5758 (class 1259 OID 27167)
-- Name: idx_roulette_results_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_roulette_results_user ON public.roulette_results USING btree (user_id);


--
-- TOC entry 5765 (class 1259 OID 27173)
-- Name: idx_search_analytics_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_search_analytics_created ON public.search_analytics USING btree (created_at);


--
-- TOC entry 5766 (class 1259 OID 27172)
-- Name: idx_search_analytics_term; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_search_analytics_term ON public.search_analytics USING btree (search_term);


--
-- TOC entry 5767 (class 1259 OID 27171)
-- Name: idx_search_analytics_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_search_analytics_user ON public.search_analytics USING btree (user_id);


--
-- TOC entry 5584 (class 1259 OID 26232)
-- Name: idx_sentiment_tags_category; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sentiment_tags_category ON public.sentiment_tags USING btree (category_id);


--
-- TOC entry 5585 (class 1259 OID 26237)
-- Name: idx_sentiment_tags_usage; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sentiment_tags_usage ON public.sentiment_tags USING btree (usage_count DESC);


--
-- TOC entry 5501 (class 1259 OID 25447)
-- Name: idx_shows_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_shows_title ON public.shows USING btree (title);


--
-- TOC entry 5674 (class 1259 OID 26746)
-- Name: idx_trailers_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_trailers_content ON public.trailers USING btree (content_type, content_id);


--
-- TOC entry 5675 (class 1259 OID 26747)
-- Name: idx_trailers_featured; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_trailers_featured ON public.trailers USING btree (is_featured);


--
-- TOC entry 5676 (class 1259 OID 26748)
-- Name: idx_trailers_release_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_trailers_release_date ON public.trailers USING btree (release_date);


--
-- TOC entry 5742 (class 1259 OID 27164)
-- Name: idx_trending_content_rank; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_trending_content_rank ON public.trending_content USING btree (rank_position);


--
-- TOC entry 5743 (class 1259 OID 27163)
-- Name: idx_trending_content_type_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_trending_content_type_date ON public.trending_content USING btree (content_type, trending_type, date_calculated);


--
-- TOC entry 5723 (class 1259 OID 27042)
-- Name: idx_user_activity_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_activity_created ON public.user_activity USING btree (created_at);


--
-- TOC entry 5724 (class 1259 OID 27041)
-- Name: idx_user_activity_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_activity_type ON public.user_activity USING btree (activity_type, reference_type);


--
-- TOC entry 5725 (class 1259 OID 27040)
-- Name: idx_user_activity_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_activity_user ON public.user_activity USING btree (user_id);


--
-- TOC entry 5809 (class 1259 OID 27302)
-- Name: idx_user_device_preferences_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_device_preferences_user ON public.user_device_preferences USING btree (user_id);


--
-- TOC entry 5786 (class 1259 OID 27296)
-- Name: idx_user_filter_preferences_context; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_filter_preferences_context ON public.user_filter_preferences USING btree (context);


--
-- TOC entry 5787 (class 1259 OID 27295)
-- Name: idx_user_filter_preferences_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_filter_preferences_user ON public.user_filter_preferences USING btree (user_id);


--
-- TOC entry 5798 (class 1259 OID 27299)
-- Name: idx_user_homepage_sections_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_homepage_sections_user ON public.user_homepage_sections USING btree (user_id);


--
-- TOC entry 5799 (class 1259 OID 27300)
-- Name: idx_user_homepage_sections_visible; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_homepage_sections_visible ON public.user_homepage_sections USING btree (is_visible, sort_order);


--
-- TOC entry 5543 (class 1259 OID 25590)
-- Name: idx_user_interactions_content; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_interactions_content ON public.user_interactions USING btree (content_type, content_id, interaction_type_id);


--
-- TOC entry 5804 (class 1259 OID 27301)
-- Name: idx_user_notification_preferences_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_notification_preferences_user ON public.user_notification_preferences USING btree (user_id);


--
-- TOC entry 5712 (class 1259 OID 27036)
-- Name: idx_user_points_likes; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_points_likes ON public.user_points USING btree (total_likes_received);


--
-- TOC entry 5713 (class 1259 OID 27034)
-- Name: idx_user_points_tier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_points_tier ON public.user_points USING btree (current_tier_id);


--
-- TOC entry 5714 (class 1259 OID 27035)
-- Name: idx_user_points_total; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_points_total ON public.user_points USING btree (total_points);


--
-- TOC entry 5715 (class 1259 OID 27339)
-- Name: idx_user_points_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_points_user ON public.user_points USING btree (user_id);


--
-- TOC entry 5733 (class 1259 OID 27046)
-- Name: idx_user_post_interactions_post; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_post_interactions_post ON public.user_post_interactions USING btree (post_id);


--
-- TOC entry 5734 (class 1259 OID 27047)
-- Name: idx_user_post_interactions_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_post_interactions_user ON public.user_post_interactions USING btree (user_id);


--
-- TOC entry 5739 (class 1259 OID 27048)
-- Name: idx_user_post_replies_post; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_post_replies_post ON public.user_post_replies USING btree (post_id);


--
-- TOC entry 5728 (class 1259 OID 27045)
-- Name: idx_user_posts_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_posts_created ON public.user_posts USING btree (created_at);


--
-- TOC entry 5729 (class 1259 OID 27044)
-- Name: idx_user_posts_trending; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_posts_trending ON public.user_posts USING btree (is_trending);


--
-- TOC entry 5730 (class 1259 OID 27043)
-- Name: idx_user_posts_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_posts_user ON public.user_posts USING btree (user_id);


--
-- TOC entry 5638 (class 1259 OID 26636)
-- Name: idx_user_reports_moderator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_reports_moderator ON public.user_reports USING btree (assigned_moderator_id);


--
-- TOC entry 5639 (class 1259 OID 26635)
-- Name: idx_user_reports_reported_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_reports_reported_user ON public.user_reports USING btree (reported_user_id);


--
-- TOC entry 5640 (class 1259 OID 26634)
-- Name: idx_user_reports_reporter; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_reports_reporter ON public.user_reports USING btree (reporter_id);


--
-- TOC entry 5641 (class 1259 OID 26633)
-- Name: idx_user_reports_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_reports_status ON public.user_reports USING btree (status, created_at);


--
-- TOC entry 5770 (class 1259 OID 27174)
-- Name: idx_user_sessions_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_sessions_user ON public.user_sessions USING btree (user_id);


--
-- TOC entry 5771 (class 1259 OID 27175)
-- Name: idx_user_sessions_uuid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_sessions_uuid ON public.user_sessions USING btree (session_uuid);


--
-- TOC entry 5792 (class 1259 OID 27298)
-- Name: idx_user_tab_preferences_page; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_tab_preferences_page ON public.user_tab_preferences USING btree (page_context);


--
-- TOC entry 5793 (class 1259 OID 27297)
-- Name: idx_user_tab_preferences_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_tab_preferences_user ON public.user_tab_preferences USING btree (user_id);


--
-- TOC entry 5780 (class 1259 OID 27294)
-- Name: idx_user_view_preferences_page; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_view_preferences_page ON public.user_view_preferences USING btree (page_section);


--
-- TOC entry 5781 (class 1259 OID 27293)
-- Name: idx_user_view_preferences_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_view_preferences_user ON public.user_view_preferences USING btree (user_id);


--
-- TOC entry 5520 (class 1259 OID 25450)
-- Name: idx_watchlist_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_watchlist_user_id ON public.watchlists USING btree (user_id);


--
-- TOC entry 5952 (class 2620 OID 27309)
-- Name: point_transactions calculate_total_points_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER calculate_total_points_trigger AFTER INSERT ON public.point_transactions FOR EACH ROW EXECUTE FUNCTION public.calculate_user_total_points();


--
-- TOC entry 5935 (class 2620 OID 26029)
-- Name: reviews check_review_spoilers; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_review_spoilers BEFORE INSERT OR UPDATE OF review_text ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.check_for_spoiler_keywords();


--
-- TOC entry 5944 (class 2620 OID 25614)
-- Name: user_connections create_connection_notification_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER create_connection_notification_trigger AFTER INSERT OR UPDATE OF status ON public.user_connections FOR EACH ROW EXECUTE FUNCTION public.create_connection_notification();


--
-- TOC entry 5945 (class 2620 OID 25612)
-- Name: user_interactions create_interaction_notification_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER create_interaction_notification_trigger AFTER INSERT ON public.user_interactions FOR EACH ROW EXECUTE FUNCTION public.create_interaction_notification();


--
-- TOC entry 5954 (class 2620 OID 27507)
-- Name: missing_content_requests log_request_status_change_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER log_request_status_change_trigger BEFORE UPDATE ON public.missing_content_requests FOR EACH ROW EXECUTE FUNCTION public.log_request_status_change();


--
-- TOC entry 5931 (class 2620 OID 25913)
-- Name: movies queue_movie_changes; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER queue_movie_changes AFTER INSERT OR DELETE OR UPDATE ON public.movies FOR EACH ROW EXECUTE FUNCTION public.queue_data_change();


--
-- TOC entry 5939 (class 2620 OID 27315)
-- Name: comments track_comment_activity_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER track_comment_activity_trigger AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.track_user_activity();


--
-- TOC entry 5950 (class 2620 OID 27314)
-- Name: community_posts track_community_post_activity_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER track_community_post_activity_trigger AFTER INSERT ON public.community_posts FOR EACH ROW EXECUTE FUNCTION public.track_user_activity();


--
-- TOC entry 5953 (class 2620 OID 27313)
-- Name: user_posts track_post_activity_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER track_post_activity_trigger AFTER INSERT ON public.user_posts FOR EACH ROW EXECUTE FUNCTION public.track_user_activity();


--
-- TOC entry 5936 (class 2620 OID 27312)
-- Name: reviews track_review_activity_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER track_review_activity_trigger AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.track_user_activity();


--
-- TOC entry 5940 (class 2620 OID 25458)
-- Name: comments update_comments_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_comments_modtime BEFORE UPDATE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- TOC entry 5949 (class 2620 OID 27310)
-- Name: community_memberships update_community_members_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_community_members_trigger AFTER INSERT OR DELETE OR UPDATE ON public.community_memberships FOR EACH ROW EXECUTE FUNCTION public.update_community_member_count();


--
-- TOC entry 5951 (class 2620 OID 27311)
-- Name: community_posts update_community_posts_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_community_posts_trigger AFTER INSERT OR DELETE ON public.community_posts FOR EACH ROW EXECUTE FUNCTION public.update_community_post_count();


--
-- TOC entry 5946 (class 2620 OID 25604)
-- Name: user_interactions update_interaction_count_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_interaction_count_trigger AFTER INSERT OR DELETE ON public.user_interactions FOR EACH ROW EXECUTE FUNCTION public.update_interaction_count();


--
-- TOC entry 5955 (class 2620 OID 27505)
-- Name: missing_content_requests update_missing_request_timestamp_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_missing_request_timestamp_trigger BEFORE UPDATE ON public.missing_content_requests FOR EACH ROW EXECUTE FUNCTION public.update_missing_request_timestamp();


--
-- TOC entry 5934 (class 2620 OID 25880)
-- Name: moviegenres update_movie_genres_array_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_movie_genres_array_trigger AFTER INSERT OR UPDATE ON public.moviegenres FOR EACH ROW EXECUTE FUNCTION public.update_movie_genres_array();


--
-- TOC entry 5932 (class 2620 OID 25455)
-- Name: movies update_movies_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_movies_modtime BEFORE UPDATE ON public.movies FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- TOC entry 5937 (class 2620 OID 25457)
-- Name: reviews update_reviews_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_reviews_modtime BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- TOC entry 5948 (class 2620 OID 26239)
-- Name: content_sentiment_tags update_sentiment_tag_usage_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_sentiment_tag_usage_trigger AFTER INSERT OR DELETE ON public.content_sentiment_tags FOR EACH ROW EXECUTE FUNCTION public.update_sentiment_tag_usage();


--
-- TOC entry 5933 (class 2620 OID 25456)
-- Name: shows update_shows_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_shows_modtime BEFORE UPDATE ON public.shows FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- TOC entry 5947 (class 2620 OID 27308)
-- Name: user_interactions update_user_points_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_user_points_trigger AFTER INSERT ON public.user_interactions FOR EACH ROW EXECUTE FUNCTION public.update_user_points();


--
-- TOC entry 5941 (class 2620 OID 25459)
-- Name: watchlists update_watchlists_modtime; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_watchlists_modtime BEFORE UPDATE ON public.watchlists FOR EACH ROW EXECUTE FUNCTION public.update_modified_column();


--
-- TOC entry 5943 (class 2620 OID 25465)
-- Name: favorites validate_favorite_content_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER validate_favorite_content_trigger BEFORE INSERT OR UPDATE ON public.favorites FOR EACH ROW EXECUTE FUNCTION public.validate_favorite_content();


--
-- TOC entry 5938 (class 2620 OID 25461)
-- Name: reviews validate_review_content_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER validate_review_content_trigger BEFORE INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.validate_review_content();


--
-- TOC entry 5942 (class 2620 OID 25463)
-- Name: watchlist_items validate_watchlist_item_content_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER validate_watchlist_item_content_trigger BEFORE INSERT OR UPDATE ON public.watchlist_items FOR EACH ROW EXECUTE FUNCTION public.validate_watchlist_item_content();


--
-- TOC entry 5859 (class 2606 OID 25893)
-- Name: augmented_recommendations augmented_recommendations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.augmented_recommendations
    ADD CONSTRAINT augmented_recommendations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5874 (class 2606 OID 26487)
-- Name: auth0_sessions auth0_sessions_auth0_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_sessions
    ADD CONSTRAINT auth0_sessions_auth0_user_id_fkey FOREIGN KEY (auth0_user_id) REFERENCES public.auth0_users(auth0_user_id) ON DELETE CASCADE;


--
-- TOC entry 5873 (class 2606 OID 26469)
-- Name: auth0_users auth0_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auth0_users
    ADD CONSTRAINT auth0_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5844 (class 2606 OID 25400)
-- Name: comments comments_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.reviews(review_id) ON DELETE CASCADE;


--
-- TOC entry 5845 (class 2606 OID 25395)
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5888 (class 2606 OID 26781)
-- Name: communities communities_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.community_categories(category_id) ON DELETE SET NULL;


--
-- TOC entry 5889 (class 2606 OID 26791)
-- Name: communities communities_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5890 (class 2606 OID 26786)
-- Name: communities communities_genre_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.communities
    ADD CONSTRAINT communities_genre_id_fkey FOREIGN KEY (genre_id) REFERENCES public.genres(genre_id) ON DELETE SET NULL;


--
-- TOC entry 5891 (class 2606 OID 26808)
-- Name: community_memberships community_memberships_community_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_memberships
    ADD CONSTRAINT community_memberships_community_id_fkey FOREIGN KEY (community_id) REFERENCES public.communities(community_id) ON DELETE CASCADE;


--
-- TOC entry 5892 (class 2606 OID 26813)
-- Name: community_memberships community_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_memberships
    ADD CONSTRAINT community_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5895 (class 2606 OID 26869)
-- Name: community_post_comments community_post_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.community_post_comments(comment_id) ON DELETE CASCADE;


--
-- TOC entry 5896 (class 2606 OID 26859)
-- Name: community_post_comments community_post_comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.community_posts(post_id) ON DELETE CASCADE;


--
-- TOC entry 5897 (class 2606 OID 26864)
-- Name: community_post_comments community_post_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_post_comments
    ADD CONSTRAINT community_post_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5893 (class 2606 OID 26837)
-- Name: community_posts community_posts_community_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_posts
    ADD CONSTRAINT community_posts_community_id_fkey FOREIGN KEY (community_id) REFERENCES public.communities(community_id) ON DELETE CASCADE;


--
-- TOC entry 5894 (class 2606 OID 26842)
-- Name: community_posts community_posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.community_posts
    ADD CONSTRAINT community_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5913 (class 2606 OID 27158)
-- Name: content_discovery_metrics content_discovery_metrics_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_discovery_metrics
    ADD CONSTRAINT content_discovery_metrics_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5887 (class 2606 OID 26711)
-- Name: content_platform_availability content_platform_availability_platform_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_platform_availability
    ADD CONSTRAINT content_platform_availability_platform_id_fkey FOREIGN KEY (platform_id) REFERENCES public.streaming_platforms(platform_id) ON DELETE CASCADE;


--
-- TOC entry 5860 (class 2606 OID 25930)
-- Name: content_progress content_progress_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_progress
    ADD CONSTRAINT content_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5879 (class 2606 OID 26572)
-- Name: content_reports content_reports_assigned_moderator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_reports
    ADD CONSTRAINT content_reports_assigned_moderator_id_fkey FOREIGN KEY (assigned_moderator_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5880 (class 2606 OID 26567)
-- Name: content_reports content_reports_report_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_reports
    ADD CONSTRAINT content_reports_report_type_id_fkey FOREIGN KEY (report_type_id) REFERENCES public.report_types(report_type_id);


--
-- TOC entry 5881 (class 2606 OID 26562)
-- Name: content_reports content_reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_reports
    ADD CONSTRAINT content_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5927 (class 2606 OID 27464)
-- Name: content_request_comments content_request_comments_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_comments
    ADD CONSTRAINT content_request_comments_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.missing_content_requests(request_id) ON DELETE CASCADE;


--
-- TOC entry 5928 (class 2606 OID 27469)
-- Name: content_request_comments content_request_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_comments
    ADD CONSTRAINT content_request_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5929 (class 2606 OID 27489)
-- Name: content_request_history content_request_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_history
    ADD CONSTRAINT content_request_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5930 (class 2606 OID 27484)
-- Name: content_request_history content_request_history_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_history
    ADD CONSTRAINT content_request_history_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.missing_content_requests(request_id) ON DELETE CASCADE;


--
-- TOC entry 5925 (class 2606 OID 27442)
-- Name: content_request_votes content_request_votes_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_votes
    ADD CONSTRAINT content_request_votes_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.missing_content_requests(request_id) ON DELETE CASCADE;


--
-- TOC entry 5926 (class 2606 OID 27447)
-- Name: content_request_votes content_request_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_request_votes
    ADD CONSTRAINT content_request_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5869 (class 2606 OID 26171)
-- Name: content_sentiment_tags content_sentiment_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_tags
    ADD CONSTRAINT content_sentiment_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.sentiment_tags(tag_id) ON DELETE CASCADE;


--
-- TOC entry 5870 (class 2606 OID 26176)
-- Name: content_sentiment_tags content_sentiment_tags_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_sentiment_tags
    ADD CONSTRAINT content_sentiment_tags_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5867 (class 2606 OID 26023)
-- Name: content_spoiler_tags content_spoiler_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_spoiler_tags
    ADD CONSTRAINT content_spoiler_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.spoiler_tags(tag_id) ON DELETE CASCADE;


--
-- TOC entry 5864 (class 2606 OID 25990)
-- Name: discussion_posts discussion_posts_topic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_posts
    ADD CONSTRAINT discussion_posts_topic_id_fkey FOREIGN KEY (topic_id) REFERENCES public.discussion_topics(topic_id) ON DELETE CASCADE;


--
-- TOC entry 5865 (class 2606 OID 25995)
-- Name: discussion_posts discussion_posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_posts
    ADD CONSTRAINT discussion_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5872 (class 2606 OID 26323)
-- Name: discussion_summary_sources discussion_summary_sources_summary_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_summary_sources
    ADD CONSTRAINT discussion_summary_sources_summary_id_fkey FOREIGN KEY (summary_id) REFERENCES public.gpt_summaries(summary_id) ON DELETE CASCADE;


--
-- TOC entry 5863 (class 2606 OID 25973)
-- Name: discussion_topics discussion_topics_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discussion_topics
    ADD CONSTRAINT discussion_topics_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5848 (class 2606 OID 25441)
-- Name: favorites favorites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5910 (class 2606 OID 27111)
-- Name: featured_content featured_content_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.featured_content
    ADD CONSTRAINT featured_content_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5856 (class 2606 OID 25598)
-- Name: interaction_counts interaction_counts_interaction_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interaction_counts
    ADD CONSTRAINT interaction_counts_interaction_type_id_fkey FOREIGN KEY (interaction_type_id) REFERENCES public.interaction_types(interaction_type_id) ON DELETE CASCADE;


--
-- TOC entry 5857 (class 2606 OID 25793)
-- Name: login_attempts login_attempts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5920 (class 2606 OID 27420)
-- Name: missing_content_requests missing_content_requests_added_movie_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_added_movie_id_fkey FOREIGN KEY (added_movie_id) REFERENCES public.movies(movie_id) ON DELETE SET NULL;


--
-- TOC entry 5921 (class 2606 OID 27425)
-- Name: missing_content_requests missing_content_requests_added_show_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_added_show_id_fkey FOREIGN KEY (added_show_id) REFERENCES public.shows(show_id) ON DELETE SET NULL;


--
-- TOC entry 5922 (class 2606 OID 27410)
-- Name: missing_content_requests missing_content_requests_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5923 (class 2606 OID 27415)
-- Name: missing_content_requests missing_content_requests_duplicate_of_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_duplicate_of_fkey FOREIGN KEY (duplicate_of) REFERENCES public.missing_content_requests(request_id) ON DELETE SET NULL;


--
-- TOC entry 5924 (class 2606 OID 27405)
-- Name: missing_content_requests missing_content_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.missing_content_requests
    ADD CONSTRAINT missing_content_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5882 (class 2606 OID 26590)
-- Name: moderation_actions moderation_actions_moderator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moderation_actions
    ADD CONSTRAINT moderation_actions_moderator_id_fkey FOREIGN KEY (moderator_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5883 (class 2606 OID 26600)
-- Name: moderation_actions moderation_actions_reversed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moderation_actions
    ADD CONSTRAINT moderation_actions_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5884 (class 2606 OID 26595)
-- Name: moderation_actions moderation_actions_target_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moderation_actions
    ADD CONSTRAINT moderation_actions_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5839 (class 2606 OID 25344)
-- Name: moviegenres moviegenres_genre_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moviegenres
    ADD CONSTRAINT moviegenres_genre_id_fkey FOREIGN KEY (genre_id) REFERENCES public.genres(genre_id) ON DELETE CASCADE;


--
-- TOC entry 5840 (class 2606 OID 25339)
-- Name: moviegenres moviegenres_movie_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moviegenres
    ADD CONSTRAINT moviegenres_movie_id_fkey FOREIGN KEY (movie_id) REFERENCES public.movies(movie_id) ON DELETE CASCADE;


--
-- TOC entry 5851 (class 2606 OID 25544)
-- Name: notifications notifications_notification_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_notification_type_id_fkey FOREIGN KEY (notification_type_id) REFERENCES public.notification_types(notification_type_id) ON DELETE RESTRICT;


--
-- TOC entry 5852 (class 2606 OID 25549)
-- Name: notifications notifications_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5853 (class 2606 OID 25539)
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5900 (class 2606 OID 26938)
-- Name: point_transactions point_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.point_transactions
    ADD CONSTRAINT point_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5838 (class 2606 OID 25293)
-- Name: preferences preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preferences
    ADD CONSTRAINT preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5885 (class 2606 OID 26618)
-- Name: report_escalations report_escalations_escalated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_escalations
    ADD CONSTRAINT report_escalations_escalated_by_fkey FOREIGN KEY (escalated_by) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5886 (class 2606 OID 26623)
-- Name: report_escalations report_escalations_escalated_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_escalations
    ADD CONSTRAINT report_escalations_escalated_to_fkey FOREIGN KEY (escalated_to) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5843 (class 2606 OID 25379)
-- Name: reviews reviews_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5909 (class 2606 OID 27094)
-- Name: roulette_results roulette_results_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roulette_results
    ADD CONSTRAINT roulette_results_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5911 (class 2606 OID 27126)
-- Name: search_analytics search_analytics_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.search_analytics
    ADD CONSTRAINT search_analytics_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5868 (class 2606 OID 26155)
-- Name: sentiment_tags sentiment_tags_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sentiment_tags
    ADD CONSTRAINT sentiment_tags_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.sentiment_categories(category_id) ON DELETE SET NULL;


--
-- TOC entry 5841 (class 2606 OID 25359)
-- Name: showgenres showgenres_genre_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.showgenres
    ADD CONSTRAINT showgenres_genre_id_fkey FOREIGN KEY (genre_id) REFERENCES public.genres(genre_id) ON DELETE CASCADE;


--
-- TOC entry 5842 (class 2606 OID 25354)
-- Name: showgenres showgenres_show_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.showgenres
    ADD CONSTRAINT showgenres_show_id_fkey FOREIGN KEY (show_id) REFERENCES public.shows(show_id) ON DELETE CASCADE;


--
-- TOC entry 5861 (class 2606 OID 25948)
-- Name: spoiler_reports spoiler_reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_reports
    ADD CONSTRAINT spoiler_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5862 (class 2606 OID 25953)
-- Name: spoiler_reports spoiler_reports_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_reports
    ADD CONSTRAINT spoiler_reports_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5866 (class 2606 OID 26012)
-- Name: spoiler_tags spoiler_tags_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.spoiler_tags
    ADD CONSTRAINT spoiler_tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5901 (class 2606 OID 26953)
-- Name: user_activity user_activity_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_activity
    ADD CONSTRAINT user_activity_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5849 (class 2606 OID 25511)
-- Name: user_connections user_connections_followed_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_connections
    ADD CONSTRAINT user_connections_followed_id_fkey FOREIGN KEY (followed_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5850 (class 2606 OID 25506)
-- Name: user_connections user_connections_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_connections
    ADD CONSTRAINT user_connections_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5919 (class 2606 OID 27288)
-- Name: user_device_preferences user_device_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_device_preferences
    ADD CONSTRAINT user_device_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5915 (class 2606 OID 27217)
-- Name: user_filter_preferences user_filter_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_filter_preferences
    ADD CONSTRAINT user_filter_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5917 (class 2606 OID 27252)
-- Name: user_homepage_sections user_homepage_sections_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_homepage_sections
    ADD CONSTRAINT user_homepage_sections_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5854 (class 2606 OID 25585)
-- Name: user_interactions user_interactions_interaction_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_interactions
    ADD CONSTRAINT user_interactions_interaction_type_id_fkey FOREIGN KEY (interaction_type_id) REFERENCES public.interaction_types(interaction_type_id) ON DELETE RESTRICT;


--
-- TOC entry 5855 (class 2606 OID 25580)
-- Name: user_interactions user_interactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_interactions
    ADD CONSTRAINT user_interactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5918 (class 2606 OID 27270)
-- Name: user_notification_preferences user_notification_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_notification_preferences
    ADD CONSTRAINT user_notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5898 (class 2606 OID 26923)
-- Name: user_points user_points_current_tier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_points
    ADD CONSTRAINT user_points_current_tier_id_fkey FOREIGN KEY (current_tier_id) REFERENCES public.ranking_tiers(tier_id) ON DELETE SET NULL;


--
-- TOC entry 5899 (class 2606 OID 26918)
-- Name: user_points user_points_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_points
    ADD CONSTRAINT user_points_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5904 (class 2606 OID 26997)
-- Name: user_post_interactions user_post_interactions_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_interactions
    ADD CONSTRAINT user_post_interactions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.user_posts(post_id) ON DELETE CASCADE;


--
-- TOC entry 5905 (class 2606 OID 27002)
-- Name: user_post_interactions user_post_interactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_interactions
    ADD CONSTRAINT user_post_interactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5906 (class 2606 OID 27029)
-- Name: user_post_replies user_post_replies_parent_reply_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_replies
    ADD CONSTRAINT user_post_replies_parent_reply_id_fkey FOREIGN KEY (parent_reply_id) REFERENCES public.user_post_replies(reply_id) ON DELETE CASCADE;


--
-- TOC entry 5907 (class 2606 OID 27019)
-- Name: user_post_replies user_post_replies_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_replies
    ADD CONSTRAINT user_post_replies_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.user_posts(post_id) ON DELETE CASCADE;


--
-- TOC entry 5908 (class 2606 OID 27024)
-- Name: user_post_replies user_post_replies_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_post_replies
    ADD CONSTRAINT user_post_replies_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5902 (class 2606 OID 26982)
-- Name: user_posts user_posts_original_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_posts
    ADD CONSTRAINT user_posts_original_post_id_fkey FOREIGN KEY (original_post_id) REFERENCES public.user_posts(post_id) ON DELETE CASCADE;


--
-- TOC entry 5903 (class 2606 OID 26977)
-- Name: user_posts user_posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_posts
    ADD CONSTRAINT user_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5875 (class 2606 OID 26537)
-- Name: user_reports user_reports_assigned_moderator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_assigned_moderator_id_fkey FOREIGN KEY (assigned_moderator_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5876 (class 2606 OID 26532)
-- Name: user_reports user_reports_report_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_report_type_id_fkey FOREIGN KEY (report_type_id) REFERENCES public.report_types(report_type_id);


--
-- TOC entry 5877 (class 2606 OID 26527)
-- Name: user_reports user_reports_reported_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reported_user_id_fkey FOREIGN KEY (reported_user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5878 (class 2606 OID 26522)
-- Name: user_reports user_reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_reports
    ADD CONSTRAINT user_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5871 (class 2606 OID 26227)
-- Name: user_sentiment_patterns user_sentiment_patterns_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sentiment_patterns
    ADD CONSTRAINT user_sentiment_patterns_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5912 (class 2606 OID 27144)
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- TOC entry 5916 (class 2606 OID 27232)
-- Name: user_tab_preferences user_tab_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tab_preferences
    ADD CONSTRAINT user_tab_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5914 (class 2606 OID 27200)
-- Name: user_view_preferences user_view_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_view_preferences
    ADD CONSTRAINT user_view_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5858 (class 2606 OID 25825)
-- Name: watch_history watch_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watch_history
    ADD CONSTRAINT watch_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 5847 (class 2606 OID 25429)
-- Name: watchlist_items watchlist_items_watchlist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watchlist_items
    ADD CONSTRAINT watchlist_items_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES public.watchlists(watchlist_id) ON DELETE CASCADE;


--
-- TOC entry 5846 (class 2606 OID 25417)
-- Name: watchlists watchlists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.watchlists
    ADD CONSTRAINT watchlists_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 6169 (class 0 OID 26077)
-- Dependencies: 271 6273
-- Name: augmented_movies; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: postgres
--

REFRESH MATERIALIZED VIEW public.augmented_movies;


--
-- TOC entry 6170 (class 0 OID 26089)
-- Dependencies: 272 6273
-- Name: augmented_shows; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: postgres
--

REFRESH MATERIALIZED VIEW public.augmented_shows;


--
-- TOC entry 6151 (class 0 OID 25830)
-- Dependencies: 252 6273
-- Name: augmented_user_profiles; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: postgres
--

REFRESH MATERIALIZED VIEW public.augmented_user_profiles;


-- Completed on 2025-07-25 11:23:13

--
-- PostgreSQL database dump complete
--

