-- ============================================================================
-- VexinStream v7.0 — Supabase schema, RPCs, RLS & level-gated cosmetics
-- Created & Developed by VenixRyzen
-- ----------------------------------------------------------------------------
-- Run this whole file once in your Supabase project:
--   Dashboard → SQL Editor → New query → paste → Run
--
-- Then paste your Project URL + anon public key into index.html:
--   const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
--   const SUPABASE_ANON_KEY = "eyJ...";
--
-- Authentication → URL Configuration → Redirect URLs must include:
--   https://your-site.example/path/        (your exact deployed page)
--   http://localhost:PORT/path/            (for local testing)
-- Providers → Google must be enabled for "Continue with Google".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PROFILES — one row per auth user. Never stores email (privacy).
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  display_name           text        not null default 'Anime Fan',
  avatar_url             text        not null default '',
  xp                     integer     not null default 0 check (xp >= 0),
  level                  integer     not null default 1 check (level >= 1),
  episodes_watched       integer     not null default 0 check (episodes_watched >= 0),
  is_public              boolean     not null default true,
  equipped_title         text        not null default 'newcomer',
  equipped_name_color    text        not null default 'default',
  equipped_name_effect   text        not null default 'none',
  equipped_avatar_frame  text        not null default 'none',
  equipped_banner        text        not null default 'sunset-drift',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists profiles_public_xp_idx
  on public.profiles (is_public, xp desc, level desc);

-- Keep updated_at fresh on every write.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 2. WATCH XP LOG — server-side anti-cheat dedupe.
--    PRIMARY KEY (user_id, anime_id, episode_num) means each episode can only
--    ever award XP once per account, no matter how often the client calls.
-- ----------------------------------------------------------------------------
create table if not exists public.watch_xp_log (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  anime_id    integer     not null,
  episode_num integer     not null,
  xp_awarded  integer     not null default 50,
  awarded_at  timestamptz not null default now(),
  primary key (user_id, anime_id, episode_num)
);

-- ----------------------------------------------------------------------------
-- 3. COSMETICS — server-side mirror of the client COSMETIC_CATALOG.
--    equip_cosmetic() reads required_level from here so the level gate cannot
--    be bypassed with devtools.
-- ----------------------------------------------------------------------------
create table if not exists public.cosmetics (
  category       text    not null check (category in ('title', 'name_color', 'name_effect', 'avatar_frame', 'banner')),
  id             text    not null,
  label          text    not null,
  required_level integer not null check (required_level >= 1),
  primary key (category, id)
);

insert into public.cosmetics (category, id, label, required_level) values
  -- Titles
  ('title', 'newcomer',        'Newcomer',        1),
  ('title', 'sub-enjoyer',     'Sub Enjoyer',     2),
  ('title', 'binge-watcher',   'Binge Watcher',   4),
  ('title', 'night-owl',       'Night Owl',       6),
  ('title', 'sakuga-hunter',   'Sakuga Hunter',   9),
  ('title', 'vexin-vanguard',  'Vexin Vanguard', 12),
  ('title', 'anime-archivist', 'Anime Archivist', 16),
  ('title', 'venix-elite',     'Venix Elite',    20),
  -- Name colors
  ('name_color', 'default',         'Default',          1),
  ('name_color', 'cyber-cyan',      'Cyber Cyan',       2),
  ('name_color', 'sakura-pink',     'Sakura Pink',      3),
  ('name_color', 'emerald-mint',    'Emerald Mint',     5),
  ('name_color', 'royal-gold',      'Royal Gold',       7),
  ('name_color', 'sunset-gradient', 'Sunset Gradient', 10),
  ('name_color', 'nebula-gradient', 'Nebula Gradient', 13),
  ('name_color', 'prismatic-rgb',   'Prismatic RGB',   18),
  -- Name effects
  ('name_effect', 'none',           'None',            1),
  ('name_effect', 'soft-glow',      'Soft Glow',       6),
  ('name_effect', 'neon-pulse',     'Neon Pulse',     11),
  ('name_effect', 'shimmer-sweep',  'Shimmer Sweep',  15),
  ('name_effect', 'chromatic-wave', 'Chromatic Wave', 20),
  -- Avatar frames
  ('avatar_frame', 'none',           'None',            1),
  ('avatar_frame', 'accent-ring',    'Accent Ring',     3),
  ('avatar_frame', 'gold-crest',     'Gold Crest',      8),
  ('avatar_frame', 'cyber-pulse',    'Cyber Pulse',    14),
  ('avatar_frame', 'legendary-aura', 'Legendary Aura', 20),
  -- Profile banners
  ('banner', 'sunset-drift',   'Sunset Drift',    1),
  ('banner', 'sakura-night',   'Sakura Night',    4),
  ('banner', 'neon-city',      'Neon City',       8),
  ('banner', 'aurora-sky',     'Aurora Sky',     12),
  ('banner', 'starlight-void', 'Starlight Void', 17)
on conflict (category, id) do update
  set label = excluded.label,
      required_level = excluded.required_level;

-- ----------------------------------------------------------------------------
-- 4. AUTO-CREATE PROFILE ON SIGN-UP (email, Google OAuth, etc.)
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, 'anime fan'), '@', 1),
      'Anime Fan'
    ), 24),
    coalesce(
      new.raw_user_meta_data ->> 'avatar_url',
      new.raw_user_meta_data ->> 'picture',
      ''
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 5. RPC: award_watch_xp(anime_id, episode_num)
--    Awards 50 XP once per (user, anime, episode). Level formula matches the
--    client: level = floor(sqrt(total_xp / 100)) + 1
-- ----------------------------------------------------------------------------
create or replace function public.award_watch_xp(p_anime_id integer, p_episode_num integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid        uuid    := auth.uid();
  xp_amount  constant integer := 50;
  old_xp     integer := 0;
  old_level  integer := 1;
  new_xp     integer;
  new_level  integer;
  ep_count   integer := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_anime_id is null or p_anime_id <= 0 or p_episode_num is null or p_episode_num <= 0 then
    raise exception 'Invalid anime or episode';
  end if;

  -- Ensure a profile exists (safety net if the trigger was added later).
  insert into public.profiles (id) values (uid) on conflict (id) do nothing;

  select xp, level, episodes_watched
    into old_xp, old_level, ep_count
    from public.profiles
   where id = uid
   for update;

  -- Anti-cheat: the composite PK makes this a no-op after the first award.
  insert into public.watch_xp_log (user_id, anime_id, episode_num, xp_awarded)
  values (uid, p_anime_id, p_episode_num, xp_amount)
  on conflict (user_id, anime_id, episode_num) do nothing;

  if not found then
    return jsonb_build_object(
      'awarded', false,
      'xp', 0,
      'total_xp', old_xp,
      'level', old_level,
      'old_level', old_level,
      'leveled_up', false,
      'episodes_watched', ep_count
    );
  end if;

  new_xp := old_xp + xp_amount;
  new_level := (floor(sqrt(new_xp / 100.0)) + 1)::int;

  update public.profiles
     set xp = new_xp,
         level = new_level,
         episodes_watched = episodes_watched + 1
   where id = uid
  returning episodes_watched into ep_count;

  return jsonb_build_object(
    'awarded', true,
    'xp', xp_amount,
    'total_xp', new_xp,
    'level', new_level,
    'old_level', old_level,
    'leveled_up', new_level > old_level,
    'episodes_watched', ep_count
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. RPC: equip_cosmetic(category, value)
--    Validates ownership level + category server-side, then equips.
-- ----------------------------------------------------------------------------
create or replace function public.equip_cosmetic(p_category text, p_value text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid           uuid := auth.uid();
  required      integer;
  current_level integer;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_category not in ('title', 'name_color', 'name_effect', 'avatar_frame', 'banner') then
    raise exception 'Unknown cosmetic category';
  end if;

  select required_level
    into required
    from public.cosmetics
   where category = p_category and id = p_value;

  if required is null then
    raise exception 'Unknown cosmetic';
  end if;

  select level into current_level from public.profiles where id = uid;
  if current_level is null then
    raise exception 'Profile not found';
  end if;

  if current_level < required then
    raise exception 'Locked: requires level %', required;
  end if;

  update public.profiles
     set equipped_title = case when p_category = 'title' then p_value else equipped_title end,
         equipped_name_color = case when p_category = 'name_color' then p_value else equipped_name_color end,
         equipped_name_effect = case when p_category = 'name_effect' then p_value else equipped_name_effect end,
         equipped_avatar_frame = case when p_category = 'avatar_frame' then p_value else equipped_avatar_frame end,
         equipped_banner = case when p_category = 'banner' then p_value else equipped_banner end
   where id = uid;

  return jsonb_build_object('ok', true, 'category', p_category, 'value', p_value);
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.watch_xp_log enable row level security;
alter table public.cosmetics   enable row level security;

drop policy if exists "profiles_select_public_or_own" on public.profiles;
create policy "profiles_select_public_or_own"
  on public.profiles for select
  using (is_public = true or auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "cosmetics_read_all" on public.cosmetics;
create policy "cosmetics_read_all"
  on public.cosmetics for select
  using (true);

-- watch_xp_log intentionally has NO policies: clients cannot read or write it.
-- Only the SECURITY DEFINER RPC can touch it.

-- ----------------------------------------------------------------------------
-- 8. GRANTS
--    Column-level grants prevent a cheater from PATCHing xp/level/equipped_*
--    directly through PostgREST. Only the RPCs (SECURITY DEFINER) may write
--    progression + cosmetic columns.
-- ----------------------------------------------------------------------------
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant insert (id, display_name, avatar_url) on public.profiles to authenticated;
grant update (display_name, is_public) on public.profiles to authenticated;

revoke all on public.watch_xp_log from anon, authenticated;

revoke all on public.cosmetics from anon, authenticated;
grant select on public.cosmetics to anon, authenticated;

revoke all on function public.award_watch_xp(integer, integer) from public, anon;
revoke all on function public.equip_cosmetic(text, text) from public, anon;
grant execute on function public.award_watch_xp(integer, integer) to authenticated;
grant execute on function public.equip_cosmetic(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. OPTIONAL: refresh existing levels if the formula ever changes.
--    update public.profiles
--       set level = (floor(sqrt(xp / 100.0)) + 1)::int;
-- ----------------------------------------------------------------------------