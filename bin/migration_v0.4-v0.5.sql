-- 添加请求和响应内容字段到 logs 表
-- 用于记录完整的请求和响应内容，便于调试和分析

-- 添加请求内容字段
ALTER TABLE logs ADD COLUMN request_content TEXT DEFAULT '' COMMENT '请求内容（JSON格式）';

-- 添加响应内容字段
ALTER TABLE logs ADD COLUMN response_content TEXT DEFAULT '' COMMENT '响应内容（JSON格式）';
