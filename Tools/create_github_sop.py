from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "GitHub上传SOP_小白版.docx"

BLUE = "2E74B5"
DARK_BLUE = "1F4D78"
INK = "0B2545"
MUTED = "5B6573"
LIGHT_BLUE = "E8EEF5"
LIGHT_GRAY = "F2F4F7"
CAUTION = "FFF8E8"
WHITE = "FFFFFF"
# STSong is a macOS Supplemental TrueType Collection that the bundled
# LibreOffice renderer can resolve for Chinese glyphs.
FONT = "STSong"
LATIN_FONT = "STSong"


def set_run_font(run, size=11, color=INK, bold=False, italic=False, name=FONT):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), LATIN_FONT)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), LATIN_FONT)
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    run.font.size = Pt(size)
    run.font.color.rgb = RGBColor.from_string(color)
    run.bold = bold
    run.italic = italic


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=80, start=120, bottom=80, end=120):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for edge, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_cell_width(cell, width):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_w = tc_pr.find(qn("w:tcW"))
    if tc_w is None:
        tc_w = OxmlElement("w:tcW")
        tc_pr.append(tc_w)
    tc_w.set(qn("w:w"), str(width))
    tc_w.set(qn("w:type"), "dxa")


def set_table_geometry(table, widths, indent=120):
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    table.autofit = False
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(sum(widths)))
    tbl_w.set(qn("w:type"), "dxa")
    tbl_ind = tbl_pr.find(qn("w:tblInd"))
    if tbl_ind is None:
        tbl_ind = OxmlElement("w:tblInd")
        tbl_pr.append(tbl_ind)
    tbl_ind.set(qn("w:w"), str(indent))
    tbl_ind.set(qn("w:type"), "dxa")
    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(width))
        grid.append(col)
    for row in table.rows:
        for cell, width in zip(row.cells, widths):
            set_cell_width(cell, width)
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def set_table_borders(table, color="C9D2DE", size="6"):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.find(qn("w:tblBorders"))
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = borders.find(qn(f"w:{edge}"))
        if tag is None:
            tag = OxmlElement(f"w:{edge}")
            borders.append(tag)
        tag.set(qn("w:val"), "single")
        tag.set(qn("w:sz"), size)
        tag.set(qn("w:space"), "0")
        tag.set(qn("w:color"), color)


def mark_header_row(row):
    tr_pr = row._tr.get_or_add_trPr()
    header = OxmlElement("w:tblHeader")
    header.set(qn("w:val"), "true")
    tr_pr.append(header)


def set_paragraph(p, before=0, after=6, line=1.25, keep=False):
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = line
    p.paragraph_format.keep_with_next = keep


def add_text(doc, text, *, size=11, color=INK, bold=False, italic=False, before=0, after=6, line=1.25, align=None):
    p = doc.add_paragraph()
    set_paragraph(p, before=before, after=after, line=line)
    if align is not None:
        p.alignment = align
    run = p.add_run(text)
    set_run_font(run, size=size, color=color, bold=bold, italic=italic)
    return p


def add_heading(doc, text, level=1):
    sizes = {1: 16, 2: 13, 3: 12}
    before = {1: 18, 2: 14, 3: 10}
    after = {1: 10, 2: 7, 3: 5}
    colors = {1: BLUE, 2: BLUE, 3: DARK_BLUE}
    p = doc.add_paragraph(style=f"Heading {level}")
    set_paragraph(p, before=before[level], after=after[level], line=1.15, keep=True)
    run = p.add_run(text)
    set_run_font(run, size=sizes[level], color=colors[level], bold=True)
    return p


def add_list_item(doc, text, numbered=False):
    style = "List Number" if numbered else "List Bullet"
    p = doc.add_paragraph(style=style)
    p.paragraph_format.left_indent = Inches(0.375)
    p.paragraph_format.first_line_indent = Inches(-0.188)
    set_paragraph(p, before=0, after=4, line=1.25)
    run = p.add_run(text)
    set_run_font(run)
    return p


def new_numbered_list(doc):
    """Create a fresh Word numbering instance so each procedure starts at 1."""
    numbering = doc.part.numbering_part.element
    num_ids = [
        int(node.get(qn("w:numId")))
        for node in numbering.findall(qn("w:num"))
        if node.get(qn("w:numId")) is not None
    ]
    num_id = max(num_ids, default=0) + 1
    num = OxmlElement("w:num")
    num.set(qn("w:numId"), str(num_id))
    abstract = OxmlElement("w:abstractNumId")
    abstract.set(qn("w:val"), "7")
    num.append(abstract)
    override = OxmlElement("w:lvlOverride")
    override.set(qn("w:ilvl"), "0")
    start = OxmlElement("w:startOverride")
    start.set(qn("w:val"), "1")
    override.append(start)
    num.append(override)
    numbering.append(num)
    return num_id


def add_numbered_item(doc, text, num_id):
    p = add_list_item(doc, text, numbered=True)
    p_pr = p._p.get_or_add_pPr()
    num_pr = OxmlElement("w:numPr")
    ilvl = OxmlElement("w:ilvl")
    ilvl.set(qn("w:val"), "0")
    direct_num_id = OxmlElement("w:numId")
    direct_num_id.set(qn("w:val"), str(num_id))
    num_pr.extend((ilvl, direct_num_id))
    p_pr.append(num_pr)
    return p


def add_note(doc, label, text, fill=CAUTION):
    table = doc.add_table(rows=1, cols=1)
    set_table_geometry(table, [9360], indent=120)
    set_table_borders(table, color="E1C77A", size="6")
    cell = table.cell(0, 0)
    set_cell_shading(cell, fill)
    p = cell.paragraphs[0]
    set_paragraph(p, before=0, after=0, line=1.2)
    lead = p.add_run(f"{label}  ")
    set_run_font(lead, color="7A5A00", bold=True)
    body = p.add_run(text)
    set_run_font(body, color=INK)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def add_label_table(doc, rows, widths=(2700, 6660), header=None):
    table = doc.add_table(rows=1 if header else 0, cols=2)
    if header:
        hdr = table.rows[0]
        mark_header_row(hdr)
        for idx, value in enumerate(header):
            set_cell_shading(hdr.cells[idx], LIGHT_BLUE)
            p = hdr.cells[idx].paragraphs[0]
            set_paragraph(p, before=0, after=0, line=1.15)
            run = p.add_run(value)
            set_run_font(run, color=DARK_BLUE, bold=True)
    for label, value in rows:
        cells = table.add_row().cells
        for idx, text in enumerate((label, value)):
            p = cells[idx].paragraphs[0]
            set_paragraph(p, before=0, after=0, line=1.18)
            run = p.add_run(text)
            set_run_font(run, bold=(idx == 0), color=(DARK_BLUE if idx == 0 else INK))
            if idx == 0:
                set_cell_shading(cells[idx], LIGHT_GRAY)
    set_table_geometry(table, list(widths), indent=120)
    set_table_borders(table)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return table


def add_code_line(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.18)
    set_paragraph(p, before=0, after=4, line=1.05)
    run = p.add_run(text)
    set_run_font(run, size=9.5, color="243447", name="Menlo")
    return p


def configure_document(doc):
    section = doc.sections[0]
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)
    section.header_distance = Inches(0.492)
    section.footer_distance = Inches(0.492)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = LATIN_FONT
    normal._element.rPr.rFonts.set(qn("w:ascii"), LATIN_FONT)
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), LATIN_FONT)
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
    normal.font.size = Pt(11)
    normal.font.color.rgb = RGBColor.from_string(INK)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.25
    for level in (1, 2, 3):
        style = styles[f"Heading {level}"]
        style.font.name = LATIN_FONT
        style._element.rPr.rFonts.set(qn("w:ascii"), LATIN_FONT)
        style._element.rPr.rFonts.set(qn("w:hAnsi"), LATIN_FONT)
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
        style.font.color.rgb = RGBColor.from_string(BLUE if level < 3 else DARK_BLUE)

    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    set_paragraph(header, before=0, after=0, line=1.0)
    run = header.add_run("性能简读  ·  GitHub 上传指南")
    set_run_font(run, size=9, color=MUTED)
    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_paragraph(footer, before=0, after=0, line=1.0)
    run = footer.add_run("本地部署优先  ·  完全离线  ·  2026")
    set_run_font(run, size=9, color=MUTED)


def build():
    doc = Document()
    configure_document(doc)
    props = doc.core_properties
    props.title = "GitHub 上传 SOP（小白版）"
    props.subject = "性能简读的 GitHub 发布与本地安装指南"
    props.author = "MenuMonitor contributors"
    props.keywords = "GitHub, macOS, MenuMonitor, SOP"

    # Cover-like first page: editorial_cover pattern, kept practical for an SOP.
    add_text(doc, "操作手册", size=11, color=BLUE, bold=True, before=92, after=16, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(doc, "GitHub 上传 SOP（小白版）", size=28, color=INK, bold=True, before=0, after=10, line=1.1, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_text(doc, "把“性能简读”安全地发布到 GitHub", size=14, color=MUTED, after=28, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_label_table(
        doc,
        [
            ("适用对象", "第一次把本地项目上传到 GitHub 的 macOS 用户"),
            ("项目", "性能简读（原生 Swift 6 + SwiftUI/AppKit 菜单栏工具）"),
            ("发行方式", "本地 ad-hoc 签名；不需要 Developer ID 或 Team ID"),
            ("当前版本", "v1.0.1（build 2）"),
            ("更新时间", "2026 年 8 月"),
        ],
        widths=(1800, 7560),
    )
    add_note(doc, "先记住", "上传源码和发布 DMG 是两件事：GitHub 保存源码与说明，DMG 供别人下载；其他 Mac 请双击 DMG 内的 MenuMonitor-Installer.pkg，本机源码安装继续使用 install.sh。")
    add_text(doc, "阅读完本页后，按“推荐路径”操作即可。遇到系统提示时不要关闭 Gatekeeper，也不要把密码、证书或个人配置上传到仓库。", size=10.5, color=MUTED, after=0)
    doc.add_page_break()

    add_heading(doc, "1. 先知道三件事", 1)
    add_list_item(doc, "这个项目完全离线运行：代码没有网络请求、统计上报、WebView 或云端依赖。")
    add_list_item(doc, "当前没有 Developer ID Application 证书，应用使用 ad-hoc 签名；本机可以直接运行，其他 Mac 首次打开可能需要在“系统设置 → 隐私与安全性”手动批准。")
    add_list_item(doc, "安装脚本会把应用放到 /Applications 并注册开机自启；不要把“拖进应用程序”当成必要步骤。")
    add_list_item(doc, "v1.0.1 面板将系统功耗详情改为 CPU/GPU 温度，四项详情保持单行；指标告警只改变标题颜色，状态栏图标下方的灰色悬停帮助标签已修复。")
    add_note(doc, "安全边界", "任何 GitHub 仓库都可能被公开阅读。提交前检查是否包含 API key、密码、私钥、个人日志、带用户名的绝对路径或本机偏好文件。")

    add_heading(doc, "2. 准备工作", 1)
    add_heading(doc, "2.1 建立 GitHub 仓库", 2)
    add_list_item(doc, "登录 github.com，点击右上角 + → New repository。")
    add_list_item(doc, "仓库名建议使用 menu-monitor 或 performance-menu-monitor；可见性按你的计划选择 Public 或 Private。")
    add_list_item(doc, "创建时不要勾选 README、.gitignore 或 License（本项目本地已经有这些文件），这样第一次推送不会产生冲突。")
    add_heading(doc, "2.2 检查本地目录", 2)
    add_code_line(doc, 'PROJECT_DIR="<项目目录>"')
    add_code_line(doc, 'cd "$PROJECT_DIR"')
    add_code_line(doc, "ls Package.swift README.md install.sh uninstall.sh")
    add_text(doc, "如果能看到这些文件，说明你位于正确的项目目录。build/、.build/ 和 dist/ 已被忽略，不会进入提交；dist/ 里的 DMG 应作为 Release 附件上传。维护者还可以参考仓库中的 GITHUB_RELEASE_CHECKLIST.md。", size=10.5, color=MUTED)

    add_heading(doc, "3. 推荐路径：GitHub Desktop", 1)
    add_text(doc, "GitHub Desktop 对第一次使用的人最直观。以下步骤只做本地版本控制和推送，不会改变应用运行方式。", size=11)
    steps = [
        "打开 GitHub Desktop，选择 File → Add Local Repository。",
        "选择你的“性能简读”项目目录；如果提示“不是 Git 仓库”，点击 create a repository。",
        "在 Name 中确认项目名，在 Local Path 中确认路径，点击 Create Repository。",
        "回到 Changes 页面，确认没有 build/、.build/、dist/、.DS_Store 或个人文件；这些通常已经被 .gitignore 排除。",
        "在 Summary 中输入首个提交说明，例如 Initial release；点击 Commit to main。",
        "点击 Publish repository，确认仓库名称和 Public/Private 选项后发布。",
        "发布完成后点击 Push origin，等待右上角同步完成。",
        "在 GitHub 网页刷新仓库，确认 README、Sources、Resources、Tests 和脚本都可见。",
    ]
    num_id = new_numbered_list(doc)
    for step in steps:
        add_numbered_item(doc, step, num_id)
    add_note(doc, "检查点", "GitHub 页面上应该能看到 README.md 和 LICENSE；不应该看到 .build、build、dist、任何 .plist 偏好备份或密码文件。")

    add_heading(doc, "4. 备选路径：只用浏览器", 1)
    add_text(doc, "如果不想安装 GitHub Desktop，可以在仓库网页使用 Add file → Upload files。浏览器上传适合少量文件，不适合频繁更新。", size=11)
    num_id = new_numbered_list(doc)
    for step in [
        "先按第 2 节创建一个空仓库。",
        "在项目文件夹中选中 Package.swift、README.md、LICENSE、Sources、Resources、Tests 和脚本文件。不要选 build、.build、dist。",
        "把文件拖进 GitHub 的 Upload files 页面，填写提交说明，点击 Commit changes。",
        "后续更新需要重新上传发生变化的文件；文件很多时应改用 GitHub Desktop。",
    ]:
        add_numbered_item(doc, step, num_id)
    add_note(doc, "推荐", "浏览器上传很容易漏掉隐藏文件（例如 .gitignore）。第一次发布后，建议改用 GitHub Desktop 或命令行维护版本。")

    add_heading(doc, "5. 发布 DMG", 1)
    add_text(doc, "源码仓库发布后，可以生成一个给别人下载的本地 DMG。这个 DMG 仍然是 ad-hoc、未公证版本，不会自动绕过 Gatekeeper。", size=11)
    add_code_line(doc, 'cd "$PROJECT_DIR"')
    add_code_line(doc, "version=\"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)\"")
    add_code_line(doc, "./package-dmg.sh \"dist/MenuMonitor-${version}-universal.dmg\"")
    add_text(doc, "脚本会从 Info.plist 自动读取版本号，生成 dist/MenuMonitor-<版本>-universal.dmg；镜像内含可双击的 MenuMonitor-Installer.pkg、应用本体和 Applications 快捷方式。脚本还会检查应用签名、arm64 + x86_64 架构和 UDZO 镜像。", size=11)
    add_code_line(doc, "./package-pkg.sh \"dist/MenuMonitor-${version}-Installer.pkg\"")
    add_code_line(doc, "shasum -a 256 \"dist/MenuMonitor-${version}-universal.dmg\"")
    add_text(doc, "复制输出的 SHA-256 校验值留在发布说明中。然后打开 GitHub 仓库的 Releases → Draft a new release，选择同名版本标签，把刚刚验证过的 DMG 拖到附件区域。不要把 dist/ 整个目录提交到源码仓库。", size=11)
    num_id = new_numbered_list(doc)
    for step in [
        "确认标签、Info.plist 版本号、DMG 文件名三者一致，例如 v1.0.1 与 MenuMonitor-1.0.1-universal.dmg。",
        "在发布说明中写明 macOS 26、Apple Silicon/Intel 通用、ad-hoc、未公证和 SHA-256 校验值。",
        "明确说明功耗是 CPU + GPU（可选 DRAM）芯片估算，不是墙上功耗；面板不显示内部来源标签，命令行探针仍可输出它；IOReport 不可用是受支持结果。",
        "发布后下载一次附件并重新计算 SHA-256，确认与发布说明一致。",
    ]:
        add_numbered_item(doc, step, num_id)
    add_label_table(
        doc,
        [
            ("源码变更", "先提交到仓库，再创建 release"),
            ("DMG 文件", "只上传 dist/MenuMonitor-<版本>-universal.dmg（内含 Installer.pkg），不上传 build/、.build/ 或整个 dist/"),
            ("版本说明", "写明 macOS 26、Apple Silicon/Intel 通用、ad-hoc、未公证"),
            ("用户安装", "本机使用 install.sh；其他 Mac 首次打开按系统提示批准"),
        ],
        widths=(1800, 7560),
        header=("项目", "发布时怎么做"),
    )

    add_heading(doc, "6. 在本机验证安装", 1)
    add_text(doc, "每次发布前建议做一次从源码到菜单栏的完整检查。", size=11)
    num_id = new_numbered_list(doc)
    for step in [
        "执行 ./install.sh，等待它完成构建、复制、启动和登录项注册。",
        "确认菜单栏出现波形图标；点击后能打开监控面板。",
        "确认系统功耗详情行显示 CPU/GPU 温度；四项中英文详情都保持单行，面板内没有 CPU + GPU SoC estimate 来源标签。",
        "让某项指标达到告警阈值时，确认只有对应标题变为橙色/红色，详情区没有新增告警文字；内存详情不显示“正常”。",
        "点击齿轮打开设置，切换中文 / English，再切回你的常用语言。",
        "如果接入电源且电池已满，充电功率的小字应显示“旁路供电”；主值仍是 0 W。",
        "将鼠标悬停在菜单栏图标上，确认不再出现灰色 tooltip/help 矩形；点击图标仍能打开面板。",
        "执行 ./uninstall.sh，确认应用退出、登录项移除，再执行 ./install.sh 复测。",
    ]:
        add_numbered_item(doc, step, num_id)
    add_code_line(doc, "./install.sh")
    add_code_line(doc, "./uninstall.sh")

    add_heading(doc, "7. 常见提示怎么处理", 1)
    add_label_table(
        doc,
        [
            ("无法验证开发者", "这是 ad-hoc 未公证应用的正常提示。在系统设置 → 隐私与安全性中手动允许一次；不要使用脚本关闭 Gatekeeper。"),
            ("/Applications 需要密码", "安装脚本只在复制应用时请求一次管理员授权；采集指标不会请求 sudo。"),
            ("功耗不可用", "IOReport 依赖硬件和系统版本。显示不可用比显示猜测值更安全，尤其是在部分 Apple Silicon 或 Intel 机型上。"),
            ("登录项未启用", "确认应用来自 /Applications/MenuMonitor.app，再重新运行 install.sh；不要从 build/ 目录直接注册。"),
        ],
        widths=(2100, 7260),
        header=("提示", "处理方式"),
    )

    add_heading(doc, "8. 提交前清单", 1)
    for item in [
        "README 中已写明完全离线、无数据上报、已知硬件限制。",
        "LICENSE、CONTRIBUTING.md、SECURITY.md 已存在。",
        "没有提交 API key、证书、私钥、个人日志或本机偏好文件。",
        "swift test -c debug 通过，./build.sh 能生成 arm64 + x86_64 通用应用。",
        "./package-pkg.sh 和 ./package-dmg.sh 能生成并验证 Installer.pkg 与 dist/MenuMonitor-<版本>-universal.dmg。",
        "install.sh 和 uninstall.sh 已各自跑过一次。",
        "发布附件的 SHA-256 已记录，并且没有上传源码之外的个人文件。",
    ]:
        add_list_item(doc, item)

    add_heading(doc, "9. 命令速查", 1)
    add_label_table(
        doc,
        [
            ("测试", "swift test -c debug"),
            ("构建", "./build.sh"),
            ("安装", "./install.sh"),
            ("卸载", "./uninstall.sh"),
            ("生成 DMG", "./package-dmg.sh dist/MenuMonitor-<版本>-universal.dmg"),
            ("生成安装器", "./package-pkg.sh dist/MenuMonitor-<版本>-Installer.pkg"),
            ("采集验证", "swift run -c release MenuMonitorProbe --samples 4 --interval 2"),
        ],
        widths=(2100, 7260),
    )
    add_text(doc, "完成后，你可以把 GitHub 仓库地址和 Releases 页面地址发给别人；本机继续由 /Applications/MenuMonitor.app 负责菜单栏常驻。", size=10.5, color=MUTED, before=8, after=0)

    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build()
