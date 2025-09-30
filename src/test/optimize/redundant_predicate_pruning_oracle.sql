-- Oracle Redundant Predicate Pruning Tests
-- 目标：验证优化器是否能识别并裁剪被更强条件蕴含的冗余谓词

BEGIN EXECUTE IMMEDIATE DROP
