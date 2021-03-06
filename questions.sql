create schema questions;
grant usage on schema questions to get;
set local search_path to questions,api,pg_temp;
--
--
create view question with (security_barrier) as
select question_id,question_at,question_change_at,question_votes,question_poll_major_id,question_poll_minor_id,question_is_deleted
     , (case question_type when 'question' then '' when 'meta' then (case community_name when 'meta' then '' else 'Meta Question: ' end) when 'blog' then 'Blog Post: ' end)||question_title question_title
     , account_id question_account_id
     , account_name question_account_name
     , coalesce(question_vote_votes,0) question_votes_from_me
     , coalesce(communicant_votes,0) question_communicant_votes
     , case when question_se_imported_at=question_change_at then 'imported' when question_change_at>question_at then 'edited' else 'asked' end question_change
from api._question natural join db.question natural join db.account natural join db.community natural join db.communicant
     natural left join (select question_id,question_vote_votes from db.question_vote natural join db.login where login_uuid=get_login_uuid() and question_vote_votes>0) v
where community_id=get_community_id();
--
create view tag with (security_barrier) as
select question_id,tag_id,tag_name,tag_question_count
from db.question_tag_x qt natural join (select * from db.tag where community_id=get_community_id()) t
where not exists (select 1 from db.question_tag_x natural join db.tag where question_id=qt.question_id and tag_implies_id=t.tag_id and tag_name like t.tag_name||'%');
--
create view answer with (security_barrier) as
select community_id,question_id,answer_id,answer_at,answer_change_at,answer_markdown,answer_votes,answer_is_deleted
     , coalesce(answer_vote_votes,0) answer_votes_from_me
     , account_id answer_account_id
     , account_name answer_account_name
     , coalesce(communicant_votes,0) answer_communicant_votes
     , case when answer_se_imported_at=answer_change_at then 'imported' when answer_change_at>answer_at then 'edited' else 'answered' end answer_change
from api._answer natural join db.answer natural join db.account  natural left join db.communicant
     natural left join (select answer_id,answer_vote_votes from db.answer_vote natural join db.login where login_uuid=get_login_uuid() and answer_vote_votes>0) v;
--
create view one with (security_barrier) as
select account_id,community_id,community_name,community_code_language
     , coalesce(account_is_dev,false) account_is_dev
     , coalesce(communicant_is_post_flag_crew,false) communicant_is_post_flag_crew
     , encode(community_dark_shade,'hex') colour_dark
     , encode(community_mid_shade,'hex') colour_mid
     , encode(community_light_shade,'hex') colour_light
     , encode(community_highlight_color,'hex') colour_highlight
     , encode(community_warning_color,'hex') colour_warning
     , (select font_name from db.font where font_id=coalesce(communicant_regular_font_id,community_regular_font_id)) my_community_regular_font_name
     , (select font_name from db.font where font_id=coalesce(communicant_monospace_font_id,community_monospace_font_id)) my_community_monospace_font_name
     , 1+trunc(log(greatest(communicant_votes,0)+1)) community_my_power
     , (select count(*) from question) num_questions
from db.community
     natural left join (select * from db.login natural join db.account natural join db.communicant where login_uuid=get_login_uuid()) a
where community_id=get_community_id();
--
--
create function login_community(uuid,text) returns boolean language sql security definer as $$select api.login_room($1,(select community_room_id from db.community where community_name=$2));$$;
--
create function search(text) returns table (question_id integer, rn bigint) language sql security definer set search_path=db,api,questions,x_pg_trgm,pg_temp as $$
  with q as (select question_id, question_markdown txt, strict_word_similarity($1,question_markdown) word_similarity, similarity($1,question_markdown) similarity
             from db.question
             where community_id=get_community_id() and $1<<%question_markdown)
    , qt as (select question_id, question_title txt, strict_word_similarity($1,question_title)*2 word_similarity, similarity($1,question_title)*2 similarity
             from db.question
             where community_id=get_community_id() and $1<<%question_title)
     , a as (select question_id, answer_markdown txt, strict_word_similarity($1,answer_markdown) word_similarity, similarity($1,answer_markdown) similarity
             from db.answer natural join (select question_id,community_id from db.question) z
             where community_id=get_community_id() and $1<<%answer_markdown)
     , s as (select question_id, bool_or(txt like '%'||$1||'%') exact, max(word_similarity+similarity) similarity from (select * from q union all select * from qt union all select * from a) z group by question_id)
  select question_id, row_number() over (order by exact desc, similarity desc) rn
  from s natural join db.question q natural join api._question natural join db.account natural join db.community natural join db.communicant
  where community_id=get_community_id() and $1 is not null
  order by exact desc, similarity desc limit 50;
$$;
--
create function recent() returns integer language sql security definer set search_path=db,api,questions,pg_temp as $$
  select greatest(min(question_poll_major_id)-1,0)::integer from (select question_poll_major_id from question where community_id=get_community_id() order by question_poll_major_id desc limit 10) z;
$$;
--
create function recent(page integer) returns table (startid integer, endid integer) language sql security definer set search_path=db,api,questions,pg_temp as $$
  select coalesce(min(question_poll_major_id),0)::integer,coalesce(max(question_poll_major_id),0)::integer from (select question_poll_major_id from questions.question order by question_poll_major_id desc offset (page-1)*10 limit 10) z;
$$;
--
revoke all on all functions in schema questions from public;
do $$
begin
  execute (select string_agg('grant select on '||viewname||' to get;', E'\n') from pg_views where schemaname='questions' and viewname!~'^_');
  execute ( select string_agg('grant execute on function '||p.oid::regproc||'('||pg_get_function_identity_arguments(p.oid)||') to get;', E'\n')
            from pg_proc p join pg_namespace n on p.pronamespace=n.oid
            where n.nspname='questions' and proname!~'^_' );
end$$;
