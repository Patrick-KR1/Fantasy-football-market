-- Cosmetic catalog expansion (design pass 2026-11-21): 8 nameplates, 8 player frames, 8 pitches.
-- Catalog rows only. Prices are proposals for the policy owner to confirm before this is applied;
-- existing items keep their prices. Artwork is original CSS/SVG in the app (no external assets).
insert into kickx_private.shop_items(id,category,name,description,price,theme,sort_order) values
 ('nameplate-royal','nameplate','로열 크레스트','금빛 문장과 리본이 감싸는 왕실 네임태그',22000,'royal',5),
 ('nameplate-glacier','nameplate','글레이셜','얼음 결정이 반짝이는 빙하 네임태그',20000,'glacier',6),
 ('nameplate-sakura','nameplate','사쿠라 블룸','벚꽃잎이 흩날리는 분홍 네임태그',20000,'sakura',7),
 ('nameplate-neon','nameplate','네온 시티','네온사인과 글리치가 깜빡이는 도시 네임태그',24000,'neon',8),
 ('nameplate-jungle','nameplate','정글 바인','덩굴과 황금 잎이 감긴 정글 네임태그',20000,'jungle',9),
 ('nameplate-void','nameplate','보이드 리프트','공간이 갈라진 보랏빛 균열 네임태그',28000,'void',10),
 ('nameplate-pixel','nameplate','픽셀 아케이드','8비트 픽셀과 하트가 빛나는 아케이드 네임태그',18000,'pixel',11),
 ('nameplate-champion','nameplate','챔피언 리본','트로피와 붉은 리본의 우승 네임태그',30000,'champion',12),
 ('frame-bronze','frame','브론즈 실드','구리빛 방패와 작은 날개의 입문 테두리',10000,'bronze',20),
 ('frame-silver','frame','실버 윙','은빛 날개가 펼쳐지는 테두리',16000,'silver',21),
 ('frame-gold','frame','골드 크레스트','황금 문장과 붉은 보석의 테두리',22000,'gold',22),
 ('frame-platinum','frame','플래티넘 프리즘','청록 결정이 솟은 프리즘 테두리',28000,'platinum',23),
 ('frame-diamond','frame','다이아몬드 헤일로','푸른 다이아몬드와 광륜의 테두리',34000,'diamond',24),
 ('frame-master','frame','마스터 크라운','보랏빛 왕관과 보석 날개의 테두리',40000,'master',25),
 ('frame-legend','frame','레전드 이클립스','금빛 광선이 터지는 일식 테두리',50000,'legend',26),
 ('frame-frost','frame','프로스트 팽','얼음 송곳과 눈꽃이 둘러싼 테두리',30000,'frost',27),
 ('pitch-sky','pitch','스카이 아일랜드','구름 위에 떠 있는 섬 경기장',35000,'sky',33),
 ('pitch-arcade','pitch','네온 아케이드','네온 격자와 오락기가 빛나는 경기장',35000,'arcade',34),
 ('pitch-desert','pitch','오아시스','모래 언덕과 야자수의 사막 경기장',32000,'desert',35),
 ('pitch-deepsea','pitch','딥 블루','산호와 물방울이 떠오르는 해저 경기장',35000,'deepsea',36),
 ('pitch-blossom','pitch','블라썸 가든','벚꽃과 등불이 걸린 정원 경기장',35000,'blossom',37),
 ('pitch-haunted','pitch','문라이트 할로우','달빛 아래 호박과 묘비가 선 경기장',32000,'haunted',38),
 ('pitch-candy','pitch','캔디 랜드','사탕 줄무늬와 막대사탕의 경기장',30000,'candy',39),
 ('pitch-ruins','pitch','정글 템플','이끼 낀 석상과 덩굴의 유적 경기장',35000,'ruins',40)
on conflict (id) do nothing;
-- Keep each category together: nameplates, frames, pitches, then the recovery ticket.
update kickx_private.shop_items s set sort_order=v.sort_order
from (values ('nameplate-aurora',1),('nameplate-arcane',2),('nameplate-circuit',3),('nameplate-inferno',4),('frame-laurel',13),('frame-circuit',14),('frame-arcane',15),('frame-seraph',16),('frame-dragon',17),('frame-astral',18),('frame-tempest',19),('pitch-myth',28),('pitch-engineering',29),('pitch-christmas',30),('pitch-volcano',31),('pitch-cosmos',32),('attendance-ticket',41)) as v(id,sort_order) where s.id=v.id;
