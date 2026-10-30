import {createHash} from 'node:crypto';
export const SAMPLE_BATCH='kickx-demo-20261030';
export const sampleId=key=>{
 const h=createHash('sha1').update(`${SAMPLE_BATCH}:${key}`).digest('hex');
 return `${h.slice(0,8)}-${h.slice(8,12)}-5${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
};
const names=['박스밖한입','주말엔축구','왼발감아차기','원터치패스','골대뒤관중','후반전커피','역습한스푼','수비도예술','중원산책','오늘도직관',
 '라리가산책','짧게주고받기','터치라인옆','볼보이출신','새벽경기러','패스맵수집가','스루패스좋아','잔디위낭만','풋볼메모장','느린빌드업',
 '세리에한바퀴','수비라인맞춰','오프사이드깃발','코너킥한번더','경기장앞카페','공은둥글다','백패스도전술','측면돌파중','전술판낙서','연장전은없다',
 '독일축구일기','압박좀더','세컨드볼먼저','풀백관찰자','발끝의온도','노란카드주의','문전앞침착','유니폼수집중','한골차의미학','볼점유중',
 '리그앙산책','하프스페이스','전반끝나면커피','낭만적인패스','킥오프대기중','골키퍼도주인공','경기복기하는밤','포지션은중미','매치데이노트','휘슬불면시작'];
const heads=['기록 다시 보니 생각이 좀 달라짐','일단 한 경기 더 보려고요','이 점수는 조금 반가웠다','지금 자리 그대로 둘까 고민 중','출전 시간부터 확인하고 들어옴',
 '이름값 말고 기록으로 보니까','생각보다 자꾸 눈이 가는 선수','이런 경기 기록 보는 재미가 있네요','보유할지 바꿀지 아직 고민','숫자만 보고 판단하기는 어렵네',
 '이 선수 보는 분들 기준이 궁금함','당장 갈아타기엔 조금 아쉬워서','오늘은 거래보다 기록 복기','요즘 먼저 확인하는 이름','이 정도면 다음 경기 기다려볼 만한가',
 '한 경기만으로 결론은 안 내리려고','지금 가격에서 관심 가는 이유','경기력 탭 열었다가 오래 봄','내 기준은 결국 꾸준한 출전','가격표 보고 기록까지 다시 확인',
 '한 자리 맡겨둘 만한지 고민','이런 선수 고르는 게 더 어렵다','기록에 비해 관심이 덜 가는 느낌','오늘 선수 목록에서 멈춘 지점','팬심이랑 보유는 또 별개네요',
 '숫자 정리하고 나니 차분해짐','바로 판단하지 않고 지켜보는 중','한 번쯤 자세히 볼 만한 기록','다음 경기까지 생각하면 고민됨','기록 챙겨보는 분 있나요',
 '골 장면만 볼 때와는 다르네요','수익률보다 먼저 열어본 경기 기록','계속 가지고 갈 기준을 정해봄','다음 교체 후보를 고르는 중','점수와 출전 시간을 같이 보게 됨',
 '이래서 경기 기록을 찾아보는 듯','잘 고른 건지는 조금 더 봐야겠음','당분간은 포지션을 유지하려고','보유 선수 비교하다가 적어봅니다','괜히 자꾸 목록에서 찾게 됨',
 '오늘은 급하게 결정 안 할 생각','한 경기 기록으로도 얘깃거리가 있네','비슷한 가격 선수와 비교 중','생각보다 선택이 쉽지 않네요','기록 보고 들어온 사람 또 있나',
 '다음 경기에서 확인하고 싶은 것','조금 길게 볼 선수인지 고민','출전 기록 쌓이는 걸 보고 싶음','이 선수 얘기는 많이 안 보이길래','내 보유 목록에서 제일 고민되는 자리'];
const opinions=['골만 보던 버릇이 있었는데 출전 시간하고 세부 점수까지 같이 보니까 인상이 다르네요. 다음 기록도 보고 판단하려고요.',
 '당장 다른 선수로 바꾸기보다 한 경기 더 보겠습니다. 매번 바꾸면 수수료부터 쌓일 것 같아서요.',
 '이름 익숙하다고 무조건 고르던 때보다 이렇게 기록 찾아보는 쪽이 재밌네요. 다른 분들은 어느 항목부터 보세요?',
 '가격이 움직였다고 바로 따라가기보다는, 제가 골랐던 이유가 아직 남아 있는지 보게 됩니다.',
 '점수 하나만으로 잘했다 못했다 딱 자르기는 어렵지만 비교할 기준이 생긴 건 좋네요. 출전 시간도 계속 체크할 생각입니다.',
 '선수 한 명 바꾸는 것도 꽤 고민되네요 ㅋㅋ 다음 경기까지는 지켜보고 싶은 쪽입니다.',
 '짧게 흔들리는 가격보다 꾸준히 경기에 나오는지가 더 신경 쓰여요. 다음 기록까지 보고 결정할게요.',
 '비슷한 가격대 선수랑 번갈아 보고 있는데 장단점이 달라서 쉽게 못 고르겠네요.',
 '팬심으로 보는 경기랑 보유 선수 기록 확인하는 건 느낌이 또 다릅니다. 괜히 한 번 더 눌러보게 돼요.',
 '바로 결론 내리기엔 아직 아쉬워서 메모만 남겨둡니다. 다음 경기 끝나면 이 글 다시 보려고요.',
 '저는 오히려 바꿀 선수를 정하는 게 더 어렵네요. 사는 이유는 금방 떠오르는데 보유 기준은 또 다르네요.',
 '오늘도 목록만 한참 봤습니다. 마음 정한 것 같다가 다른 선수 기록 누르면 다시 고민됨...',
 '개인적으로 제일 먼저 보는 건 출전 시간입니다. 점수는 그다음에 확인하는 편이에요.',
 '이 선수를 오래 봐온 분들은 어떤 점을 중요하게 보시는지 궁금하네요. 저는 아직 기록 읽는 연습 중입니다.',
 '다음 경기 끝나고 괜히 성급했다고 하지 않으려고요. 오늘은 여기까지 보고 닫겠습니다.',
 '제 기준을 하나씩 만들어보는 중이에요. 잘 고르는 것도 좋지만 왜 골랐는지는 남겨두고 싶어서요.',
 '경기 끝나면 무조건 바꾸던 버릇부터 줄여보려고 합니다. 지금 자리의 이유부터 다시 읽어봤어요.',
 '비슷한 가격 선수들 비교하다 보면 시간 금방 가네요. 한 자리만 고르라니까 더 어려움 ㅋㅋ',
 '좋은 기록이 나와도 바로 확신으로 이어지는 건 아닌 것 같아요. 다음 출전까지 같이 봐야겠죠.',
 '보유하는 동안 뭘 확인할지 먼저 정해뒀습니다. 점수가 움직여도 급하게 판단하지 않으려고요.',
 '오늘은 선수 이름 가리고 기록만 비교해봤어요. 평소 보던 순서랑 조금 달라서 재밌네요.',
 '친숙한 이름이라 그냥 넘겼었는데 상세 기록은 이번에 처음 제대로 봤습니다. 다른 의견도 듣고 싶어요.',
 '가격표만 보고 닫기 아쉬워서 적어봅니다. 기록 볼 때 놓치고 있는 항목이 있는지도 궁금하네요.',
 '당장 결론보다는 다음 경기에 확인할 것 하나만 정해두는 쪽입니다. 저는 출전 시간부터 볼게요.',
 '한 선수에 기대를 너무 많이 걸지 않으려고요. 기록 확인하면서 천천히 기준을 바꿔볼 생각입니다.',
 '다른 분들 글 읽다가 제 보유 이유도 다시 생각해봤습니다. 이렇게 얘기 나누는 건 좋네요.',
 '오른 숫자만 보고 관심 가지는 버릇이 있어서 이번에는 경기 기록부터 열었습니다. 좀 더 차분해지네요.',
 '계속 보는 선수인데도 기록을 숫자로 정리하면 놓쳤던 게 보여요. 다음 기록 나오면 또 비교해보겠습니다.',
 '결국 오래 지켜볼 수 있는 선수를 고르는 게 저한테는 맞는 것 같습니다. 자주 바꾸는 건 성격상 피곤하네요.',
 '이런 고민 하는 사람이 저만 있는 건 아니겠죠 ㅎㅎ 비슷한 가격대 보시는 분들 의견 궁금합니다.'];
const clubTopics=['팬심이랑 보유 기준은 다르게 두는 중','경기 끝나면 제일 먼저 확인하는 선수','우리 팀 선수만 담기엔 고민이 많네요','응원하면서 기록도 같이 챙기게 됨','다음 리그 경기까지 기다리는 이유',
 '한 자리 고르려니 생각보다 어렵다','구단 팬들 보유 기준이 궁금합니다','결과 말고 선수 기록도 보는 중','오늘은 보유 목록 정리만 했어요','팬 입장에서 자꾸 눌러보는 기록'];
const clubTails=['응원하는 팀이라고 전부 담을 수는 없으니 몇 자리만 정해서 보는 중입니다. 다른 팬분들은 누구부터 확인하시나요?',
 '팀 결과를 보는 재미랑 선수별 점수 보는 재미가 조금 다르네요. 다음 리그 기록도 챙겨보려고 합니다.',
 '골 장면만 보고 넘기던 때보다 출전 시간까지 보게 됐어요. 팬 입장에서는 이런 기록 얘기도 편하게 나누면 좋겠습니다.',
 '보유는 욕심내지 않고 여유 포인트를 남겨뒀습니다. 다음 경기 보고 바꿀지 유지할지 생각해보려고요.',
 '다른 리그 선수도 섞어두니 응원하는 마음과 선택 기준이 가끔 갈리네요 ㅋㅋ 여러분은 어느 쪽인가요?',
 '구단 이름만 보고 골랐다가 기록을 다시 읽는 중입니다. 이래서 팬심과 보유 판단을 따로 해보라는 말이 있나 봐요.',
 '확신한다고 쓰기보다는 지금 보고 있는 기준만 남깁니다. 다음 기록이 나오면 생각이 달라질 수도 있으니까요.',
 '팀 선수들끼리도 포지션마다 점수 구성이 달라서 단순 비교가 잘 안 되네요. 일단 출전 시간부터 보고 있습니다.',
 '경기 끝나고 기록 복기하는 글이 조금 더 많아졌으면 좋겠어요. 다른 분들 관점도 궁금합니다.',
 '오늘은 자꾸 선수만 바꾸지 말고 기다려보자는 쪽으로 정리했습니다. 다음 리그 경기에서 또 얘기해요.'];
const comments=['출전 시간 같이 보는 거 동의해요. 점수만 보고 고르면 나중에 왜 골랐는지 기억도 안 나더라고요.',
 '저도 다음 경기까지는 보려구요. 선수 바꿀 때마다 수수료부터 계산하게 됨 ㅋㅋ',
 '이름 익숙한 선수만 누르고 있었는데 이런 기록 정리 좋네요.',
 '비슷한 가격대랑 비교하면 더 고민될 듯요. 저는 일단 지금 자리 유지입니다.',
 '팬심하고 보유 기준 분리하는 게 말처럼 쉽지 않네요 ㅎㅎ',
 '기록 보고 판단한 이유가 있으면 한 경기 더 기다려보는 것도 괜찮아 보여요.',
 '요즘 저도 득점만 보지 않고 출전 시간을 먼저 확인하게 됩니다.',
 '한 번 골랐다고 끝은 아니니까 다음 기록도 보고 다시 얘기해봐요.',
 '포인트 여유 남기는 편이 마음은 편하더라고요. 빈 자리 보이면 자꾸 바꾸게 돼서요.',
 '저랑 보는 기준 비슷하네요. 단순히 오른 선수 따라가기는 좀 망설여집니다.',
 '세부 점수까지 챙기는 분들 글 더 올라오면 좋겠네요.',
 '한 경기만으로 단정 안 하는 쪽이 저도 맞는 것 같아요. 일단 메모해둠.',
 '같은 가격이어도 포지션이 다르면 역할부터 다르니 어렵네요.',
 '보유 이유를 먼저 정해두는 거 좋네요. 저는 바꿀 이유부터 찾고 있었음...',
 '다음 경기 끝나면 이 글 다시 보러 올게요. 저도 관심 목록에 넣어뒀습니다.'];
const replies=['맞아요. 저도 그 부분 때문에 바로 결정은 안 하려고요. 다음 기록 나오면 다시 적어볼게요.',
 '수수료 생각하면 괜히 손이 덜 가죠 ㅋㅋ 일단 기다리는 쪽입니다.',
 '다른 관점 궁금했는데 댓글 고마워요. 출전 시간부터 같이 보겠습니다.',
 '저도 아직 확신은 없습니다. 기록 좀 더 쌓이면 다시 비교해보려고요.',
 '팬심 빼는 게 제일 어렵네요 ㅎㅎ 그래도 기준은 적어두는 중입니다.'];
const number=n=>Number(n).toLocaleString('ko-KR');
const date=s=>new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',month:'numeric',day:'numeric'}).format(new Date(s));
function factText(p,style=0){
 const r=p.recent[0];if(!r)return `${p.name_ko} 현재 표시 가격은 ${number(p.price)}P입니다.`;
 if(r.status==='not-played')return style%2?`${date(r.starts_at)} 기록을 열었는데 미출전이네요. 제가 확인한 가격은 ${number(p.price)}P였습니다. 다음 출전 기록부터 다시 보려고요.`:`${date(r.starts_at)} 리그 기록은 미출전으로 잡혀 있네요. 가격은 ${number(p.price)}P로 확인했습니다.`;
 const extras=[['goals','골'],['assists','도움'],['shots_on_target','유효슈팅'],['saves','선방']].filter(([k])=>Number(r.metrics[k]?.value)>0).map(([k,n])=>`${n} ${r.metrics[k].value}개`).slice(0,2);
 const line=[
 `${date(r.starts_at)} ${r.home_name} ${r.home_score}:${r.away_score} ${r.away_name} 경기 기록을 보니 ${r.minutes}분 출전, Performance ${r.score}점이네요.`,
 `${date(r.starts_at)} 기록 보고 왔어요. ${r.minutes}분에 ${r.score}점. 출전 시간이랑 점수를 같이 적어봤습니다.`,
 `마지막 리그 기록은 ${date(r.starts_at)}, ${r.minutes}분 출전에 ${r.score}점이었습니다.`,
 `${r.home_name} ${r.home_score}-${r.away_score} ${r.away_name} (${date(r.starts_at)})\n${r.minutes}분 출전 / Performance ${r.score}점.`,
 `저는 ${date(r.starts_at)} 기록부터 봤는데 ${r.score}점이더라고요. 출전 시간은 ${r.minutes}분으로 확인했습니다.`,
 `기록으로 보면 ${date(r.starts_at)}의 ${r.score}점이 먼저 눈에 들어옵니다. ${r.minutes}분 뛴 경기였네요.`,
 `${date(r.starts_at)} 경기에서 찍힌 ${r.score}점. ${r.minutes}분 출전했다는 것도 같이 보고 있어요.`,
 `최근 리그 기록 메모해둡니다.\n${date(r.starts_at)} · ${r.minutes}분 · ${r.score}점.`][style%8];
 return line+(extras.length?`\n${extras.join(', ')}${style%2?'가 기록에 잡혀 있습니다.':'도 확인했습니다.'}`:'');
}
export function buildDemoData(source){
 const leagues=['bsd-1','bsd-3','bsd-4','bsd-5','bsd-6'],users=[],posts=[];
 const pool=source.players.filter(p=>p.recent.length&&p.recent[0].status!=='blocked');
 if(pool.length<100||names.length!==50)throw Error('SAMPLE_SOURCE_INCOMPLETE');
 for(let i=0;i<50;i++){
  const clubs=source.clubs.filter(t=>t.league===leagues[Math.floor(i/10)]),club=clubs[i%clubs.length];
  const own=pool.filter(p=>p.team_id===club.id).sort((a,b)=>a.rn-b.rn),anchor=own[Math.floor((i%10)/clubs.length)%Math.min(5,own.length)];
  if(!anchor)throw Error('SAMPLE_CLUB_SOURCE_REQUIRED');
  const mixed=pool.filter(p=>p.team_id!==club.id).sort((a,b)=>sampleId(`${i}:${a.id}`).localeCompare(sampleId(`${i}:${b.id}`)));
  const rest=[...own.filter(p=>p.id!==anchor.id).slice(0,3),...mixed,...own,...pool];
  const buys=[anchor];let cost=anchor.price;
  for(const p of rest){if(buys.length>=6+i%5)break;if(buys.some(q=>q.id===p.id)||cost+p.price>1_105_000)continue;buys.push(p);cost+=p.price;}
  if(buys.length<5)throw Error('SAMPLE_BUDGET_INCOMPLETE');
  const sold=new Set();if(i%4===0)sold.add(anchor.id);if(i%7===0)sold.add(buys.at(-1).id);
  const trades=[...buys.map(p=>({playerId:p.id,side:'buy',requestId:sampleId(`${i}:buy:${p.id}`)})),...Array.from(sold,id=>({playerId:id,side:'sell',requestId:sampleId(`${i}:sell:${id}`)}))];
  const teams=[club.id];if(i%2===0){const other=source.clubs.find(t=>t.league===leagues[(Math.floor(i/10)+1)%5]);teams.push(other.id);}
  const user={index:i,id:sampleId(`user:${i}`),nickname:`${names[i]}_샘플`,email:`kickx-demo-${String(i+1).padStart(2,'0')}@example.invalid`,teams,primaryTeam:club.id,anchor:anchor.id,trades};users.push(user);
  const exited=sold.has(anchor.id),attachment=exited?sampleId(`${i}:sell:${anchor.id}`):i%3===0?sampleId(`${i}:buy:${anchor.id}`):null;
  const closing=exited?'이번에는 정리하면서 매도 수수료 2%도 확인했어요. 다시 볼지는 다음 출전 기록을 보고 정하려고요.':opinions[i%opinions.length];
  posts.push({key:`player-${i}`,author:i,scope:'player',target:anchor.id,title:`${anchor.name_ko}, ${heads[i]}`,body:`${factText(anchor,i)}\n\n${closing}${i%4===1?`\n가격은 ${number(anchor.price)}P로 확인하고 비교 중입니다.`:''}`,tradeRequest:attachment,sourceFixture:anchor.recent[0].fixture_id});
  const clubAttachment=i%5===0?trades.find(t=>t.side==='buy'&&!sold.has(t.playerId)):null;
  const title=[`${club.name}, ${clubTopics[i%10]}`,`${club.name} 팬들은 ${anchor.name_ko} 어떻게 보고 있나요`,`${anchor.name_ko} 기록 보다가 쓴 ${club.name} 잡담`,`${club.name} 선수 기록 보고 계신 분?`,`${club.name} 팬인데 ${clubTopics[i%10]}`][i%5];
  posts.push({key:`club-${i}`,author:i,scope:'club',target:club.id,title,body:`소속 선수 중에서는 ${anchor.name_ko} 기록을 먼저 봤습니다.\n${factText(anchor,i+3)}\n\n${clubTails[(i+Math.floor(i/10))%clubTails.length]}`,tradeRequest:clubAttachment?.requestId??null,sourceFixture:anchor.recent[0].fixture_id});
 }
 const discussion=[];
 for(let i=0;i<posts.length;i++){
  const p=posts[i],author=users[p.author];const peers=users.filter(u=>u.index!==author.index&&(p.scope==='player'||u.teams.includes(p.target)));
  const peer=peers[i%peers.length];if(!peer)throw Error('SAMPLE_COMMENT_FAN_REQUIRED');
  discussion.push({key:`comment-${i}`,postKey:p.key,author:peer.index,body:comments[(i+peer.index)%comments.length]});
 }
 for(let i=0;i<posts.length;i+=5)discussion.push({key:`reply-${i}`,postKey:posts[i].key,author:posts[i].author,parentKey:`comment-${i}`,body:replies[(i/5)%replies.length]});
 return {batch:SAMPLE_BATCH,sourceAsOf:source.asOf,users,posts,comments:discussion};
}
