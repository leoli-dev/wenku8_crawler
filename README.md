# Wenku8 Crawler

一个专门抓取 [Wenku8](https://www.wenku8.net/) 小说目录与正文的命令行脚本。整体流程：

1. 访问目录页，读取小说标题，自动在 `downloaded/` 下创建 `小说名/卷名/` 层级结构（自动用 `_` 替换标点）。
2. 解析每卷、每章的标题和链接，包含所有章节（含插图）。
3. 依序请求每个章节页面，把 `<div id="content">` 的正文抓下来写入 `001_章节名.txt`（每卷独立编号，便于排序）；若章节名称包含“插图”则抓取 `<img>` 并按网页顺序保存为 `0001.jpg`、`0002.jpg`…（每个插图章节独立编号）。
4. 每次请求后随机等待，降低触发防爬限制的风险；已存在且非空的章节会被跳过，空文件会自动重新写入。

## 项目结构

- `crawler.sh`：主入口，使用 `curl + iconv + python3` 驱动整体流程。
- `scripts/parse_catalog.py`：解析目录页 HTML，输出卷/章映射。
- `scripts/extract_content.py`：从章节页面抽取纯文字正文。
- `scripts/extract_images.py`：在插图章节中提取图片链接与文件名。
- `downloaded/`：运行时生成的小说文本（默认路径）。

## 运行方式

```bash
chmod +x crawler.sh
# 一次下载多本小说（自动去重、顺序执行）
./crawler.sh https://www.wenku8.net/novel/1/1508/index.htm https://www.wenku8.net/novel/4/4011/index.htm
# 自定义输出目录与请求延迟
./crawler.sh -o my_dir -d 15 https://www.wenku8.net/novel/1/1508/index.htm
```

- 依赖：`bash`、`curl`、`iconv`、`python3`（标准库即可）。
- `-o/--output`：自定义根目录（默认 `downloaded`，每本小说会在其下生成独立子文件夹）。
- `-d/--delay`：每次请求的基础等待秒数（默认 `10`，实际会加一点随机抖动）。
- 其余位置参数皆视为目录网址，脚本会先列出任务列表并依次执行。

## 注意事项

- 网站采用 GBK 编码，脚本会自动转换为 UTF-8。
- 若站点结构调整，需同步更新 `scripts/` 下的解析逻辑。
- 访问频率过高可能触发 403，可适当调大延迟或隔段时间再运行。
