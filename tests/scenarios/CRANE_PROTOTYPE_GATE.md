# S00 / PORT-003 — Crane Prototype Test Contract

Bu belge, S00 crane PoC'sinin ölçülebilir geçiş kapısıdır. Testler prototype'ın
görsel davranışını ve contract'ını doğrular; production PortOps resource'u,
kalıcı container/move/yard domain'i ve framework entegrasyonu bu kapsamda
değildir.

## 1. Test amacı ve karar kuralı

Test, operator client'ın local smooth simulation'ını; server'ın crane/session/
attach authority'sini; observer'ın canonical snapshot'ı tutarlı görmesini
kanıtlamalıdır. Fizik, rope/cable veya network ownership tek başına gameplay
authority kabul edilmez.

Bir senaryo **PASS** yalnızca bütün pass koşulları sağlanır ve hiçbir fail
koşulu görülmezse PASS'tir. Her senaryo en az 5 ardışık tekrarda PASS olmalı;
bir tekrar fail olursa kök neden düzeltilip bütün seri yeniden çalıştırılır.

## 2. Prerequisites / fixture

- Test sunucusu ve prototype resource temiz başlatılmış; debug log seviyesi
  açık, gerçek production resource'u kapalı.
- Tek crane fixture: `QC-01`; profile origin/local axes, gantry/trolley
  bounds ve spreader min/max değerleri kayıtlı.
- Test container: `CONT-01`, beklenen attach hedefi ve boş terminal trailer
  `TRL-01`. Container başlangıç konumu server fixture'ında sabittir.
- Profile fixtures: `QC-01` baseline axes and `QC-ROTATED` with a rotated or
  reversed local axis basis. Each fixture's origin, axes, min/max, and expected
  min/center/max world transforms are checked against the coordinate spec.
- `QC-ROTATED` fixture example: `origin=(100,200,30)`, gantry axis
  `(0,1,0)` with `[0,80]`, trolley axis `(-1,0,0)` with `[-12,12]`, and
  spreader axis `(0,0,1)` with `[2,25]`. Expected positions are min
  `(112,200,32)`, center `(100,240,43.5)`, max `(88,280,55)`.
- Oyuncu A: crane operator yetkili, aktif duty, crane session açmaya uygun.
  Oyuncu B: aynı crane yetkisine sahip, aktif session'ı olmayan ikinci operator;
  üçüncü istemci varsa ayrıca yetkisiz observer olarak kullanılır.
- Senaryo başında `QC-01` `AVAILABLE`, active session yok, attached container
  yok, entity registry temizdir. Önceki senaryonun state'i kullanılmaz.
- İstemci FPS testlerinde 30, 60 ve 120 FPS profilleri; multiplayer testinde
  aynı build ve aynı server tick/snapshot ayarları kullanılır.
- Kanıt: server canonical state log'u (sequence, timestamp, version), client
  input/action log'u, observer capture ve ekran kaydı. Saatler UTC veya tek bir
  monotonic test clock ile eşleştirilir.

## 3. Canonical observables and tolerances

Bu değerler profile/config ile override edilebilir; test raporu kullanılan
değeri mutlaka yazar. Override yoksa aşağıdaki S00 varsayılanları geçerlidir:

| Ölçüm | PASS eşiği |
|---|---|
| Gantry/trolley normalized state | Her accepted state `0.0..1.0`; sınırda clamp veya reject, taşma yok |
| Spreader height | Profile min/max aralığı içinde; taşma yok |
| Attach alignment | Container center yatay mesafesi ≤ `0.25 m`, dikey fark ≤ `0.15 m`, yaw farkı ≤ `3°` |
| Observer convergence | Accepted snapshot'tan sonra ≤ `500 ms` içinde canonical transform'a ≤ `0.50 m`; kalıcı teleport/jitter yok |
| Snapshot order | Eski sequence/timestamp discard; state version geriye gitmez |
| Camera switch | İstenen geçerli moda ≤ `250 ms`; geçersiz mod aktif kamerayı değiştirmez |
| Session/token | Bir crane'de aynı anda 1 operator; attach token TTL ≤ `5 s`, tek kullanımlı |
| Cleanup | Exit/disconnect sonrası transient entity/session/resource handle ≤ `2 s` içinde temiz veya `RECOVERY_REQUIRED` olarak işaretli |

Canonical snapshot/persistence stores gantry, trolley, spreader, and optional
yaw as normalized `[0,1]` values. Metric spreader height is derived from the
active profile and is never accepted as an alternate authoritative wire format.
Timestamp fixture defaults are `futureSkewMs = 250` and `maxAgeMs = 2000`; values
must be logged when overridden. A snapshot newer than `now + futureSkewMs` or
older than `now - maxAgeMs` is rejected/discarded before state mutation.

## 4. Scenarios

### CRANE-001 — Operator enter / exit and exclusive session

**Setup:** A, `QC-01` yanında; B aynı crane interaction noktasında.

1. A enter ister; server session oluşturur, state `OPERATOR_ENTERING` sonra
   `OPERATING` olur ve operator/crane/session ID'leri canonical state'e yazılır.
2. A içerideyken B enter ister; B reddedilir, A session değişmez.
3. A exit ister; state `OPERATOR_EXITING` sonra `AVAILABLE` olur; session ve
   operator temizlenir.
4. A exit'i iki kez yollar; ikinci çağrı idempotent/rejected olur.

**PASS:** Tek session invariant hiç bozulmaz; enter/exit sonunda doğru state ve
entity cleanup gözlenir. **FAIL:** İki operator kabulü, stuck session, duplicate
reward/state transition veya client-only enter görülmesi.

### CRANE-002 — Gantry, trolley and spreader control

**Setup:** A operating; başlangıç canonical state center (`0.5`, `0.5`, `0.5`).
Metric spreader height, profile min/max'tan türetilir; wire state'e metre değeri
yazılmaz.

1. `QC-01` üzerinde gantry, trolley ve spreader her birini ayrı ayrı ileri/geri hareket ettir;
   diğer iki eksenin state'i kabul edilen input boyunca değişmemeli.
2. Her ekseni min ve max yönüne sür; sınırda hareket durmalı veya input reject
   edilmelidir.
3. Aynı hareketi 30/60/120 FPS'te aynı gerçek süreyle tekrarla.
4. `QC-ROTATED` fixture'ına geç; min, center ve max state'leri için türetilen
   world position'ı coordinate modeldeki beklenen değerle `≤0.01 m` farkla assert et.
5. Server snapshot'ta sequence/version monoton artmalı; geç snapshot discard
   edilmeli.

**PASS:** Hareket profile-local transform ile yapılır, normalized/bounds
kurallarına uyar; iki farklı axis/origin fixture'ında min/center/max world
transform assert'i geçer; üç FPS sonucunun endpoint farkı ≤ `0.05` normalized
veya spreader için ≤ `0.15 m`; server canonical state client tahmininden
bağımsız doğrulanır. **FAIL:** World-coordinate hardcode nedeniyle profile
dışında konum, overshoot, frame-rate bağımlı belirgin fark veya eski snapshot'ın
state'i geri alması.

### CRANE-003 — Camera mode switching

**Setup:** A operating, fixture'da cabin/reset, top-down alignment,
spreader-down, left, right ve varsa trailer alignment modları etkin.

1. Her geçerli moda sırayla geç; mode identifier ve camera transform log'la.
2. Geçersiz/boş mode identifier gönder.
3. Exit ve resource stop sırasında camera kontrolünü serbest bırak.

**PASS:** Her geçerli mod ≤`250 ms` içinde aktif olur, hedef rig/interaction
point'i görür ve input binding çalışır. Ölçüm, mode-request event timestamp'i
ile stable camera-active acknowledgement arasındaki monotonic süre üzerinden
yapılır; hedef görüşü ekran kaydı ve camera transform log'u ile doğrulanır.
Invalid mode reject edilir ve aktif camera değişmez; exit/stop sonrası gameplay
camera/input restore olur.

### CRANE-004 — Container alignment contract

**Setup:** `CONT-01` expected move step ve expected attach target olarak server
tarafından atanır. Spreader'ı hedef dışı, sınırda ve hedef tolerans içinde üç
konuma getir.

**PASS:** Yalnız yatay ≤`0.25 m`, dikey ≤`0.15 m`, yaw ≤`3°` olduğunda alignment
true olur. Sınır dışı konum attach ön koşulunu karşılamaz; alignment sonucu
server log'unda measured deltas ile görünür. Görsel yakınlık tek başına yeterli
değildir.

### CRANE-005 — Server-approved attach / detach

**Setup:** A valid session; `CONT-01` free/reserved ve doğru move step.

1. CRANE-004 toleransında attach request gönder; server kısa ömürlü token verir.
2. Token ile bir kez attach; logical state `CRANE_ATTACHED`, visual attachment
   ve `attachedContainerId` eşleşir.
3. Aynı tokenı tekrar kullan; expired token, başka session tokenı ve `CONT-02`
   token/container mismatch dene.
4. Yanlış trailer/target (`TRL-02`) detach isteğini gönder; rejection/error code
   kaydet ve state'in `CRANE_ATTACHED` kaldığını doğrula.
5. Doğru trailer (`TRL-01`) detach request gönder; state `ON_TERMINAL_TRAILER`
   olur, canonical trailer metadata yazılır ve visual attachment kaldırılır.
6. Aynı detach isteğini tekrar gönder; ikinci çağrı idempotent/rejected olur.

**PASS:** Attach yalnız doğru session + move step + container + alignment ve
tek kullanımlık token ile gerçekleşir; token TTL ≤`5 s`; replay/wrong-session/
wrong-container reject ve security event üretir. Wrong-target detach reject
edilir; doğru detach `ON_TERMINAL_TRAILER` state'ini üretir; tekrar çağrı
idempotent/rejected olur ve orphan entity bırakmaz. Raw client attach event
logical state değiştirmez.

### CRANE-006 — Second-player observer synchronization

**Setup:** A operating; B crane scope içinde farklı pozisyonda; C varsa scope
dışında başlayıp sonradan scope'a girer.

1. A gantry/trolley/spreader hareket ettirip attach/detach yapar.
2. B snapshot/interpolation ile izler; C scope dışına çıkıp geri girer.
3. Eski snapshot ve gecikmiş snapshot kontrollü olarak inject edilir.

**PASS:** B ve C accepted canonical snapshots sonrası ≤`500 ms` içinde ≤`0.50 m`
transform farkına gelir; attached container aynı crane ilişkisinde görünür;
sequence gerisi discard edilir; scope re-entry canonical resync yapar. Normal
oyunda major teleport veya kalıcı jitter (tek frame'de >`2.0 m`) yoktur.

### CRANE-007 — Operator disconnect / recovery

**Setup:** A operating; önce attached değil, sonra attached durumda iki ayrı run;
B observer olarak bağlı.

1. A istemcisini/oyuncusunu disconnect et.
2. Server disconnect event ve B gözlemini kaydet; yeni operator ile tekrar enter
   dene.

**PASS:** Unattached run'da ≤`2 s` içinde session invalid, crane hareketi freeze
edilir ve crane `AVAILABLE` olur; yeni valid operator temiz session ile girebilir.
Attached run'da crane ve container zorunlu olarak `RECOVERY_REQUIRED` olur;
attached container raw havada asılı production state olarak kabul edilmez.
Recovery tamamlanana kadar yeni operator enter isteği reject edilir. Recovery
marker temizlendikten sonra observer resync olur ve yeni valid operator girebilir.
A'nın eski token/snapshot'ı hiçbir run'da sonradan state değiştiremez.

### CRANE-008 — Invalid movement and abuse rejection

**Setup:** Valid session ile A; ayrıca session'sız ikinci operator B ve
crane permission'ı olmayan observer C. B'nin authorization'ı CRANE-001'den
bağımsızdır; C'nin rejection'ı permission guard'ı ayrıca kanıtlar.

Şunları ayrı ayrı gönder: gantry/trolley `-0.1` veya `1.1`, spreader height
min/max dışı, aşırı delta/speed, wrong crane ID, stale session ID, malformed or
oversized payload, out-of-order snapshot, future timestamp beyond allowed clock
skew, stale timestamp outside the accepted window ve operator olmayan movement
request.

**PASS:** Her geçersiz request reject veya güvenli clamp edilir; canonical state,
attached container, reward ve session ownership değişmez; rate-limit/security
log'u gerekli olayları kaydeder. Future/stale timestamp request'leri reject
edilir veya açıkça discard edilir; bir geçersiz çağrı sonraki geçerli hareketi
bozmaz. **FAIL:** Client istediği koordinatı doğrudan authoritative yaparsa,
timestamp manipülasyonu kabul edilirse, state corruption veya reward/state skip
oluşursa.

### CRANE-009 — Resource/interaction cleanup

**Setup:** Operator enter, camera switch, movement, attach ve detach sonrası
resource stop/start; ayrıca exit sırasında resource-owned handle registry ölçülür.
Registry kapsamı spawned rig/cable/container entities, camera handles, control
overrides, event listeners ve active sessions'tır; native global entity count
tek başına cleanup kanıtı sayılmaz.

**PASS:** Exit ve stop sonrası camera/input restore, session cleanup, entity
cleanup ve event listener cleanup ≤`2 s`; bu süre stop/exit event timestamp'i
ile registry'nin baseline'a dönmesi arasındaki monotonic süre olarak ölçülür.
Restart sonrası duplicate rig/cable/container entity yok; logical
attachment/state yalnız fixture contract'ına göre korunur. Five start/stop
cycles sonunda her registry kategorisi baseline count'a döner.

## 5. Security and authority checklist

- [ ] Session reserve atomic; bir crane için tek active operator.
- [ ] Client hareketi prediction/presentation; server bounds, rate, sequence ve
  session doğrular.
- [ ] Attach/detach, move step ve container association server kararındadır.
- [ ] Token action/container/session-bound, TTL'li ve one-time'dır; replay loglanır.
- [ ] Network ownership değişimi veya visual entity deletion logical state'i
  değiştirmez.
- [ ] Invalid payload ve unauthorized event standard reject/error sonucu verir;
  sessiz state mutation yoktur.

## 6. Test report template

```text
Run ID:
Build / commit:
Server/runtime:
Profile + origin/axes/bounds:
FPS profile(s):
Players / roles:
Clock / timezone:

| ID | Attempt | Result (PASS/FAIL) | Observed values | Evidence | Notes |
|----|---------:|--------------------|-----------------|----------|-------|
| CRANE-001 | 1..5 | | | | |

Canonical state before:
Canonical state after:
Rejected requests and error codes:
Security/replay log references:
Observer convergence measurements:
Cleanup/entity counts before/after:
Known deviations / follow-up:
Gate decision: GO / NO-GO
Reviewer:
Date:
```

## 7. S00 gate

S00 **GO** yalnızca şu koşulların tümü sağlanır:

- CRANE-001..009, her biri 5/5 repeat PASS; rapor ve evidence mevcut.
- Operator loop, controls, camera, alignment ve attach/detach contract'ı
  ölçülebilir eşiklerle doğrulanmış.
- B observer senaryosunda coherent sync ve scope re-entry resync PASS.
- Disconnect ve cleanup orphan session/entity üretmiyor.
- Invalid movement, token replay, wrong target ve unauthorized calls state'i
  değiştirmiyor.
- `PORT-001` reference notes ve `PORT-002` coordinate modelindeki profile,
  bounds ve authority kararları bu contract ile çelişmiyor.

Herhangi bir madde NO-GO ise S01'e geçilmez; yeni feature eklenmez. Önce crane,
network veya authority contract'ı düzeltilir ve bütün ilgili seri tekrarlanır.
