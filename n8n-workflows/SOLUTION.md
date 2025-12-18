# 知识管理系统 - 完整实施方案

## 目录

1. [知识库规划](#1-知识库规划)
2. [n8n 工作流总览](#2-n8n-工作流总览)
3. [工作流详细配置](#3-工作流详细配置)
4. [部署步骤](#4-部署步骤)
5. [后续使用方案](#5-后续使用方案)

---

## 1. 知识库规划

### 1.1 推荐知识库分类

基于你的网络安全工程师背景和学习目标，建议在 RagFlow 中创建以下知识库：

| 知识库名称 | 用途 | 标签建议 |
|-----------|------|---------|
| **网络安全** | 漏洞分析、渗透测试、安全工具、攻防技术 | `漏洞`, `渗透`, `安全工具`, `CTF`, `红队`, `蓝队` |
| **安全情报** | CVE 漏洞预警、威胁情报、APT 报告、安全通告 | `CVE`, `威胁情报`, `APT`, `勒索`, `供应链` |
| **编程开发** | Python、Go、Rust、Shell 等编程语言及框架 | `Python`, `Go`, `Rust`, `Shell`, `Web开发` |
| **AI与机器学习** | 大模型、AI 安全、机器学习、深度学习 | `LLM`, `NLP`, `安全AI`, `模型训练`, `RAG` |
| **云原生与DevOps** | 容器安全、K8s、CI/CD、云安全 | `Docker`, `K8s`, `AWS`, `Azure`, `云安全` |
| **资讯速读** | 每日技术资讯、行业动态、快讯（短期存储） | `资讯`, `快讯`, `周报` |

### 1.2 RagFlow 知识库创建命令

在 knowledge-management 界面或通过 API 创建：

```bash
# 通过 API 创建知识库示例
curl -X POST http://localhost:5000/api/datasets \
  -H "Content-Type: application/json" \
  -d '{
    "name": "网络安全",
    "description": "网络安全领域知识库：漏洞分析、渗透测试、安全工具",
    "language": "Chinese",
    "embedding_model": "BAAI/bge-large-zh-v1.5",
    "chunk_method": "naive"
  }'
```

### 1.3 解析器选择建议

| 内容类型 | 推荐解析器 | 说明 |
|---------|-----------|------|
| 技术文章 | `naive` | 通用解析，适合网页文章 |
| PDF 论文 | `paper` | 学术论文解析 |
| 技术书籍 | `book` | 书籍章节解析 |
| 代码文档 | `naive` | 保留代码格式 |

---

## 2. n8n 工作流总览

### 2.1 工作流架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         n8n 工作流架构                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐     │
│  │ 定时触发器    │────▶│ RSS/数据源   │────▶│                  │     │
│  │ (6:00/18:00) │     │ 获取工作流   │     │                  │     │
│  └──────────────┘     └──────────────┘     │                  │     │
│                                             │   核心爬取       │     │
│  ┌──────────────┐                          │   工作流         │     │
│  │ Webhook      │─────────────────────────▶│   (Firecrawl)   │     │
│  │ 手动触发     │                          │                  │     │
│  └──────────────┘                          └────────┬─────────┘     │
│                                                      │               │
│                                                      ▼               │
│                                             ┌──────────────────┐     │
│  ┌──────────────┐                          │ knowledge-mgmt   │     │
│  │ Ollama 队列  │◀─────────────────────────│ 入库工作流       │     │
│  │ 本地AI处理   │                          │ (RagFlow API)    │     │
│  └──────────────┘                          └────────┬─────────┘     │
│                                                      │               │
│  ┌──────────────┐                                   │               │
│  │ 错误处理     │◀──────────────────────────────────┘               │
│  │ 重试工作流   │                                                    │
│  └──────────────┘                                                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 工作流清单

| 序号 | 工作流名称 | 文件名 | 触发方式 | 功能描述 |
|-----|-----------|--------|---------|---------|
| 1 | 定时RSS数据源抓取 | `01-scheduled-fetch.json` | Cron (6:00/18:00) | 获取数据源和RSS，触发爬取 |
| 2 | 核心文章爬取 | `02-core-crawler.json` | 被调用(Webhook) | Firecrawl 爬取并入库 |
| 3 | 手动URL入库 | `03-manual-ingest.json` | Webhook | 手动触发立即入库 |
| 4 | 错误处理重试 | `04-error-retry.json` | Webhook | 失败任务重试 |
| 5 | Ollama任务队列 | `05-ollama-queue.json` | 定时检测 | 本地AI处理队列 |
| 6 | 系统健康监控 | `06-health-monitor.json` | 定时 (每5分钟) | 监控服务状态 |
| 7 | AI内容总结 | `07-ai-summarize.json` | 被调用 | 在线AI总结文章 |

---

## 3. 工作流详细配置

### 3.1 配置方式说明

每个工作流都包含一个名为 **"配置参数"** 的 Set 节点，所有配置都在此节点中定义。这种方式兼容 n8n 个人版（社区版），无需企业版的 Variables 功能。

#### 修改配置步骤：

1. 打开工作流
2. 双击 **"配置参数"** 节点（通常是第二个节点）
3. 在 JSON 编辑器中修改对应的值
4. 保存工作流

#### 主要配置项说明：

| 配置项 | 说明 | 示例值 |
|-------|------|--------|
| `KNOWLEDGE_MGMT_URL` | knowledge-management 服务地址 | `http://knowledge-backend:5000` |
| `FIRECRAWL_API_URL` | Firecrawl 服务地址 | `http://firecrawl:3002` |
| `N8N_WEBHOOK_URL` | n8n Webhook 基础地址 | `http://n8n:5678` |
| `RAGFLOW_URL` | RagFlow 服务地址 | `http://ragflow:9380` |
| `OLLAMA_URL` | Ollama 服务地址（Win11 IP） | `http://192.168.1.100:11434` |
| `DEFAULT_MODEL` | Ollama 默认模型 | `qwen2.5:7b` |
| `RAGFLOW_DATASET_ID_*` | 各知识库的 ID | 在 RagFlow 创建后获取 |

### 3.2 各工作流详细说明

#### 工作流 1: 定时RSS数据源抓取 (01-scheduled-fetch.json)

**功能**:
- 每天 6:00 和 18:00 自动触发
- 获取所有启用的 RSS 订阅源和数据源
- 解析 RSS Feed 获取最新文章
- 调用核心爬取工作流处理每篇文章
- 更新 RSS 的 last_fetched 时间

**关键节点**:
1. Schedule Trigger - Cron 表达式 `0 6,18 * * *`
2. HTTP Request - 获取 RSS 列表 `GET /api/rss?is_active=true`
3. HTTP Request - 获取数据源列表 `GET /api/datasources?is_active=true`
4. RSS Feed Read - 解析 RSS XML
5. Filter - 过滤已处理的文章（基于时间）
6. HTTP Request - 调用核心爬取工作流

#### 工作流 2: 核心文章爬取 (02-core-crawler.json)

**功能**:
- 接收 URL 和目标知识库 ID
- 使用 Firecrawl 爬取网页内容
- 提取正文、标题、元数据
- 调用 knowledge-management API 入库到 RagFlow
- 错误处理和重试机制

**输入参数**:
```json
{
  "url": "https://example.com/article",
  "dataset_id": "xxx",
  "tags": ["security", "vulnerability"],
  "source": "rss|manual|datasource",
  "priority": "normal|high"
}
```

#### 工作流 3: 手动URL入库 (03-manual-ingest.json)

**功能**:
- 暴露 Webhook URL 供手动调用
- 接收文章 URL 和可选的目标知识库
- 立即调用核心爬取工作流
- 返回处理结果

**调用方式**:
```bash
curl -X POST https://your-n8n/webhook/manual-ingest \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com/good-article",
    "dataset": "security",
    "tags": ["learning", "important"]
  }'
```

#### 工作流 4: 错误处理重试 (04-error-retry.json)

**功能**:
- 存储失败的任务到队列
- 定期检查并重试
- 最多重试 3 次
- 超过重试次数发送告警

#### 工作流 5: Ollama任务队列 (05-ollama-queue.json)

**功能**:
- 维护需要本地 AI 处理的任务队列
- 定期检测 Ollama 服务可用性
- 可用时自动处理队列中的任务
- 支持暂停/恢复功能

#### 工作流 6: 系统健康监控 (06-health-monitor.json)

**功能**:
- 每 5 分钟检测各服务状态
- 监控: RagFlow, Firecrawl, knowledge-management
- 服务不可用时发送告警
- 记录监控日志

#### 工作流 7: AI内容总结 (07-ai-summarize.json)

**功能**:
- 使用在线 AI API (OpenAI/Claude) 总结文章
- 生成关键要点
- 自动提取标签
- 可选添加到文章元数据

---

## 4. 部署步骤

### 4.1 前置检查

```bash
# 1. 确认 Docker 网络
docker network ls | grep knowledge-net

# 2. 确认服务运行状态
docker ps | grep -E "ragflow|firecrawl|n8n|knowledge"

# 3. 检查 knowledge-management API
curl http://localhost:5000/health
```

### 4.2 导入工作流到 n8n

**方式一: 通过 n8n UI 导入**

1. 登录 n8n 界面
2. 点击左侧菜单 "Workflows"
3. 点击 "Import from File"
4. 选择 JSON 文件导入
5. 按顺序导入所有工作流

**方式二: 通过 n8n API 导入**

```bash
# 获取 n8n API Key (在 n8n Settings 中创建)
N8N_API_KEY="your-api-key"
N8N_URL="http://localhost:5678"

# 导入工作流
for file in /home/ubuntu/knowledge-management/n8n-workflows/*.json; do
  curl -X POST "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$file"
done
```

### 4.3 配置凭证

1. **Firecrawl 凭证**
   - 在 n8n 中: Settings > Credentials > Add Credential
   - 类型: HTTP Header Auth
   - Name: Firecrawl API
   - Header: Authorization
   - Value: Bearer YOUR_FIRECRAWL_KEY

2. **OpenAI 凭证 (可选)**
   - 类型: OpenAI API
   - API Key: your-openai-key

### 4.4 激活工作流

```bash
# 激活所有工作流
# 在 n8n UI 中，打开每个工作流并点击 "Active" 开关
```

### 4.5 测试验证

```bash
# 1. 测试手动入库工作流
curl -X POST http://localhost:5678/webhook/manual-ingest \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/test-article"}'

# 2. 检查 RagFlow 文档
curl http://localhost:5000/api/ragflow/documents?dataset_id=YOUR_DATASET_ID
```

---

## 5. 后续使用方案

### 5.1 知识库使用界面

#### 方案 A: RagFlow 自带的聊天界面

RagFlow 提供了内置的 Chat 功能：

1. 登录 RagFlow 管理界面 (http://ragflow:9380)
2. 创建 "Chat Assistant"
3. 关联你的知识库
4. 配置 LLM 模型（可使用 Ollama 本地模型或在线 API）
5. 获得 Chat 界面进行知识检索和问答

#### 方案 B: 自建聊天界面

在 knowledge-management 前端添加聊天功能：

```javascript
// 调用 RagFlow Chat API
const response = await fetch('/api/ragflow/chat', {
  method: 'POST',
  body: JSON.stringify({
    question: '什么是SQL注入?',
    dataset_ids: ['security-kb-id'],
    model: 'deepseek-chat'  // 或其他模型
  })
});
```

### 5.2 AI 总结配置

#### 在线 AI API 选择

| 提供商 | 模型 | 优点 | 缺点 |
|-------|------|------|------|
| OpenAI | gpt-4o-mini | 效果好，速度快 | 需要科学上网 |
| DeepSeek | deepseek-chat | 便宜，中文效果好 | API 较新 |
| 阿里云 | qwen-turbo | 国内可用，免费额度 | 需要申请 |
| Moonshot | kimi | 长上下文 | 速率限制 |

#### 工作流中使用 AI 总结

在核心爬取工作流中添加 AI 总结节点：

```json
{
  "name": "AI Summarize",
  "type": "n8n-nodes-base.openAi",
  "parameters": {
    "operation": "message",
    "model": "gpt-4o-mini",
    "messages": {
      "values": [
        {
          "content": "请用中文总结以下文章的核心要点，格式为:\n1. 一句话总结\n2. 关键要点（3-5条）\n3. 相关标签\n\n文章内容:\n{{ $json.content }}"
        }
      ]
    }
  }
}
```

### 5.3 知识体系化建设

#### 5.3.1 标签体系

建议创建分层标签体系：

```
网络安全
├── 攻击技术
│   ├── Web安全
│   │   ├── SQL注入
│   │   ├── XSS
│   │   └── CSRF
│   ├── 二进制安全
│   └── 社会工程学
├── 防御技术
│   ├── 入侵检测
│   ├── 安全加固
│   └── 应急响应
└── 工具使用
    ├── Burp Suite
    ├── Nmap
    └── Metasploit
```

#### 5.3.2 知识关联

在 knowledge-management 中添加知识关联功能（需扩展开发）：

1. **文档相似度关联**: 基于 embedding 找相似文档
2. **标签关联**: 相同标签的文档自动关联
3. **手动关联**: 允许手动建立文档关系

#### 5.3.3 学习路径

创建学习路径功能：

1. 定义学习主题（如：Web安全入门）
2. 按顺序关联相关文档
3. 标记学习进度
4. 生成学习报告

### 5.4 搜索和检索

#### RagFlow 搜索 API

```bash
# 语义搜索
curl -X POST http://localhost:5000/api/ragflow/search \
  -H "Content-Type: application/json" \
  -d '{
    "dataset_ids": ["security-kb"],
    "question": "如何检测SQL注入漏洞",
    "top_k": 10
  }'
```

#### 高级搜索功能

1. **全文搜索**: 关键词匹配
2. **语义搜索**: 基于 embedding 的相似度搜索
3. **标签过滤**: 按标签筛选
4. **时间范围**: 按入库时间筛选
5. **来源过滤**: 按数据源/RSS 来源筛选

### 5.5 数据导出和备份

#### 定期备份

```bash
# 备份脚本示例
#!/bin/bash
BACKUP_DIR="/backup/knowledge-$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# 备份 SQLite 数据库
docker cp knowledge-backend:/app/data/knowledge.db $BACKUP_DIR/

# 导出 RagFlow 文档列表
curl http://localhost:5000/api/ragflow/documents?dataset_id=xxx > $BACKUP_DIR/docs.json

# 备份 n8n 工作流
curl -H "X-N8N-API-KEY: xxx" http://localhost:5678/api/v1/workflows > $BACKUP_DIR/workflows.json
```

### 5.6 推荐数据源

#### 网络安全

| 名称 | URL | 类型 |
|-----|-----|-----|
| FreeBuf | https://www.freebuf.com/feed | RSS |
| 安全客 | https://www.anquanke.com/rss.xml | RSS |
| Seebug | https://paper.seebug.org/rss/ | RSS |
| 先知社区 | https://xz.aliyun.com/feed | RSS |
| SecWiki | https://www.sec-wiki.com/news/rss | RSS |
| HackerNews Security | 手动抓取 | DataSource |
| GitHub Security Lab | https://securitylab.github.com/research/feed.xml | RSS |

#### AI/技术

| 名称 | URL | 类型 |
|-----|-----|-----|
| Hacker News | https://news.ycombinator.com/rss | RSS |
| InfoQ | https://www.infoq.cn/feed | RSS |
| 机器之心 | https://www.jiqizhixin.com/rss | RSS |
| Papers With Code | 手动抓取 | DataSource |

---

## 6. 故障排查

### 常见问题

1. **Firecrawl 爬取失败**
   - 检查 API Key
   - 检查目标网站是否可访问
   - 查看 Firecrawl 日志

2. **RagFlow 入库失败**
   - 检查 dataset_id 是否正确
   - 检查 API Key 权限
   - 查看 RagFlow 日志

3. **n8n 工作流执行失败**
   - 检查各服务网络连通性
   - 查看执行日志
   - 检查凭证配置

### 日志查看

```bash
# 查看各服务日志
docker logs knowledge-backend -f
docker logs n8n -f
docker logs firecrawl-api -f
```

---

## 7. 扩展开发建议

### 7.1 API 扩展

1. **添加文章去重接口**: 防止重复入库
2. **添加批量标签接口**: 批量更新文章标签
3. **添加搜索 API**: 封装 RagFlow 搜索功能
4. **添加统计 API**: 知识库统计数据

### 7.2 前端扩展

1. **知识图谱可视化**: 展示知识关联
2. **学习进度看板**: 追踪学习进度
3. **智能推荐**: 基于阅读历史推荐
4. **聊天界面**: 与知识库对话

---

**文档版本**: 1.0
**更新时间**: 2025-01-15
**适用组件版本**:
- n8n: 1.123.4
- Firecrawl: v2.7.0
- RagFlow: v0.22.1
