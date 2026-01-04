# 请求和响应内容记录功能

## 功能说明

本功能为 New API 添加了记录模型请求和响应内容的能力，便于调试、分析和审计。

## 修改内容

### 1. 数据库模型修改

#### 文件：`model/log.go`

**修改 1：Log 结构体添加新字段**
```go
type Log struct {
    // ... 现有字段 ...
    RequestContent   string `json:"request_content" gorm:"type:text"`
    ResponseContent  string `json:"response_content" gorm:"type:text"`
}
```

**修改 2：RecordConsumeLogParams 结构体添加新字段**
```go
type RecordConsumeLogParams struct {
    // ... 现有字段 ...
    RequestContent   string `json:"request_content"`
    ResponseContent  string `json:"response_content"`
}
```

**修改 3：RecordConsumeLog 函数更新**
在创建日志记录时，添加请求和响应内容：
```go
log := &Log{
    // ... 现有字段 ...
    RequestContent:   params.RequestContent,
    ResponseContent:  params.ResponseContent,
}
```

### 2. 配置开关

#### 文件：`common/constants.go`

添加了新的配置开关：
```go
var LogRequestResponseEnabled = false
```

**默认值：** `false`（默认关闭，避免影响性能）

**启用方法：**
在环境变量中设置：
```bash
export LOG_REQUEST_RESPONSE_ENABLED=true
```

或在 `.env` 文件中添加：
```
LOG_REQUEST_RESPONSE_ENABLED=true
```

### 3. 请求内容捕获

#### 文件：`relay/compatible_handler.go`

在 `TextHelper` 函数中，捕获请求内容：

**PassThrough 模式：**
```go
if model_setting.GetGlobalSettings().PassThroughRequestEnabled || info.ChannelSetting.PassThroughBodyEnabled {
    body, err := common.GetRequestBody(c)
    // ...
    requestBody = bytes.NewBuffer(body)
    
    if common.LogRequestResponseEnabled {
        c.Set("request_content", string(body))
    }
}
```

**普通模式：**
```go
jsonData, err := common.Marshal(convertedRequest)
// ...
requestBody = bytes.NewBuffer(jsonData)

if common.LogRequestResponseEnabled {
    c.Set("request_content", string(jsonData))
}
```

### 4. 响应内容捕获

#### 文件：`relay/channel/openai/relay-openai.go`

**非流式响应：**
在 `OpenaiHandler` 函数中：
```go
service.IOCopyBytesGracefully(c, resp, responseBody)

if common.LogRequestResponseEnabled {
    c.Set("response_content", string(responseBody))
}

return &simpleResponse.Usage, nil
```

**流式响应：**
在 `OaiStreamHandler` 函数中：
```go
HandleFinalResponse(c, info, lastStreamData, responseId, createAt, model, systemFingerprint, usage, containStreamUsage)

if common.LogRequestResponseEnabled && len(streamItems) > 0 {
    fullResponse := strings.Join(streamItems, "")
    c.Set("response_content", fullResponse)
}

return usage, nil
```

### 5. 日志记录更新

#### 文件：`relay/compatible_handler.go`

在 `postConsumeQuota` 函数中，从上下文获取请求和响应内容：

```go
requestContent := ""
responseContent := ""
if common.LogRequestResponseEnabled {
    if reqContent, exists := ctx.Get("request_content"); exists {
        if str, ok := reqContent.(string); ok {
            requestContent = str
        }
    }
    if respContent, exists := ctx.Get("response_content"); exists {
        if str, ok := respContent.(string); ok {
            responseContent = str
        }
    }
}

model.RecordConsumeLog(ctx, relayInfo.UserId, model.RecordConsumeLogParams{
    // ... 现有参数 ...
    RequestContent:   requestContent,
    ResponseContent:  responseContent,
})
```

### 6. 数据库迁移脚本

#### 文件：`bin/migration_v0.4-v0.5.sql`

```sql
-- 添加请求内容字段
ALTER TABLE logs ADD COLUMN request_content TEXT DEFAULT '' COMMENT '请求内容（JSON格式）';

-- 添加响应内容字段
ALTER TABLE logs ADD COLUMN response_content TEXT DEFAULT '' COMMENT '响应内容（JSON格式）';
```

## 使用方法

### 1. 执行数据库迁移

**MySQL：**
```bash
mysql -u root -p oneapi < bin/migration_v0.4-v0.5.sql
```

**PostgreSQL：**
```bash
psql -U postgres oneapi -f bin/migration_v0.4-v0.5.sql
```

**SQLite：**
```bash
sqlite3 one-api.db < bin/migration_v0.4-v0.5.sql
```

### 2. 启用功能

**方法 1：环境变量**
```bash
export LOG_REQUEST_RESPONSE_ENABLED=true
```

**方法 2：.env 文件**
```
LOG_REQUEST_RESPONSE_ENABLED=true
```

**方法 3：Docker Compose**
```yaml
services:
  new-api:
    environment:
      - LOG_REQUEST_RESPONSE_ENABLED=true
```

### 3. 重启服务

```bash
# 如果使用 systemd
sudo systemctl restart new-api

# 如果使用 Docker
docker-compose restart

# 如果直接运行
./new-api
```

## 查询日志

### SQL 查询示例

**查看最近的请求和响应：**
```sql
SELECT 
    id,
    created_at,
    username,
    model_name,
    request_content,
    response_content,
    quota
FROM logs 
WHERE type = 2 
ORDER BY id DESC 
LIMIT 10;
```

**按用户查询：**
```sql
SELECT 
    id,
    created_at,
    model_name,
    request_content,
    response_content
FROM logs 
WHERE type = 2 
  AND user_id = 123 
ORDER BY id DESC;
```

**按模型查询：**
```sql
SELECT 
    id,
    created_at,
    username,
    request_content,
    response_content
FROM logs 
WHERE type = 2 
  AND model_name LIKE '%gpt-4%' 
ORDER BY id DESC 
LIMIT 20;
```

## 注意事项

### 1. 性能影响

- **存储空间**：每个请求和响应都会占用额外的数据库空间
- **写入性能**：启用后会增加每次请求的数据库写入时间
- **建议**：仅在调试或审计需要时启用

### 2. 隐私安全

- **敏感信息**：请求和响应可能包含用户敏感数据
- **访问控制**：确保数据库访问权限正确配置
- **数据清理**：定期清理旧的请求响应数据

### 3. 流式响应

- **内存占用**：流式响应需要累积完整内容
- **大响应**：对于超长响应，可能需要考虑截断

### 4. 数据库优化

**定期清理旧数据：**
```sql
-- 删除 30 天前的请求响应数据
UPDATE logs 
SET request_content = '', 
    response_content = '' 
WHERE created_at < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY));
```

**添加索引（如果查询频繁）：**
```sql
CREATE INDEX idx_logs_request_content ON logs(request_content(255));
CREATE INDEX idx_logs_response_content ON logs(response_content(255));
```

## 故障排查

### 问题：日志中没有请求响应内容

**检查清单：**
1. 确认 `LOG_REQUEST_RESPONSE_ENABLED=true` 已设置
2. 确认数据库迁移已执行
3. 检查日志类型是否为 `LogTypeConsume` (type=2)
4. 查看应用日志是否有错误

### 问题：数据库字段不存在

**解决方案：**
```bash
# 重新执行迁移脚本
mysql -u root -p oneapi < bin/migration_v0.4-v0.5.sql

# 检查字段是否存在
mysql -u root -p oneapi -e "DESCRIBE logs;"
```

## 扩展建议

### 1. 内容截断

对于超长内容，可以添加截断逻辑：

```go
const MaxContentLength = 10000 // 10KB

if len(requestContent) > MaxContentLength {
    requestContent = requestContent[:MaxContentLength] + "... [截断]"
}
```

### 2. 内容压缩

对大内容进行压缩存储：

```go
import "compress/gzip"

func compressContent(content string) (string, error) {
    var buf bytes.Buffer
    gz := gzip.NewWriter(&buf)
    if _, err := gz.Write([]byte(content)); err != nil {
        return "", err
    }
    if err := gz.Close(); err != nil {
        return "", err
    }
    return buf.String(), nil
}
```

### 3. 加密存储

对敏感内容进行加密：

```go
import "crypto/aes"

func encryptContent(content string, key []byte) (string, error) {
    block, err := aes.NewCipher(key)
    if err != nil {
        return "", err
    }
    // 加密逻辑...
}
```

## 修改文件清单

1. `model/log.go` - 数据模型和日志记录函数
2. `common/constants.go` - 配置开关
3. `relay/compatible_handler.go` - 请求捕获和日志记录
4. `relay/channel/openai/relay-openai.go` - 响应捕获
5. `bin/migration_v0.4-v0.5.sql` - 数据库迁移脚本

## 版本信息

- **版本**：v0.5
- **兼容性**：向后兼容 v0.4
- **依赖**：无新增依赖
