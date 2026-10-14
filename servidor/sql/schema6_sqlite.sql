-- Esquema de sql/schema6.sql adaptado a SQLite.
-- "on update current_timestamp" de MySQL se reemplaza con triggers.

create table if not exists users (
    id integer primary key autoincrement,
    deleted boolean not null default 0,
    username varchar(32) not null unique,
    serial char(20) not null,
    hash char(32) not null unique,
    reset_nonce varchar(32) default null,
    updated_on timestamp not null default current_timestamp
);

create table if not exists profiles (
    id integer primary key autoincrement,
    deleted boolean not null default 0,
    user_id integer not null references users (id),
    ordinal tinyint not null default -1,
    name varchar(32) not null unique,
    `rank` integer not null default 0,
    rating integer not null default 0,
    points integer not null default 0,
    disconnects integer not null default 0,
    updated_on timestamp not null default current_timestamp,
    seconds_played bigint not null default 0,
    comment varchar(256) default null
);

create table if not exists matches (
    id integer primary key autoincrement,
    score_home integer not null default 0,
    score_away integer not null default 0,
    team_id_home integer not null default -1,
    team_id_away integer not null default -1,
    played_on timestamp not null default current_timestamp
);

create table if not exists matches_played (
    id integer primary key autoincrement,
    match_id integer not null references matches (id),
    profile_id integer not null references profiles (id),
    home boolean not null default 0,
    unique (match_id, profile_id)
);

create table if not exists streaks (
    id integer primary key autoincrement,
    profile_id integer not null unique references profiles (id),
    wins integer not null default 0,
    best integer not null default 0
);

create table if not exists friends (
    id integer primary key autoincrement,
    profile_id integer not null references profiles (id),
    friend_profile_id integer not null references profiles (id),
    unique (profile_id, friend_profile_id)
);

create table if not exists blocked (
    id integer primary key autoincrement,
    profile_id integer not null references profiles (id),
    blocked_profile_id integer not null references profiles (id),
    unique (profile_id, blocked_profile_id)
);

create table if not exists settings (
    id integer primary key autoincrement,
    profile_id integer not null unique references profiles (id),
    settings1 blob default null,
    settings2 blob default null
);

create trigger if not exists users_updated after update on users
when old.updated_on = new.updated_on
begin
    update users set updated_on = current_timestamp where id = new.id;
end;

create trigger if not exists profiles_updated after update on profiles
when old.updated_on = new.updated_on
begin
    update profiles set updated_on = current_timestamp where id = new.id;
end;
