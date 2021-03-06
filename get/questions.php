<?
include '../db.php';
include '../nocache.php';
$_SERVER['REQUEST_METHOD']==='GET' || fail(405,'only GETs allowed here');
isset($_GET['community']) || fail(400,'community must be set');
db("set search_path to questions,pg_temp");
$auth = ccdb("select login_community(nullif($1,'')::uuid,$2)",$_COOKIE['uuid']??'',$_GET['community']);
$search = $_GET['search']??'';
extract(cdb("select account_id,account_is_dev,community_name,community_code_language,my_community_regular_font_name,my_community_monospace_font_name,community_my_power,colour_dark,colour_mid,colour_light,colour_highlight,num_questions from one"));
$_GET['community']===$community_name || fail(400,'invalid community');
if(isset($_GET['changes'])) exit(ccdb("select coalesce(jsonb_agg(jsonb_build_array(question_id,question_poll_minor_id)),'[]')::json from question where question_poll_minor_id>$1",$_GET['fromid']));
if($search){
  db("select set_config('pg_trgm.strict_word_similarity_threshold','0.5',false)");
  $results = db("select question_id,question_at,question_change_at,question_change,question_title,question_votes,question_votes_from_me,question_poll_major_id,question_poll_minor_id,question_account_id,question_account_name
                       ,question_is_deleted,question_communicant_votes
                      , extract('epoch' from current_timestamp-question_at) question_when
                      , extract('epoch' from current_timestamp-question_change_at) question_change_when
                      , question_account_id=$2 account_is_me
                 from search($1) natural join question
                 order by rn",$_GET['search'],$account_id);
}else{
  if(isset($_GET['page'])){
    extract(cdb("select startid,endid from recent($1)",$_GET['page']));
  }elseif(isset($_GET['one'])){
    $startid = ccdb("select question_poll_major_id from question where question_id=$1",$_GET['id']);
    $endid = $startid;
  }else{
    $startid = intval($_GET['id'])+1;
    $endid = '';
  }
  $results = db("select question_id,question_change,question_title,question_votes,question_votes_from_me,question_poll_major_id,question_poll_minor_id,question_account_id,question_account_name
                       ,question_is_deleted,question_communicant_votes
                      , extract('epoch' from current_timestamp-question_at) question_when
                      , extract('epoch' from current_timestamp-question_change_at) question_change_when
                      , question_account_id=$3 account_is_me
                 from question where question_poll_major_id>=$1 and ($2='' or question_poll_major_id<=nullif($2,'')::integer)
                 order by question_poll_major_id desc",$startid,$endid,$account_id);
}
?>
<?foreach($results as $r){ extract($r);?>
  <div id="q<?=$question_id?>" class="question post<?=$question_is_deleted?' deleted':''?>" data-id="<?=$question_id?>" data-poll-major-id="<?=$question_poll_major_id?>" data-poll-minor-id="<?=$question_poll_minor_id?>" data-of="<?=$num_questions?>">
    <a href="/<?=$community_name?>?q=<?=$question_id?>#question" title="<?=$question_title?>"><?=$question_title?></a>
    <div class="bar">
      <div>
        <img title="Stars: <?=$question_communicant_votes?>" class="icon" data-name="<?=explode(' ',$question_account_name)[0]?>" src="/identicon?id=<?=$question_account_id?>">
        <span class="element"><?=$question_account_name?></span>
        <?if($question_votes){?>
          <span class="element">
            <i class="fa fa-star<?=(($question_account_id!==$account_id)&&($question_votes_from_me<$community_my_power))?'-o':''?><?=$question_votes_from_me?' highlight':''?>" data-count="<?=$question_votes?>"></i>
          </span>
        <?}?>
        <span class="when element" data-seconds="<?=$question_when?>"><?=$question_account_name?></span>
        <?if($question_change==='asked'){?>
          <span class="element hover">(asked)</span>
        <?}else{?>
          <span class="element hover when" data-prefix="(<?=$question_change?>, " data-postfix=")" data-seconds="<?=$question_change_when?>"></span>
        <?}?>
      </div>
      <div class="element container">
        <?foreach(db("select question_id,tag_id,tag_name from tag where question_id=$1 order by tag_question_count",$question_id) as $r){ extract($r);?>
          <span class="tag element" data-question-id="<?=$question_id?>" data-tag-id="<?=$tag_id?>"><?=$tag_name?> <i class="fa fa-times-circle"></i></span>
        <?}?>
      </div>
    </div>
    <div class="answers">
      <?foreach(db("select answer_id,answer_change,answer_markdown,answer_account_id,answer_votes,answer_votes_from_me,answer_account_name,answer_is_deleted,answer_communicant_votes
                         , extract('epoch' from current_timestamp-answer_at) answer_when
                         , extract('epoch' from current_timestamp-answer_change_at) answer_change_when
                    from answer
                    where question_id=$1
                    order by answer_votes desc, answer_communicant_votes desc, answer_id desc",$question_id) as $r){ extract($r);?>
        <div class="bar<?=$answer_is_deleted?' deleted':''?>">
          <a href="/<?=$community_name?>?q=<?=$question_id?>#a<?=$answer_id?>" class="element summary shrink">Answer: <span data-markdown="<?=strtok($answer_markdown,"\n\r");?>"><?=strtok($answer_markdown,"\n\r");?></span></a>
          <div>
            <?if($answer_change==='answered'){?>
              <span class="element hover">(answered)</span>
            <?}else{?>
              <span class="element hover when" data-prefix="(<?=$answer_change?>, " data-postfix=")" data-seconds="<?=$answer_change_when?>"></span>
            <?}?>
            <span class="when element" data-seconds="<?=$answer_when?>"></span>
            <?if($answer_votes){?>
              <span class="element">
                <i class="fa fa-star<?=(($answer_account_id!==$account_id)&&($answer_votes_from_me<$community_my_power))?'-o':''?><?=$answer_votes_from_me?' highlight':''?>" data-count="<?=$answer_votes?>"></i>
              </span>
            <?}?>
            <span class="element"><?=$answer_account_name?></span>
            <img title="Stars: <?=$answer_communicant_votes?>" class="icon" data-name="<?=explode(' ',$answer_account_name)[0]?>" src="/identicon?id=<?=$answer_account_id?>">
          </div>
        </div>
      <?}?>
    </div>
  </div>
<?}?>
