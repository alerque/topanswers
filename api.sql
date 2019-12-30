/*
\i ~/git/api.sql
*/
begin;
--
drop schema if exists answer_history cascade;
drop schema if exists question_history cascade;
drop schema if exists identicon cascade;
drop schema if exists roomicon cascade;
drop schema if exists sitemap cascade;
drop schema if exists upload cascade;
drop schema if exists answer cascade;
drop schema if exists profile cascade;
drop schema if exists question cascade;
drop schema if exists room cascade;
drop schema if exists questions cascade;
drop schema if exists community cascade;
drop schema if exists transcript cascade;
drop schema if exists chat cascade;
drop schema if exists notification cascade;
drop schema if exists api cascade;
create schema api;
grant usage on schema api to get,post;
set local search_path to api,pg_temp;
--
--
create function _error(integer,text) returns void language plpgsql as $$begin raise exception '%', $2 using errcode='H0'||$1; end;$$;
create function _error(text) returns void language sql as $$select _error(403,$1);$$;
--
create function get_login_uuid() returns uuid stable language sql security definer as $$select nullif(current_setting('custom.uuid',true),'')::uuid;$$;
create function get_account_id() returns integer stable language sql security definer as $$select account_id from db.login where login_uuid=nullif(current_setting('custom.uuid',true),'')::uuid;$$;
--
create function _get_id(text) returns integer stable language sql security definer set search_path=db,api,pg_temp as $$
  with w as (select account_encryption_key from login natural join account where login_uuid=nullif(current_setting('custom.uuid',true),'')::uuid
             union all
             select one_encryption_key from one where nullif(current_setting('custom.uuid',true),'')::uuid is null)
  select x_pgcrypto.pgp_sym_decrypt(current_setting('custom.'||$1||'_id',true)::bytea,(select account_encryption_key from w)::text||current_setting('custom.timestamp',true))::integer
$$;
--
create function get_room_id() returns integer stable language sql security definer as $$select api._get_id('room'::text);$$;
create function get_community_id() returns integer stable language sql security definer as $$select api._get_id('community'::text);$$;
create function get_question_id() returns integer stable language sql security definer as $$select api._get_id('question'::text);$$;
create function get_answer_id() returns integer stable language sql security definer as $$select api._get_id('answer'::text);$$;
--
create function _set_id(text,integer) returns void stable language sql security definer set search_path=db,api,pg_temp as $$
  with w as (select account_encryption_key from login natural join account where login_uuid=nullif(current_setting('custom.uuid',true),'')::uuid
             union all
             select one_encryption_key from one where nullif(current_setting('custom.uuid',true),'')::uuid is null)
  select set_config('custom.'||$1||'_id',x_pgcrypto.pgp_sym_encrypt($2::text,(select account_encryption_key from w)::text||current_setting('custom.timestamp',true))::text,false)
$$;
--
--
create view _community with (security_barrier) as
select c.*
     , 1+trunc(log(greatest(communicant_votes,0)+1)) community_my_power
from (select community_id from db.community natural left join (select community_id,account_id from db.member where account_id=get_account_id()) m where community_type='public' or account_id is not null) c
     natural left join (select community_id,communicant_votes from db.communicant where account_id=get_account_id()) a;
--
create view _room with (security_barrier) as
select r.*
from (select room_id,community_id
           , get_account_id() is not null and (room_type='public' or account_id is not null) room_can_chat
      from db.room natural left join (select * from db.account_room_x where account_id=get_account_id()) a
      where room_type<>'private' or account_id is not null) r
     natural join (select community_id from api._community) c;
--
create view _question with (security_barrier) as
select question_id,community_id
     , question_crew_flags>0 or (question_crew_flags=0 and question_flags>0) question_is_deleted
from db.question natural join _community
     natural left join (select community_id,communicant_is_post_flag_crew from db.communicant where account_id=get_account_id()) a
where communicant_is_post_flag_crew or question_crew_flags<0 or ((get_account_id() is not null or question_flags=0) and question_crew_flags=0) or account_id=get_account_id();
--
create view _answer with (security_barrier) as
select answer_id,question_id,community_id
     , answer_crew_flags>0 or (answer_crew_flags=0 and answer_flags>0) answer_is_deleted
from db.answer natural join _question
     natural left join (select community_id,communicant_is_post_flag_crew from db.communicant where account_id=get_account_id()) a
where communicant_is_post_flag_crew or answer_crew_flags<0 or ((get_account_id() is not null or answer_flags=0) and answer_crew_flags=0) or account_id=get_account_id();
--
--
create function login(uuid uuid) returns boolean language sql security definer set search_path=db,api,pg_temp as $$
  select set_config('custom.timestamp',current_timestamp::text,false), set_config('custom.uuid',uuid::text,false);
  select exists(select 1 from login where login_uuid=uuid);
$$;
--
create function login_community(uuid uuid, cid integer) returns boolean language sql security definer set search_path=db,api,pg_temp as $$
  select _error('invalid community')
  where not exists (select 1 from community c where community_id=cid and (community_type='public' or exists (select 1 from member m natural join login where m.community_id=c.community_id and login_uuid=uuid)));
  --
  select set_config('custom.timestamp',current_timestamp::text,false), set_config('custom.uuid',uuid::text,false);
  select _set_id('community',community_id) from community where community_id=cid;
  select login(uuid);
$$;
--
create function login_room(uuid uuid, rid integer) returns boolean language sql security definer set search_path=db,api,pg_temp as $$
  --
  select _error('invalid room') where not exists (select 1
                                                  from room r natural join (select community_id,community_type from community) c 
                                                  where room_id=rid and (community_type='public' or exists (select 1 from member m natural join login where m.community_id=r.community_id and login_uuid=uuid))
                                                                    and (room_type<>'private' or exists (select 1 from account_room_x a natural join login where a.room_id=r.room_id and login_uuid=uuid)));
  --
  select set_config('custom.timestamp',current_timestamp::text,false), set_config('custom.uuid',uuid::text,false);
  select _set_id('room',room_id),_set_id('community',community_id) from room where room_id=rid;
  select login(uuid);
$$;
--
create function login_question(uuid uuid, qid integer) returns boolean language sql security definer set search_path=db,api,pg_temp as $$
  --
  select _error('invalid question') where not exists (select 1
                                                      from question r natural join (select community_id,community_type from community) c 
                                                      where question_id=qid and (community_type='public' or exists (select 1 from member m natural join login where m.community_id=r.community_id and login_uuid=uuid)));
  --
  select set_config('custom.timestamp',current_timestamp::text,false), set_config('custom.uuid',uuid::text,false);
  select _set_id('question',question_id),_set_id('room',question_room_id),_set_id('community',community_id) from question where question_id=qid;
  select login(uuid);
$$;
--
create function login_answer(uuid uuid, id integer) returns boolean language sql security definer set search_path=db,api,pg_temp as $$
  select set_config('custom.timestamp',current_timestamp::text,false), set_config('custom.uuid',uuid::text,false);
  select _error('invalid answer') where not exists (select 1 from _answer where answer_id=id);
  select _set_id('answer',answer_id),_set_id('question',question_id),_set_id('community',community_id) from _answer where answer_id=id;
  select login(uuid);
$$;
--
create function _new_community(cname text) returns integer language plpgsql security definer set search_path=db,post,pg_temp as $$
declare
  rid integer;
  cid integer;
begin
  insert into room(community_id) values(0) returning room_id into rid;
  insert into community(community_name,community_room_id,community_display_name) values(cname,rid,initcap(cname)) returning community_id into cid;
  --
  insert into communicant(account_id,community_id,communicant_se_user_id,communicant_regular_font_id,communicant_monospace_font_id)
  select 208,cid,0,community_regular_font_id,community_monospace_font_id from community where community_id=cid;
  --
  update room set community_id=cid where room_id=rid;
  return cid;
end$$;
--
create function _ensure_communicant(aid integer, cid integer) returns void language sql security definer set search_path=db,pg_temp as $$
  insert into communicant(account_id,community_id,communicant_regular_font_id,communicant_monospace_font_id)
  select aid,cid,community_regular_font_id,community_monospace_font_id from community where community_id=cid
  on conflict on constraint communicant_pkey do nothing;
$$;
--
create function _create_seuser(cid integer, seuid integer, seuname text) returns integer language plpgsql security definer set search_path=db,post,pg_temp as $$
declare
  id integer;
begin
  if exists(select 1 from communicant where community_id=cid and communicant_se_user_id=seuid) then
    select account_id from communicant where community_id=cid and communicant_se_user_id=seuid into id;
  else
    insert into account(account_name,account_license_id,account_codelicense_id,account_is_imported) values(trim(regexp_replace(seuname,'-|\.',' ','g')),4,1,true) returning account_id into id;
    --
    insert into communicant(account_id,community_id,communicant_se_user_id,communicant_regular_font_id,communicant_monospace_font_id)
    select id,cid,seuid,community_regular_font_id,community_monospace_font_id from community where community_id=cid;
  end if;
  return id;
end;
$$;
--
--
revoke all on all functions in schema api from public;
do $$
begin
  execute ( select string_agg('grant execute on function '||p.oid::regproc||'('||pg_get_function_identity_arguments(p.oid)||') to get,post;', E'\n')
            from pg_proc p join pg_namespace n on p.pronamespace=n.oid
            where n.nspname='api' and proname!~'^_' );
end$$;
--
\i ~/git/transcript.sql
\i ~/git/chat.sql
\i ~/git/notification.sql
\i ~/git/community.sql
\i ~/git/questions.sql
\i ~/git/room.sql
\i ~/git/question.sql
\i ~/git/profile.sql
\i ~/git/answer.sql
\i ~/git/upload.sql
\i ~/git/sitemap.sql
\i ~/git/roomicon.sql
\i ~/git/identicon.sql
\i ~/git/question-history.sql
\i ~/git/answer-history.sql
--
commit;
