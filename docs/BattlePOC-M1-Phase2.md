# Battle POC — Phase 2 玩家部署與六對六編隊

> 🔖 **AI 接續提醒**：若在新工作階段接續本階段，先載入 `msw-planning`，依恢復流程讀取 `Archive/As-built.md`、`BattlePOC-M1-GDD.md` 與本文件；開始實作或修改 checklist 狀態前，必須完整閱讀 `references/build-management.md`。
> Parent doc: `BattlePOC-M1-GDD.md` · This Phase's goal: 在固定戰場完成玩家一至六隻單位的部署，按開始後鎖定編隊，與右側固定六隻敵軍進入自動戰鬥。
> **Skills to reference (this Phase)**: `msw-general`、`msw-scripting`、`msw-combat-system`、`msw-ui-system`（只串接人類交付的既有 UI，不設計外觀）。

## Status checklist

> States: ⬜ not started · 🟡 implemented (untested) · ✅ tested.
> All items start ⬜. Mark 🟡 when built, ✅ only after verification passes.
> UI 視覺、按鈕可用狀態與實際滑鼠手感需要使用者在 Maker Play 驗證；AI 不修改 UI 外觀或階層。

- 🟡 串接人類提供的部署按鈕與開始按鈕 UI 實體。 ⚠️ client adapter 已完成並掛到 `map01`；`/ui/BattleGroup` 已提供 `BtnTank`、`BtnAssault`、`BtnShooter`、`BtnStart`，Maker Play 已記錄 `bound deployment buttons=4`；仍需人工點擊確認操作流程。
- 🟡 完成左側自由放置、點擊移除、0.6 最小間距、一至六隻限制與伺服器驗證。 ⚠️ server gate／roster API 與命名 UI 已具備；需透過 Maker Play 完成輸入與驗證。
- 🟡 建立右側固定六隻敵軍與可調位置設定，預設二坦克、二突擊、二射手。 ⚠️ Maker Play 已確認六隻生成與 snapshot 編成／座標；正式人工驗收待 Phase 2 UI 流程可進入。
- 🟡 開戰後鎖定所有部署操作。 ⚠️ phase gate 與轉場 guard 已實作；需至少一隻玩家部署後透過 UI 驗證拒絕新增／移除／換位。
- 🟡 驗證一至六隻任意重複兵種皆能開始並完成單局。 ⚠️ roster／phase transition 與命名 UI 已具備；完整 1–6 編隊與單局驗證待人工操作。

## Task detail

### 1. 串接部署與開始按鈕

- **Goal**: 以既有且命名符合契約的 `BtnTank`、`BtnAssault`、`BtnShooter`、`BtnStart` 發送部署／開始意圖；沒有這些人類 UI 實體時保留明確 blocker，不以範本按鈕冒充交付。
- **Required systems·components**: 客戶端 `@Logic` 或 UI adapter、`ButtonComponent`、伺服器 `BattleSession` 意圖入口；不新增 `.ui` 外觀。
- **Data**: 不新增 dataset；兵種選擇只使用 `TANK`、`ASSAULT`、`SHOOTER` 三個封閉值。
- **UI**: 人類提供的既有 `.ui`；實體名稱與 GDD §4.6 完全一致。
- **Done (verification) criteria**: Maker Play 中點擊三個兵種按鈕會更新目前選擇，點擊開始只在至少一隻合法部署單位存在時被接受；缺少 UI 時由使用者補交後才能標記 ✅。
- **Dependencies**: 人類 UI 交付；Task 2 的伺服器部署入口。
- **Skills to reference (predicted)**: `msw-scripting/SKILL.md`、`msw-ui-system/SKILL.md`；若需 UI binding，讀 UI client-only 與 ButtonComponent 章節。

### 2. 玩家部署區與伺服器驗證

- **Goal**: 在 `X=-5..-2`、`Y=-3..1` 接受點擊部署，拒絕區外、重疊小於 `0.6`、超過六隻及戰鬥後的新增；部署階段再次點擊玩家單位會移除它。
- **Required systems·components**: `BattleSession` 部署狀態、玩家意圖事件／RPC 邊界、可部署單位的 `BattleUnit` 記錄與 `SpawnByModelId`；所有規則在伺服器重驗證。
- **Data**: `DeploymentMinDistance=0.6`、`DeploymentMaxUnits=6`、`DeploymentBounds=(-5,-2,-3,1)`；集中於 `BattleSession` 可調屬性。
- **UI**: 使用部署按鈕目前選擇與滑鼠世界座標；不改 UI 版面。
- **Done (verification) criteria**: Node 契約覆蓋邊界、間距、數量、移除與非法請求；Maker Play 由使用者確認合法／非法點擊結果與單位位置。
- **Dependencies**: Task 1 的意圖入口；既有 `BattleUnit.model` 與 `RectTile` map。
- **Skills to reference (predicted)**: `msw-general` 的 spawn／RectTile 參考、`msw-scripting` 的事件與 client/server exec-space 規則、`msw-combat-system` 的 battle-session 邊界。

### 3. 固定六隻敵軍與編成設定

- **Goal**: 部署階段建立右側固定敵軍，位置由設定提供，預設為二坦克、二突擊、二射手；玩家不能選取、移動或移除敵軍。
- **Required systems·components**: `BattleSession` 的固定 roster、`BattleUnit` 的 `UnitKind`／兵種設定、既有可生成 model；後續 Phase 3 才啟用各兵種完整攻擊規則。
- **Data**: 六個敵軍位置與 `TANK/TANK/ASSAULT/ASSAULT/SHOOTER/SHOOTER` 編成集中於 session 設定；本階段不建立 UserDataSet。
- **UI**: 無新增 UI；敵軍不可由玩家輸入修改。
- **Done (verification) criteria**: server snapshot 能列出六隻固定敵軍與兵種；Maker Play 由使用者確認敵軍只出現在右側且每次 Play 的位置一致。
- **Dependencies**: Task 2 的 session roster；`BattleUnit.model` 可由 `SpawnByModelId` 複用。
- **Skills to reference (predicted)**: `msw-general` spawn／model 規則、`msw-scripting` component state、`msw-combat-system` faction／target gating。

### 4. 開戰鎖定部署操作

- **Goal**: `DEPLOYMENT → BATTLE` 成功轉換後拒絕所有新增、移除、換位與重複開始請求；結果階段同樣拒絕部署意圖。
- **Required systems·components**: server-authoritative `BattleSession.Phase` gate、所有部署意圖的統一驗證入口、同步中的 phase／roster snapshot。
- **Data**: 只允許 `DEPLOYMENT` 處理部署操作；`BATTLE` 與 `RESULT` 皆回傳拒絕原因。
- **UI**: 按鈕如何顯示停用由人類決定；邏輯仍需在伺服器拒絕輸入。
- **Done (verification) criteria**: Node 契約確認每個部署入口都受 phase gate；Maker Play 使用者確認開始後點擊不會改變 roster 或單位位置。
- **Dependencies**: Task 1–3；所有部署／開始意圖必須共用同一 phase gate。
- **Skills to reference (predicted)**: `msw-scripting` sync／event 規則、`msw-combat-system` phase and result boundary。

### 5. 一至六隻任意重複兵種的完整單局

- **Goal**: 玩家可用一至六隻任意重複兵種開始戰鬥，固定敵軍加入後正常進入 `BATTLE`，並在一方全滅後只產生一次結果。
- **Required systems·components**: Phase 1 的 `BattleSession`／`BattleUnit`／`AssaultAttack` 回歸路徑，加上 Phase 2 roster 與 phase transition；不在本階段加入坦克／射手的完整兵種差異。
- **Data**: 測試矩陣涵蓋 1、2、3、4、5、6 隻，以及全坦克、全突擊、全射手與混合編隊。
- **UI**: 使用既有 UI 完成部署與開始；結果顯示仍沿用目前 M1 的 runtime boundary，完整結果 UI 串接留在 Phase 4。
- **Done (verification) criteria**: Node 契約通過 roster／結果／單次結算檢查；Maker Play 由使用者逐項確認至少一隻、六隻、重複兵種與完整一局。
- **Dependencies**: Tasks 1–4；Phase 1 所有 `✅ Tested` 契約保持通過。
- **Skills to reference (predicted)**: `msw-scripting`、`msw-combat-system`、`msw-general`。

## Risks / cautions

- `map01` 必須維持 `TileMapMode=1`，所有動態單位維持 `KinematicbodyComponent`；不可用檔案編輯切換地圖模式。
- `SpawnByModelId` 產生的每個單位都要先加入並確認 `BattleUnit`／攻擊元件，再加入 session roster；不存在的 model 或 script component 必須讓請求失敗而不是留下半初始化單位。
- Client 點擊座標不能直接成為可信世界座標；伺服器必須重驗證部署範圍、最小間距、數量、擁有者與 phase。
- `ui/` 目前只有範本 UI；在 `BtnTank` 等實體交付前，Task 1 與依賴它的 Maker Play 驗證不能標記 ✅。
- 不要把 Phase 3 的坦克接觸傷害、射手遠距攻擊或 Phase 4 的資產串接偷偷塞入本階段；若實作時發現必要的新範圍，先更新 GDD 與本文件 checklist。
