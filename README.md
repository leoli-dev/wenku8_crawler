# Wenku8 Crawler

一个专门抓取 [Wenku8](https://www.wenku8.net/) 小说目录与正文的命令行脚本。整体流程：

1. 访问目录页，读取小说标题，自动在 `downloaded/` 下创建 `小说名/卷名/` 层级结构（自动用 `_` 替换标点）。
2. 解析每卷、每章的标题和链接，自动跳过名字含“插图”的章节。
3. 依序请求每个章节页面，把 `<div id="content">` 的正文抓下来写入对应的 `.txt` 文件。
4. 每次请求后随机等待，降低触发防爬限制的风险；已存在且非空的章节会被跳过，空文件会自动重新写入。

## 项目结构

- `crawler.sh`：主入口，使用 `curl + iconv + python3` 驱动整体流程。
- `scripts/parse_catalog.py`：解析目录页 HTML，输出卷/章映射。
- `scripts/extract_content.py`：从章节页面抽取纯文字正文。
- `downloaded/`：运行时生成的小说文本（默认路径）。

## 运行方式

```bash
chmod +x crawler.sh
./crawler.sh https://www.wenku8.net/novel/1/1508/index.htm
# 或指定输出目录与延迟
./crawler.sh https://www.wenku8.net/novel/1/1508/index.htm my_dir 15
```

- 依赖：`bash`、`curl`、`iconv`、`python3`（标准库即可）。
- 参数 2：输出根目录（默认 `downloaded`）。
- 参数 3：每次请求的基础等待秒数（默认 `10`，实际会加一点随机抖动）。

## 注意事项

- 网站采用 GBK 编码，脚本会自动转换为 UTF-8。
- 若站点结构调整，需同步更新 `scripts/` 下的解析逻辑。
- 访问频率过高可能触发 403，可适当调大延迟或隔段时间再运行。
