/*
 * Inequality transitivity support.
 *
 * NOTE: This is an experimental module that builds a lightweight graph of
 *       inequality relations and derives transitive constraints that can be
 *       pushed to base rels. The initial version focuses on deriving
 *       var op Const from {var = expr in EC} and {expr op Const} patterns,
 *       and basic var op var chaining within the same join domain.
 */

#include "postgres.h"

#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "optimizer/optimizer.h"
#include "optimizer/pathnode.h"
#include "optimizer/paths.h"
#include "optimizer/restrictinfo.h"
#include "parser/parse_oper.h"
#include "utils/lsyscache.h"

typedef enum InequalityType {
    INEQ_GT,     /* > */
    INEQ_GE,     /* >= */
    INEQ_LT,     /* < */
    INEQ_LE,     /* <= */
    INEQ_EQ      /* = (来自 EquivalenceClass) */
} InequalityType;

/* Historically some helpers use IneqOperator; alias it to the same enum */
typedef InequalityType IneqOperator;

#define INEQ_INVALID ((IneqOperator) -1)

typedef struct InequalityEdge {
    Expr       *left_expr;      /* 左操作数表达式 */
    Expr       *right_expr;     /* 右操作数表达式 */
    InequalityType op_type;     /* 不等式类型 */
    Relids      required_rels;  /* 所需的关系集 */
    bool        is_derived;     /* 是否为推导出的约束 */
    List       *source_edges;   /* 推导来源（用于调试和EXPLAIN）*/
} InequalityEdge;

typedef struct InequalityGraph {
    List       *edges;          /* InequalityEdge 列表 */
    List       *ec_list;        /* EquivalenceClass 列表 */
    HTAB       *expr_index;     /* 表达式到节点的索引 */
    MemoryContext context;      /* 内存上下文 */
} InequalityGraph;

/* 不等式组合规则 */
typedef struct IneqTransitionRule
{
    IneqOperator op1;        /* 第一个操作符 */
    IneqOperator op2;        /* 第二个操作符 */
    IneqOperator result_op;  /* 推导出的操作符 */
    bool         is_valid;   /* 是否可推导 */
} IneqTransitionRule;

/* 规则表：op1(a,b) AND op2(b,c) => result_op(a,c) */
static const IneqTransitionRule transition_rules[] = {
    /* op1    op2     result   valid */
    {INEQ_LT, INEQ_LT, INEQ_LT, true},   /* a<b, b<c => a<c */
    {INEQ_LT, INEQ_LE, INEQ_LT, true},   /* a<b, b<=c => a<c */
    {INEQ_LE, INEQ_LT, INEQ_LT, true},   /* a<=b, b<c => a<c */
    {INEQ_LE, INEQ_LE, INEQ_LE, true},   /* a<=b, b<=c => a<=c */
    
    {INEQ_GT, INEQ_GT, INEQ_GT, true},   /* a>b, b>c => a>c */
    {INEQ_GT, INEQ_GE, INEQ_GT, true},   /* a>b, b>=c => a>c */
    {INEQ_GE, INEQ_GT, INEQ_GT, true},   /* a>=b, b>c => a>c */
    {INEQ_GE, INEQ_GE, INEQ_GE, true},   /* a>=b, b>=c => a>=c */
    
    {INEQ_EQ, INEQ_LT, INEQ_LT, true},   /* a=b, b<c => a<c */
    {INEQ_EQ, INEQ_LE, INEQ_LE, true},   /* a=b, b<=c => a<=c */
    {INEQ_EQ, INEQ_GT, INEQ_GT, true},   /* a=b, b>c => a>c */
    {INEQ_EQ, INEQ_GE, INEQ_GE, true},   /* a=b, b>=c => a>=c */
    
    {INEQ_LT, INEQ_EQ, INEQ_LT, true},   /* a<b, b=c => a<c */
    {INEQ_LE, INEQ_EQ, INEQ_LE, true},   /* a<=b, b=c => a<=c */
    {INEQ_GT, INEQ_EQ, INEQ_GT, true},   /* a>b, b=c => a>c */
    {INEQ_GE, INEQ_EQ, INEQ_GE, true},   /* a>=b, b=c => a>=c */
    
    {INEQ_EQ, INEQ_EQ, INEQ_EQ, true},   /* a=b, b=c => a=c */
};

/* Forward declarations for helpers used below */
static IneqOperator lookup_transition_rule(IneqOperator op1, IneqOperator op2);
static bool expressions_equivalent(PlannerInfo *root, Expr *a, Expr *b);
static void build_expr_index(InequalityGraph *graph);
static void add_ec_to_graph(PlannerInfo *root, EquivalenceClass *ec, InequalityGraph *graph);
static void extract_inequality_constraints(PlannerInfo *root, Node *qual, InequalityGraph *graph);
static InequalityEdge *create_derived_edge(PlannerInfo *root, Expr *left, Expr *right,
                                          IneqOperator op, List *sources);
static RestrictInfo *make_restrictinfo_from_inequality(PlannerInfo *root, InequalityEdge *edge);
static bool constraint_can_use_index(InequalityEdge *edge);

static InequalityGraph *
build_inequality_graph(PlannerInfo *root)
{
    InequalityGraph *graph;
    ListCell *lc;
    
    graph = (InequalityGraph *) palloc(sizeof(InequalityGraph));
    graph->edges = NIL;
    graph->ec_list = root->eq_classes;
    graph->context = CurrentMemoryContext;
    
    /* 1. 从 WHERE 子句提取不等式约束
     * jointree->quals 是隐式 AND 的列表(Node*)，使用 pull_varnos 等更安全；
     * 这里走简化：若 quals 为列表就遍历列表，否则按单节点处理。
     */
    if (root->parse->jointree && root->parse->jointree->quals)
    {
        Node *quals = root->parse->jointree->quals;
        if (IsA(quals, List))
        {
            foreach(lc, (List *) quals)
                extract_inequality_constraints(root, (Node *) lfirst(lc), graph);
        }
        else
        {
            extract_inequality_constraints(root, quals, graph);
        }
    }
    
    /* 2. 从 EquivalenceClass 提取等值约束 */
    foreach(lc, root->eq_classes)
    {
        EquivalenceClass *ec = (EquivalenceClass *) lfirst(lc);
        add_ec_to_graph(root, ec, graph);
    }
    
    /* 3. 建立表达式索引 */
    build_expr_index(graph);
    
    return graph;
}

/*
 * try_combine_edges
 *    尝试组合两条边推导新约束
 */
 static InequalityEdge *
 try_combine_edges(PlannerInfo *root,
                  InequalityGraph *graph,
                  InequalityEdge *edge1,
                  InequalityEdge *edge2)
 {
     InequalityEdge *result = NULL;
     IneqOperator result_op;
     
     /* 情况1: edge1: a op1 b, edge2: b op2 c
      *        推导: a result_op c
      * 
      * 要求: edge1.right = edge2.left
      */
     if (equal(edge1->right_expr, edge2->left_expr))
     {
        result_op = lookup_transition_rule(edge1->op_type, 
                                          edge2->op_type);
         
         if (result_op != INEQ_INVALID)
         {
             result = create_derived_edge(root,
                                         edge1->left_expr,
                                         edge2->right_expr,
                                         result_op,
                                         list_make2(edge1, edge2));
         }
     }
     
     /* 情况2: edge1: a = b (from EC), edge2: b op c
      *        推导: a op c
      * 
      * 利用等价类关系
      */
     else if (edge1->op_type == INEQ_EQ &&
              equal(edge1->right_expr, edge2->left_expr))
     {
         result = create_derived_edge(root,
                                     edge1->left_expr,
                                     edge2->right_expr,
                                     edge2->op_type,
                                     list_make2(edge1, edge2));
     }
     
     /* 情况3: edge1: a op b, edge2: b = c (from EC)
      *        推导: a op c
      */
     else if (edge2->op_type == INEQ_EQ &&
              equal(edge1->right_expr, edge2->left_expr))
     {
         result = create_derived_edge(root,
                                     edge1->left_expr,
                                     edge2->right_expr,
                                     edge1->op_type,
                                     list_make2(edge1, edge2));
     }
     
     /* 情况4: 通过等价类间接连接
      *        edge1: a op1 b, edge2: c op2 d
      *        如果 b 和 c 在同一个等价类
      *        推导: a result_op d
      */
     else if (expressions_equivalent(root, 
                                    edge1->right_expr,
                                    edge2->left_expr))
     {
         result_op = lookup_transition_rule(edge1->op_type,
                                           edge2->op_type);
         
         if (result_op != INEQ_INVALID)
         {
             result = create_derived_edge(root,
                                         edge1->left_expr,
                                         edge2->right_expr,
                                         result_op,
                                         list_make2(edge1, edge2));
         }
     }
     
     return result;
 }

/* 将推导出的约束添加到查询计划 */
static void
static void
apply_derived_constraints(PlannerInfo *root, InequalityGraph *graph)
{
    ListCell *lc;
    
    foreach(lc, graph->edges)
    {
        InequalityEdge *edge = (InequalityEdge *) lfirst(lc);
        
        if (!edge->is_derived)
            continue;
        
        /* 只应用可以在当前层级执行的约束 */
        if (!bms_is_subset(edge->required_rels, root->all_baserels))
            continue;
        
        /* 构造 RestrictInfo */
        RestrictInfo *rinfo = make_restrictinfo_from_inequality(root, edge);
        
        /* 添加到合适的 RelOptInfo */
        if (bms_membership(edge->required_rels) == BMS_SINGLETON)
        {
            /* 单表约束 */
            int relid = bms_singleton_member(edge->required_rels);
            RelOptInfo *rel = find_base_rel(root, relid);
            rel->baserestrictinfo = lappend(rel->baserestrictinfo, rinfo);
        }
        else
        {
        /* 多表约束：暂不分发，后续在 join 阶段可考虑生成 */
        }
    }
}

/* 使用启发式限制传递闭包计算 */
#define MAX_INEQUALITY_EDGES 1000
#define MAX_TRANSITIVITY_DEPTH 5

static bool
should_derive_constraint(InequalityEdge *new_edge, InequalityGraph *graph)
{
    /* 如果约束太多，只保留最有价值的 */
    if (list_length(graph->edges) > MAX_INEQUALITY_EDGES)
        return false;
    
    /* 如果推导链太长，停止 */
    if (list_length(new_edge->source_edges) > MAX_TRANSITIVITY_DEPTH)
        return false;
    
    /* 优先保留涉及常量的约束 */
    if (IsA(new_edge->right_expr, Const))
        return true;
    
    /* 优先保留涉及索引列的约束 */
    if (constraint_can_use_index(new_edge))
        return true;
    
    return true;
}

/*
 * derive_transitive_constraints_incremental
 *    增量式推导（只处理新加入的边）
 */
void
 derive_transitive_constraints_incremental(PlannerInfo *root,
                                          InequalityGraph *graph)
 {
    int initial_count = list_length(graph->edges);
    int iteration = 0;

    while (iteration < MAX_TRANSITIVITY_DEPTH)
    {
        List *new_edges = NIL;
        ListCell *lc1, *lc2;
        bool changed = false;
        iteration++;

        foreach(lc1, graph->edges)
        {
            InequalityEdge *e1 = (InequalityEdge *) lfirst(lc1);
            foreach(lc2, graph->edges)
            {
                InequalityEdge *e2 = (InequalityEdge *) lfirst(lc2);
                InequalityEdge *d;

                d = try_combine_edges(root, graph, e1, e2);
                if (d && should_derive_constraint(d, graph))
                {
                    new_edges = lappend(new_edges, d);
                    changed = true;
                }

                d = try_combine_edges(root, graph, e2, e1);
                if (d && should_derive_constraint(d, graph))
                {
                    new_edges = lappend(new_edges, d);
                    changed = true;
                }
            }
        }

        if (!changed)
            break;

        graph->edges = list_concat(graph->edges, new_edges);
    }

    elog(DEBUG2, "Incremental derivation: %d initial edges, %d final edges",
         initial_count, list_length(graph->edges));
 }

 /*
 * apply_derived_inequality_constraints
 *    将推导出的不等式约束应用到查询计划
 */
void
apply_derived_inequality_constraints(PlannerInfo *root,
                                    InequalityGraph *graph)
{
    ListCell *lc;
    int applied_count = 0;
    
    foreach(lc, graph->edges)
    {
        InequalityEdge *edge = (InequalityEdge *) lfirst(lc);
        
        /* 只处理推导出的约束 */
        if (!edge->is_derived)
            continue;
        
        /* 优先应用涉及常量的约束 */
        if (!IsA(edge->right_expr, Const))
            continue;
        
        /* 检查约束是否可以在当前层级应用 */
        if (!bms_is_subset(edge->required_rels, root->all_baserels))
            continue;
        
        /* 转换为 RestrictInfo */
        RestrictInfo *rinfo = make_restrictinfo_from_inequality(root, edge);
        
        if (rinfo == NULL)
            continue;
        
        /* 标记为推导约束 */
        /* 标记字段保留为默认 */
        
        /* 根据涉及的表数量分发约束 */
        if (bms_membership(edge->required_rels) == BMS_SINGLETON)
        {
            /* 单表约束：添加到 baserestrictinfo */
            int relid = bms_singleton_member(edge->required_rels);
            RelOptInfo *rel = find_base_rel(root, relid);
            
            rel->baserestrictinfo = lappend(rel->baserestrictinfo, rinfo);
            applied_count++;
            
            elog(DEBUG2, "Applied derived inequality to base rel %d", relid);
        }
        else
        {
            /* 多表约束：添加到 joininfo */
            distribute_restrictinfo_to_rels(root, rinfo);
            applied_count++;
            
            elog(DEBUG2, "Applied derived inequality to join");
        }
    }
    
    elog(DEBUG1, "Applied %d derived inequality constraints", applied_count);
}

/* ------------------------
 * Helper implementations
 * ------------------------
 */

static IneqOperator
lookup_transition_rule(IneqOperator op1, IneqOperator op2)
{
    int i;
    for (i = 0; i < (int) lengthof(transition_rules); i++)
    {
        if (transition_rules[i].op1 == op1 &&
            transition_rules[i].op2 == op2 &&
            transition_rules[i].is_valid)
            return transition_rules[i].result_op;
    }
    return (IneqOperator) -1; /* invalid */
}

static bool
expressions_equivalent(PlannerInfo *root, Expr *a, Expr *b)
{
    /* Cheap first pass: exact match */
    if (equal(a, b))
        return true;

    /* Future: consult EquivalenceClasses. For now, keep conservative. */
    (void) root;
    return false;
}

static void
build_expr_index(InequalityGraph *graph)
{
    /* Placeholder: could build a hash from Expr to edges to speed lookups. */
    graph->expr_index = NULL;
}

static void
add_ec_to_graph(PlannerInfo *root, EquivalenceClass *ec, InequalityGraph *graph)
{
    /* Add equality edges for EC members to allow a=b style chaining. */
    ListCell *lc1;
    (void) root;
    foreach(lc1, ec->ec_members)
    {
        EquivalenceMember *em1 = (EquivalenceMember *) lfirst(lc1);
        ListCell *lc2;
        foreach(lc2, ec->ec_members)
        {
            EquivalenceMember *em2 = (EquivalenceMember *) lfirst(lc2);
            InequalityEdge *e;
            if (em1 == em2)
                continue;
            e = (InequalityEdge *) palloc0(sizeof(InequalityEdge));
            e->left_expr = em1->em_expr;
            e->right_expr = em2->em_expr;
            e->op_type = INEQ_EQ;
            e->required_rels = em1->em_relids; /* conservative */
            e->is_derived = false;
            graph->edges = lappend(graph->edges, e);
        }
    }
}

static IneqOperator
map_btree_strat_to_ineq(Oid opno)
{
    const char *name = get_opname(opno);
    if (name == NULL)
        return INEQ_INVALID;
    if (strcmp(name, "<") == 0)
        return INEQ_LT;
    if (strcmp(name, "<=") == 0)
        return INEQ_LE;
    if (strcmp(name, ">") == 0)
        return INEQ_GT;
    if (strcmp(name, ">=") == 0)
        return INEQ_GE;
    if (strcmp(name, "=") == 0)
        return INEQ_EQ;
    return INEQ_INVALID;
}

static void
extract_inequality_constraints(PlannerInfo *root, Node *qual, InequalityGraph *graph)
{
    /* Only simple OpExpr with two args; ignore volatile/complex for now. */
    if (qual && IsA(qual, OpExpr))
    {
        OpExpr *op = (OpExpr *) qual;
        if (list_length(op->args) == 2)
        {
            Expr *left = (Expr *) linitial(op->args);
            Expr *right = (Expr *) lsecond(op->args);
            IneqOperator k = map_btree_strat_to_ineq(op->opno);
            if ((int) k >= 0)
            {
                InequalityEdge *e = (InequalityEdge *) palloc0(sizeof(InequalityEdge));
                e->left_expr = left;
                e->right_expr = right;
                e->op_type = k;
                e->required_rels = pull_varnos(root, (Node *) op);
                e->is_derived = false;
                graph->edges = lappend(graph->edges, e);
            }
        }
    }
}

static InequalityEdge *
create_derived_edge(PlannerInfo *root, Expr *left, Expr *right,
                    IneqOperator op, List *sources)
{
    InequalityEdge *e = (InequalityEdge *) palloc0(sizeof(InequalityEdge));
    (void) root;
    e->left_expr = left;
    e->right_expr = right;
    e->op_type = op;
    e->required_rels = bms_union(pull_varnos(root, (Node *) left),
                                 pull_varnos(root, (Node *) right));
    e->is_derived = true;
    e->source_edges = sources;
    return e;
}

static Oid
ineq_operator_oid_for_types(IneqOperator op, Oid ltype, Oid rtype)
{
    /* Try to find a matching operator in the btree opfamilies via lookup */
    const char *opname = NULL;
    switch (op)
    {
        case INEQ_LT: opname = "<"; break;
        case INEQ_LE: opname = "<="; break;
        case INEQ_GT: opname = ">"; break;
        case INEQ_GE: opname = ">="; break;
        case INEQ_EQ: opname = "="; break;
        default: return InvalidOid;
    }
    return OpernameGetOprid(list_make1(makeString(pstrdup(opname))), ltype, rtype);
}

static RestrictInfo *
make_restrictinfo_from_inequality(PlannerInfo *root, InequalityEdge *edge)
{
    Oid ltype = exprType((Node *) edge->left_expr);
    Oid rtype = exprType((Node *) edge->right_expr);
    Oid opno = ineq_operator_oid_for_types(edge->op_type, ltype, rtype);
    OpExpr *op;
    if (!OidIsValid(opno))
        return NULL;

    op = make_opclause(opno,
                       BOOLOID,
                       false,
                       copyObject(edge->left_expr),
                       copyObject(edge->right_expr),
                       InvalidOid,
                       InvalidOid);

    return make_restrictinfo(root,
                             (Expr *) op,
                             true,   /* is_pushed_down */
                             false,  /* has_clone */
                             false,  /* is_clone */
                             false,  /* pseudoconstant */
                             0,      /* security_level */
                             NULL,   /* required_relids (let RInfo compute) */
                             NULL,   /* incompatible_relids */
                             NULL);  /* outer_relids */
}

static bool
constraint_can_use_index(InequalityEdge *edge)
{
    /* Heuristic: if either side is a Var, likely indexable. */
    return IsA(edge->left_expr, Var) || IsA(edge->right_expr, Var);
}

/* Public entry (optional): build → derive → apply in one call. */
void
pg_derive_and_apply_inequality_transitivity(PlannerInfo *root)
{
    InequalityGraph *graph = build_inequality_graph(root);
    derive_transitive_constraints_incremental(root, graph);
    apply_derived_inequality_constraints(root, graph);
}