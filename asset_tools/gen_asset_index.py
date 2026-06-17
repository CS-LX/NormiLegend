#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
资产索引生成器（Asset Index Generator）

扫描 assets/image/** 下的图片，自动推断分类、读取尺寸、解析帧数，
生成 Grep 友好的 ASSET_INDEX.md。

特性：
- 全自动：path / cat / 尺寸 / 帧数 / 中文名
- 增量更新：保留已有索引里人工/AI 补写的语义描述（按 path 匹配）
- 哈希名图片标记 "?" 待补描述

用法：
    python3 asset_tools/gen_asset_index.py
"""

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGE_DIR = os.path.join(ROOT, "assets", "image")
INDEX_PATH = os.path.join(ROOT, "ASSET_INDEX.md")

IMG_EXTS = (".png", ".jpg", ".jpeg")

# 分类显示顺序与中文标签
CAT_LABELS = [
    ("bg", "背景"),
    ("tile", "地面/平台"),
    ("sign", "标志"),
    ("interact", "交互物件"),
    ("effect", "特效"),
    ("seq", "序列帧/动画"),
    ("portrait", "立绘/头像"),
    ("dlg_bg", "对话框-底图"),
    ("dlg_portrait", "对话框-立绘"),
    ("dlg_whole", "对话框-整体"),
    ("dlg", "对话框-其他"),
    ("ui", "UI 界面"),
    ("icon", "图标"),
    ("cursor", "光标"),
    ("transition", "转场"),
    ("solid", "纯色"),
    ("other", "其他/未分类"),
]


def read_png_size(fp):
    fp.seek(0)
    sig = fp.read(8)
    if sig[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    # IHDR 紧跟在签名后：4字节长度 + "IHDR" + 4字节宽 + 4字节高
    fp.read(4)  # length
    if fp.read(4) != b"IHDR":
        return None
    w, h = struct.unpack(">II", fp.read(8))
    return (w, h)


def read_jpg_size(fp):
    fp.seek(0)
    if fp.read(2) != b"\xff\xd8":
        return None
    while True:
        b = fp.read(1)
        if not b:
            return None
        if b != b"\xff":
            continue
        marker = fp.read(1)
        while marker == b"\xff":
            marker = fp.read(1)
        m = marker[0]
        # SOF0..SOF15 (排除 DHT/JPG/DAC: C4,C8,CC)
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            fp.read(3)  # length(2) + precision(1)
            h, w = struct.unpack(">HH", fp.read(4))
            return (w, h)
        seg_len = struct.unpack(">H", fp.read(2))[0]
        fp.seek(seg_len - 2, os.SEEK_CUR)


def read_size(path):
    # 按真实文件头判断（部分文件扩展名是 .png 实为 JPEG）
    try:
        with open(path, "rb") as fp:
            magic = fp.read(8)
            if magic == b"\x89PNG\r\n\x1a\n":
                return read_png_size(fp)
            if magic[:2] == b"\xff\xd8":
                return read_jpg_size(fp)
    except Exception:
        return None
    return None


HASH_PATTERNS = [
    re.compile(r"^cgt-\d{14}-\w+", re.I),
    re.compile(r"^Image_\d+", re.I),
    re.compile(r"^[0-9a-f]{16,}$", re.I),
]


def is_hashname(stem):
    return any(p.match(stem) for p in HASH_PATTERNS)


def clean_name(stem):
    """清洗显示名：去时间戳尾巴、_last_frame、edited_ 前缀。"""
    s = stem
    s = re.sub(r"_last_frame$", "", s)
    s = re.sub(r"_v\d+$", "", s)
    s = re.sub(r"_2026\d{8,}$", "", s)   # _20260604085456 时间戳尾
    s = re.sub(r"_2026\d{6}$", "", s)
    if s.startswith("edited_"):
        s = s[len("edited_"):]
    return s.strip("_- ") or stem


def detect_frames(stem):
    m = re.search(r"(\d+)f(?:_|$|\W)", stem.lower())
    if m:
        return int(m.group(1))
    m = re.search(r"_(\d+)f", stem.lower())
    if m:
        return int(m.group(1))
    return None


# 顶层散文件的文件名关键词规则
BG_KW = ["背景", "poster", "古堡", "城堡", "教堂", "废墟", "洞穴", "浮岛",
         "拱门", "横版", "竖版", "星空", "blueprint", "蓝图", "garden",
         "花园", "bg_", "chapter_bg", "克莱因蓝", "罗马", "穹顶", "空岛", "时钟"]
SEQ_PREFIX = ("bat_", "ghost_", "wolf_", "skeleton_", "wyvern_", "gargoyle_",
              "enemy_", "char1_", "char2_", "char3_", "idle_", "run_", "jump_",
              "attack_", "hit_", "block_", "crouch_", "heal_", "charge_",
              "ice_charge", "ice_bg")


def classify(rel_from_image, stem):
    """rel_from_image: 形如 '对话框/底图/xxx.png' 的相对路径（不含 image/ 前缀）。"""
    d = os.path.dirname(rel_from_image)  # 目录部分
    low = stem.lower()

    # —— 目录优先 ——
    if "对话框/底图" in d:
        return "dlg_bg"
    if "对话框/整体" in d:
        return "dlg_whole"
    if "对话框" in d and ("立绘" in d or "portrait" in d.lower()):
        return "dlg_portrait"
    if "对话框" in d:
        return "dlg"
    if "地图素材/标志" in d:
        return "sign"
    if "地图素材" in d:
        if stem.startswith("平台-"):
            return "tile"
        if stem.startswith("背景-"):
            return "bg"
        return "other"
    if "光之祭坛" in d:
        return "interact"
    if "主界面背景图" in d:
        return "bg"
    if "ui" in d.lower() or "面板" in d:
        return "ui"
    if "序列帧" in d:
        return "seq"
    if "序章图标" in d:
        return "icon"

    # —— 顶层散文件：文件名规则 ——
    if detect_frames(stem) is not None:
        return "seq"
    if low.startswith(SEQ_PREFIX):
        return "seq"
    if "spritesheet" in low or "精灵图" in stem or "序列帧" in stem:
        return "seq"
    if "特效" in stem or "shatter" in low or "wings_effect" in low:
        return "effect"
    if stem.startswith(("角色正面", "角色背面", "角色侧面")) or "三视图" in stem:
        return "portrait"
    if "world_map" in low:
        return "bg"
    if stem.endswith("层") or "中景" in stem or "远景" in stem or "前景" in stem:
        return "bg"
    if stem in ("白色", "透明"):
        return "solid"
    if low.startswith("cursor_"):
        return "cursor"
    if low.startswith("transition_"):
        return "transition"
    if low.startswith("icon_") or "图标" in stem:
        return "icon"
    if low.startswith("avatar_") or "大头照" in stem or "portrait" in low or "live2d" in low or "立绘" in stem:
        return "portrait"
    if low.startswith(("platform_", "ground_")):
        return "tile"
    if any(k in stem or k.lower() in low for k in BG_KW):
        return "bg"
    return "other"


def parse_existing_desc(index_path):
    """从已有索引解析 path -> desc，用于增量保留人工描述。"""
    descs = {}
    if not os.path.exists(index_path):
        return descs
    line_re = re.compile(r"^\[[^\]]+\]\s+(image/\S+(?:\s\S+)*?)\s+\|\s+[^|]*\|\s+([^|]*)")
    with open(index_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.startswith("["):
                continue
            # 拆分： [tag] path | name | desc | size
            try:
                tag_end = line.index("]")
                rest = line[tag_end + 1:].strip()
                parts = [p.strip() for p in rest.split("|")]
                if len(parts) >= 3:
                    path = parts[0]
                    desc = parts[2]
                    if desc and desc != "?":
                        descs[path] = desc
            except ValueError:
                continue
    return descs


def main():
    if not os.path.isdir(IMAGE_DIR):
        print("找不到目录:", IMAGE_DIR)
        sys.exit(1)

    existing = parse_existing_desc(INDEX_PATH)

    entries = []  # dict: path, cat, name, desc, size, frames, need_desc
    for dirpath, _, files in os.walk(IMAGE_DIR):
        for fn in files:
            ext = os.path.splitext(fn)[1].lower()
            if ext not in IMG_EXTS:
                continue
            if fn.endswith(".meta"):
                continue
            full = os.path.join(dirpath, fn)
            rel_from_image = os.path.relpath(full, IMAGE_DIR).replace(os.sep, "/")
            ref = "image/" + rel_from_image  # 与 ImportTexture/cache 用法一致
            stem = os.path.splitext(fn)[0]

            cat = classify(rel_from_image, stem)
            frames = detect_frames(stem)
            size = read_size(full)
            hashed = is_hashname(stem)
            name = stem if hashed else clean_name(stem)

            if ref in existing:
                desc = existing[ref]
            elif hashed:
                desc = "?"
            else:
                desc = clean_name(stem)

            entries.append({
                "path": ref, "cat": cat, "name": name, "desc": desc,
                "size": size, "frames": frames, "need_desc": (desc == "?"),
            })

    # 分组
    by_cat = {}
    for e in entries:
        by_cat.setdefault(e["cat"], []).append(e)
    for lst in by_cat.values():
        lst.sort(key=lambda x: x["path"])

    total = len(entries)
    need = sum(1 for e in entries if e["need_desc"])

    out = []
    out.append("# 资产索引（ASSET_INDEX）")
    out.append("")
    out.append("> 自动生成，请勿手改格式。语义描述（第3列）可人工/AI 补充，重跑会保留。")
    out.append("> 重新生成：`python3 asset_tools/gen_asset_index.py`")
    out.append(">")
    out.append("> 行格式：`[分类:帧数] 路径 | 名称 | 语义描述 | 宽x高`")
    out.append(">")
    out.append("> **查找方式：用 Grep 按关键词检索本文件，不要全文读取。**")
    out.append("> 例：找对话框立绘 `Grep \"dlg|对话框|立绘\"`；找冰法 `Grep \"冰法\"`")
    out.append("")
    out.append(f"统计：共 {total} 项，其中 {need} 项待补描述（标记为 `?`）。")
    out.append("")

    present_cats = [c for c, _ in CAT_LABELS if c in by_cat]
    # 目录概览
    out.append("## 分类概览")
    out.append("")
    label_map = dict(CAT_LABELS)
    for c in present_cats:
        out.append(f"- `[{c}]` {label_map.get(c, c)}：{len(by_cat[c])} 项")
    out.append("")

    for c in present_cats:
        out.append(f"## [{c}] {label_map.get(c, c)}")
        out.append("")
        out.append("```")
        for e in by_cat[c]:
            tag = e["cat"]
            if e["frames"]:
                tag = f"{tag}:{e['frames']}f"
            size = f"{e['size'][0]}x{e['size'][1]}" if e["size"] else "?"
            out.append(f"[{tag}] {e['path']} | {e['name']} | {e['desc']} | {size}")
        out.append("```")
        out.append("")

    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    print(f"已生成 {INDEX_PATH}")
    print(f"共 {total} 项，{need} 项待补描述")
    # 分类统计
    for c in present_cats:
        print(f"  [{c}] {len(by_cat[c])}")


if __name__ == "__main__":
    main()
