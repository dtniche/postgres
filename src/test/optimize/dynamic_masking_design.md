## 动态数据脱敏设计（pg_mask_policy + SQL 重写）

### 1. 背景与目标

- **目标**: 在 PostgreSQL 中实现“动态数据脱敏”。当用户查询包含受保护列的数据时，于 SQL 重写阶段为这些列自动套上脱敏表达式，从而在查询结果中返回脱敏后的值，而不改变存储与执行计划的语义。
- **原则**:
  - 仅影响输出（targetlist 中的可见列）；不影响过滤条件的语义与索引选择，避免逻辑语义变化和性能退化。
  - 脱敏策略以系统表记录，支持按“表+列”粒度配置。
  - 提供常用内建脱敏函数，便于策略表达式复用。
  - 与权限控制、RLS、视图、函数、COPY、逻辑复制等内核特性良好协作。

### 2. 范围

- 覆盖的 SQL 类型: SELECT、INSERT/UPDATE/DELETE ... RETURNING、COPY TO。
- 不覆盖（不应用脱敏）: WHERE/ON/HAVING/QUALS、JOIN 条件、分区路由、索引表达式、CHECK/GENERATED/DEFAULT 表达式内部。
- 视图、物化视图: 查询视图时应用；创建物化视图时按“创建时”应用（数据被脱敏存入），后续刷新依策略而定（见 9.3）。

### 3. 系统表设计：`pg_mask_policy`

- 目的: 以 catalog 记录“列级脱敏策略表达式”。
- 表结构（概念设计，物理实现遵循 Postgres 系统表规范）：
  - `oid` OID: 行标识。
  - `polname` name: 策略名称（便于管理和唯一性约束，建议在 `(polreloid, polattrid)` 上唯一）。
  - `polreloid` OID: 目标表 OID（引用 `pg_class.oid`）。
  - `polattrid` int2: 目标列 attnum（引用 `pg_attribute.attnum`，>0 为普通列）。
  - `masking_expression` pg_node_tree: 脱敏表达式的解析树（Parse tree）。表达式中允许引用目标列本身（作为 `Var`），以及常量、内建脱敏函数等。

建议补充字段（可选）：
- `polowner` OID: 策略所有者（引用 `pg_authid.oid`）。
- `polenabled` bool: 是否启用（默认 true）。
- `created_at`/`updated_at` timestamptz: 审计与变更跟踪。

索引与约束：
- 唯一约束: `(polreloid, polattrid)`，确保同一列仅有一个生效策略。
- 普通索引: `polreloid`，加速按表查找策略。

DDL（示意伪代码，仅用于文档，实际需遵循 bootstrap catalog 方式）：
```sql
-- 仅文档示意
CREATE TABLE pg_catalog.pg_mask_policy (
  oid                oid PRIMARY KEY,
  polname            name NOT NULL,
  polreloid          oid  NOT NULL REFERENCES pg_catalog.pg_class(oid),
  polattrid          int2 NOT NULL,
  masking_expression pg_node_tree NOT NULL,
  polowner           oid  DEFAULT CURRENT_USERID,
  polenabled         bool DEFAULT true
);
CREATE UNIQUE INDEX pg_mask_policy_reloid_attr_idx
  ON pg_catalog.pg_mask_policy(polreloid, polattrid)
  WHERE polenabled;
```

### 4. 内建脱敏函数

为简化策略表达与复用，提供以下内建函数（放入 `pg_catalog`，拥有 `PROPARALLEL SAFE` 或 `IMMUTABLE/STABLE` 视语义而定）：

- `mask_random(numeric)` → `numeric`
  - 用途: 数值型脱敏（加入随机扰动，保持数量级）。
  - 语义建议：在给定范围内添加噪声，或映射到稳定伪随机值（可选基于列值+隐含盐的稳定 hash → 区间映射）。
  - 标注：若为稳定映射，函数应为 `IMMUTABLE`；若每次结果不同，应为 `VOLATILE` 并谨慎用于物化视图。

- `mask_part(text, pre_len int, mask_char text, post_len int)` → `text`
  - 用途: 字符串型局部遮挡，如手机号/邮箱等。
  - 行为: 保留前 `pre_len` 与后 `post_len` 个字符，中间以 `mask_char` 重复填充，`mask_char` 默认可设为 `'*'`。
  - 边界: 输入长度不足时尽最大可能保留边界并避免越界。

扩展建议：
- `mask_hash(text[, salt text])`、`mask_uuid(uuid)`、`mask_date(date, granularity text)` 等。

### 5. 权限与可见性

- 超级用户、表所有者或具备专用 BYPASS 权限（可引入 `pg_permissions` 位或 GUC `masking.bypass=true` 且仅超级用户可设置）可跳过脱敏。
- 普通用户在无 BYPASS 权限时，始终对目标列返回脱敏后的值。
- 策略 DDL 建议仅允许表所有者或超级用户创建/更新/删除对应表列的策略。

### 6. SQL 重写与解析点位

总体策略：在“查询重写/解析后、规划之前”的阶段，对最终可见的 targetlist 条目进行包裹，不影响 quals 与路径选择。

推荐切入点：
- 在 parse analysis 完成后、RLS/视图展开之后，对 Query 的 `targetList` 进行遍历；
- 对每个 `TargetEntry`（`resjunk == false`）中出现的 `Var`（或可归约到单列的简单表达式）检查其来源列是否存在策略；
- 若存在，则构造策略表达式的 `Node`（从 `pg_node_tree` 反序列化为 `Expr`），将其中对“本列”的占位 `Var` 绑定为当前列的 `Var`，并以该表达式替换原 `Var`，或包裹原 `Expr`（见下）。

替换策略：
- 简单列 `Var`（最常见）：直接将 `tlist` 中的 `Var` 替换为 `masking_expr(Var)`。
- 表达式列（例如 `a + b`）：仅当目标列本身为单列直通时才替换；对于复合表达式不做深入拆分，避免语义争议。推荐在“列直出”场景应用（`SELECT a FROM ...`、`SELECT t.* FROM ...`）。
- `SELECT *` 展开后对每个具体列应用策略。

不影响处：
- quals（`WHERE/ON/HAVING`）、JOIN key、分组键、排序键、窗口函数分区键等维持原始表达式，避免语义变化与索引失效。

类型与可空性：
- 确保 `masking_expression` 的输出类型可隐式转换到列可见类型；否则在解析阶段报错。
- 允许 NULL：若输入列为 NULL，策略表达式需自行定义行为（多数函数应对 NULL 传递）。

### 7. 执行期与显示

- 由于在计划前完成重写，执行期按普通表达式计算，无需额外钩子。
- EXPLAIN 将显示包裹后的表达式，有助于审计与调试。

### 8. DDL 与 DML 影响

- ALTER TABLE RENAME/COLUMN TYPE 变更：
  - 若类型变更导致策略输出与新类型不兼容，阻塞变更并给出错误；或标记策略为禁用（`polenabled=false`），由管理员修复。
  - RENAME COLUMN 不改变 `attnum` 仅改变 `attname`，策略仍然生效。
- DROP COLUMN：自动级联删除对应策略行。
- INSERT/UPDATE RETURNING：对 RETURNING 列同样应用脱敏策略。
- COPY TO：对导出列应用脱敏；COPY FROM 不涉及。

### 9. 视图与物化视图、函数

- 普通视图：查询视图时在最终查询 targetlist 上应用策略；若视图定义中已对列二次处理，策略仍仅对输出端直出的列生效。
- 物化视图：
  - 选择一：创建/刷新物化视图时应用（数据以脱敏后形式落地）。优点：下游消费默认安全；缺点：策略变更需要刷新。
  - 选择二：不在物化阶段应用，而在查询物化视图时再应用（需把策略绑定到源表列映射，复杂）。
  - 建议：默认在物化阶段应用，文档清晰化提示变更需 REFRESH。
- SQL 函数：函数体内查询不自动应用（除非进入重写器的顶层查询）。若需要，可提供 GUC 以在函数内启用。

### 10. 性能与开销评估

- 重写阶段开销：按 targetlist 列数与策略查找（哈希或 syscache）线性，极低。
- 执行阶段开销：等同于表达式计算成本。`mask_part` 为 O(n) 字符处理；`mask_random` 视算法而定。
- 规避影响索引：不在 quals 中应用，避免计划退化。

### 11. 管理与接口

- 管理函数/命令（建议）：
  - `CREATE MASK POLICY polname ON tbl(col) USING (expr)`
  - `ALTER MASK POLICY polname SET ENABLED {true|false}`
  - `DROP MASK POLICY polname`
  - 或提供 `pg_mask_policy_upsert(polreloid, polattrid, expr)` 等内部函数
- 可视图：`pg_mask_policy` + 友好视图 `pg_mask_policy_ext`（解析 `polreloid`、`polattrid` 到 `schemaname.relname.column`）。

示例：
```sql
-- 数值列随机扰动
INSERT INTO pg_catalog.pg_mask_policy(polname, polreloid, polattrid, masking_expression)
VALUES ('salary_mask', 'emp'::regclass::oid,
        (SELECT attnum FROM pg_attribute WHERE attrelid='emp'::regclass AND attname='salary'),
        'mask_random($COLUMN$)'::pg_node_tree);

-- 字符串列部分遮挡（保留前3后2）
INSERT INTO pg_catalog.pg_mask_policy(polname, polreloid, polattrid, masking_expression)
VALUES ('phone_mask', 'emp'::regclass::oid,
        (SELECT attnum FROM pg_attribute WHERE attrelid='emp'::regclass AND attname='phone'),
        'mask_part($COLUMN$, 3, ''*'', 2)'::pg_node_tree);
```
说明：`$COLUMN$` 为文档占位语法，实际实现中以真实 `Var` 编码于 `pg_node_tree`，不是文本替换。

### 12. 错误处理与日志

- 策略表达式解析失败或类型不匹配：在创建/更新策略时即报错。
- 查询重写阶段若找不到列或表（DDL 变更导致）：记录 WARNING 并禁用策略或直接 ERROR（建议 ERROR 以保证安全）。
- 审计：可在 `log_statement=all` 环境下通过 EXPLAIN/auto_explain 观察包裹表达式；可选引入轻量审计日志记录“策略命中情况”。

### 13. 迁移与备份

- `pg_dump`：导出 `pg_mask_policy` 内容以及内建函数定义。
- `pg_upgrade`：提供 catalog 版本升级脚本，初始化内建函数与新系统表。

### 14. 测试计划（放置于 `src/test/optimize/`）

- 单元用例：
  - 建立策略后 `SELECT col`、`SELECT *` 输出被脱敏。
  - quals 不受影响（过滤仍用原值）。
  - `RETURNING`、`COPY TO` 被脱敏。
  - 视图查询被脱敏；物化视图创建后数据已脱敏。
  - 超级用户/表所有者具 BYPASS 能力时不脱敏。
  - 类型不兼容策略创建时报错。

- 回归与性能：
  - 大量列/策略存在时的开销评估。
  - `mask_part` 与 `mask_random` 的边界与稳定性测试。

### 15. 实现要点与代码改动定位（高层）

- Catalog：
  - 新增 `pg_mask_policy`，完成 syscache 支持（按 `polreloid`、`(polreloid, polattrid)` 查询）。
  - DDL 支持与权限检查。

- 解析/重写：
  - 在 parse analysis 后（`transformSelectStmt` 完成）、RLS/视图展开后，遍历 `Query->targetList`。
  - 对 `TargetEntry` 的 `Expr` 进行 `Var` 扫描，匹配 `RTE_RELATION` 来源，按 `(relid, attnum)` 查询策略。
  - 命中时：反序列化 `masking_expression`（`stringToNode`），替换或包裹为新 `Expr`，并进行类型校验与 `coerce_to_target_type`。

#### 15.1 在 `subquery_planner` 阶段使用 `replace_rte_variables`

为降低对解析阶段的侵入，并确保在规划前统一处理目标列，可在 `subquery_planner` 进入子查询规划前，对“可见输出列”进行基于 RTE 的替换，使用 `replace_rte_variables` 钩住特定 `RTE` 的 `Var` 并进行表达式替换。

核心 API：

```1416:1441:src/backend/rewrite/rewriteManip.c
/*
 * replace_rte_variables() finds all Vars in an expression tree
 * that reference a particular RTE, and replaces them with substitute
 * expressions obtained from a caller-supplied callback function.
 */
Node *
replace_rte_variables(Node *node, int target_varno, int sublevels_up,
                      replace_rte_variables_callback callback,
                      void *callback_arg,
                      bool *outer_hasSubLinks);
```

行为要点：
- 在表达式树中查找 `Var`，当 `var->varno == target_varno` 且 `var->varlevelsup == sublevels_up` 时，调用回调替换为自定义表达式；
- 若回调返回的表达式包含 `SubLink`，需配合 `outer_hasSubLinks` 标志正确维护 `Query->hasSubLinks`；
- 会递归进入子查询并维护 `sublevels_up`，可精确控制作用层级。

集成策略：仅对“输出端”应用，避免改变 quals/联接/分组等语义。

- 目标位置：
  - `Query->targetList`（`resjunk == false`）。
  - `Query->returningList`（若存在）。
  - setop 顶层输出 `targetList`。
  - 不处理：`jointree->quals`、`havingQual`、`sortClause`、`groupClause` 等。

- 目标 RTE 与层级：
  - 遍历 `rtable`，对每个 `RTE_RELATION` 的 `varno` 执行一次替换；
  - 对当前正在规划的查询，`sublevels_up=0`；对子查询可在递归进入其 `subquery_planner` 时分别处理。

- 回调函数逻辑（伪代码）：

```c
// context 包含: relid->per-column 策略缓存，类型校验辅助等
static Node *MaskingReplaceCallback(Var *var, replace_rte_variables_context *ctx)
{
    if (var->varattno <= 0) {
        // 系统列或 whole-row，当前跳过
        return (Node *) copyObject(var);
    }
    Policy *p = find_policy(ctx->relid, var->varattno);
    if (!p || !p->enabled)
        return (Node *) copyObject(var);

    Expr *mask = (Expr *) stringToNode(p->masking_expression);
    mask = substitute_column_placeholder(mask, var);
    return coerce_to_target_type_if_needed(mask, exprType((Node *)var));
}
```

- 调用示意（仅文档伪代码）：

```c
// 在 subquery_planner(Query *parse, ...) 入参 parse 处理开始处：
for (int rti = 1; rti <= list_length(parse->rtable); rti++) {
    RangeTblEntry *rte = rt_fetch(rti, parse->rtable);
    if (rte->rtekind != RTE_RELATION)
        continue;
    MaskCtx mctx = build_mask_ctx_from_catalog(rte->relid);

    parse->targetList = (List *) replace_rte_variables((Node *) parse->targetList,
                                                       rti /* target_varno */, 0 /* sublevels_up */,
                                                       MaskingReplaceCallback, &mctx,
                                                       &parse->hasSubLinks);

    if (parse->returningList)
        parse->returningList = (List *) replace_rte_variables((Node *) parse->returningList,
                                                              rti, 0,
                                                              MaskingReplaceCallback, &mctx,
                                                              &parse->hasSubLinks);
}
```

注意事项：
- 不要对 `jointree->quals`、`havingQual` 等处调用替换；
- `masking_expression` 若含 `SubLink`，通过 `&parse->hasSubLinks` 正确传播；
- 需确保 `masking_expression` 引用的函数均为可在计划期/执行期解析的有效表达式；
- `SELECT *` 展开发生在解析期，`targetList` 已为具体列，替换将逐列生效。

- 内建函数：
  - 在 `pg_proc.h` 注册 `mask_random`、`mask_part`，实现于 `src/backend/utils/adt/` 新文件，如 `maskfuncs.c`。
  - 标注并实现并行/稳定性属性，完善 `pg_proc.dat`。

#### 15.2 在 `fireRIRrules` 阶段（RIR - "Rule Instead Rewrite" 的缩写）预构建 `RTE.mask_exprs`

为了避免在 `MaskingReplaceCallback` 中重复访问系统表/反序列化表达式，建议在规则展开阶段对每个 `RTE_RELATION` 的列预先构建脱敏表达式数组，并挂到 `RangeTblEntry` 上供后续规划阶段直接使用。

参考位置与签名：

```1991:1995:src/backend/rewrite/rewriteHandler.c
static Query *
fireRIRrules(Query *parsetree, List *activeRIRs)
{
    int			origResultRelation = parsetree->resultRelation;
    int			rt_index;
```

放置点建议：在通过“是否被引用”的检查后（避免未用 RTE 的无效开销），并在确定 `rte->rtekind == RTE_RELATION`、且非 `RELKIND_MATVIEW`、非 EXCLUDED 的分支中，调用辅助例程为该 RTE 构建掩码表达式数组。

数据结构（设计）：
- 在 `RangeTblEntry` 中新增成员：
  - `Expr **mask_exprs;` 长度为 `rte->maxattr`（或基于 `rel->rd_att->natts`），按 `attnum`（1..natts）索引；
  - `int mask_natts;` 记录数组大小；
- 若某列无策略，则数组对应位置为 NULL。

构建流程：
1. 收集策略：按 `rte->relid` 查询 `pg_mask_policy`，得到 `(attnum -> pg_node_tree)` 映射；
2. 反序列化：使用 `stringToNode()` 将 `pg_node_tree` 解析为 `Expr *`；
3. 绑定占位：将表达式中对“本列”的占位变量（设计为 encode 成 `Var`/`Param`）替换为当前 RTE 的该列 `Var(varno=rt_index, varattno=attnum, varlevelsup=0)`；
4. 类型校验：确保表达式输出能隐式转换到列外显类型，必要时包装 `CoerceViaIO` 或 `RelabelType`；
5. 存储：将得到的 `Expr *` 存入 `rte->mask_exprs[attnum-1]`；
6. 内存上下文：在 `parsetree` 所在上下文或等价长寿命上下文分配，保证贯穿至规划阶段可见。

伪代码：
```c
if (rte->rtekind == RTE_RELATION && rte->relkind != RELKIND_MATVIEW && is_rte_used(parsetree, rt_index)) {
    AttrNumber natts = get_relation_natts(rte->relid);
    rte->mask_natts = natts;
    rte->mask_exprs = palloc0(sizeof(Expr *) * natts);

    List *pols = load_mask_policies_for_rel(rte->relid); // from pg_mask_policy
    foreach(policy in pols) {
        AttrNumber attno = policy->attnum;
        if (attno <= 0 || attno > natts)
            continue;
        Expr *mask = (Expr *) stringToNode(policy->pg_node_tree);
        mask = bind_column_placeholder(mask, rt_index, attno);
        mask = ensure_type(mask, get_atttype(rte->relid, attno));
        rte->mask_exprs[attno - 1] = mask; // may overwrite if multiple => earlier校验杜绝
    }
}
```

回调侧消费（衔接 15.1）：
- 在 `MaskingReplaceCallback` 中，不再访问系统表；改为直接读取 `rte->mask_exprs[var->varattno - 1]`：

```c
static Node *MaskingReplaceCallback(Var *var, replace_rte_variables_context *ctx)
{
    RangeTblEntry *rte = rt_fetch(ctx->target_varno, ctx->parse->rtable);
    if (var->varattno <= 0 || !rte->mask_exprs)
        return (Node *) copyObject(var);
    Expr *mask = rte->mask_exprs[var->varattno - 1];
    if (!mask)
        return (Node *) copyObject(var);
    return (Node *) copyObject(mask); // 复制以免共享节点被下游改写
}
```

注意事项：
- 视图展开：`fireRIRrules` 会将视图 RTE 替换为 `RTE_SUBQUERY`；仅对 `RTE_RELATION` 构建 `mask_exprs`，对子查询将在其自身 `fireRIRrules` 递归中处理。
- 物化视图：保持忽略（同上）；若将来支持在查询 MVs 时应用，可在其 RTE 也构建。
- 变更与一致性：`ALTER TABLE ... DROP/TYPE` 等在同一事务中变更 schema 时，策略加载应使用快照一致性并在不兼容时报错。
- 拷贝与共享：规划阶段可能复制/变换表达式，`MaskingReplaceCallback` 应返回拷贝节点，避免多处共享引发副作用。

### 16. 兼容性与边界

- 外表（FDW）：若重写作用于上层 Query，理论上可应用，但具体 FDW 可能下推表达式，需谨慎（默认不下推脱敏函数）。
- 逻辑复制：订阅端若直接查询源表需重复配置策略；或在发布端以物化视图/导出时已脱敏。
- 分区表：对子分区列与父表列分别记录策略；`SELECT *` 展开后逐列处理。
- 多重策略：通过唯一约束避免同列多策略；若存在多条（历史残留），选择“最新启用的一条”或直接 ERROR（建议 ERROR）。

### 17. 开放问题

- 是否提供“按角色/上下文”的条件脱敏（例如仅对非某角色用户生效）？可在表达式中读取 `current_user`/GUC 进行条件判断，但需评估安全性与缓存影响。
- `mask_random` 的确定性选择：为可重现分析，推荐默认“稳定伪随机”（基于值+盐）并提供非确定版本。
- 在 ORDER BY/ GROUP BY 中是否应用？为避免行为变化，当前不应用；若业务需要，可引入可配置开关。

### 18. 里程碑

1. Catalog 与 syscache 框架搭建，内建函数落地。
2. 重写逻辑与类型校验完成，基本 SELECT/RETURNING/COPY TO 支持。
3. 视图/物化视图与 BYPASS 权限集成。
4. 回归测试与性能评估，文档与工具函数完善。

---

附：示例效果（文档演示）

原始语句：
```sql
SELECT emp_id, salary, phone FROM emp;
```

重写后（EXPLAIN 可见）：
```sql
SELECT emp_id,
       mask_random(salary) AS salary,
       mask_part(phone, 3, '*', 2) AS phone
FROM emp;
```


