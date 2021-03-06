<?    
include '../db.php';
include '../nocache.php';
$_SERVER['REQUEST_METHOD']==='GET' || fail(405,'only GETs allowed here');
db("set search_path to question_history,pg_temp");
ccdb("select login_question(nullif($1,'')::uuid,nullif($2,'')::integer)",$_COOKIE['uuid']??'',$_GET['id']??'') || fail(403,'access denied');
extract(cdb("select account_id
                   ,question_id,question_title,question_is_imported
                   ,community_name,community_display_name,community_code_language
                   ,my_community_regular_font_name,my_community_monospace_font_name
                   ,colour_dark,colour_mid,colour_light,colour_highlight
             from one"));
?>
<!doctype html>
<html style="box-sizing: border-box; font-family: '<?=$my_community_regular_font_name?>', serif; font-size: smaller;">
<head>
  <link rel="stylesheet" href="/fonts/<?=$my_community_regular_font_name?>.css">
  <link rel="stylesheet" href="/fonts/<?=$my_community_monospace_font_name?>.css">
  <link rel="stylesheet" href="/lib/fork-awesome/css/fork-awesome.min.css">
  <link rel="stylesheet" href="/lib/lightbox2/css/lightbox.min.css">
  <link rel="stylesheet" href="/lib/codemirror/codemirror.css">
  <link rel="shortcut icon" href="/favicon.ico" type="image/x-icon">
  <link rel="icon" href="/favicon.ico" type="image/x-icon">
  <style>
    *:not(hr) { box-sizing: inherit; }
    html, body { margin: 0; padding: 0; scroll-behavior: smooth; }
    textarea, pre, code, .CodeMirror, .diff { font-family: '<?=$my_community_monospace_font_name?>', monospace; }
    header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; flex: 0 0 auto; font-size: 1rem; color: #<?=$colour_light?>; background: #<?=$colour_dark?>; white-space: nowrap; }
    header a { color: #<?=$colour_light?>; }
    header>div>:not(.icon) { margin: 3px; }
    header .icon { border: 1px solid #<?=$colour_light?>; margin: 1px; }
    header .icon>img { background: #<?=$colour_mid?>; height: 24px; border: 1px solid #<?=$colour_dark?>; display: block; padding: 1px; }
    [data-rz-handle] { flex: 0 0 2px; background: black; }

    .markdown, .diff, .title { border: 1px solid #<?=$colour_dark?>; padding: 0.5rem; border-radius: 4px; }
    .markdown, .title { background-color: white; }
    .separator { border-bottom: 0.3rem solid #<?=$colour_dark?>; margin: 1rem -1rem; }
    .separator:last-child { display: none; }
    .diff { background-color: #<?=$colour_mid?>; overflow-wrap: break-word; white-space: pre-wrap; font-family: monospace; }
    .diff:target, .diff:target+div { box-shadow: 0 0 3px 3px #<?=$colour_highlight?>; }

    .who, .when { white-space: nowrap; }
    .when { font-size: smaller; }

    .CodeMirror { height: 100%; border: 1px solid #<?=$colour_dark?>; font-size: 1.1rem; border-radius: 4px; }
    .CodeMirror pre.CodeMirror-placeholder { color: darkgrey; }
    .CodeMirror-wrap pre { word-break: break-word; }
  </style>
  <script src="/lib/lodash.js"></script>
  <script src="/lib/jquery.js"></script>
  <script src="/lib/codemirror/codemirror.js"></script>
  <script src="/lib/codemirror/markdown.js"></script>
  <script src="/lib/codemirror/sql.js"></script>
  <?require '../markdown.php';?>
  <script src="/lib/moment.js"></script>
  <script src="/lib/diff_match_patch.js"></script>
  <script>
    $(function(){
      var dmp = new diff_match_patch();
      $('textarea').each(function(){
        var m = $(this).next(), cm = CodeMirror.fromTextArea($(this)[0],{ lineWrapping: true, readOnly: true });
        m.attr('data-markdown',cm.getValue()).renderMarkdown();
        $(cm.getWrapperElement()).css('grid-area',$(this).data('grid-area'));
      });
      $('.diff').each(function(){
        var d = dmp.diff_main($(this).attr('data-from'),$(this).attr('data-to'));
        dmp.diff_cleanupSemantic(d);
        $(this).html(dmp.diff_prettyHtml(d));
      });
      setTimeout(function(){ $('.diff:target').each(function(){ $(this)[0].scrollIntoView(); }); }, 500);
    });
  </script>
  <title>Question History - TopAnswers</title>
</head>
<body style="font-size: larger; background-color: #<?=$colour_light?>;">
  <header style="border-bottom: 2px solid black;">
    <div style="margin: 0.2rem;">
      <a href="/<?=$community_name?>">TopAnswers <?=$community_display_name?></a>
      <span>Question History for: "<a href="/<?=$community_name?>?q=<?=$question_id?>"><?=$question_title?></a>"</span>
    </div>
    <div style="display: flex; align-items: center;">
      <a href="/profile" class="icon"><img src="/identicon?id=<?=$account_id?>"></a>
    </div>
  </header>
  <div style="width: 100%; display: grid; align-items: start; grid-template-columns: auto 1fr 1fr; grid-auto-rows: auto; grid-gap: 1rem; padding: 1rem;">
    <?foreach(db("select question_history_id,account_id,account_name,question_history_markdown,question_history_title,question_history_at,prev_markdown,prev_title,rn from history order by rn desc") as $i=>$r){ extract($r);?>
      <?$rowspan = ($rn>1)?4:2;?>
      <?$rowoffset = 5*$i;?>
      <div style="grid-area: <?=(1+$rowoffset)?> / 1 / <?=(1+$rowspan+$rowoffset)?> / 2;">
        <div class="who"><?=$account_name?></div>
        <div><?=($rn===1)?($question_is_imported?'imported':'asked'):'edited'?></div>
        <div class="when"><?=$question_history_at?></div>
      </div>
      <div style="grid-area: <?=(1+$rowoffset)?> / 2 / span 1 / 4;" class="title"><?=$question_history_title?></div>
      <textarea data-grid-area="<?=(2+$rowoffset)?> / 2 / span 1 / 3"><?=$question_history_markdown?></textarea>
      <div style="grid-area: <?=(2+$rowoffset)?> / 3 / span 1 / 4; overflow: hidden;" class="markdown"></div>
      <?if($rn>1){?>
        <div id="h<?=$question_history_id?>" style="grid-area: <?=(3+$rowoffset)?> / 2 / span 1 / 4;" class="diff" data-from="<?=$prev_title?>" data-to="<?=$question_history_title?>"></div>
        <div style="grid-area: <?=(4+$rowoffset)?> / 2 / span 1 / 4; overflow: hidden;" class="diff" data-from="<?=$prev_markdown?>" data-to="<?=$question_history_markdown?>"></div>
      <?}?>
      <div style="grid-area: <?=(1+$rowspan+$rowoffset)?> / 1 / span 1 / 4;" class="separator"></div>
    <?}?>
  </div>
</body>   
</html>   
