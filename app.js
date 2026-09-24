const API="https://search.zemer.io";
const state={player:null,current:null,queue:[],index:-1,playing:false,timer:null,album:null};
const $=id=>document.getElementById(id);
const esc=s=>String(s??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll(String.fromCharCode(34),"&quot;").replaceAll("'","&#39;");
const thumb=x=>x?.thumbnailUrl||x?.thumbnail||x?.thumbnailUrlSmall||x?.art||(x?.videoId||x?.id?("https://i.ytimg.com/vi/"+encodeURIComponent(x.videoId||x.id)+"/hqdefault.jpg"):"");
const title=x=>x?.title||x?.name||"";
const artist=x=>x?.artistName||x?.artist||x?.author||x?.artist?.name||"";
const idOf=x=>x?.videoId||x?.id||"";
function normalize(v,kind){if(!v||typeof v!=="object")return null;return {...v,_kind:kind,_videoId:v.videoId||((kind==="songs"||kind==="videos"||kind==="singles"||kind==="episodes")?v.id:"")};}
function flatten(v,k){return Array.isArray(v)?v.map(x=>normalize(x,k)).filter(Boolean):[];}
function itemRow(x,i){const image=thumb(x),can=!!x._videoId;return '<div class="row" data-i="'+i+'"><div class="tracknum">'+(i+1)+'</div><img class="art" src="'+esc(image)+'" loading="lazy"><div class="info"><div class="title">'+esc(title(x))+'</div><div class="sub">'+esc(artist(x)||x.subtitle||"")+'</div></div><button class="action">'+(can?"▶":"›")+'</button></div>';}
function renderSearch(data,q){const cats=data?.categories||{};const order=[["Songs",cats.songs],["Artists",cats.artists],["Albums",cats.albums],["Singles",cats.singles],["Videos",cats.videos],["Playlists",cats.playlists],["Podcasts",cats.podcasts]];let html="",total=0;for(const pair of order){const name=pair[0],items=flatten(pair[1],name.toLowerCase());if(!items.length)continue;total+=items.length;html+='<section class="section"><h2>'+esc(name)+'</h2>';items.forEach((x,i)=>{html+=itemRow(x,i);});html+='</section>';document.querySelectorAll(".section").length;}$("results").innerHTML=html;$("status").textContent=total?total+" results for “"+q+"”":"No results.";bindRows();}
function bindRows(){document.querySelectorAll(".row").forEach(row=>row.addEventListener("click",async e=>{const i=Number(row.dataset.i);const section=row.closest(".section");const heading=section?.querySelector("h2")?.textContent||"";const data=window._lastCategories?.[heading.toLowerCase()]||[];const item=data[i];if(!item)return;if(heading==="Albums"){openAlbum(item);}else if(heading==="Artists"){openArtist(item);}else if(heading==="Podcasts"){openPodcast(item);}else if(item._videoId){state.queue=data.filter(x=>x._videoId);state.index=state.queue.findIndex(x=>idOf(x)===idOf(item));play(item);}}));}
function homeItemKind(x){return x?._kind||x?.type||x?.kind||"";}
function homeRowTitle(x){return x?.title||x?.name||x?.label||"";}
function homeItems(v){if(Array.isArray(v))return v;return Array.isArray(v?.items)?v.items:Array.isArray(v?.results)?v.results:Array.isArray(v?.data)?v.data:[];}
function homeCard(x,i,rowKind){
  const n=normalize(x,rowKind||homeItemKind(x));
  const playable=!!n?._videoId;
  return '<div class="homeCard" data-hi="'+i+'" data-hk="'+esc(rowKind||homeItemKind(x))+'"><img src="'+esc(thumb(n))+'" loading="lazy"><div class="homeCardTitle">'+esc(title(n)||homeRowTitle(n))+'</div><div class="homeCardSub">'+esc(artist(n)||n.subtitle||"")+'</div>'+(playable?'<button class="homePlay" type="button">▶</button>':'')+'</div>';
}
function renderHome(data){
  const root=$("results");
  const rows=Array.isArray(data?.rows)?data.rows:null;
  let html="";
  if(rows){
    rows.forEach((row,ri)=>{
      const items=homeItems(row);
      if(!items.length)return;
      const kind=String(row?.kind||row?.type||"").toLowerCase();
      html+='<section class="homeSection"><div class="homeSectionHead"><h2>'+esc(row?.title||row?.name||"Featured")+'</h2></div><div class="homeRail">'+items.slice(0,12).map((x,i)=>homeCard(x,i,kind)).join("")+'</div></section>';
    });
  }else{
    const defs=[
      ["Featured Albums",data?.albums||data?.featuredAlbums,"albums"],
      ["Featured Videos",data?.videos||data?.featuredVideos,"videos"],
      ["Featured Artists",data?.artists||data?.featuredArtists,"artists"],
      ["Featured Playlists",data?.playlists||data?.featuredPlaylists,"playlists"]
    ];
    defs.forEach(([label,val,kind])=>{
      const items=homeItems(val); if(!items.length)return;
      html+='<section class="homeSection"><div class="homeSectionHead"><h2>'+esc(label)+'</h2></div><div class="homeRail">'+items.slice(0,12).map((x,i)=>homeCard(x,i,kind)).join("")+'</div></section>';
    });
  }
  root.innerHTML=html||'<div class="emptyHome"><div class="emptyIcon">♪</div><h2>Welcome to Zemer</h2><p>Featured music will appear here.</p></div>';
  $("status").textContent="";
  bindHome();
}
function bindHome(){
  document.querySelectorAll(".homeCard").forEach(card=>{
    card.onclick=e=>{
      if(e.target.closest(".homePlay"))return;
      const i=Number(card.dataset.hi), kind=card.dataset.hk;
      const data=window._homeRows?.[kind]||[];
      const item=data[i]; if(!item)return;
      if(kind==="albums")openAlbum(item);
      else if(kind==="artists")openArtist(item);
      else if(item._videoId) {state.queue=data.filter(x=>x._videoId);state.index=state.queue.findIndex(x=>idOf(x)===idOf(item));play(item);}
    };
    const playBtn=card.querySelector(".homePlay");
    if(playBtn)playBtn.onclick=e=>{
      e.stopPropagation();
      const i=Number(card.dataset.hi), kind=card.dataset.hk, data=window._homeRows?.[kind]||[], item=data[i];
      if(item?._videoId){state.queue=data.filter(x=>x._videoId);state.index=state.queue.findIndex(x=>idOf(x)===idOf(item));play(item);}
    };
  });
}
async function loadHome(){
  $("status").textContent="Loading Home…";$("results").innerHTML="";
  try{
    const r=await fetch(API+"/home-rows?allowFemale=0&kidZone=0&blockVideos=1",{headers:{Accept:"application/json"}});
    if(!r.ok)throw Error("HTTP "+r.status);
    const d=await r.json();
    const source=d?.rows||d;
    const raw={};
    if(Array.isArray(d?.rows))d.rows.forEach(row=>{const kind=String(row?.kind||row?.type||row?.title||"").toLowerCase().replace(/[^a-z]/g,"");raw[kind]=homeItems(row);});
    raw.albums=(d?.albums||d?.featuredAlbums||raw.albums||raw.featuredalbums||[]);
    raw.videos=(d?.videos||d?.featuredVideos||raw.videos||raw.featuredvideos||[]);
    raw.artists=(d?.artists||d?.featuredArtists||raw.artists||raw.featuredartists||[]);
    raw.playlists=(d?.playlists||d?.featuredPlaylists||raw.playlists||raw.featuredplaylists||[]);
    window._homeRows=Object.fromEntries(Object.entries(raw).map(([k,v])=>[k,homeItems(v).map(x=>normalize(x,k))]));
    renderHome(d);
  }catch(e){console.error(e);$("results").innerHTML='<div class="emptyHome"><h2>Home is unavailable right now</h2><p>Search still works normally.</p></div>';$("status").textContent="";}
}
async function search(q){q=q.trim();if(!q)return;showTab("search",false);$("status").textContent="Searching…";$("results").innerHTML="";try{const r=await fetch(API+"/search?q="+encodeURIComponent(q)+"&allowFemale=0&kidZone=0&blockVideos=1&k=50",{headers:{Accept:"application/json"}});if(!r.ok)throw Error("HTTP "+r.status);const data=await r.json();const cats=data?.categories||{};window._lastCategories={songs:flatten(cats.songs,"songs"),artists:flatten(cats.artists,"artists"),albums:flatten(cats.albums,"albums"),singles:flatten(cats.singles,"singles"),videos:flatten(cats.videos,"videos"),playlists:flatten(cats.playlists,"playlists"),podcasts:flatten(cats.podcasts,"podcasts")};renderSearch(data,q);}catch(e){console.error(e);$("status").textContent="Couldn’t search right now. Try again in a moment.";}}
async function openAlbum(item){const aid=item.id||item.albumId; if(!aid)return; $("status").textContent="Loading album…";try{const r=await fetch(API+"/album?id="+encodeURIComponent(aid)+"&allowFemale=0&kidZone=0&blockVideos=1");if(!r.ok)throw Error("HTTP "+r.status);const d=await r.json();const tracks=d?.tracks||d?.songs||d?.items||[];state.album=d;state.queue=tracks.map(x=>normalize(x,"songs")).filter(x=>x&&x._videoId);state.index=-1;renderAlbum(d,tracks);}catch(e){console.error(e);$("status").textContent="Couldn't open that album.";}}
function renderAlbum(d,tracks){const cover=d.thumbnailUrl||d.thumbnail||d.cover||thumb(d);const name=d.title||d.name||"Album";const by=d.artistName||d.artist?.name||d.artist||"";let html='<button class="back" id="back">← Back</button><div class="albumHero"><img class="heroArt" src="'+esc(cover)+'"><div><div class="heroTitle">'+esc(name)+'</div><div class="heroSub">'+esc(by)+'</div><button class="action" id="albumPlay" style="margin-top:14px">▶</button></div></div><section class="section">';tracks.forEach((x,i)=>{const n=normalize(x,"songs");html+=itemRow(n,i);});html+='</section>';$("results").innerHTML=html;$("status").textContent="";$("back").onclick=()=>search($("q").value);$("albumPlay").onclick=()=>{if(state.queue[0]){state.index=0;play(state.queue[0]);}};document.querySelectorAll(".row").forEach(row=>row.addEventListener("click",()=>{const i=Number(row.dataset.i);const n=normalize(tracks[i],"songs");if(n?._videoId){state.queue=tracks.map(x=>normalize(x,"songs")).filter(x=>x&&x._videoId);state.index=state.queue.findIndex(x=>idOf(x)===idOf(n));play(n);}}));}
async function openPodcast(item){const pid=item.id||item.podcastId||item.podcast?.id;if(!pid)return;$("status").textContent="Loading podcast…";try{const r=await fetch(API+"/podcast?id="+encodeURIComponent(pid)+"&allowFemale=0&kidZone=0&blockVideos=1");if(!r.ok)throw Error("HTTP "+r.status);const d=await r.json();const show=d?.podcast||d?.show||d;const episodes=d?.episodes||d?.items||d?.results||[];const cover=show?.thumbnailUrl||show?.thumbnail||thumb(item);let html='<button class="back" id="back">← Back</button><div class="albumHero"><img class="heroArt" src="'+esc(cover)+'"><div><div class="heroTitle">'+esc(show?.title||show?.name||title(item)||"Podcast")+'</div><div class="heroSub">'+esc(show?.author||show?.authorName||show?.artistName||artist(item)||"")+'</div></div></div><section class="section"><h2>Episodes</h2>';episodes.forEach((x,i)=>{const e=normalize(x,"episodes");html+=itemRow(e,i);});html+='</section>';$("results").innerHTML=html;$("status").textContent=episodes.length?episodes.length+" episodes":"No episodes found.";$("back").onclick=()=>search($("q").value);state.queue=episodes.map(x=>normalize(x,"episodes")).filter(x=>x&&x._videoId);document.querySelectorAll(".row").forEach(row=>row.onclick=()=>{const i=Number(row.dataset.i);const e=state.queue[i];if(e){state.index=i;play(e);}});}catch(e){console.error(e);$("status").textContent="Couldn't open that podcast.";}}
async function openArtist(item){const aid=item.id||item.artistId; if(!aid)return;try{const r=await fetch(API+"/artist?id="+encodeURIComponent(aid)+"&allowFemale=0&kidZone=0&blockVideos=1");if(!r.ok)throw Error("HTTP "+r.status);const d=await r.json();const albums=d?.albums||d?.sections?.albums||[];let html='<button class="back" id="back">← Back</button><div class="albumHero"><img class="heroArt" src="'+esc(thumb(d))+'"><div><div class="heroTitle">'+esc(d.name||d.title||"Artist")+'</div></div></div>';if(albums.length){html+='<section class="section"><h2>Albums</h2>';albums.forEach((a,i)=>{html+='<div class="row" data-ai="'+i+'"><img class="art" src="'+esc(thumb(a))+'"><div class="info"><div class="title">'+esc(a.title||a.name||"")+'</div><div class="sub">'+esc(a.artistName||d.name||"")+'</div></div></div>';});html+='</section>';}$("results").innerHTML=html;$("status").textContent="";$("back").onclick=()=>search($("q").value);document.querySelectorAll("[data-ai]").forEach(row=>row.onclick=()=>openAlbum(albums[Number(row.dataset.ai)]));}catch(e){console.error(e);$("status").textContent="Couldn't open that artist.";}}
let streamController=null;
const DEVICE_KEY="zemer-web-device";
function relayDevice(){let v=localStorage.getItem(DEVICE_KEY);if(!v){v=crypto.randomUUID();localStorage.setItem(DEVICE_KEY,v);}return v;}
async function play(item){if(!item?._videoId)return;state.current=item;$("player").hidden=false;updatePlayer();const a=$("audio");if(streamController)streamController.abort();streamController=new AbortController();state.playing=false;updateButtons();$("status").textContent="Loading audio…";try{const r=await fetch("https://zemer-app.vercel.app/api/stream?v="+encodeURIComponent(item._videoId),{headers:{Accept:"audio/*","x-zemer-device":relayDevice()},signal:streamController.signal});if(!r.ok)throw Error("HTTP "+r.status);const blob=await r.blob();const url=URL.createObjectURL(blob);a.onloadeddata=()=>URL.revokeObjectURL(url);a.src=url;await a.play();state.playing=true;$("status").textContent="";updateButtons();}catch(e){if(e.name!=="AbortError"){console.error("Zemer relay playback failed",e);$("status").textContent="Playback couldn’t start for this song.";state.playing=false;updateButtons();}}tick();}
function renderQueue(){const el=$("queue");if(!el)return;el.innerHTML=state.queue.map((x,i)=>'<div class="qrow" data-q="'+i+'"><img src="'+esc(thumb(x))+'"><div class="qinfo"><div class="qtitle">'+esc(title(x))+'</div><div class="qsub">'+esc(artist(x))+'</div></div></div>').join("");el.querySelectorAll("[data-q]").forEach(row=>row.onclick=()=>{state.index=Number(row.dataset.q);play(state.queue[state.index]);});}
function updatePlayer(){$("ptitle").textContent=title(state.current);$("psub").textContent=artist(state.current);$("part").src=thumb(state.current);$("ftitle").textContent=title(state.current);$("fartist").textContent=artist(state.current);$("fart").src=thumb(state.current);renderQueue();}
function updateButtons(){$("pause").textContent=state.playing?"❚❚":"▶";$("fpause").textContent=state.playing?"❚❚":"▶";}
function next(){if(state.index<state.queue.length-1){state.index++;play(state.queue[state.index]);}}
function prev(){const a=$("audio");if(a.currentTime>5){a.currentTime=0;return;}if(state.index>0){state.index--;play(state.queue[state.index]);}}
function fmt(s){s=Math.max(0,Math.floor(s||0));return Math.floor(s/60)+":"+String(s%60).padStart(2,"0");}
function tick(){clearInterval(state.timer);state.timer=setInterval(()=>{const a=$("audio"),d=a.duration||0,c=a.currentTime||0;$("bar").style.width=d?(c/d*100)+"%":"0%";$("seek").value=d?(c/d*1000):0;$("cur").textContent=fmt(c);$("dur").textContent=fmt(d);},300);}
function showTab(tab,load=true){
  document.querySelectorAll(".tab").forEach(b=>b.classList.toggle("active",b.dataset.tab===tab));
  $("searchArea").hidden=tab!=="search";
  if(tab==="home"){if(load)loadHome();}
  else if(tab==="library"){ $("status").textContent=""; $("results").innerHTML='<div class="emptyHome"><h2>Your Library</h2><p>Playlists and saved music will live here.</p></div>'; }
}
document.querySelectorAll(".tab").forEach(b=>b.onclick=()=>showTab(b.dataset.tab));
showTab("home");
$("form").addEventListener("submit",e=>{e.preventDefault();search($("q").value);});
$("pause").onclick=()=>{const a=$("audio");if(a.paused){a.play();state.playing=true;}else{a.pause();state.playing=false;}updateButtons();};
$("fpause").onclick=()=>$("pause").click();$("next").onclick=next;$("fnext").onclick=next;$("prev").onclick=prev;$("fprev").onclick=prev;
$("part").onclick=()=>openFull();$("ptitle").onclick=()=>openFull();$("psub").onclick=()=>openFull();
$("closeFull").onclick=()=>$("full").classList.remove("open");$("openQueue").onclick=()=>{};
function openFull(){$("full").classList.add("open");updatePlayer();}
$("seek").addEventListener("input",()=>{const a=$("audio"),d=a.duration||0;a.currentTime=d*(Number($("seek").value)/1000);});

$("audio").addEventListener("ended",next);$("audio").addEventListener("play",()=>{state.playing=true;updateButtons();});$("audio").addEventListener("pause",()=>{state.playing=false;updateButtons();});$("audio").addEventListener("error",()=>{console.error("Zemer stream unavailable");$("status").textContent="Playback couldn’t start for this song.";});
