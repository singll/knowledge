# n8n 工作流快速部署指南

## 工作流文件说明

| 文件名 | 功能 | 触发方式 |
|-------|------|---------|
| `01-scheduled-fetch.json` | 定时获取 RSS 和数据源 | Cron: 每天 6:00 和 18:00 |
| `02-core-crawler.json` | 核心爬取工作流 | Webhook: `/webhook/core-crawler` |
| `03-manual-ingest.json` | 手动URL入库 | Webhook: `/webhook/manual-ingest` |
| `04-error-retry.json` | 错误重试队列 | Cron: 每 30 分钟 |
| `05-ollama-queue.json` | Ollama 本地AI队列 | Cron: 每 10 分钟检测 |
| `06-health-monitor.json` | 系统健康监控 | Cron: 每 5 分钟 |
| `07-ai-summarize.json` | AI 内容总结 | Webhook: `/webhook/ai-summarize` |

## 新特性：动态知识库映射

**重要更新**: 工作流现在支持通过 knowledge-management API 动态获取知识库映射，不再需要在工作流中硬编码知识库 ID。

### 工作原理

1. **知识库映射管理**: 在 knowledge-management 系统的"知识库"页面管理知识库映射
2. **标签关联**: 每个知识库映射可关联多个标签
3. **智能入库**: 工作流调用 `/api/ragflow/upload/with-tags` 接口，系统根据文章标签自动选择目标知识库
4. **自动创建标签**: 工作流提取的标签如果不存在，会自动创建

### 配置知识库映射

1. 打开 knowledge-management 系统
2. 进入"知识库"页面
3. 点击"新建映射"
4. 填写：
   - **映射名称**: 如 `security`、`news`、`ai`（用于工作流分类）
   - **显示名称**: 如"安全知识库"
   - **Dataset ID**: 从 RagFlow 获取的知识库 ID
   - **关联标签**: 选择该知识库应接收的文章标签
   - **设为默认**: 无法匹配标签时的兜底知识库

## 快速部署步骤

### 1. 导入工作流

#### 方式一：通过 UI 导入

1. 登录 n8n 界面
2. 点击 Workflows > Import from File
3. 按顺序导入各 JSON 文件

#### 方式二：通过脚本导入

```bash
#!/bin/bash
N8N_URL="http://localhost:5678"
N8N_API_KEY="your-n8n-api-key"

for file in /home/ubuntu/knowledge-management/n8n-workflows/*.json; do
  echo "Importing: $file"
  curl -X POST "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$file"
done
```

### 2. 修改配置参数

**重要**: 现在只需要配置服务地址，知识库 ID 通过 API 动态获取。

#### 修改步骤：

1. 打开工作流
2. 双击 **"配置参数"** 节点（通常是第二个节点）
3. 在 JSON 编辑器中修改对应的值
4. 保存工作流

#### 需要配置的参数：

**01-scheduled-fetch.json (定时抓取)**:
```json
{
  "KNOWLEDGE_MGMT_URL": "http://knowledge-backend:5000",
  "FIRECRAWL_API_URL": "http://firecrawl:3002",
  "N8N_WEBHOOK_URL": "http://n8n:5678"
}
```

**02-core-crawler.json (核心爬取)**:
```json
{
  "KNOWLEDGE_MGMT_URL": "http://knowledge-backend:5000",
  "FIRECRAWL_API_URL": "http://firecrawl:3002",
  "N8N_WEBHOOK_URL": "http://n8n:5678"
}
```

**03-manual-ingest.json (手动入库)**:
```json
{
  "KNOWLEDGE_MGMT_URL": "http://knowledge-backend:5000",
  "FIRECRAWL_API_URL": "http://firecrawl:3002"
}
```

**04-error-retry.json (错误重试)**:
```json
{
  "N8N_WEBHOOK_URL": "http://n8n:5678"
}
```

**05-ollama-queue.json (Ollama队列)**:
```json
{
  "OLLAMA_URL": "http://你的Win11IP:11434",
  "DEFAULT_MODEL": "qwen2.5:7b"
}
```

**06-health-monitor.json (健康监控)**:
```json
{
  "KNOWLEDGE_MGMT_URL": "http://knowledge-backend:5000",
  "FIRECRAWL_API_URL": "http://firecrawl:3002",
  "RAGFLOW_URL": "http://ragflow:9380",
  "OLLAMA_URL": "http://你的Win11IP:11434"
}
```

**07-ai-summarize.json (AI总结)**:
```json
{
  "OLLAMA_URL": "http://你的Win11IP:11434",
  "DEFAULT_MODEL": "qwen2.5:7b",
  "DEEPSEEK_API_URL": "https://api.deepseek.com"
}
```

### 3. 配置凭证

在 n8n 的 Settings > Credentials 中添加：

**Firecrawl API:**
- Type: HTTP Header Auth
- Name: `Firecrawl API`
- Header Name: `Authorization`
- Header Value: `Bearer YOUR_FIRECRAWL_API_KEY`

**RagFlow API:**
- Type: HTTP Header Auth
- Name: `RagFlow API`
- Header Name: `Authorization`
- Header Value: `Bearer YOUR_RAGFLOW_API_KEY`

**DeepSeek API (可选，用于 AI 总结):**
- Type: HTTP Header Auth
- Name: `DeepSeek API`
- Header Name: `Authorization`
- Header Value: `Bearer YOUR_DEEPSEEK_API_KEY`

### 4. 关联凭证

导入工作流后，需要手动关联凭证：

1. 打开每个工作流
2. 找到使用 HTTP 请求的节点（如 "Firecrawl 爬取"、"上传到RagFlow" 等）
3. 点击节点，在 "Credential to connect with" 处选择对应的凭证
4. 保存工作流

### 5. 配置知识库映射（重要！）

在首次使用前，需要在 knowledge-management 系统中配置知识库映射：

1. 访问 knowledge-management 前端
2. 进入"知识库"页面 -> "知识库映射"标签
3. 为每个 RagFlow 知识库创建映射
4. 设置一个默认知识库（用于兜底）

### 6. 激活工作流

**激活顺序建议**:
1. `06-health-monitor` - 健康监控
2. `02-core-crawler` - 核心爬取
3. `04-error-retry` - 错误重试
4. `03-manual-ingest` - 手动入库
5. `05-ollama-queue` - Ollama队列
6. `07-ai-summarize` - AI总结
7. `01-scheduled-fetch` - 定时抓取（最后激活）

## 使用说明

### 手动入库文章

```bash
# 使用分类（会根据分类匹配知识库映射）
curl -X POST http://your-n8n:5678/webhook/manual-ingest \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com/article",
    "category": "security",
    "tags": ["漏洞", "Web安全"]
  }'

# 使用标签自动匹配知识库
curl -X POST http://your-n8n:5678/webhook/manual-ingest \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com/article",
    "tags": ["AI", "机器学习", "深度学习"]
  }'
```

### API 接口说明

**获取所有知识库映射**:
```bash
curl http://your-backend:5000/api/dataset-mappings/all
```

**根据标签获取推荐知识库**:
```bash
curl -X POST http://your-backend:5000/api/dataset-mappings/by-tag \
  -H "Content-Type: application/json" \
  -d '{
    "tags": ["安全", "漏洞"],
    "category": "security"
  }'
```

**智能上传文档（带标签处理）**:
```bash
curl -X POST http://your-backend:5000/api/ragflow/upload/with-tags \
  -H "Content-Type: application/json" \
  -d '{
    "content": "文档内容...",
    "filename": "article.md",
    "title": "文章标题",
    "url": "https://example.com/article",
    "tags": ["安全", "漏洞"],
    "keywords": ["CVE", "RCE"],
    "category": "security",
    "auto_create_tags": true
  }'
```

### AI 总结内容

```bash
# 使用 DeepSeek
curl -X POST http://your-n8n:5678/webhook/ai-summarize \
  -H "Content-Type: application/json" \
  -d '{
    "content": "要总结的内容...",
    "provider": "deepseek",
    "task_type": "summarize"
  }'

# 使用本地 Ollama
curl -X POST http://your-n8n:5678/webhook/ai-summarize \
  -H "Content-Type: application/json" \
  -d '{
    "content": "要总结的内容...",
    "provider": "ollama",
    "model": "qwen2.5:7b",
    "task_type": "security_analysis"
  }'
```

### Ollama 队列操作

```bash
# 添加任务
curl -X POST http://your-n8n:5678/webhook/ollama-queue \
  -H "Content-Type: application/json" \
  -d '{
    "content": "要处理的内容...",
    "task_type": "summarize"
  }'

# 暂停队列
curl -X POST http://your-n8n:5678/webhook/ollama-control \
  -H "Content-Type: application/json" \
  -d '{"action": "pause"}'

# 恢复队列
curl -X POST http://your-n8n:5678/webhook/ollama-control \
  -H "Content-Type: application/json" \
  -d '{"action": "resume"}'

# 查看队列状态
curl -X POST http://your-n8n:5678/webhook/ollama-control \
  -H "Content-Type: application/json" \
  -d '{"action": "status"}'

# 清除已完成任务
curl -X POST http://your-n8n:5678/webhook/ollama-control \
  -H "Content-Type: application/json" \
  -d '{"action": "clear", "clear_type": "completed"}'
```

### 查看系统健康状态

```bash
curl http://your-n8n:5678/webhook/health-status
```

## 标签与知识库关联说明

### 工作流程

1. **文章爬取**: 工作流爬取文章内容
2. **提取关键词**: 从文章元数据（标题、描述、关键词）中提取关键词
3. **标签匹配**:
   - 将输入的标签与系统中已有标签匹配
   - 根据关键词匹配可能相关的标签
4. **自动创建**: 不存在的标签会自动创建（灰色标记）
5. **知识库选择**:
   - 优先：根据文章标签匹配关联了相同标签的知识库
   - 其次：根据分类名称匹配知识库映射
   - 兜底：使用默认知识库
6. **入库并关联**: 文档入库后，自动创建文档-标签关联记录

### 通过标签筛选文章

在 knowledge-management 系统中：
- 进入"知识库"页面
- 查看文档列表
- 每个文档显示其关联的标签
- 可以通过标签筛选文档

## 故障排查

### 工作流执行失败

1. 检查 n8n 日志：`docker logs n8n -f`
2. 在 n8n UI 中查看执行历史
3. 检查 **"配置参数"** 节点中的值是否正确
4. 检查凭证是否正确配置并关联

### 知识库映射问题

1. 确认已在 knowledge-management 中创建知识库映射
2. 检查是否设置了默认知识库
3. 查看 API 响应：`curl http://your-backend:5000/api/dataset-mappings/all`

### Firecrawl 爬取失败

1. 检查 Firecrawl 服务状态
2. 检查 API Key 是否有效
3. 检查目标网站是否可访问
4. 查看 Firecrawl 日志：`docker logs firecrawl -f`

### RagFlow 入库失败

1. 检查 RagFlow 服务状态
2. 验证知识库映射中的 dataset_id 是否正确
3. 检查 API Key 权限
4. 查看 knowledge-management 日志

### Ollama 连接失败

1. 确认 Win11 电脑 Ollama 服务已启动
2. 检查防火墙是否允许 11434 端口
3. 确认配置参数中的 OLLAMA_URL IP 地址正确
4. 尝试从服务器 ping Win11

## 推荐 RSS 源

### 网络安全

```
FreeBuf: https://www.freebuf.com/feed
安全客: https://www.anquanke.com/rss.xml
先知社区: https://xz.aliyun.com/feed
Seebug: https://paper.seebug.org/rss/
SecWiki: https://www.sec-wiki.com/news/rss
```

### 技术资讯

```
InfoQ: https://www.infoq.cn/feed
Hacker News: https://news.ycombinator.com/rss
机器之心: https://www.jiqizhixin.com/rss
```

---

详细方案请查看 [SOLUTION.md](./SOLUTION.md)
