typedef enum InequalityType {
    INEQ_GT,     /* > */
    INEQ_GE,     /* >= */
    INEQ_LT,     /* < */
    INEQ_LE,     /* <= */
    INEQ_EQ      /* = (来自 EquivalenceClass) */
} InequalityType;

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

static InequalityGraph *
build_inequality_graph(PlannerInfo *root)
{
    InequalityGraph *graph;
    ListCell *lc;
    
    graph = (InequalityGraph *) palloc(sizeof(InequalityGraph));
    graph->edges = NIL;
    graph->ec_list = root->eq_classes;
    graph->context = CurrentMemoryContext;
    
    /* 1. 从 WHERE 子句提取不等式约束 */
    foreach(lc, root->parse->jointree->quals)
    {
        Node *qual = (Node *) lfirst(lc);
        extract_inequality_constraints(root, qual, graph);
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
        RestrictInfo *rinfo = make_restrictinfo_from_edge(root, edge);
        
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
            /* 多表约束 */
            distribute_restrictinfo_to_rels(root, rinfo);
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
     List *new_edges = NIL;
     ListCell *lc_new, *lc_all;
     int initial_count = list_length(graph->edges);
     
     /* 标记初始边 */
     foreach(lc_all, graph->edges)
     {
         InequalityEdge *edge = (InequalityEdge *) lfirst(lc_all);
         edge->processed = true;
     }
     
     bool changed = true;
     int iteration = 0;
     
     while (changed && iteration < enable_inequality_max_depth)
     {
         changed = false;
         iteration++;
         
         /* 只用新边与所有边组合 */
         foreach(lc_new, graph->edges)
         {
             InequalityEdge *new_edge = (InequalityEdge *) lfirst(lc_new);
             
             /* 跳过已处理的边 */
             if (new_edge->processed)
                 continue;
             
             /* 与所有边（包括自己）组合 */
             foreach(lc_all, graph->edges)
             {
                 InequalityEdge *existing = (InequalityEdge *) lfirst(lc_all);
                 InequalityEdge *derived;
                 
                 /* 尝试组合 */
                 derived = try_combine_edges(root, graph, 
                                            new_edge, existing);
                 if (derived && should_derive_constraint(root, graph, derived))
                 {
                     derived->processed = false;
                     new_edges = lappend(new_edges, derived);
                     changed = true;
                 }
                 
                 /* 反向组合 */
                 derived = try_combine_edges(root, graph,
                                            existing, new_edge);
                 if (derived && should_derive_constraint(root, graph, derived))
                 {
                     derived->processed = false;
                     new_edges = lappend(new_edges, derived);
                     changed = true;
                 }
             }
             
             /* 标记为已处理 */
             new_edge->processed = true;
         }
         
         /* 添加新推导的边 */
         graph->edges = list_concat(graph->edges, new_edges);
         new_edges = NIL;
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
        if (!bms_is_subset(edge->required_relids, root->all_baserels))
            continue;
        
        /* 转换为 RestrictInfo */
        RestrictInfo *rinfo = make_restrictinfo_from_inequality(root, edge);
        
        if (rinfo == NULL)
            continue;
        
        /* 标记为推导约束 */
        rinfo->is_derived_from_inequality = true;
        
        /* 根据涉及的表数量分发约束 */
        if (bms_membership(edge->required_relids) == BMS_SINGLETON)
        {
            /* 单表约束：添加到 baserestrictinfo */
            int relid = bms_singleton_member(edge->required_relids);
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

/* 从等价类推导新的约束 */
void generate_base_implied_equalities(PlannerInfo *root)
{
    ListCell *lc;
    
    foreach(lc, root->eq_classes)
    {
        EquivalenceClass *ec = (EquivalenceClass *) lfirst(lc);
        
        /* 如果等价类包含常量 */
        if (ec->ec_has_const)
        {
            Expr *const_expr = find_const_member(ec);
            ListCell *lc2;
            
            /* 为每个非常量成员生成 "成员 = 常量" */
            foreach(lc2, ec->ec_members)
            {
                EquivalenceMember *em = (EquivalenceMember *) lfirst(lc2);
                
                if (!em->em_is_const)
                {
                    /* 生成：t1.a = 100 */
                    RestrictInfo *rinfo = 
                        create_equality_restrictinfo(em->em_expr, const_expr);
                    
                    /* 添加到对应表的约束 */
                    distribute_restrictinfo_to_rels(root, rinfo);
                }
            }
        }
        
        /* 为每对成员生成等式（按需，不是全部） */
        generate_join_equalities_for_ec(root, ec);
    }
}